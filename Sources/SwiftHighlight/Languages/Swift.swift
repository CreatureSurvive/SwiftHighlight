extension BuiltinGrammars {
    static let swift = Grammar(
        name: "Swift",
        aliases: ["swiftui"],
        fileExtensions: ["swift", "swiftinterface"],
        firstLinePattern: #"^#!.*\bswift\b"#,
        states: [
            "root": [
                .include("comments"),
                .include("strings"),
                .match(#"@[A-Za-z_]\w*"#, .attribute),
                .match(#"#(?:if|elseif|else|endif|sourceLocation|warning|error)\b"#, .preprocessor),
                .match(#"#(?:available|unavailable|selector|keyPath|file|fileID|filePath|line|column|function|dsohandle|colorLiteral|imageLiteral|fileLiteral)\b"#, .keyword),
                .match(#"#[A-Za-z_]\w*"#, .functionCall),
                .include("numbers"),
                .match(#"\b(func)\s+([A-Za-z_]\w*|`[^`]+`)"#, captures: [1: .keywordDeclaration, 2: .function]),
                .match(#"\b(class|struct|enum|protocol|actor|extension|typealias|associatedtype|macro|precedencegroup)\s+([A-Za-z_]\w*)"#,
                       captures: [1: .keywordDeclaration, 2: .type]),
                .match(#"\b(as|try)[?!]"#, .keyword),
                .words(declarationKeywords, .keywordDeclaration),
                .words(controlKeywords, .keywordControl),
                .words(modifierKeywords, .modifier),
                .words(["true", "false", "nil"], .constant),
                .words(["self", "Self", "super"], .variableBuiltin),
                .words(["is", "as", "in", "some", "any"], .keyword),
                .match(#"[A-Z][A-Za-z0-9_]*"#, .type),
                .match(#"[a-z_][A-Za-z0-9_]*(?=\s*\()"#, .functionCall),
                .match(#"(?<=\.)[a-z_][A-Za-z0-9_]*"#, .property),
                .match(#"\$\d+|\$[A-Za-z_]\w*"#, .variable),
            ],
            "code": [.include("root")],
            "comments": [
                .match(#"///.*"#, "comment.line.documentation"),
                .match(#"//.*"#, .commentLine),
                .push(#"/\*"#, "blockComment"),
            ],
            "blockComment": GrammarState(scope: .commentBlock, rules: [
                .push(#"/\*"#, "blockComment"),
                .pop(#"\*/"#),
            ]),
            "numbers": [
                .match(#"\b(?:0x[0-9a-fA-F_]+(?:\.[0-9a-fA-F_]+)?(?:[pP][+-]?\d+)?|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?)\b"#, .number),
            ],
            "strings": [
                .push(#"(#+)""""#, "rawMultilineString", delimiter: 1),
                .push(#"(#+)""#, "rawString", delimiter: 1),
                .push("\"\"\"", "multilineString"),
                .push("\"", "string"),
                .push(#"(#+)/"#, "regex", delimiter: 1),
            ],
            "string": GrammarState(scope: .string, popAtLineEnd: true, rules: [
                .push(#"\\\("#, "interpolation", scope: .interpolation),
                .match(#"\\(?:u\{[0-9a-fA-F]{1,8}\}|.)"#, .escape),
                .pop("\""),
            ]),
            "multilineString": GrammarState(scope: .string, rules: [
                .push(#"\\\("#, "interpolation", scope: .interpolation),
                .match(#"\\(?:u\{[0-9a-fA-F]{1,8}\}|.)"#, .escape),
                .pop("\"\"\""),
            ]),
            "rawString": GrammarState(scope: .string, popAtLineEnd: true, rules: [
                .push(#"\\\k\("#, "interpolation", scope: .interpolation),
                .match(#"\\\k(?:u\{[0-9a-fA-F]{1,8}\}|.)"#, .escape),
                .pop("\"\\k"),
            ]),
            "rawMultilineString": GrammarState(scope: .string, rules: [
                .push(#"\\\k\("#, "interpolation", scope: .interpolation),
                .match(#"\\\k(?:u\{[0-9a-fA-F]{1,8}\}|.)"#, .escape),
                .pop("\"\"\"\\k"),
            ]),
            "regex": GrammarState(scope: .stringRegex, rules: [
                .match(#"\\."#, .escape),
                .pop(#"/\k"#),
            ]),
            "interpolation": [
                .pop(#"\)"#, scope: .interpolation),
                .push(#"\("#, "parens"),
                .include("root"),
            ],
            "parens": [
                .push(#"\("#, "parens"),
                .pop(#"\)"#),
                .include("root"),
            ],
        ]
    )

    private static let declarationKeywords = [
        "class", "struct", "enum", "protocol", "extension", "func", "let", "var", "init", "deinit", "subscript",
        "typealias", "associatedtype", "actor", "macro", "operator", "precedencegroup", "import", "case",
        "get", "set", "willSet", "didSet", "_modify", "_read", "package",
    ]

    private static let controlKeywords = [
        "if", "else", "guard", "return", "for", "while", "repeat", "switch", "default", "break", "continue",
        "fallthrough", "do", "try", "catch", "throw", "throws", "rethrows", "defer", "where", "await", "async",
        "yield", "discard", "then",
    ]

    private static let modifierKeywords = [
        "public", "private", "fileprivate", "internal", "open", "static", "final", "override", "mutating",
        "nonmutating", "lazy", "weak", "unowned", "dynamic", "optional", "required", "convenience", "indirect",
        "nonisolated", "isolated", "consuming", "borrowing", "sending", "inout", "prefix", "postfix", "infix",
        "each", "consume", "copy", "distributed",
    ]
}
