/// Source text with its tokens: the input to every renderer.
public struct HighlightedCode: Sendable {
    public let source: String
    public let language: Language
    /// Tokens in order, non-overlapping, UTF-8 offsets into `source`.
    public let tokens: [Token]

    public init(source: String, language: Language, tokens: [Token]) {
        self.source = source
        self.language = language
        self.tokens = tokens
    }
}

public extension Language {
    /// Tokenizes a whole document.
    func tokenize(_ code: String, registry: LanguageRegistry = .shared) -> [Token] {
        var code = code
        return code.withUTF8 { buffer -> [Token] in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return [] }
            let tokenizer = Tokenizer(state: LineState(language: self), resolve: { registry.language(named: $0) })
            var tokens: [Token] = []
            tokens.reserveCapacity(buffer.count / 8)
            tokenizer.tokenize(base, count: buffer.count, into: &tokens)
            return tokens
        }
    }

    /// Tokenizes a whole document, keeping the source alongside for rendering.
    func highlight(_ code: String, registry: LanguageRegistry = .shared) -> HighlightedCode {
        HighlightedCode(source: code, language: self, tokens: tokenize(code, registry: registry))
    }

    /// Tokenizes one line (without its line break) starting in `state`, and advances `state` to
    /// where the next line starts. Token offsets are relative to the line.
    ///
    /// Convenient for one-off use; for many lines, reuse a ``LineTokenizer`` (or a
    /// ``HighlightSession``), which keeps its scratch buffers between lines.
    func tokenizeLine(_ line: some StringProtocol, state: inout LineState, registry: LanguageRegistry = .shared) -> [Token] {
        var text = String(line)
        return text.withUTF8 { buffer -> [Token] in
            let tokenizer = Tokenizer(state: state, resolve: { registry.language(named: $0) })
            var end = buffer.count
            if end > 0, buffer[end - 1] == 0x0A { end -= 1 }
            if end > 0, buffer[end - 1] == 0x0D { end -= 1 }
            var tokens: [Token] = []
            if let base = buffer.baseAddress {
                tokenizer.tokenizeLine(base, start: 0, end: end, into: &tokens)
            }
            state = tokenizer.lineState
            return tokens
        }
    }

    /// The language with this id, name or alias in the shared registry, or plain text.
    static func named(_ name: String) -> Language {
        LanguageRegistry.shared.language(named: name) ?? .plainText
    }

    /// The language for a file path in the shared registry, or plain text.
    static func forPath(_ path: String) -> Language {
        LanguageRegistry.shared.language(forPath: path) ?? .plainText
    }

    /// No highlighting at all.
    static let plainText: Language = {
        // A grammar with no rules cannot fail to compile.
        try! Language(Grammar(name: "Plain Text", id: "plaintext", aliases: ["text", "txt", "plain"],
                              fileExtensions: ["txt"], states: ["root": []]))
    }()
}

// MARK: - Built-in languages

public extension Language {
    static var swift: Language { named("swift") }
    static var objectiveC: Language { named("objective-c") }
    static var c: Language { named("c") }
    static var cpp: Language { named("cpp") }
    static var csharp: Language { named("csharp") }
    static var java: Language { named("java") }
    static var kotlin: Language { named("kotlin") }
    static var dart: Language { named("dart") }
    static var go: Language { named("go") }
    static var rust: Language { named("rust") }
    static var javascript: Language { named("javascript") }
    static var typescript: Language { named("typescript") }
    static var tsx: Language { named("tsx") }
    static var json: Language { named("json") }
    static var html: Language { named("html") }
    static var xml: Language { named("xml") }
    static var css: Language { named("css") }
    static var scss: Language { named("scss") }
    static var graphql: Language { named("graphql") }
    static var python: Language { named("python") }
    static var ruby: Language { named("ruby") }
    static var php: Language { named("php") }
    static var lua: Language { named("lua") }
    static var shell: Language { named("shell") }
    static var yaml: Language { named("yaml") }
    static var toml: Language { named("toml") }
    static var ini: Language { named("ini") }
    static var sql: Language { named("sql") }
    static var protobuf: Language { named("protobuf") }
    static var dockerfile: Language { named("dockerfile") }
    static var makefile: Language { named("makefile") }
    static var diff: Language { named("diff") }
    static var markdown: Language { named("markdown") }
}
