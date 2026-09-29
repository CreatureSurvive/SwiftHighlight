/// Incremental highlighting for text that changes: editors and streamed output.
///
/// The session keeps the text, each line's tokens and each line's end state. An edit
/// re-tokenizes from the first changed line only until a line ends in the same state it did
/// before — past that point nothing can have changed — so typing in a large file costs about one
/// line of work, and appending streamed text re-tokenizes only the last line and what follows.
///
/// ```swift
/// let session = HighlightSession(language: .named("swift"))
/// for chunk in stream {
///     let changed = session.append(chunk)   // lines to redraw
///     render(session.highlightedCode)
/// }
/// ```
///
/// Not thread-safe: use a session from one thread or actor at a time.
public final class HighlightSession {
    public let language: Language
    public let registry: LanguageRegistry

    private var bytes: [UInt8] = []
    /// UTF-8 offset where each line starts. Always at least one line.
    private var lineStarts: [Int] = [0]
    /// The state each line ends in.
    private var endStates: [LineState]
    /// Each line's tokens, with offsets relative to the line start.
    private var lineTokens: [[Token]] = [[]]
    private let tokenizer: Tokenizer
    private let initialState: LineState

    public init(language: Language, text: String = "", registry: LanguageRegistry = .shared) {
        self.language = language
        self.registry = registry
        initialState = LineState(language: language)
        endStates = [initialState]
        tokenizer = Tokenizer(state: initialState, resolve: { registry.language(named: $0) })
        if !text.isEmpty { setText(text) }
    }

    // MARK: Reading

    /// The current text.
    public var text: String { String(decoding: bytes, as: UTF8.self) }

    /// The text's length in UTF-8 bytes.
    public var utf8Count: Int { bytes.count }

    public var lineCount: Int { lineStarts.count }

    /// UTF-8 range of line `index`, without its line break.
    public func lineRange(_ index: Int) -> Range<Int> {
        let start = lineStarts[index]
        var end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : bytes.count
        if end > start, bytes[end - 1] == 0x0D { end -= 1 }
        return start..<end
    }

    /// Tokens of line `index`, with offsets into the whole text.
    public func tokens(inLine index: Int) -> [Token] {
        let start = lineStarts[index]
        return lineTokens[index].map { Token(range: $0.range.lowerBound + start..<$0.range.upperBound + start, scope: $0.scope) }
    }

    /// Tokens of line `index`, with offsets relative to the start of the line.
    public func lineRelativeTokens(inLine index: Int) -> [Token] {
        lineTokens[index]
    }

    /// The state line `index` ends in.
    public func endState(ofLine index: Int) -> LineState {
        endStates[index]
    }

    /// All tokens, with offsets into the whole text.
    public var tokens: [Token] {
        var result: [Token] = []
        result.reserveCapacity(lineTokens.reduce(0) { $0 + $1.count })
        for (index, line) in lineTokens.enumerated() {
            let start = lineStarts[index]
            for token in line {
                result.append(Token(range: token.range.lowerBound + start..<token.range.upperBound + start, scope: token.scope))
            }
        }
        return result
    }

    /// The text and tokens, ready for a renderer.
    public var highlightedCode: HighlightedCode {
        HighlightedCode(source: text, language: language, tokens: tokens)
    }

    // MARK: Editing

    /// Replaces the whole text. Returns the range of lines to redraw (all of them).
    @discardableResult
    public func setText(_ text: String) -> Range<Int> {
        bytes = Array(text.utf8)
        lineStarts = [0]
        for (offset, byte) in bytes.enumerated() where byte == 0x0A { lineStarts.append(offset + 1) }
        endStates = Array(repeating: initialState, count: lineStarts.count)
        lineTokens = Array(repeating: [], count: lineStarts.count)
        tokenizer.reset(to: initialState)
        bytes.withUnsafeBufferPointer { buffer in
            for line in 0..<lineStarts.count { tokenize(line: line, in: buffer) }
        }
        return 0..<lineStarts.count
    }

    /// Appends text (streaming). Returns the range of lines to redraw.
    @discardableResult
    public func append(_ text: String) -> Range<Int> {
        replace(utf8Range: bytes.count..<bytes.count, with: text)
    }

    /// Replaces `range` of `currentText` — which must equal ``text`` — with `replacement`.
    @discardableResult
    public func replace(_ range: Range<String.Index>, in currentText: String, with replacement: String) -> Range<Int> {
        let utf8 = currentText.utf8
        let lower = utf8.distance(from: utf8.startIndex, to: range.lowerBound)
        let upper = lower + utf8.distance(from: range.lowerBound, to: range.upperBound)
        return replace(utf8Range: lower..<upper, with: replacement)
    }

    /// Replaces a UTF-8 byte range of the text. Returns the range of lines (in the new text)
    /// whose tokens changed; lines after it only moved.
    @discardableResult
    public func replace(utf8Range range: Range<Int>, with replacement: String) -> Range<Int> {
        precondition(range.lowerBound >= 0 && range.upperBound <= bytes.count, "Range outside the text")
        let firstLine = line(containing: range.lowerBound)
        let lastLine = line(containing: range.upperBound)
        let oldLineCount = lineStarts.count
        let oldRegionEndState = endStates[lastLine]
        // Offset of the newline ending `lastLine` (or the end of the text), before the edit.
        let oldRegionEnd = lastLine + 1 < oldLineCount ? lineStarts[lastLine + 1] - 1 : bytes.count

        let inserted = Array(replacement.utf8)
        let delta = inserted.count - range.count
        bytes.replaceSubrange(range, with: inserted)

        // New line starts inside the edited region.
        let regionStart = lineStarts[firstLine]
        let regionEnd = oldRegionEnd + delta
        var newStarts = [regionStart]
        var offset = regionStart
        while offset < regionEnd {
            if bytes[offset] == 0x0A { newStarts.append(offset + 1) }
            offset += 1
        }
        let tail = lineStarts[(lastLine + 1)...].map { $0 + delta }
        lineStarts.replaceSubrange(firstLine..., with: newStarts + tail)
        let placeholderStates = Array(repeating: initialState, count: newStarts.count)
        endStates.replaceSubrange(firstLine...lastLine, with: placeholderStates)
        lineTokens.replaceSubrange(firstLine...lastLine, with: Array(repeating: [], count: newStarts.count))

        // Re-tokenize the region, then onward until states converge.
        tokenizer.reset(to: firstLine > 0 ? endStates[firstLine - 1] : initialState)
        var line = firstLine
        let regionLast = firstLine + newStarts.count - 1
        bytes.withUnsafeBufferPointer { buffer in
            while line <= regionLast {
                tokenize(line: line, in: buffer)
                line += 1
            }
            if endStates[regionLast] == oldRegionEndState { return }
            while line < lineStarts.count {
                let previous = endStates[line]
                tokenize(line: line, in: buffer)
                line += 1
                if endStates[line - 1] == previous { break }
            }
        }
        return firstLine..<line
    }

    // MARK: Internals

    private func line(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Tokenizes one line continuing from the tokenizer's current state.
    private func tokenize(line: Int, in buffer: UnsafeBufferPointer<UInt8>) {
        let range = lineRange(line)
        var tokens: [Token] = []
        if let base = buffer.baseAddress {
            tokenizer.tokenizeLine(base + range.lowerBound, start: 0, end: range.count, into: &tokens)
        } else {
            let empty: [UInt8] = [0]
            empty.withUnsafeBufferPointer { tokenizer.tokenizeLine($0.baseAddress!, start: 0, end: 0, into: &tokens) }
        }
        lineTokens[line] = tokens
        endStates[line] = tokenizer.lineState
    }
}

/// Tokenizes a document one line at a time, carrying state between lines — for callers that
/// manage their own lines (a text view's layout pass, a log viewer).
public final class LineTokenizer {
    public let language: Language
    private let tokenizer: Tokenizer

    /// The state the next line starts in.
    public var state: LineState {
        get { tokenizer.lineState }
        set { tokenizer.reset(to: newValue) }
    }

    public init(language: Language, state: LineState? = nil, registry: LanguageRegistry = .shared) {
        self.language = language
        tokenizer = Tokenizer(state: state ?? LineState(language: language), resolve: { registry.language(named: $0) })
    }

    /// Tokenizes `line` (a trailing line break is ignored) and advances ``state``. Token
    /// offsets are UTF-8 offsets into `line`.
    public func tokenize(_ line: some StringProtocol) -> [Token] {
        var text = String(line)
        return text.withUTF8 { buffer in
            var end = buffer.count
            if end > 0, buffer[end - 1] == 0x0A { end -= 1 }
            if end > 0, buffer[end - 1] == 0x0D { end -= 1 }
            var tokens: [Token] = []
            if let base = buffer.baseAddress {
                tokenizer.tokenizeLine(base, start: 0, end: end, into: &tokens)
            } else {
                let empty: [UInt8] = [0]
                empty.withUnsafeBufferPointer { tokenizer.tokenizeLine($0.baseAddress!, start: 0, end: 0, into: &tokens) }
            }
            return tokens
        }
    }
}
