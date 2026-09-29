/// Bytecode for grammar patterns: a backtracking VM program in flat, trivially-copyable arrays,
/// so the matcher's inner loop does no reference counting and no bounds-checked collection work.
enum Opcode: UInt8 {
    /// Succeed. In a lookbehind body, only at the required end position.
    case match
    /// One byte equal to `a`.
    case byte
    /// `b` bytes from the literal pool at `a`; `flag` 1 compares ASCII case-insensitively.
    case literal
    /// One scalar from set `a`.
    case set
    /// One scalar of any kind.
    case any
    /// Scalars from set `a`, between `b` and `c` (-1: unbounded) of them; `flag` 0 greedy,
    /// 1 lazy, 2 possessive.
    case repeatSet
    /// Try `a`; on failure, `b`.
    case split
    /// Continue at `a`.
    case jump
    /// Record the position in capture slot `a`.
    case save
    /// Zero-width test of kind `flag` (see `AnchorKind`).
    case anchor
    /// Lookaround of the body at `a`, continuing at `b`. `flag` bit 0: negated, bit 1: behind.
    /// For lookbehind, `c` indexes the body's byte-length bounds.
    case look
    /// Match the body at `a` once, without backtracking into it, then continue at `b`.
    case atomic
    /// The text captured by group `a`.
    case backreference
    /// The delimiter captured when the enclosing state was entered.
    case delimiter
    /// Fail when the position has not moved since capture slot `a` was saved (empty-loop guard).
    case progress
    /// The text matched so far must be a word in keyword table `a`; `flag` 1 folds case.
    case words
}

enum AnchorKind: UInt8 {
    case lineStart, lineEnd, wordBoundary, notWordBoundary
}

struct Instruction {
    var op: Opcode
    var flag: UInt8 = 0
    var a: Int32 = 0
    var b: Int32 = 0
    var c: Int32 = 0
}

/// A keyword hash table: open addressing over FNV-1a, storing (offset, length) into the literal
/// pool. Lookups compare raw bytes and never allocate.
struct KeywordTableDescriptor {
    var slotOffset: Int32
    var mask: Int32
    var caseInsensitive: Bool
}

/// Immutable compiled bytecode shared by every rule in one grammar.
final class Program: @unchecked Sendable {
    let instructions: UnsafeMutableBufferPointer<Instruction>
    let sets: UnsafeMutableBufferPointer<ByteSet>
    let literals: UnsafeMutableBufferPointer<UInt8>
    let lookbehindBounds: UnsafeMutableBufferPointer<(Int32, Int32)>
    let keywordTables: UnsafeMutableBufferPointer<KeywordTableDescriptor>
    /// Keyword slots: -1 for empty, else an index into `keywordEntries`.
    let keywordSlots: UnsafeMutableBufferPointer<Int32>
    /// Keyword entries: offset and length into `literals`, and the word's scope.
    let keywordEntries: UnsafeMutableBufferPointer<KeywordEntry>

    /// The same tables as raw pointers, for the matcher's inner loop.
    let view: ProgramView

    init(builder: ProgramBuilder) {
        instructions = Self.freeze(builder.instructions)
        sets = Self.freeze(builder.sets)
        literals = Self.freeze(builder.literals)
        lookbehindBounds = Self.freeze(builder.lookbehindBounds)
        keywordTables = Self.freeze(builder.keywordTables)
        keywordSlots = Self.freeze(builder.keywordSlots)
        keywordEntries = Self.freeze(builder.keywordEntries)
        view = ProgramView(instructions: instructions.baseAddress!, sets: sets.baseAddress!,
                           literals: literals.baseAddress!, lookbehindBounds: lookbehindBounds.baseAddress!,
                           keywordTables: keywordTables.baseAddress!, keywordSlots: keywordSlots.baseAddress!,
                           keywordEntries: keywordEntries.baseAddress!)
    }

    deinit {
        instructions.deallocate()
        sets.deallocate()
        literals.deallocate()
        lookbehindBounds.deallocate()
        keywordTables.deallocate()
        keywordSlots.deallocate()
        keywordEntries.deallocate()
    }

    private static func freeze<T>(_ array: [T]) -> UnsafeMutableBufferPointer<T> {
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: max(array.count, 1))
        _ = buffer.initialize(from: array)
        return buffer
    }
}

struct KeywordEntry {
    var offset: Int32
    var length: Int32
    var scope: UInt32
}

/// Raw pointers into a `Program`'s tables. Valid while the program is alive.
struct ProgramView {
    let instructions: UnsafeMutablePointer<Instruction>
    let sets: UnsafeMutablePointer<ByteSet>
    let literals: UnsafeMutablePointer<UInt8>
    let lookbehindBounds: UnsafeMutablePointer<(Int32, Int32)>
    let keywordTables: UnsafeMutablePointer<KeywordTableDescriptor>
    let keywordSlots: UnsafeMutablePointer<Int32>
    let keywordEntries: UnsafeMutablePointer<KeywordEntry>
}

@inline(__always)
func foldASCII(_ byte: UInt8) -> UInt8 {
    byte &- 65 < 26 ? byte | 0x20 : byte
}

@inline(__always)
func keywordHash(_ base: UnsafePointer<UInt8>, _ start: Int, _ end: Int, fold: Bool) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    var index = start
    while index < end {
        let byte = fold ? foldASCII(base[index]) : base[index]
        hash = (hash ^ UInt32(byte)) &* 16_777_619
        index &+= 1
    }
    return hash
}

/// Accumulates bytecode for one grammar, then freezes into a `Program`.
struct ProgramBuilder {
    var instructions: [Instruction] = []
    var sets: [ByteSet] = []
    var literals: [UInt8] = []
    var lookbehindBounds: [(Int32, Int32)] = []
    var keywordTables: [KeywordTableDescriptor] = []
    var keywordSlots: [Int32] = []
    var keywordEntries: [KeywordEntry] = []

    private var setIndex: [ByteSet: Int32] = [:]

    /// Instruction count limit per grammar; unrolled bounded repeats are the usual way to hit it.
    static let maxInstructions = 1 << 20

    mutating func internSet(_ set: ByteSet) -> Int32 {
        if let existing = setIndex[set] { return existing }
        let index = Int32(sets.count)
        sets.append(set)
        setIndex[set] = index
        return index
    }

    mutating func internLiteral(_ bytes: [UInt8]) -> Int32 {
        let offset = Int32(literals.count)
        literals.append(contentsOf: bytes)
        return offset
    }

    @discardableResult
    mutating func emit(_ instruction: Instruction) -> Int {
        instructions.append(instruction)
        return instructions.count - 1
    }

    var nextPC: Int32 { Int32(instructions.count) }

    /// Adds a table mapping each word to a scope. When a word appears in several groups, the
    /// first group wins, as the first of several rules would.
    mutating func addKeywordTable(_ groups: [(words: [String], scope: UInt32)], caseInsensitive: Bool) -> Int32 {
        var unique: [(String, UInt32)] = []
        var seen: Set<String> = []
        for group in groups {
            for raw in group.words {
                let word = caseInsensitive ? raw.lowercased() : raw
                if !word.isEmpty, seen.insert(word).inserted { unique.append((word, group.scope)) }
            }
        }
        var capacity = 8
        while capacity < unique.count * 2 { capacity <<= 1 }
        let slotOffset = Int32(keywordSlots.count)
        keywordSlots.append(contentsOf: repeatElement(-1, count: capacity))
        for (word, scope) in unique {
            let bytes = Array(word.utf8)
            let offset = internLiteral(bytes)
            let entry = Int32(keywordEntries.count)
            keywordEntries.append(KeywordEntry(offset: offset, length: Int32(bytes.count), scope: scope))
            let hash = bytes.withUnsafeBufferPointer { buffer in
                keywordHash(buffer.baseAddress!, 0, bytes.count, fold: caseInsensitive)
            }
            var slot = Int(hash) & (capacity - 1)
            while keywordSlots[Int(slotOffset) + slot] != -1 { slot = (slot + 1) & (capacity - 1) }
            keywordSlots[Int(slotOffset) + slot] = entry
        }
        let table = Int32(keywordTables.count)
        keywordTables.append(KeywordTableDescriptor(slotOffset: slotOffset, mask: Int32(capacity - 1),
                                                    caseInsensitive: caseInsensitive))
        return table
    }
}

/// Lowers a parsed pattern into bytecode.
struct CodeGenerator {
    var builder: ProgramBuilder
    /// First capture slot free for hidden (empty-loop guard) use.
    var nextHiddenSlot: Int
    let pattern: String

    init(builder: ProgramBuilder, groups: Int, pattern: String) {
        self.builder = builder
        nextHiddenSlot = (groups + 1) * 2
        self.pattern = pattern
    }

    mutating func generate(_ node: PatternNode) throws(PatternError) {
        guard builder.instructions.count < ProgramBuilder.maxInstructions else {
            throw PatternError(pattern: pattern, offset: 0, message: "Pattern compiles to too many instructions")
        }
        switch node {
        case .empty:
            break
        case let .literal(bytes, caseInsensitive):
            if bytes.count == 1, !caseInsensitive || !isASCIILetter(bytes[0]) {
                builder.emit(Instruction(op: .byte, a: Int32(bytes[0])))
            } else if !bytes.isEmpty {
                let stored = caseInsensitive ? bytes.map(foldASCII) : bytes
                let offset = builder.internLiteral(stored)
                builder.emit(Instruction(op: .literal, flag: caseInsensitive ? 1 : 0, a: offset, b: Int32(bytes.count)))
            }
        case let .set(set):
            builder.emit(Instruction(op: .set, a: builder.internSet(set)))
        case .any:
            builder.emit(Instruction(op: .any))
        case let .sequence(items):
            for item in items { try generate(item) }
        case let .alternation(branches):
            try generateAlternation(branches[...])
        case let .repeated(inner, min, max, mode):
            try generateRepeat(inner, min: min, max: max, mode: mode)
        case let .group(index, inner):
            if let index { builder.emit(Instruction(op: .save, a: Int32(index * 2))) }
            try generate(inner)
            if let index { builder.emit(Instruction(op: .save, a: Int32(index * 2 + 1))) }
        case let .atomic(inner):
            if let inline = possessiveForm(inner) {
                try generate(inline)
            } else {
                try generateSubroutine(.atomic, inner)
            }
        case let .look(inner, ahead, negated):
            var flag: UInt8 = negated ? 1 : 0
            var boundsIndex: Int32 = 0
            if !ahead {
                flag |= 2
                guard let bounds = inner.lengthBounds, bounds.max <= 255 else {
                    throw PatternError(pattern: pattern, offset: 0,
                                       message: "Lookbehind must have a bounded length of at most 255 bytes")
                }
                boundsIndex = Int32(builder.lookbehindBounds.count)
                builder.lookbehindBounds.append((Int32(bounds.min), Int32(bounds.max)))
            }
            try generateSubroutine(.look, inner, flag: flag, c: boundsIndex)
        case let .anchor(kind):
            let anchor: AnchorKind = switch kind {
            case .lineStart: .lineStart
            case .lineEnd: .lineEnd
            case .wordBoundary: .wordBoundary
            case .notWordBoundary: .notWordBoundary
            }
            builder.emit(Instruction(op: .anchor, flag: anchor.rawValue))
        case let .backreference(group):
            builder.emit(Instruction(op: .backreference, a: Int32(group)))
        case .delimiter:
            builder.emit(Instruction(op: .delimiter))
        }
    }

    private func isASCIILetter(_ byte: UInt8) -> Bool {
        foldASCII(byte) &- 97 < 26
    }

    /// `op` body at pc+1, terminated by `match`; the instruction's `b` is patched to the
    /// continuation once the body length is known.
    private mutating func generateSubroutine(_ op: Opcode, _ inner: PatternNode, flag: UInt8 = 0, c: Int32 = 0) throws(PatternError) {
        let head = builder.emit(Instruction(op: op, flag: flag, a: 0, b: 0, c: c))
        builder.instructions[head].a = Int32(head + 1)
        try generate(inner)
        builder.emit(Instruction(op: .match))
        builder.instructions[head].b = builder.nextPC
    }

    private mutating func generateAlternation(_ branches: ArraySlice<PatternNode>) throws(PatternError) {
        guard let first = branches.first else { return }
        if branches.count == 1 {
            try generate(first)
            return
        }
        let split = builder.emit(Instruction(op: .split))
        builder.instructions[split].a = builder.nextPC
        try generate(first)
        let jump = builder.emit(Instruction(op: .jump))
        builder.instructions[split].b = builder.nextPC
        try generateAlternation(branches.dropFirst())
        builder.instructions[jump].a = builder.nextPC
    }

    /// An equivalent of `atomic(node)` that needs no subroutine, when one exists: single scalars
    /// followed by at most one trailing repeat of a single scalar, which can then be possessive
    /// (nothing after it could make it give characters back). Identifier scans take this form.
    private func possessiveForm(_ node: PatternNode) -> PatternNode? {
        let items: [PatternNode]
        if case let .sequence(sequence) = node { items = sequence } else { items = [node] }
        guard let last = items.last else { return nil }
        for item in items.dropLast() {
            if case .repeated = item { return nil }
            guard scalarSet(item) != nil else { return nil }
            if case let .literal(bytes, _) = item, bytes.count > 1 { return nil }
        }
        switch last {
        case let .repeated(inner, min, max, _) where scalarSet(inner) != nil:
            return .sequence(Array(items.dropLast()) + [.repeated(inner, min: min, max: max, mode: .possessive)])
        default:
            return scalarSet(last) != nil ? node : nil
        }
    }

    /// The set a single-scalar node matches, when it is one; such repeats become one tight loop.
    private func scalarSet(_ node: PatternNode) -> ByteSet? {
        switch node {
        case let .set(set): return set
        case .any: return .all
        case let .literal(bytes, caseInsensitive) where bytes.count == 1 && bytes[0] < 0x80:
            var set = ByteSet()
            set.insert(bytes[0])
            return caseInsensitive ? set.caseFolded : set
        case let .group(nil, inner): return scalarSet(inner)
        default: return nil
        }
    }

    private mutating func generateRepeat(_ inner: PatternNode, min: Int, max: Int?, mode: PatternNode.RepeatMode) throws(PatternError) {
        if let set = scalarSet(inner) {
            let flag: UInt8 = switch mode {
            case .greedy: 0
            case .lazy: 1
            case .possessive: 2
            }
            builder.emit(Instruction(op: .repeatSet, flag: flag, a: builder.internSet(set),
                                     b: Int32(min), c: Int32(max ?? -1)))
            return
        }
        if mode == .possessive {
            try generateSubroutine(.atomic, .repeated(inner, min: min, max: max, mode: .greedy))
            return
        }
        for _ in 0..<min { try generate(inner) }
        let lazy = mode == .lazy
        if let max {
            // Nested optionals: x? (x? (x? …)) so each extra copy is only tried after the last.
            var exits: [Int] = []
            for _ in min..<max {
                let split = builder.emit(Instruction(op: .split))
                exits.append(split)
                if lazy {
                    builder.instructions[split].b = builder.nextPC
                } else {
                    builder.instructions[split].a = builder.nextPC
                }
                try generate(inner)
            }
            let end = builder.nextPC
            for split in exits {
                if lazy { builder.instructions[split].a = end } else { builder.instructions[split].b = end }
            }
            return
        }
        // Unbounded loop, with a progress guard when the body can match empty.
        let guardSlot: Int32? = inner.isNullable ? Int32(allocateHiddenSlot()) : nil
        let loop = builder.emit(Instruction(op: .split))
        let body = builder.nextPC
        if let guardSlot { builder.emit(Instruction(op: .save, a: guardSlot)) }
        try generate(inner)
        if let guardSlot { builder.emit(Instruction(op: .progress, a: guardSlot)) }
        builder.emit(Instruction(op: .jump, a: Int32(loop)))
        let exit = builder.nextPC
        builder.instructions[loop].a = lazy ? exit : body
        builder.instructions[loop].b = lazy ? body : exit
    }

    private mutating func allocateHiddenSlot() -> Int {
        defer { nextHiddenSlot += 1 }
        return nextHiddenSlot
    }
}
