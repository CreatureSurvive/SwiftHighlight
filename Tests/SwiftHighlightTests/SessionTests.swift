@testable import SwiftHighlight
import Testing

@Suite("Incremental sessions")
struct SessionTests {
    /// A deterministic generator so failures reproduce.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let swiftSource = """
    import Foundation

    /* A block
       comment */
    struct Item: Codable {
        let name: String // trailing
        var text = \"\"\"
            multi \\(name) line
            \"\"\"
        func render() -> String { "value: \\(name.count) \\n" }
    }
    """

    @Test func sessionMatchesFullTokenization() {
        let swift = builtin("swift")
        let session = HighlightSession(language: swift, text: Self.swiftSource)
        #expect(session.tokens == swift.tokenize(Self.swiftSource))
        #expect(session.text == Self.swiftSource)
        #expect(session.lineCount == Self.swiftSource.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    @Test(arguments: ["swift", "markdown", "html", "python", "shell"])
    func randomEditsStayConsistent(_ id: String) {
        let language = builtin(id)
        let fragments = ["\"", "\"\"\"", "/*", "*/", "\n", "\\(", ")", "{", "}", "`", "```swift\n", "```", "#", "'",
                         "<script>", "</script>", "let x = 1", " ", "<<EOF\n", "EOF\n", "é", "😀", "\r\n", "'''"]
        var generator = SplitMix(state: UInt64(abs(id.hashValue % 1000)))
        var text = Self.swiftSource
        let session = HighlightSession(language: language, text: text)
        for _ in 0..<300 {
            let bytes = Array(text.utf8)
            // Pick scalar-aligned edit bounds.
            func boundary(_ value: Int) -> Int {
                var offset = min(value, bytes.count)
                while offset < bytes.count, bytes[offset] & 0xC0 == 0x80 { offset += 1 }
                return offset
            }
            let lower = boundary(Int.random(in: 0...bytes.count, using: &generator))
            let upper = boundary(min(bytes.count, lower + Int.random(in: 0...12, using: &generator)))
            let insertion = (0..<Int.random(in: 0...3, using: &generator))
                .map { _ in fragments.randomElement(using: &generator)! }.joined()
            let changed = session.replace(utf8Range: lower..<upper, with: insertion)
            text = String(decoding: bytes[..<lower] + Array(insertion.utf8) + bytes[upper...], as: UTF8.self)
            #expect(changed.lowerBound <= changed.upperBound)
            #expect(session.text == text)
            let expected = language.tokenize(text)
            #expect(session.tokens == expected, "diverged after edit at \(lower)..<\(upper) inserting \(insertion.debugDescription)")
            if session.tokens != expected { return }
        }
    }

    @Test func streamingAppendMatchesFullTokenization() {
        let markdown = builtin("markdown")
        let document = "# Title\n\nSome `code` and\n```swift\nlet s = \"multi\nline\"\n```\n- item **bold**\n"
        let session = HighlightSession(language: markdown)
        var index = document.startIndex
        var chunkSize = 1
        while index < document.endIndex {
            let end = document.index(index, offsetBy: chunkSize, limitedBy: document.endIndex) ?? document.endIndex
            session.append(String(document[index..<end]))
            index = end
            chunkSize = chunkSize % 7 + 1
            #expect(session.tokens == markdown.tokenize(String(document[..<end])))
        }
    }

    @Test func editsStopWhenStatesConverge() {
        let swift = builtin("swift")
        let lines = (0..<1000).map { "let value\($0) = \($0) // comment" }
        let session = HighlightSession(language: swift, text: lines.joined(separator: "\n"))
        // Editing inside one line re-tokenizes only that line.
        let offset = session.lineRange(500).lowerBound + 4
        let changed = session.replace(utf8Range: offset..<offset, with: "x")
        #expect(changed == 500..<501)
        // Opening a block comment re-tokenizes everything after it…
        let open = session.lineRange(10).lowerBound
        let opened = session.replace(utf8Range: open..<open, with: "/*")
        #expect(opened == 10..<1000)
        // …and closing it again restores the rest, stopping as soon as states agree.
        let close = session.lineRange(12).lowerBound
        let closed = session.replace(utf8Range: close..<close, with: "*/")
        #expect(closed == 12..<1000)
        #expect(session.tokens == swift.tokenize(session.text))
    }

    @Test func lineTokenizerCarriesState() {
        let tokenizer = LineTokenizer(language: builtin("swift"))
        _ = tokenizer.tokenize("let a = /* open")
        #expect(tokenizer.state.stateNames == ["root", "blockComment"])
        let tokens = tokenizer.tokenize("still comment */ let")
        #expect(tokens.map(\.scope.name) == ["comment.block", "storage.type"])
        #expect(tokenizer.state.isRoot)
    }

    @Test func embeddedLanguageStateIsVisible() {
        var state = LineState(language: builtin("markdown"))
        _ = builtin("markdown").tokenizeLine("```python", state: &state)
        #expect(state.language.id == "python")
        #expect(state.rootLanguage.id == "markdown")
        _ = builtin("markdown").tokenizeLine("```", state: &state)
        #expect(state.language.id == "markdown")
    }
}

@Suite("Robustness")
struct RobustnessTests {
    @Test(arguments: BuiltinGrammars.all.map(\.id))
    func fuzz(_ id: String) {
        let language = builtin(id)
        var generator = SessionTests.SplitMix(state: 42)
        let alphabet = Array("abcXYZ_09 \t\n\r\"'`\\/*#$@{}()[]<>!?=:;,.-+%&|^~é😀\u{0}".unicodeScalars)
        for length in [0, 1, 2, 5, 17, 64, 300, 2000] {
            var scalars = String.UnicodeScalarView()
            for _ in 0..<length { scalars.append(alphabet.randomElement(using: &generator)!) }
            let text = String(scalars)
            #expect(validate(language.tokenize(text), in: text), "\(id) produced invalid tokens")
        }
    }

    @Test func invalidUTF8IsSafe() {
        // Strings repair invalid UTF-8; make sure the repaired text tokenizes.
        let text = String(decoding: [0x22, 0xFF, 0xC3, 0x28, 0x22, 0x0A, 0xE2, 0x82], as: UTF8.self)
        for grammar in BuiltinGrammars.all {
            #expect(validate(builtin(grammar.id).tokenize(text), in: text))
        }
    }

    @Test func pathologicalLinesStayLinear() {
        // A grammar with catastrophic backtracking still finishes, via the step budget.
        let hostile = try! Language(Grammar(name: "Hostile", states: ["root": [.match("(a+)+b", .keyword)]]))
        let line = String(repeating: "a", count: 20_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = hostile.tokenize(line) }
        #expect(elapsed < .seconds(2))
    }

    @Test func deepNestingIsCapped() {
        let swift = builtin("swift")
        let text = String(repeating: "/*", count: 10_000)
        var state = LineState(language: swift)
        _ = swift.tokenizeLine(text, state: &state)
        #expect(state.frames.count <= Tokenizer.maxDepth)
    }

    @Test func minifiedLine() {
        let code = String(repeating: "{\"key\":[1,2,{\"a\":\"b\\\"c\"}],\"t\":true},", count: 20_000)
        let tokens = builtin("json").tokenize(code)
        #expect(validate(tokens, in: code))
        #expect(tokens.count > 100_000)
    }
}
