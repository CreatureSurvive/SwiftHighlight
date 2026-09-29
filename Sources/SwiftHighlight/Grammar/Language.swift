import Foundation

/// A compiled, immutable, thread-safe grammar, ready to tokenize.
///
/// Compiling does all the expensive work once — parsing patterns to bytecode, flattening
/// includes, building a first-byte dispatch table for every state — so tokenizing only ever runs
/// the rules that can possibly match the next byte. Built-in languages are compiled lazily on
/// first use and cached; keep your own `Language` values around rather than recompiling.
public final class Language: Hashable, Sendable, CustomStringConvertible {
    /// The definition this language was compiled from.
    public let grammar: Grammar

    public var name: String { grammar.name }
    public var id: String { grammar.id }
    public var description: String { "Language(\(grammar.id))" }

    let program: Program
    let tables: LanguageTables

    /// Compiles `grammar`, validating every pattern and state reference.
    public init(_ grammar: Grammar) throws(GrammarError) {
        self.grammar = grammar
        var compiler = GrammarCompiler(grammar: grammar)
        let result = try compiler.compile()
        program = result.program
        tables = result.tables
    }

    public static func == (lhs: Language, rhs: Language) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// The index of a state by name, for building a ``LineState`` by hand.
    func stateIndex(_ name: String) -> Int32? {
        tables.stateNames.firstIndex(of: name).map(Int32.init)
    }

    /// Whether `line` (a file's first line) matches the grammar's `firstLinePattern`.
    func matchesFirstLine(_ line: String) -> Bool {
        guard tables.firstLinePC >= 0 else { return false }
        var line = line
        return line.withUTF8 { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let matcher = Matcher()
            matcher.input = base
            matcher.lineStart = 0
            matcher.lineEnd = buffer.count
            matcher.steps = 100_000
            return matcher.match(program.view, pc: tables.firstLinePC, at: 0, slotCount: tables.firstLineSlots) >= 0
        }
    }
}

/// A grammar that failed to compile.
public struct GrammarError: Error, CustomStringConvertible, Sendable, Equatable {
    /// The grammar's name.
    public var grammar: String
    /// The state holding the bad rule, if any.
    public var state: String?
    /// The rule's index within its state (after includes are spliced in), if any.
    public var rule: Int?
    public var message: String
    /// The underlying pattern error, when the problem is a pattern.
    public var patternError: PatternError?

    public var description: String {
        var location = "grammar \(grammar.debugDescription)"
        if let state { location += ", state \(state.debugDescription)" }
        if let rule { location += ", rule \(rule)" }
        return "\(message) (\(location))"
    }
}

// MARK: - Compiled form

enum RuleAction: UInt8 {
    case none, push, pop, set, embed
}

/// A compiled rule. Plain data: the tokenizer reads these through raw pointers.
struct CompiledRule {
    var pc: Int32
    var slotCount: Int32
    var scope: UInt32
    var captureStart: Int32
    var captureCount: Int32
    var action: RuleAction
    /// Target state for push/set.
    var target: Int32
    /// Capture group whose text becomes the pushed frame's delimiter; -1 for none.
    var delimiterGroup: Int32
    /// For embed: index into `embedNames`, or -(group) when the name comes from a capture.
    var embedName: Int32
    var endPC: Int32
    var endSlotCount: Int32
    var endScope: UInt32
    var endCaptureStart: Int32
    var endCaptureCount: Int32
    var endFirst: ByteMap
    /// A keyword rule: its scope is the matched word's, from the keyword table.
    var isWords: Bool
    /// Bytes every match starts with (offset and length in `prefixes`); checked before running
    /// the pattern. Length 0 when fewer than two bytes are known.
    var prefixOffset: Int32 = 0
    var prefixLength: Int32 = 0
}

struct CompiledState {
    var scope: UInt32
    var popAtLineEnd: Bool
    /// Offset of this state's 257-entry dispatch index in `dispatchOffsets`.
    var dispatchBase: Int32
    /// Bytes at which at least one rule of this state can start.
    var starts: ByteMap
    /// Offset of this state's 256-entry byte class table in `byteClasses`.
    var classBase: Int32
}

/// Per-state byte classes for the skip loop.
enum ByteClass {
    /// Some rule of the state can start at this byte.
    static let ruleStart: UInt8 = 1
    /// The byte belongs to a word (every non-ASCII byte does).
    static let word: UInt8 = 2
}

/// Immutable lookup tables of one language, as raw buffers.
final class LanguageTables: @unchecked Sendable {
    let states: UnsafeMutableBufferPointer<CompiledState>
    let rules: UnsafeMutableBufferPointer<CompiledRule>
    /// (group, scope) pairs referenced by rules.
    let captures: UnsafeMutableBufferPointer<(Int32, UInt32)>
    /// Per state, 257 offsets into `dispatchRules`: rules for byte b are
    /// `dispatchRules[dispatchOffsets[base + b] ..< dispatchOffsets[base + b + 1]]`, in rule order.
    let dispatchOffsets: UnsafeMutableBufferPointer<Int32>
    let dispatchRules: UnsafeMutableBufferPointer<Int32>
    let prefixes: UnsafeMutableBufferPointer<UInt8>
    let byteClasses: UnsafeMutableBufferPointer<UInt8>
    let embedNames: [String]
    let stateNames: [String]
    /// Characters of a word: unmatched text is skipped a word at a time.
    let wordMap: ByteMap
    let firstLinePC: Int32
    let firstLineSlots: Int

    init(states: [CompiledState], rules: [CompiledRule], captures: [(Int32, UInt32)], dispatchOffsets: [Int32],
         dispatchRules: [Int32], prefixes: [UInt8], byteClasses: [UInt8], embedNames: [String], stateNames: [String],
         wordMap: ByteMap, firstLinePC: Int32, firstLineSlots: Int) {
        self.prefixes = Self.freeze(prefixes)
        self.byteClasses = Self.freeze(byteClasses)
        self.states = Self.freeze(states)
        self.rules = Self.freeze(rules)
        self.captures = Self.freeze(captures)
        self.dispatchOffsets = Self.freeze(dispatchOffsets)
        self.dispatchRules = Self.freeze(dispatchRules)
        self.embedNames = embedNames
        self.stateNames = stateNames
        self.wordMap = wordMap
        self.firstLinePC = firstLinePC
        self.firstLineSlots = firstLineSlots
    }

    deinit {
        states.deallocate()
        rules.deallocate()
        captures.deallocate()
        dispatchOffsets.deallocate()
        dispatchRules.deallocate()
        prefixes.deallocate()
        byteClasses.deallocate()
    }

    private static func freeze<T>(_ array: [T]) -> UnsafeMutableBufferPointer<T> {
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: max(array.count, 1))
        _ = buffer.initialize(from: array)
        return buffer
    }
}

// MARK: - Compiler

struct GrammarCompiler {
    let grammar: Grammar
    private var builder = ProgramBuilder()
    private var stateNames: [String] = []
    private var stateIndex: [String: Int32] = [:]
    private var rules: [CompiledRule] = []
    private var ruleFirst: [ByteMap] = []
    private var ruleCache: [Rule: Int32] = [:]
    private var captures: [(Int32, UInt32)] = []
    private var embedNames: [String] = []
    private var prefixes: [UInt8] = []
    private var identifier: PatternNode = .empty

    init(grammar: Grammar) {
        self.grammar = grammar
    }

    private func failure(_ message: String, state: String? = nil, rule: Int? = nil,
                         pattern: PatternError? = nil) -> GrammarError {
        GrammarError(grammar: grammar.name, state: state, rule: rule, message: message, patternError: pattern)
    }

    mutating func compile() throws(GrammarError) -> (program: Program, tables: LanguageTables) {
        guard grammar.states["root"] != nil else { throw failure("Grammar has no \"root\" state") }
        stateNames = ["root"] + grammar.states.keys.filter { $0 != "root" }.sorted()
        for (index, name) in stateNames.enumerated() { stateIndex[name] = Int32(index) }

        // Word characters and identifiers.
        var wordSet = ByteSet.word
        if let characters = grammar.wordCharacters {
            let node: PatternNode
            do {
                node = try PatternParser.parse("[\(characters)]").node
            } catch {
                throw failure("Invalid wordCharacters: \(error.message)", pattern: error)
            }
            guard case let .set(set) = node else { throw failure("wordCharacters must be a class body") }
            wordSet = set
            wordSet.nonASCII = true
        }
        let identifierSource = grammar.identifierPattern
            ?? (grammar.wordCharacters.map { "[\($0)]+" } ?? #"[A-Za-z_]\w*"#)
        do {
            identifier = try PatternParser.parse(identifierSource).node
        } catch {
            throw failure("Invalid identifierPattern: \(error.message)", pattern: error)
        }

        var states: [CompiledState] = []
        var byteClasses: [UInt8] = []
        var dispatchOffsets: [Int32] = []
        var dispatchRules: [Int32] = []

        for name in stateNames {
            let state = grammar.states[name]!
            var visiting: Set<String> = [name]
            let flattened = try flatten(state.rules, in: name, visiting: &visiting)
            var ruleIndices: [Int32] = []
            var position = 0
            while position < flattened.count {
                // Consecutive plain keyword rules share one identifier scan and one hash lookup.
                var run = position
                while run < flattened.count, Self.isPlainWords(flattened[run]),
                      flattened[run].caseInsensitive == flattened[position].caseInsensitive {
                    run += 1
                }
                if run - position > 1 {
                    ruleIndices.append(try compileWordsRun(Array(flattened[position..<run]), state: name, position: position))
                    position = run
                    continue
                }
                ruleIndices.append(try compileRule(flattened[position], state: name, position: position))
                position += 1
            }

            let base = Int32(dispatchOffsets.count)
            var starts = ByteMap()
            for byte in 0...255 {
                dispatchOffsets.append(Int32(dispatchRules.count))
                for index in ruleIndices where ruleFirst[Int(index)].contains(UInt8(byte)) {
                    dispatchRules.append(index)
                    starts.insert(UInt8(byte))
                }
            }
            dispatchOffsets.append(Int32(dispatchRules.count))
            let classBase = Int32(byteClasses.count)
            let wordMap = ByteMap(wordSet)
            for byte in 0...255 {
                var flags: UInt8 = 0
                if starts.contains(UInt8(byte)) { flags |= ByteClass.ruleStart }
                if wordMap.contains(UInt8(byte)) { flags |= ByteClass.word }
                byteClasses.append(flags)
            }
            states.append(CompiledState(scope: state.scope?.id ?? 0, popAtLineEnd: state.popAtLineEnd,
                                        dispatchBase: base, starts: starts, classBase: classBase))
        }

        var firstLinePC: Int32 = -1
        var firstLineSlots = 0
        if let pattern = grammar.firstLinePattern {
            let compiled = try compilePattern(pattern, state: nil, position: nil)
            firstLinePC = compiled.pc
            firstLineSlots = Int(compiled.slots)
        }

        let tables = LanguageTables(states: states, rules: rules, captures: captures, dispatchOffsets: dispatchOffsets,
                                    dispatchRules: dispatchRules, prefixes: prefixes, byteClasses: byteClasses,
                                    embedNames: embedNames, stateNames: stateNames,
                                    wordMap: ByteMap(wordSet), firstLinePC: firstLinePC, firstLineSlots: firstLineSlots)
        return (Program(builder: builder), tables)
    }

    private func flatten(_ rules: [Rule], in state: String, visiting: inout Set<String>) throws(GrammarError) -> [Rule] {
        var result: [Rule] = []
        for rule in rules {
            guard let include = rule.include else {
                result.append(rule)
                continue
            }
            guard let target = grammar.states[include] else {
                throw failure("Include of unknown state \(include.debugDescription)", state: state)
            }
            guard !visiting.contains(include) else {
                throw failure("Include cycle through \(include.debugDescription)", state: state)
            }
            visiting.insert(include)
            result += try flatten(target.rules, in: state, visiting: &visiting)
            visiting.remove(include)
        }
        return result
    }

    private mutating func compilePattern(_ pattern: String, state: String?, position: Int?) throws(GrammarError)
        -> (pc: Int32, slots: Int32, node: PatternNode, groups: Int) {
        do {
            let (node, groups) = try PatternParser.parse(pattern)
            var generator = CodeGenerator(builder: builder, groups: groups, pattern: pattern)
            let pc = generator.builder.nextPC
            try generator.generate(node)
            generator.builder.emit(Instruction(op: .match))
            builder = generator.builder
            return (pc, Int32(generator.nextHiddenSlot), node, groups)
        } catch {
            throw failure(error.message, state: state, rule: position, pattern: error)
        }
    }

    private static func isPlainWords(_ rule: Rule) -> Bool {
        rule.words != nil && rule.match == nil && rule.scope != nil && rule.push == nil && rule.set == nil
            && rule.pop != true && rule.embed == nil && rule.captures == nil && rule.delimiter == nil
    }

    private mutating func compileWordsRun(_ run: [Rule], state: String, position: Int) throws(GrammarError) -> Int32 {
        let groups = run.map { (words: $0.words ?? [], scope: $0.scope?.id ?? 0) }
        let pc = try compileWords(groups, caseInsensitive: run[0].caseInsensitive ?? false)
        let (map, nullable) = identifier.firstBytes
        let index = Int32(rules.count)
        rules.append(CompiledRule(pc: pc, slotCount: 2, scope: 0, captureStart: 0, captureCount: 0, action: .none,
                                  target: -1, delimiterGroup: -1, embedName: 0, endPC: -1, endSlotCount: 0,
                                  endScope: 0, endCaptureStart: 0, endCaptureCount: 0, endFirst: ByteMap(),
                                  isWords: true))
        ruleFirst.append(nullable ? .all : map)
        return index
    }

    private mutating func compileWords(_ groups: [(words: [String], scope: UInt32)], caseInsensitive: Bool) throws(GrammarError) -> Int32 {
        let table = builder.addKeywordTable(groups, caseInsensitive: caseInsensitive)
        var generator = CodeGenerator(builder: builder, groups: 0, pattern: "<identifier>")
        let pc = generator.builder.nextPC
        do {
            try generator.generate(.atomic(identifier))
        } catch {
            throw failure("Invalid identifierPattern: \(error.message)", pattern: error)
        }
        generator.builder.emit(Instruction(op: .words, flag: caseInsensitive ? 1 : 0, a: table))
        generator.builder.emit(Instruction(op: .match))
        builder = generator.builder
        return pc
    }

    private mutating func internCaptures(_ map: [Int: Scope]?, groups: Int, state: String, position: Int) throws(GrammarError)
        -> (start: Int32, count: Int32) {
        guard let map, !map.isEmpty else { return (0, 0) }
        let start = Int32(captures.count)
        for (group, scope) in map.sorted(by: { $0.key < $1.key }) {
            guard group >= 1, group <= groups else {
                throw failure("Capture \(group) does not exist in the pattern", state: state, rule: position)
            }
            captures.append((Int32(group), scope.id))
        }
        return (start, Int32(map.count))
    }

    private mutating func compileRule(_ rule: Rule, state: String, position: Int) throws(GrammarError) -> Int32 {
        if let cached = ruleCache[rule] { return cached }

        let actions = [rule.push != nil, rule.set != nil, rule.pop == true, rule.embed != nil].filter { $0 }.count
        guard actions <= 1 else {
            throw failure("A rule can only push, set, pop or embed — not several", state: state, rule: position)
        }

        var compiled = CompiledRule(pc: 0, slotCount: 2, scope: rule.scope?.id ?? 0, captureStart: 0, captureCount: 0,
                                    action: .none, target: -1, delimiterGroup: -1, embedName: 0, endPC: -1,
                                    endSlotCount: 0, endScope: rule.endScope?.id ?? 0, endCaptureStart: 0,
                                    endCaptureCount: 0, endFirst: ByteMap(), isWords: rule.words != nil)
        var first: ByteMap
        var groups = 0

        if let words = rule.words {
            guard rule.match == nil else {
                throw failure("A rule has either `match` or `words`, not both", state: state, rule: position)
            }
            guard !words.isEmpty else { throw failure("Empty `words` list", state: state, rule: position) }
            compiled.pc = try compileWords([(words, rule.scope?.id ?? 0)], caseInsensitive: rule.caseInsensitive ?? false)
            let (map, nullable) = identifier.firstBytes
            first = nullable ? .all : map
        } else if let pattern = rule.match {
            let result = try compilePattern(pattern, state: state, position: position)
            compiled.pc = result.pc
            compiled.slotCount = result.slots
            groups = result.groups
            let prefix = result.node.requiredPrefix()
            if prefix.count >= 2 {
                compiled.prefixOffset = Int32(prefixes.count)
                compiled.prefixLength = Int32(prefix.count)
                prefixes += prefix
            }
            let (map, nullable) = result.node.firstBytes
            first = nullable ? .all : map
        } else {
            throw failure("Rule has no `match`, `words` or `include`", state: state, rule: position)
        }

        (compiled.captureStart, compiled.captureCount) = try internCaptures(rule.captures, groups: groups, state: state,
                                                                           position: position)

        if let delimiter = rule.delimiter {
            guard delimiter >= 1, delimiter <= groups else {
                throw failure("Delimiter group \(delimiter) does not exist in the pattern", state: state, rule: position)
            }
            guard rule.push != nil || rule.set != nil || rule.embed != nil else {
                throw failure("`delimiter` needs push, set or embed", state: state, rule: position)
            }
            compiled.delimiterGroup = Int32(delimiter)
        }

        if let target = rule.push ?? rule.set {
            guard let index = stateIndex[target] else {
                throw failure("Unknown state \(target.debugDescription)", state: state, rule: position)
            }
            compiled.action = rule.push != nil ? .push : .set
            compiled.target = index
        } else if rule.pop == true {
            compiled.action = .pop
        } else if let embed = rule.embed {
            compiled.action = .embed
            if embed.count == 2, embed.first == "$", let group = Int(embed.dropFirst()), group >= 1 {
                guard group <= groups else {
                    throw failure("Embed group \(group) does not exist in the pattern", state: state, rule: position)
                }
                compiled.embedName = Int32(-group)
            } else {
                compiled.embedName = Int32(embedNames.count)
                embedNames.append(embed)
            }
            guard let end = rule.end else {
                throw failure("`embed` needs an `end` pattern", state: state, rule: position)
            }
            let result = try compilePattern(end, state: state, position: position)
            compiled.endPC = result.pc
            compiled.endSlotCount = result.slots
            let (map, nullable) = result.node.firstBytes
            compiled.endFirst = nullable ? .all : map
            (compiled.endCaptureStart, compiled.endCaptureCount) = try internCaptures(
                rule.endCaptures, groups: result.groups, state: state, position: position)
        } else if rule.end != nil {
            throw failure("`end` is only valid with `embed`", state: state, rule: position)
        }

        let index = Int32(rules.count)
        rules.append(compiled)
        ruleFirst.append(first)
        ruleCache[rule] = index
        return index
    }
}
