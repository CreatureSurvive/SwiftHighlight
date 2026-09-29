// JavaScript, TypeScript, JSON, HTML, XML, CSS, SCSS, GraphQL.

extension BuiltinGrammars {
    // MARK: JavaScript / TypeScript

    private static let jsControl = ["if", "else", "switch", "case", "default", "for", "while", "do", "break",
                                    "continue", "return", "throw", "try", "catch", "finally", "await", "yield",
                                    "with", "debugger"]
    private static let jsDeclarations = ["var", "let", "const", "function", "class", "extends", "import", "export",
                                         "from", "as", "get", "set", "of", "static", "async"]
    private static let jsOperators = ["new", "delete", "typeof", "instanceof", "in", "void"]
    private static let jsConstants = ["true", "false", "null", "undefined", "NaN", "Infinity"]

    /// A regex literal where one can start: after an operator, punctuation, a keyword, or at the
    /// start of a line.
    private static let jsRegex: Rule = .match(
        #"(?:(?<=[(,=:\[!&|?{};+\-*%<>~^]\s{0,8})|(?<=^\s{0,32})|(?<=\b(?:return|typeof|case|do|else|in|of|yield|await)\s{1,4}))/(?![/*])(?:\\.|\[(?:\\.|[^\]\\])*\]|[^/\\\[])+/[dgimsuyv]*"#,
        .stringRegex
    )

    private static func scriptGrammar(name: String, id: String, aliases: [String], extensions: [String],
                                      typescript: Bool, jsx: Bool) -> Grammar {
        var rules: [Rule] = Kit.cComments + [
            .match(#"^#!.*"#, .commentLine),
            .push(#"'"#, "single"),
            .push("\"", "double"),
            .push("`", "template"),
            jsRegex,
            Kit.number,
            Kit.leadingDotNumber,
            .match(#"@[A-Za-z_][\w.]*"#, .attribute),
            .match(#"#[A-Za-z_]\w*"#, .property),
            .match(#"\b(class|interface|enum|type|namespace)\s+([A-Za-z_$][\w$]*)"#,
                   captures: [1: .keywordDeclaration, 2: .type]),
            .match(#"\b(function\*?)\s*([A-Za-z_$][\w$]*)"#, captures: [1: .keywordDeclaration, 2: .function]),
        ]
        if jsx {
            rules.append(.push(#"(?:(?<=[(,=:?&|>{}\[]\s{0,8})|(?<=^\s{0,32})|(?<=\breturn\s{1,4}))(<)([A-Za-z][\w.:-]*)(?=[\s/>])"#,
                               "jsxTag", captures: [1: .punctuation, 2: .tag]))
            rules.append(.match(#"(</)([A-Za-z][\w.:-]*)\s*(>)"#, captures: [1: .punctuation, 2: .tag, 3: .punctuation]))
            rules.append(.match(#"<>|</>"#, .punctuation))
        }
        rules += [
            .words(jsControl, .keywordControl),
            .words(jsDeclarations + (typescript
                ? ["interface", "type", "enum", "namespace", "module", "declare", "implements", "infer", "keyof",
                   "unique", "is", "asserts", "satisfies"]
                : []), .keywordDeclaration),
            .words(typescript ? ["public", "private", "protected", "readonly", "abstract", "override", "accessor"] : [],
                   .modifier),
            .words(jsOperators, .keywordOperator),
            .words(jsConstants, .constant),
            .words(["this", "super", "arguments", "globalThis"], .variableBuiltin),
        ]
        if typescript {
            rules.append(.words(["string", "number", "boolean", "any", "unknown", "never", "object", "symbol",
                                 "bigint"], .typeBuiltin))
        }
        rules += [
            .match(#"[A-Za-z_$][\w$]*(?=\s*(?:\?\.)?\()"#, .functionCall),
            .match(#"[A-Za-z_$][\w$]*(?=\s*=\s*(?:async\s*)?(?:\([^()]*\)(?:\s*:[^=;{]*)?|[A-Za-z_$][\w$]*)\s*=>)"#, .function),
            .match(#"\b[A-Z][A-Z0-9_]*[A-Z0-9]\b(?!\s*\()"#, .constantOther),
            .match(#"\b[A-Z][\w$]*"#, .type),
            .match(#"(?<=\.)[A-Za-z_$][\w$]*"#, .property),
        ]
        var states: [String: GrammarState] = [
            "root": GrammarState(rules: rules),
            "single": Kit.stringState(close: "'"),
            "double": Kit.stringState(close: "\""),
            "template": Kit.stringState(close: "`", singleLine: false, extra: [
                .push(#"\$\{"#, "interpolation", scope: .interpolation),
            ]),
        ]
        if jsx {
            states["jsxTag"] = [
                .pop(#"/?>"#, scope: .punctuation),
                .match(#"[A-Za-z_][\w:-]*"#, .tagAttribute),
                .push("\"", "jsxString"),
                .push(#"'"#, "jsxStringSingle"),
                .push(#"\{"#, "interpolationBraces"),
            ]
            states["jsxString"] = Kit.stringState(close: "\"", escape: nil, singleLine: false)
            states["jsxStringSingle"] = Kit.stringState(close: "'", escape: nil, singleLine: false)
        }
        return Grammar(
            name: name, id: id, aliases: aliases, fileExtensions: extensions,
            firstLinePattern: typescript ? nil : #"^#!.*\b(?:node|deno|bun)\b"#,
            identifierPattern: #"[A-Za-z_$][\w$]*"#,
            wordCharacters: #"A-Za-z0-9_$"#,
            states: Kit.merge(states, Kit.interpolationStates(name: "interpolation"), Kit.cCommentStates)
        )
    }

    static let javascript = scriptGrammar(
        name: "JavaScript", id: "javascript", aliases: ["js", "jsx", "node", "mjs", "cjs", "ecmascript"],
        extensions: ["js", "jsx", "mjs", "cjs"], typescript: false, jsx: true)

    static let typescript = scriptGrammar(
        name: "TypeScript", id: "typescript", aliases: ["ts", "mts", "cts"],
        extensions: ["ts", "mts", "cts", "d.ts"], typescript: true, jsx: false)

    static let tsx = scriptGrammar(
        name: "TSX", id: "tsx", aliases: ["typescriptreact"], extensions: ["tsx"], typescript: true, jsx: true)

    // MARK: JSON

    static let json = Grammar(
        name: "JSON",
        aliases: ["jsonc", "json5", "jsonl", "ndjson", "geojson", "webmanifest"],
        fileExtensions: ["json", "jsonc", "json5", "jsonl", "ndjson", "geojson", "webmanifest", "har", "avsc",
                         "code-workspace"],
        fileNames: [".babelrc", ".eslintrc", ".prettierrc", "composer.lock", "package.resolved", ".swiftpm"],
        states: Kit.merge(
            [
                "root": GrammarState(rules: Kit.cComments + [
                    .match(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .key),
                    .push("\"", "string"),
                    .match(#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#, .number),
                    .words(["true", "false", "null"], .constant),
                ]),
                "string": Kit.stringState(close: "\"", escape: #"\\(?:u\h{4}|.)"#),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: XML / HTML

    private static let markupCommon: [Rule] = [
        .push(#"<!--"#, "comment"),
        .push(#"<!\[CDATA\["#, "cdata", scope: .punctuation),
        .push(#"<\?[\w-]*"#, "processing"),
        .push(#"(?i)<!DOCTYPE\b"#, "doctype"),
        .match(#"&(?:[A-Za-z][A-Za-z0-9]*|#\d+|#[xX]\h+);"#, .escape),
        .match(#"(</)([A-Za-z_][\w:.-]*)\s*(>)"#, captures: [1: .punctuation, 2: .tag, 3: .punctuation]),
    ]

    private static let markupTagRules: [Rule] = [
        .pop(#"/?>"#, scope: .punctuation),
        .match(#"[A-Za-z_:@#.\[(*][\w:.\-@#\[\]()*]*"#, .tagAttribute),
        .push("\"", "attributeDouble"),
        .push(#"'"#, "attributeSingle"),
    ]

    private static let markupStates: [String: GrammarState] = [
        "comment": GrammarState(scope: .commentBlock, rules: [.pop(#"-->"#)]),
        "cdata": GrammarState(scope: .string, rules: [.pop(#"\]\]>"#, scope: .punctuation)]),
        "processing": GrammarState(scope: .preprocessor, rules: [.pop(#"\?>"#)]),
        "doctype": GrammarState(scope: .preprocessor, rules: [.pop(#">"#)]),
        "tag": GrammarState(rules: markupTagRules),
        "attributeDouble": GrammarState(scope: .string, rules: [
            .match(#"&(?:[A-Za-z][A-Za-z0-9]*|#\d+|#[xX]\h+);"#, .escape),
            .pop("\""),
        ]),
        "attributeSingle": GrammarState(scope: .string, rules: [
            .match(#"&(?:[A-Za-z][A-Za-z0-9]*|#\d+|#[xX]\h+);"#, .escape),
            .pop(#"'"#),
        ]),
    ]

    static let xml = Grammar(
        name: "XML",
        aliases: ["plist", "svg", "xsd", "xsl", "xslt", "rss", "atom", "xaml", "wsdl"],
        fileExtensions: ["xml", "plist", "svg", "xib", "storyboard", "xsd", "xsl", "xslt", "rss", "atom", "xaml",
                         "csproj", "fsproj", "vcxproj", "props", "targets", "entitlements", "xcscheme",
                         "xcworkspacedata", "xcsettings", "resx", "nuspec", "wsdl", "kml", "gpx", "opml", "tmTheme",
                         "tmLanguage"],
        firstLinePattern: #"^\s*<\?xml\b"#,
        states: Kit.merge(
            [
                "root": GrammarState(rules: markupCommon + [
                    .push(#"(<)([A-Za-z_][\w:.-]*)"#, "tag", captures: [1: .punctuation, 2: .tag]),
                ]),
            ],
            markupStates
        )
    )

    static let html = Grammar(
        name: "HTML",
        aliases: ["htm", "xhtml", "vue", "svelte", "erb", "handlebars", "hbs", "liquid", "jinja", "django"],
        fileExtensions: ["html", "htm", "xhtml", "shtml", "vue", "svelte", "hbs", "handlebars", "liquid", "jinja",
                         "jinja2", "njk", "ejs", "erb"],
        firstLinePattern: #"(?i)^\s*<(?:!DOCTYPE\s+html|html)\b"#,
        states: Kit.merge(
            [
                "root": GrammarState(rules: markupCommon + [
                    .match(#"\{\{[^}]*\}\}"#, .interpolation),
                    .push(#"(?i)(<)(script)\b"#, "scriptTag", captures: [1: .punctuation, 2: .tag]),
                    .push(#"(?i)(<)(style)\b"#, "styleTag", captures: [1: .punctuation, 2: .tag]),
                    .push(#"(<)([A-Za-z][\w:.-]*)"#, "tag", captures: [1: .punctuation, 2: .tag]),
                ]),
                "scriptTag": GrammarState(rules: [.set(#">"#, "scriptBody", scope: .punctuation)] + markupTagRules),
                "scriptBody": [
                    .pop(#"(?i)(?=</script)"#),
                    .embed("", language: "javascript", end: #"(?i)(?=</script)"#),
                ],
                "styleTag": GrammarState(rules: [.set(#">"#, "styleBody", scope: .punctuation)] + markupTagRules),
                "styleBody": [
                    .pop(#"(?i)(?=</style)"#),
                    .embed("", language: "css", end: #"(?i)(?=</style)"#),
                ],
            ],
            markupStates
        )
    )

    // MARK: CSS / SCSS

    private static func styleGrammar(name: String, id: String, aliases: [String], extensions: [String],
                                     scss: Bool) -> Grammar {
        var comments: [Rule] = [.push(#"/\*"#, "blockComment")]
        if scss { comments.append(.match(#"//.*"#, .commentLine)) }
        let variables: [Rule] = scss
            ? [.match(#"[$@][A-Za-z_][\w-]*"#, .variable), .push(#"#\{"#, "interpolation", scope: .interpolation)]
            : [.match(#"--[A-Za-z_][\w-]*"#, .variable)]
        let strings: [Rule] = [.push("\"", "double"), .push(#"'"#, "single")]
        let atRule: Rule = .match(#"@[A-Za-z-]+"#, .keyword)

        let selectorRules: [Rule] = comments + strings + [atRule] + variables + [
            .push(#"\{"#, "block"),
            .pop(#"\}"#),
            .match(#"\.[A-Za-z_-][\w-]*"#, .tagAttribute),
            .match(#"#[A-Za-z_-][\w-]*"#, .constantOther),
            .match(#"::?[A-Za-z-]+"#, .keyword),
            .match(#"\[[^\]]*\]"#, .tagAttribute),
            .match(#"&"#, .keyword),
            .match(#"\b[a-z][\w-]*"#, .tag),
            .match(#"\d+(?:\.\d+)?%"#, .number),
        ]
        let blockRules: [Rule] = comments + strings + [atRule] + variables + [
            .push(#"\{"#, "block"),
            .pop(#"\}"#),
            .match(#"-?[A-Za-z_-][\w-]*(?=\s*:(?!:))"#, .key),
            .match(#"#\h{3,8}\b"#, .constantOther),
            .match(#"#[A-Za-z_-][\w-]*"#, .constantOther),
            .match(#"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?(?:%|[A-Za-z]+)?"#, .number),
            .match(#"!\s*important\b"#, .keyword),
            .match(#"[A-Za-z_-][\w-]*(?=\()"#, .functionCall),
            .match(#"\.[A-Za-z_-][\w-]*"#, .tagAttribute),
            .match(#"&"#, .keyword),
            .match(#"::?[A-Za-z-]+(?![\w-]*\s*;)"#, .keyword),
            .words(["inherit", "initial", "unset", "revert", "none", "auto", "transparent", "currentColor"], .constant),
        ]
        var states: [String: GrammarState] = [
            "root": GrammarState(rules: selectorRules),
            "block": GrammarState(rules: blockRules),
            "blockComment": GrammarState(scope: .commentBlock, rules: [.pop(#"\*/"#)]),
            "double": Kit.stringState(close: "\"", escape: #"\\(?:\h{1,6}|.)"#),
            "single": Kit.stringState(close: "'", escape: #"\\(?:\h{1,6}|.)"#),
        ]
        if scss {
            states.merge(Kit.interpolationStates(name: "interpolation", include: "block")) { _, new in new }
        }
        return Grammar(name: name, id: id, aliases: aliases, fileExtensions: extensions,
                       wordCharacters: #"A-Za-z0-9_-"#, states: states)
    }

    static let css = styleGrammar(name: "CSS", id: "css", aliases: [], extensions: ["css"], scss: false)

    static let scss = styleGrammar(name: "SCSS", id: "scss", aliases: ["sass", "less"],
                                   extensions: ["scss", "sass", "less"], scss: true)

    // MARK: GraphQL

    static let graphql = Grammar(
        name: "GraphQL",
        aliases: ["gql"],
        fileExtensions: ["graphql", "graphqls", "gql"],
        states: [
            "root": [
                .match(#"#.*"#, .commentLine),
                .push("\"\"\"", "blockString"),
                .push("\"", "string"),
                .match(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, .number),
                .match(#"\$[A-Za-z_]\w*"#, .variable),
                .match(#"@[A-Za-z_]\w*"#, .attribute),
                .match(#"\b(type|interface|union|enum|input|scalar|fragment|query|mutation|subscription)\s+([A-Za-z_]\w*)"#,
                       captures: [1: .keywordDeclaration, 2: .type]),
                .words(["query", "mutation", "subscription", "fragment", "on", "type", "interface", "union", "enum",
                        "input", "scalar", "schema", "extend", "directive", "implements", "repeatable"],
                       .keywordDeclaration),
                .words(["true", "false", "null"], .constant),
                .match(#"\b[A-Z]\w*"#, .type),
                .match(#"[A-Za-z_]\w*(?=\s*[(:])"#, .property),
            ],
            "string": Kit.stringState(close: "\"", escape: #"\\(?:u\h{4}|.)"#),
            "blockString": Kit.stringState(close: "\"\"\"", escape: nil, singleLine: false),
        ]
    )
}
