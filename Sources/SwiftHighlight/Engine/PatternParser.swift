/// Parsed form of a grammar pattern — a line-anchored regular expression subset.
///
/// Supported syntax: literals and `\`-escaped punctuation; `.`; classes `[a-z_]`, `[^"\\]`;
/// `\d \D \w \W \s \S \h \H`; `\n \t \r \f \v \0 \xHH \u{HHHH}`; anchors `^ $ \b \B`; groups
/// `(…)`, `(?:…)`, `(?<name>…)`; atomic groups `(?>…)`; lookahead `(?=…) (?!…)`; bounded
/// lookbehind `(?<=…) (?<!…)`; backreferences `\1`–`\9`; quantifiers `* + ? {n} {n,} {n,m}` with
/// lazy (`*?`) and possessive (`*+`) forms; a leading `(?i)` for case-insensitive ASCII; and `\k`,
/// which matches the delimiter text a `push` rule captured (heredocs, raw strings, fences).
indirect enum PatternNode {
    case empty
    case literal([UInt8], caseInsensitive: Bool)
    case set(ByteSet)
    case any
    case sequence([PatternNode])
    case alternation([PatternNode])
    case repeated(PatternNode, min: Int, max: Int?, mode: RepeatMode)
    case group(Int?, PatternNode)
    case atomic(PatternNode)
    case look(PatternNode, ahead: Bool, negated: Bool)
    case anchor(Anchor)
    case backreference(Int)
    case delimiter

    enum RepeatMode { case greedy, lazy, possessive }
    enum Anchor { case lineStart, lineEnd, wordBoundary, notWordBoundary }
}

/// A pattern that failed to parse or compile, with the byte offset of the problem.
public struct PatternError: Error, CustomStringConvertible, Sendable, Equatable {
    public var pattern: String
    public var offset: Int
    public var message: String

    public var description: String {
        "\(message) at offset \(offset) in pattern \(pattern.debugDescription)"
    }
}

struct PatternParser {
    private let source: String
    private let bytes: [UInt8]
    private var position = 0
    private var caseInsensitive = false
    private(set) var groupCount = 0
    private(set) var groupNames: [String: Int] = [:]

    init(_ pattern: String) {
        source = pattern
        bytes = Array(pattern.utf8)
    }

    static func parse(_ pattern: String) throws(PatternError) -> (node: PatternNode, groups: Int) {
        var parser = PatternParser(pattern)
        if parser.bytes.starts(with: Array("(?i)".utf8)) {
            parser.caseInsensitive = true
            parser.position = 4
        }
        let node = try parser.parseAlternation()
        if parser.position < parser.bytes.count {
            throw parser.error("Unbalanced ')'")
        }
        return (node, parser.groupCount)
    }

    private func error(_ message: String, at offset: Int? = nil) -> PatternError {
        PatternError(pattern: source, offset: offset ?? position, message: message)
    }

    private var atEnd: Bool { position >= bytes.count }

    private func peek(_ offset: Int = 0) -> UInt8? {
        position + offset < bytes.count ? bytes[position + offset] : nil
    }

    private mutating func consume(_ literal: String) -> Bool {
        let expected = Array(literal.utf8)
        guard position + expected.count <= bytes.count,
              bytes[position..<position + expected.count].elementsEqual(expected) else { return false }
        position += expected.count
        return true
    }

    // MARK: Grammar

    private mutating func parseAlternation() throws(PatternError) -> PatternNode {
        var branches = [try parseSequence()]
        while peek() == UInt8(ascii: "|") {
            position += 1
            branches.append(try parseSequence())
        }
        return branches.count == 1 ? branches[0] : .alternation(branches)
    }

    private mutating func parseSequence() throws(PatternError) -> PatternNode {
        var items: [PatternNode] = []
        while let byte = peek(), byte != UInt8(ascii: "|"), byte != UInt8(ascii: ")") {
            let atomStart = position
            var atom = try parseAtom()
            atom = try parseQuantifier(atom, atomStart: atomStart)
            // Merge adjacent literals so a keyword compiles to one comparison.
            if case let .literal(next, nextCI) = atom, case let .literal(previous, previousCI)? = items.last,
               nextCI == previousCI {
                items[items.count - 1] = .literal(previous + next, caseInsensitive: nextCI)
            } else {
                items.append(atom)
            }
        }
        if items.isEmpty { return .empty }
        return items.count == 1 ? items[0] : .sequence(items)
    }

    private mutating func parseQuantifier(_ atom: PatternNode, atomStart: Int) throws(PatternError) -> PatternNode {
        guard let byte = peek() else { return atom }
        var min = 0
        var max: Int?
        switch byte {
        case UInt8(ascii: "*"):
            position += 1
        case UInt8(ascii: "+"):
            position += 1
            min = 1
        case UInt8(ascii: "?"):
            position += 1
            max = 1
        case UInt8(ascii: "{"):
            guard let (lower, upper) = parseBraces() else { return atom }
            min = lower
            max = upper
        default:
            return atom
        }
        switch atom {
        case .anchor, .look, .empty:
            throw error("Nothing to repeat", at: atomStart)
        default:
            break
        }
        if let max, max < min { throw error("Quantifier range is reversed", at: atomStart) }
        if min > 1_000 || (max ?? 0) > 1_000 { throw error("Quantifier bound exceeds 1000", at: atomStart) }

        var mode = PatternNode.RepeatMode.greedy
        if peek() == UInt8(ascii: "?") {
            position += 1
            mode = .lazy
        } else if peek() == UInt8(ascii: "+") {
            position += 1
            mode = .possessive
        }
        // Atoms are single scalars (runs merge only after quantifiers bind), so `ab*` is `a(b*)`.
        return .repeated(atom, min: min, max: max, mode: mode)
    }

    /// Parses `{n}`, `{n,}` or `{n,m}`; leaves the position untouched and returns nil when the
    /// brace is not a quantifier (then `{` is a literal, as in most regex dialects).
    private mutating func parseBraces() -> (Int, Int?)? {
        let start = position
        position += 1
        func number() -> Int? {
            var value: Int?
            while let byte = peek(), byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                value = (value ?? 0) * 10 + Int(byte - UInt8(ascii: "0"))
                if value! > 100_000 { return nil }
                position += 1
            }
            return value
        }
        guard let lower = number() else {
            position = start
            return nil
        }
        var upper: Int? = lower
        if peek() == UInt8(ascii: ",") {
            position += 1
            upper = number()
        }
        guard peek() == UInt8(ascii: "}") else {
            position = start
            return nil
        }
        position += 1
        return (lower, upper)
    }

    private mutating func parseAtom() throws(PatternError) -> PatternNode {
        let byte = bytes[position]
        switch byte {
        case UInt8(ascii: "("):
            return try parseGroup()
        case UInt8(ascii: "["):
            return .set(try parseClass())
        case UInt8(ascii: "."):
            position += 1
            return .any
        case UInt8(ascii: "^"):
            position += 1
            return .anchor(.lineStart)
        case UInt8(ascii: "$"):
            position += 1
            return .anchor(.lineEnd)
        case UInt8(ascii: "\\"):
            return try parseEscape()
        case UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "?"):
            throw error("Nothing to repeat")
        default:
            let length = scalarLength(byte)
            guard position + length <= bytes.count else { throw error("Invalid UTF-8") }
            let scalar = Array(bytes[position..<position + length])
            position += length
            return literal(scalar)
        }
    }

    private func literal(_ scalar: [UInt8]) -> PatternNode {
        // In (?i) mode every ASCII literal is folded, so letter and punctuation runs still merge.
        .literal(scalar, caseInsensitive: caseInsensitive && scalar.count == 1)
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    private mutating func parseGroup() throws(PatternError) -> PatternNode {
        let start = position
        position += 1
        var kind: Character = "c"
        var name: String?
        if consume("?:") {
            kind = ":"
        } else if consume("?>") {
            kind = ">"
        } else if consume("?=") {
            kind = "="
        } else if consume("?!") {
            kind = "!"
        } else if consume("?<=") {
            kind = "b"
        } else if consume("?<!") {
            kind = "n"
        } else if consume("?<") || consume("?P<") {
            var nameBytes: [UInt8] = []
            while let byte = peek(), byte != UInt8(ascii: ">") {
                nameBytes.append(byte)
                position += 1
            }
            guard consume(">"), !nameBytes.isEmpty else { throw error("Malformed group name", at: start) }
            name = String(decoding: nameBytes, as: UTF8.self)
        } else if peek() == UInt8(ascii: "?") {
            throw error("Unsupported group syntax", at: start)
        }

        var index: Int?
        if kind == "c" {
            groupCount += 1
            index = groupCount
            if let name { groupNames[name] = groupCount }
        }
        let body = try parseAlternation()
        guard consume(")") else { throw error("Missing ')'", at: start) }

        switch kind {
        case ":": return .group(nil, body)
        case ">": return .atomic(body)
        case "=": return .look(body, ahead: true, negated: false)
        case "!": return .look(body, ahead: true, negated: true)
        case "b": return .look(body, ahead: false, negated: false)
        case "n": return .look(body, ahead: false, negated: true)
        default: return .group(index, body)
        }
    }

    private mutating func parseEscape() throws(PatternError) -> PatternNode {
        let start = position
        position += 1
        guard let byte = peek() else { throw error("Trailing backslash", at: start) }
        position += 1
        if let set = classEscape(byte) { return .set(caseInsensitive ? set.caseFolded : set) }
        switch byte {
        case UInt8(ascii: "b"): return .anchor(.wordBoundary)
        case UInt8(ascii: "B"): return .anchor(.notWordBoundary)
        case UInt8(ascii: "k"): return .delimiter
        case UInt8(ascii: "1")...UInt8(ascii: "9"):
            let group = Int(byte - UInt8(ascii: "0"))
            guard group <= groupCount else { throw error("Backreference to an unopened group", at: start) }
            return .backreference(group)
        default:
            return literal(try escapedBytes(byte, start: start))
        }
    }

    private func classEscape(_ byte: UInt8) -> ByteSet? {
        switch byte {
        case UInt8(ascii: "d"): return .digits
        case UInt8(ascii: "D"): return ByteSet.digits.inverted
        case UInt8(ascii: "w"): return .word
        case UInt8(ascii: "W"): return ByteSet.word.inverted
        case UInt8(ascii: "s"): return .space
        case UInt8(ascii: "S"): return ByteSet.space.inverted
        case UInt8(ascii: "h"): return .hexDigits
        case UInt8(ascii: "H"): return ByteSet.hexDigits.inverted
        default: return nil
        }
    }

    /// The bytes an escape like `\n`, `\x41`, `\u{1F600}` or `\.` stands for.
    private mutating func escapedBytes(_ byte: UInt8, start: Int) throws(PatternError) -> [UInt8] {
        switch byte {
        case UInt8(ascii: "n"): return [0x0A]
        case UInt8(ascii: "t"): return [0x09]
        case UInt8(ascii: "r"): return [0x0D]
        case UInt8(ascii: "f"): return [0x0C]
        case UInt8(ascii: "v"): return [0x0B]
        case UInt8(ascii: "0"): return [0x00]
        case UInt8(ascii: "e"): return [0x1B]
        case UInt8(ascii: "x"):
            guard position + 2 <= bytes.count,
                  let value = UInt8(String(decoding: bytes[position..<position + 2], as: UTF8.self), radix: 16)
            else { throw error("Malformed \\x escape", at: start) }
            position += 2
            return value < 0x80 ? [value] : Array(String(UnicodeScalar(value)).utf8)
        case UInt8(ascii: "u"):
            guard consume("{") else { throw error("Expected \\u{…}", at: start) }
            var digits: [UInt8] = []
            while let next = peek(), next != UInt8(ascii: "}") {
                digits.append(next)
                position += 1
            }
            guard consume("}"), let value = UInt32(String(decoding: digits, as: UTF8.self), radix: 16),
                  let scalar = UnicodeScalar(value)
            else { throw error("Malformed \\u{…} escape", at: start) }
            return Array(String(scalar).utf8)
        default:
            if isLetter(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) {
                throw error("Unknown escape \\\(Character(UnicodeScalar(byte)))", at: start)
            }
            let length = scalarLength(byte)
            let scalarStart = position - 1
            guard scalarStart + length <= bytes.count else { throw error("Invalid UTF-8", at: start) }
            position = scalarStart + length
            return Array(bytes[scalarStart..<scalarStart + length])
        }
    }

    private mutating func parseClass() throws(PatternError) -> ByteSet {
        let start = position
        position += 1
        var negated = false
        if peek() == UInt8(ascii: "^") {
            negated = true
            position += 1
        }
        var set = ByteSet()
        var first = true
        while true {
            guard let byte = peek() else { throw error("Missing ']'", at: start) }
            if byte == UInt8(ascii: "]"), !first {
                position += 1
                break
            }
            first = false
            let lowStart = position
            var low: UInt8
            if byte == UInt8(ascii: "\\") {
                position += 1
                guard let escaped = peek() else { throw error("Trailing backslash", at: lowStart) }
                position += 1
                if let escapedSet = classEscape(escaped) {
                    set.formUnion(escapedSet)
                    continue
                }
                if escaped == UInt8(ascii: "b") {
                    low = 0x08
                } else {
                    let value = try escapedBytes(escaped, start: lowStart)
                    guard value.count == 1 else { throw error("Non-ASCII character in class", at: lowStart) }
                    low = value[0]
                }
            } else {
                guard byte < 0x80 else { throw error("Non-ASCII character in class", at: lowStart) }
                low = byte
                position += 1
            }
            // A range, unless the dash is last (`[a-]`).
            if peek() == UInt8(ascii: "-"), let next = peek(1), next != UInt8(ascii: "]") {
                position += 1
                var high: UInt8
                if next == UInt8(ascii: "\\") {
                    position += 1
                    guard let escaped = peek() else { throw error("Trailing backslash", at: position) }
                    position += 1
                    let value = try escapedBytes(escaped, start: position - 2)
                    guard value.count == 1 else { throw error("Non-ASCII character in class", at: position) }
                    high = value[0]
                } else {
                    guard next < 0x80 else { throw error("Non-ASCII character in class", at: position) }
                    high = next
                    position += 1
                }
                guard low <= high else { throw error("Class range is reversed", at: lowStart) }
                set.insert(low...high)
            } else {
                set.insert(low)
            }
        }
        if caseInsensitive { set = set.caseFolded }
        return negated ? set.inverted : set
    }
}

extension PatternNode {
    /// Whether the node can succeed without consuming input.
    var isNullable: Bool {
        switch self {
        case .empty, .anchor, .look, .delimiter, .backreference: return true
        case let .literal(bytes, _): return bytes.isEmpty
        case .set, .any: return false
        case let .sequence(items): return items.allSatisfy(\.isNullable)
        case let .alternation(branches): return branches.contains(where: \.isNullable)
        case let .repeated(node, min, _, _): return min == 0 || node.isNullable
        case let .group(_, node), let .atomic(node): return node.isNullable
        }
    }

    /// Bytes that can start a successful match, and whether the match can be empty (in which
    /// case the caller must also consider whatever follows).
    var firstBytes: (map: ByteMap, nullable: Bool) {
        switch self {
        case .empty, .anchor, .look:
            return (ByteMap(), true)
        case .delimiter, .backreference:
            return (.all, true)
        case let .literal(bytes, caseInsensitive):
            guard let first = bytes.first else { return (ByteMap(), true) }
            var map = ByteMap()
            map.insert(first)
            if caseInsensitive {
                let set = ByteSet(low: first < 64 ? 1 << UInt64(first) : 0,
                                  high: first >= 64 && first < 128 ? 1 << UInt64(first - 64) : 0).caseFolded
                map.formUnion(ByteMap(set))
            }
            return (map, false)
        case let .set(set):
            return (ByteMap(set), false)
        case .any:
            return (.all, false)
        case let .sequence(items):
            var map = ByteMap()
            for item in items {
                let (itemMap, nullable) = item.firstBytes
                map.formUnion(itemMap)
                if !nullable { return (map, false) }
            }
            return (map, true)
        case let .alternation(branches):
            var map = ByteMap()
            var nullable = false
            for branch in branches {
                let (branchMap, branchNullable) = branch.firstBytes
                map.formUnion(branchMap)
                nullable = nullable || branchNullable
            }
            return (map, nullable)
        case let .repeated(node, min, _, _):
            let (map, nullable) = node.firstBytes
            return (map, nullable || min == 0)
        case let .group(_, node), let .atomic(node):
            return node.firstBytes
        }
    }

    /// Minimum and maximum byte length of any match, or nil when unbounded or data-dependent.
    var lengthBounds: (min: Int, max: Int)? {
        switch self {
        case .empty, .anchor, .look: return (0, 0)
        case .delimiter, .backreference: return nil
        case let .literal(bytes, _): return (bytes.count, bytes.count)
        case let .set(set): return set.nonASCII ? (1, 4) : (1, 1)
        case .any: return (1, 4)
        case let .sequence(items):
            var total = (min: 0, max: 0)
            for item in items {
                guard let bounds = item.lengthBounds else { return nil }
                total.min += bounds.min
                total.max += bounds.max
            }
            return total
        case let .alternation(branches):
            var result: (min: Int, max: Int)?
            for branch in branches {
                guard let bounds = branch.lengthBounds else { return nil }
                result = result.map { (Swift.min($0.min, bounds.min), Swift.max($0.max, bounds.max)) } ?? bounds
            }
            return result ?? (0, 0)
        case let .repeated(node, min, max, _):
            guard let max, let bounds = node.lengthBounds else { return nil }
            return (bounds.min * min, bounds.max * max)
        case let .group(_, node), let .atomic(node):
            return node.lengthBounds
        }
    }

    /// Bytes every match must start with (ignoring zero-width assertions), up to `limit`.
    func requiredPrefix(limit: Int = 8) -> [UInt8] {
        var prefix: [UInt8] = []
        _ = collectPrefix(into: &prefix, limit: limit)
        return prefix
    }

    /// Appends this node's fixed leading bytes; returns whether the whole node was fixed text,
    /// so the caller may continue with what follows.
    private func collectPrefix(into prefix: inout [UInt8], limit: Int) -> Bool {
        switch self {
        case .empty, .anchor, .look:
            return true
        case let .literal(bytes, caseInsensitive):
            guard !caseInsensitive || !bytes.contains(where: { foldASCII($0) &- 97 < 26 }) else { return false }
            let room = limit - prefix.count
            prefix += bytes.prefix(room)
            return bytes.count <= room
        case let .sequence(items):
            for item in items where !item.collectPrefix(into: &prefix, limit: limit) { return false }
            return true
        case let .group(_, inner), let .atomic(inner):
            return inner.collectPrefix(into: &prefix, limit: limit)
        case let .repeated(inner, min, max, _) where min >= 1:
            let complete = inner.collectPrefix(into: &prefix, limit: limit)
            return complete && min == max && min == 1
        default:
            return false
        }
    }

    var usesDelimiter: Bool {
        switch self {
        case .delimiter: return true
        case .empty, .literal, .set, .any, .anchor, .backreference: return false
        case let .sequence(items), let .alternation(items): return items.contains(where: \.usesDelimiter)
        case let .repeated(node, _, _, _), let .group(_, node), let .atomic(node), let .look(node, _, _):
            return node.usesDelimiter
        }
    }
}
