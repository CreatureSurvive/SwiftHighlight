#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The line scanner: runs a language's states over UTF-8 lines, appending tokens.
///
/// Not thread-safe; each call to a public tokenizing API uses its own instance. The scan loop
/// works on a local `Context` of raw pointers into the current language's tables; the frame
/// stack keeps those languages alive.
final class Tokenizer {
    /// Deepest state stack allowed; pushes beyond it are ignored so hostile input cannot grow
    /// memory without bound.
    static let maxDepth = 128
    /// Matcher steps allowed per byte of a line (with a floor for short lines). Past it, the
    /// rest of the line is left in the current state's scope.
    static let stepsPerByte = 128
    static let minimumSteps = 50_000

    private let matcher = Matcher()
    // Confined to one thread; see `Matcher`.
    @exclusivity(unchecked) private(set) var frames: [Frame] {
        didSet { cachedContext = nil }
    }

    private let resolve: (String) -> Language?
    @exclusivity(unchecked) private var resolved: [String: Language] = [:]
    @exclusivity(unchecked) private var cachedContext: Context?

    // Scratch for painting capture scopes.
    @exclusivity(unchecked) private var intervals: [(start: Int, end: Int, scope: UInt32)] = []
    @exclusivity(unchecked) private var boundaries: [Int] = []

    init(state: LineState, resolve: @escaping (String) -> Language?) {
        frames = state.frames
        self.resolve = resolve
    }

    var lineState: LineState { LineState(frames: frames) }

    func reset(to state: LineState) {
        frames = state.frames
    }

    /// Everything the scan loop needs about the top of the stack.
    private struct Context {
        var program: ProgramView
        var states: UnsafeMutablePointer<CompiledState>
        var rules: UnsafeMutablePointer<CompiledRule>
        var captures: UnsafeMutablePointer<(Int32, UInt32)>
        var dispatchOffsets: UnsafeMutablePointer<Int32>
        var dispatchRules: UnsafeMutablePointer<Int32>
        var prefixes: UnsafeMutablePointer<UInt8>
        var byteClasses: UnsafeMutablePointer<UInt8>
        var wordMap: ByteMap
        var state: CompiledState
        var top: Int
        /// Index of the innermost embedded language's root frame, or -1.
        var embedIndex: Int
        var embedProgram: ProgramView?
        var embedRule: CompiledRule?
        var embedCaptures: UnsafeMutablePointer<(Int32, UInt32)>?
        var embedFirst: ByteMap
    }

    private func context() -> Context {
        if let cachedContext { return cachedContext }
        let context = makeContext()
        cachedContext = context
        return context
    }

    private func makeContext() -> Context {
        let top = frames.count - 1
        let frame = frames[top]
        let tables = frame.language.tables
        var context = Context(
            program: frame.language.program.view, states: tables.states.baseAddress!, rules: tables.rules.baseAddress!,
            captures: tables.captures.baseAddress!, dispatchOffsets: tables.dispatchOffsets.baseAddress!,
            dispatchRules: tables.dispatchRules.baseAddress!, prefixes: tables.prefixes.baseAddress!,
            byteClasses: tables.byteClasses.baseAddress! + Int(tables.states[Int(frame.state)].classBase),
            wordMap: tables.wordMap,
            state: tables.states[Int(frame.state)], top: top, embedIndex: -1, embedProgram: nil, embedRule: nil,
            embedCaptures: nil, embedFirst: ByteMap())
        var index = top
        while index > 0 {
            let candidate = frames[index]
            if candidate.embedRule >= 0, let parent = candidate.embedParent {
                let rule = parent.tables.rules[Int(candidate.embedRule)]
                context.embedIndex = index
                context.embedProgram = parent.program.view
                context.embedRule = rule
                context.embedCaptures = parent.tables.captures.baseAddress!
                context.embedFirst = rule.endFirst
                break
            }
            index -= 1
        }
        return context
    }

    // MARK: Documents

    /// Tokenizes a whole buffer, line by line. Token offsets are relative to `base`.
    func tokenize(_ base: UnsafePointer<UInt8>, count: Int, into tokens: inout [Token]) {
        var lineStart = 0
        while lineStart <= count {
            let remaining = count - lineStart
            let newline = remaining > 0 ? memchr(base + lineStart, 0x0A, remaining) : nil
            let lineEnd = newline.map { base.distance(to: $0.assumingMemoryBound(to: UInt8.self)) } ?? count
            var contentEnd = lineEnd
            if contentEnd > lineStart, base[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            tokenizeLine(base, start: lineStart, end: contentEnd, into: &tokens)
            if newline == nil { break }
            lineStart = lineEnd + 1
        }
    }

    // MARK: Lines

    /// Tokenizes `[start, end)` — one line without its terminator — continuing from the current
    /// state, and leaves the state the next line starts in.
    func tokenizeLine(_ base: UnsafePointer<UInt8>, start: Int, end: Int, into tokens: inout [Token]) {
        matcher.input = base
        matcher.lineStart = start
        matcher.lineEnd = end
        matcher.steps = max(Self.minimumSteps, (end - start) &* Self.stepsPerByte)

        var ctx = context()
        var delimiterOwner = -1
        var pos = start
        var zeroWidth = 0

        scanning: while pos < end {
            if matcher.exhausted {
                Self.emit(pos, end, ctx.state.scope, into: &tokens)
                break
            }
            let byte = base[pos]

            // The innermost embed's end pattern wins over anything inside it.
            if ctx.embedIndex >= 0, ctx.embedFirst.contains(byte), zeroWidth < 8,
               let rule = ctx.embedRule, let embedProgram = ctx.embedProgram {
                if delimiterOwner != ctx.embedIndex {
                    matcher.delimiter = frames[ctx.embedIndex].delimiter
                    delimiterOwner = ctx.embedIndex
                }
                let matchEnd = matcher.match(embedProgram, pc: rule.endPC, at: pos, slotCount: Int(rule.endSlotCount))
                if matchEnd >= 0 {
                    let outer = frames[ctx.embedIndex - 1]
                    let outerScope = outer.language.tables.states[Int(outer.state)].scope
                    emitMatch(pos, matchEnd, base: rule.endScope != 0 ? rule.endScope : outerScope,
                              captures: ctx.embedCaptures!, start: rule.endCaptureStart, count: rule.endCaptureCount,
                              into: &tokens)
                    frames.removeSubrange(ctx.embedIndex...)
                    ctx = context()
                    delimiterOwner = -1
                    zeroWidth = matchEnd == pos ? zeroWidth + 1 : 0
                    pos = matchEnd
                    continue
                }
            }

            if ctx.state.starts.contains(byte) {
                let dispatch = ctx.dispatchOffsets + Int(ctx.state.dispatchBase) + Int(byte)
                var candidate = Int(dispatch[0])
                let last = Int(dispatch[1])
                while candidate < last {
                    let ruleIndex = ctx.dispatchRules[candidate]
                    candidate &+= 1
                    let rule = ctx.rules + Int(ruleIndex)
                    let prefixLength = Int(rule.pointee.prefixLength)
                    if prefixLength > 0,
                       end &- pos < prefixLength
                        || memcmp(base + pos, ctx.prefixes + Int(rule.pointee.prefixOffset), prefixLength) != 0 {
                        continue
                    }
                    if delimiterOwner != ctx.top {
                        matcher.delimiter = frames[ctx.top].delimiter
                        delimiterOwner = ctx.top
                    }
                    let matchEnd = matcher.match(ctx.program, pc: rule.pointee.pc, at: pos,
                                                 slotCount: Int(rule.pointee.slotCount))
                    if matchEnd < 0 {
                        if matcher.exhausted { continue scanning }
                        continue
                    }
                    if matchEnd == pos {
                        if rule.pointee.action == .none || zeroWidth >= 8 { continue }
                        zeroWidth += 1
                    } else {
                        zeroWidth = 0
                    }
                    if rule.pointee.action == .none {
                        let scope = rule.pointee.isWords ? matcher.wordScope : rule.pointee.scope
                        if rule.pointee.captureCount == 0 {
                            Self.emit(pos, matchEnd, scope != 0 ? scope : ctx.state.scope, into: &tokens)
                        } else {
                            emitMatch(pos, matchEnd, base: scope != 0 ? scope : ctx.state.scope, captures: ctx.captures,
                                      start: rule.pointee.captureStart, count: rule.pointee.captureCount, into: &tokens)
                        }
                    } else {
                        apply(rule.pointee, index: ruleIndex, context: ctx, start: pos, end: matchEnd, into: &tokens)
                        ctx = context()
                        delimiterOwner = -1
                    }
                    pos = matchEnd
                    continue scanning
                }
            }

            // Nothing matched: skip ahead to the next byte where some rule could start, a whole
            // word at a time, in the current state's scope. Every non-ASCII byte is a word byte,
            // so skipping word bytes one at a time never splits a scalar.
            let classes = ctx.byteClasses
            var next = pos
            if ctx.embedIndex < 0 {
                if ctx.state.starts.isEmpty {
                    next = end
                } else {
                    repeat {
                        if classes[Int(base[next])] & ByteClass.word != 0 {
                            next &+= 1
                            while next < end, classes[Int(base[next])] & ByteClass.word != 0 { next &+= 1 }
                        } else {
                            next &+= 1
                        }
                    } while next < end && classes[Int(base[next])] & ByteClass.ruleStart == 0
                }
            } else {
                let embedFirst = ctx.embedFirst
                repeat {
                    if classes[Int(base[next])] & ByteClass.word != 0 {
                        next &+= 1
                        while next < end, classes[Int(base[next])] & ByteClass.word != 0 { next &+= 1 }
                    } else {
                        next &+= 1
                    }
                } while next < end && classes[Int(base[next])] & ByteClass.ruleStart == 0
                    && !embedFirst.contains(base[next])
            }
            Self.emit(pos, next, ctx.state.scope, into: &tokens)
            zeroWidth = 0
            pos = next
        }

        // Single-line states end with the line.
        while frames.count > 1 {
            let top = frames[frames.count - 1]
            guard top.embedRule < 0, top.language.tables.states[Int(top.state)].popAtLineEnd else { break }
            frames.removeLast()
        }
    }

    // MARK: Actions

    private func apply(_ rule: CompiledRule, index: Int32, context ctx: Context, start: Int, end: Int,
                       into tokens: inout [Token]) {
        let current = ctx.top
        let wordScope = rule.isWords ? matcher.wordScope : 0
        let ruleScope = wordScope != 0 ? wordScope : rule.scope
        switch rule.action {
        case .none:
            emitMatch(start, end, base: ruleScope != 0 ? ruleScope : ctx.state.scope, captures: ctx.captures,
                      start: rule.captureStart, count: rule.captureCount, into: &tokens)

        case .push:
            let target = ctx.states[Int(rule.target)]
            emitMatch(start, end, base: ruleScope != 0 ? ruleScope : target.scope, captures: ctx.captures,
                      start: rule.captureStart, count: rule.captureCount, into: &tokens)
            guard frames.count < Self.maxDepth else { return }
            frames.append(Frame(language: frames[current].language, state: rule.target, embedParent: nil,
                                embedRule: -1, delimiter: capturedDelimiter(rule)))

        case .set:
            let target = ctx.states[Int(rule.target)]
            emitMatch(start, end, base: ruleScope != 0 ? ruleScope : target.scope, captures: ctx.captures,
                      start: rule.captureStart, count: rule.captureCount, into: &tokens)
            frames[current].state = rule.target
            if rule.delimiterGroup > 0 { frames[current].delimiter = capturedDelimiter(rule) }

        case .pop:
            emitMatch(start, end, base: ruleScope != 0 ? ruleScope : ctx.state.scope, captures: ctx.captures,
                      start: rule.captureStart, count: rule.captureCount, into: &tokens)
            // The document root and an embedded language's root are left only by their own end.
            guard current > 0, frames[current].embedRule < 0 else { return }
            frames.removeLast()

        case .embed:
            emitMatch(start, end, base: ruleScope != 0 ? ruleScope : ctx.state.scope, captures: ctx.captures,
                      start: rule.captureStart, count: rule.captureCount, into: &tokens)
            guard frames.count < Self.maxDepth else { return }
            let language = frames[current].language
            let name = rule.embedName >= 0
                ? language.tables.embedNames[Int(rule.embedName)]
                : capturedText(group: Int(-rule.embedName))
            frames.append(Frame(language: lookup(name), state: 0, embedParent: language, embedRule: index,
                                delimiter: capturedDelimiter(rule)))
        }
    }

    private func lookup(_ name: String) -> Language {
        if let cached = resolved[name] { return cached }
        let language = resolve(name) ?? Language.plainText
        resolved[name] = language
        return language
    }

    private func capturedDelimiter(_ rule: CompiledRule) -> [UInt8] {
        guard rule.delimiterGroup > 0 else { return [] }
        let lower = matcher.slots[Int(rule.delimiterGroup) * 2]
        let upper = matcher.slots[Int(rule.delimiterGroup) * 2 + 1]
        guard lower >= 0, upper >= lower else { return [] }
        return Array(UnsafeBufferPointer(start: matcher.input + lower, count: upper - lower))
    }

    private func capturedText(group: Int) -> String {
        let lower = matcher.slots[group * 2]
        let upper = matcher.slots[group * 2 + 1]
        guard lower >= 0, upper > lower else { return "" }
        return String(decoding: UnsafeBufferPointer(start: matcher.input + lower, count: upper - lower), as: UTF8.self)
    }

    // MARK: Emitting

    @inline(__always)
    private static func emit(_ start: Int, _ end: Int, _ scope: UInt32, into tokens: inout [Token]) {
        guard scope != 0, end > start else { return }
        let count = tokens.count
        if count > 0, tokens[count - 1].range.upperBound == start, tokens[count - 1].scope.id == scope {
            tokens[count - 1].range = tokens[count - 1].range.lowerBound..<end
        } else {
            tokens.append(Token(range: start..<end, scope: Scope(id: scope)))
        }
    }

    /// Emits a match over `[start, end)` in `base`, with capture groups painted on top. Later
    /// (inner) groups win where groups overlap.
    private func emitMatch(_ start: Int, _ end: Int, base: UInt32, captures: UnsafeMutablePointer<(Int32, UInt32)>,
                           start captureStart: Int32, count: Int32, into tokens: inout [Token]) {
        guard count > 0 else {
            Self.emit(start, end, base, into: &tokens)
            return
        }
        intervals.removeAll(keepingCapacity: true)
        boundaries.removeAll(keepingCapacity: true)
        intervals.append((start, end, base))
        boundaries.append(start)
        boundaries.append(end)
        for offset in 0..<Int(count) {
            let (group, scope) = captures[Int(captureStart) + offset]
            let lower = matcher.slots[Int(group) * 2]
            let upper = matcher.slots[Int(group) * 2 + 1]
            guard lower >= start, upper > lower, upper <= end else { continue }
            intervals.append((lower, upper, scope))
            boundaries.append(lower)
            boundaries.append(upper)
        }
        boundaries.sort()
        var previous = boundaries[0]
        for boundary in boundaries.dropFirst() where boundary > previous {
            var scope: UInt32 = 0
            var interval = intervals.count - 1
            while interval >= 0 {
                if intervals[interval].start <= previous, intervals[interval].end >= boundary {
                    scope = intervals[interval].scope
                    break
                }
                interval -= 1
            }
            Self.emit(previous, boundary, scope, into: &tokens)
            previous = boundary
        }
    }
}
