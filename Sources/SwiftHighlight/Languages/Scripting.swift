// Python, Ruby, PHP, Lua, Shell.

extension BuiltinGrammars {
    // MARK: Python

    private static let pythonStringStates: (rules: [Rule], states: [String: GrammarState]) = {
        let kinds: [(prefix: String, name: String, raw: Bool, format: Bool)] = [
            (#"(?:[rR][fF]|[fF][rR])"#, "rawFormat", true, true),
            (#"[fF]"#, "format", false, true),
            (#"(?:[rR][bB]?|[bB][rR])"#, "raw", true, false),
            (#"[bBuU]?"#, "plain", false, false),
        ]
        let quotes: [(pattern: String, name: String, triple: Bool)] = [
            (#"'''"#, "TripleSingle", true), ("\"\"\"", "TripleDouble", true),
            (#"'"#, "Single", false), ("\"", "Double", false),
        ]
        var rules: [Rule] = []
        var states: [String: GrammarState] = [:]
        for kind in kinds {
            for quote in quotes {
                let name = kind.name + quote.name
                rules.append(.push(kind.prefix + quote.pattern, name))
                var extra: [Rule] = []
                if kind.format {
                    extra.append(.match(#"\{\{|\}\}"#, .escape))
                    extra.append(.push(#"\{"#, "interpolation", scope: .interpolation))
                }
                if kind.raw { extra.append(.match(#"\\."#, .string)) }
                states[name] = Kit.stringState(
                    close: quote.pattern,
                    escape: kind.raw ? nil : #"\\(?:N\{[^}]*\}|x\h{2}|u\h{4}|U\h{8}|[0-7]{1,3}|.)"#,
                    singleLine: !quote.triple, extra: extra)
            }
        }
        return (rules, states)
    }()

    static let python = Grammar(
        name: "Python",
        aliases: ["py", "python3", "py3", "gyp", "starlark", "bzl"],
        fileExtensions: ["py", "pyw", "pyi", "pyx", "pxd", "gyp", "gypi", "bzl", "star"],
        fileNames: ["SConstruct", "SConscript", "BUILD", "BUILD.bazel", "WORKSPACE", "Snakefile"],
        firstLinePattern: #"^#!.*\bpython(?:\d(?:\.\d+)?)?\b"#,
        states: Kit.merge(
            [
                "root": GrammarState(rules: Kit.rules([
                    .match(#"#.*"#, .commentLine),
                ], pythonStringStates.rules, [
                    .match(#"@[A-Za-z_][\w.]*"#, .attribute),
                    .match(#"\b(?:0[xX][\h_]+|0[oO][0-7_]+|0[bB][01_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?[jJ]?)\b"#,
                           .number),
                    .match(#"\b(def)\s+([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(class)\s+([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "elif", "else", "for", "while", "break", "continue", "return", "try", "except",
                            "finally", "raise", "with", "yield", "await", "pass", "assert", "match", "case", "async",
                            "from", "import", "as", "global", "nonlocal", "del"], .keywordControl),
                    .words(["def", "class", "lambda", "type"], .keywordDeclaration),
                    .words(["and", "or", "not", "in", "is"], .keywordOperator),
                    .words(["True", "False", "None", "NotImplemented", "Ellipsis", "__debug__"], .constant),
                    .words(["self", "cls"], .variableBuiltin),
                    .match(#"\b(?:abs|aiter|all|anext|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|classmethod|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip|__import__)(?=\s*\()"#,
                           .functionBuiltin),
                    .match(#"\b__\w+__\b"#, .variableBuiltin),
                    Kit.functionCall,
                ], Kit.constantsAndTypes, [Kit.property])),
            ],
            pythonStringStates.states,
            Kit.interpolationStates(name: "interpolation")
        )
    )

    // MARK: Ruby

    static let ruby = Grammar(
        name: "Ruby",
        aliases: ["rb", "jruby", "macruby", "rake", "gemspec", "podspec"],
        fileExtensions: ["rb", "rake", "gemspec", "podspec", "rbw", "ru", "jbuilder", "thor"],
        fileNames: ["Gemfile", "Rakefile", "Podfile", "Fastfile", "Appfile", "Matchfile", "Brewfile", "Guardfile",
                    "Vagrantfile", "Dangerfile", "Berksfile", "Capfile", ".irbrc", ".pryrc"],
        firstLinePattern: #"^#!.*\bruby\b"#,
        identifierPattern: #"[A-Za-z_]\w*[?!]?"#,
        states: Kit.merge(
            [
                "root": GrammarState(rules: [
                    .push(#"^=begin\b"#, "blockComment"),
                    .match(#"#.*"#, .commentLine),
                    .push("\"", "double"),
                    .push(#"'"#, "single"),
                    .push("`", "backtick"),
                    .push(#"%[qwi]?\("#, "percentParen"),
                    .push(#"%[qwi]?\["#, "percentBracket"),
                    .push(#"%[qwi]?\{"#, "percentBrace"),
                    .match(#"(?:(?<=[(,=:\[!&|?{};~]\s{0,8})|(?<=^\s{0,32})|(?<=\b(?:when|if|unless|and|or|not)\s{1,4}))/(?![\s=/])(?:\\.|[^/\\])*/[imxo]*"#,
                           .stringRegex),
                    .match(#"(?<!:):(?:[A-Za-z_]\w*[?!=]?|"[^"]*"|\[\]=?|[+\-*/%<>=!~^&|]+)"#, .constantOther),
                    .match(#"\b[A-Za-z_]\w*[?!]?:(?!:)"#, .constantOther),
                    .match(#"@@?[A-Za-z_]\w*|\$(?:[A-Za-z_]\w*|[!@&`'+~=/\\,;.<>_*$?:"0-9])"#, .variable),
                    .match(#"\b(?:0[xX][\h_]+|0[bB][01_]+|0[oO]?[0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?[ri]?)\b"#,
                           .number),
                    .match(#"\b(def)\s+(?:self\.)?([A-Za-z_]\w*[?!=]?|[+\-*/%<>=!~^&|\[\]]+)"#,
                           captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(class|module)\s+([A-Z][\w:]*)"#, captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "elsif", "else", "unless", "case", "when", "in", "while", "until", "for", "break",
                            "next", "redo", "retry", "return", "yield", "begin", "rescue", "ensure", "raise", "then",
                            "do", "end", "loop", "throw", "catch"], .keywordControl),
                    .words(["def", "class", "module", "alias", "undef", "require", "require_relative", "include",
                            "extend", "prepend", "attr_accessor", "attr_reader", "attr_writer", "lambda", "proc",
                            "BEGIN", "END", "using", "refine"], .keywordDeclaration),
                    .words(["private", "protected", "public", "module_function", "private_constant"], .modifier),
                    .words(["and", "or", "not", "defined?"], .keywordOperator),
                    .words(["true", "false", "nil", "__FILE__", "__LINE__", "__method__", "__dir__"], .constant),
                    .words(["self", "super"], .variableBuiltin),
                    .match(#"[A-Za-z_]\w*[?!]?(?=\s*\()"#, .functionCall),
                    .match(#"\b[A-Z]\w*"#, .type),
                    .match(#"(?<=\.)[A-Za-z_]\w*[?!]?"#, .functionCall),
                ]),
                "blockComment": GrammarState(scope: .commentBlock, rules: [.pop(#"^=end\b.*"#)]),
                "double": Kit.stringState(close: "\"", singleLine: false, extra: rubyInterpolation),
                "backtick": Kit.stringState(close: "`", singleLine: false, extra: rubyInterpolation),
                "single": Kit.stringState(close: "'", escape: #"\\[\\']"#, singleLine: false),
                "percentParen": Kit.stringState(close: #"\)"#, singleLine: false, extra: rubyInterpolation),
                "percentBracket": Kit.stringState(close: #"\]"#, singleLine: false, extra: rubyInterpolation),
                "percentBrace": Kit.stringState(close: #"\}"#, singleLine: false, extra: rubyInterpolation),
            ],
            Kit.interpolationStates(name: "interpolation")
        )
    )

    private static let rubyInterpolation: [Rule] = [.push(#"#\{"#, "interpolation", scope: .interpolation)]

    // MARK: PHP

    static let php = Grammar(
        name: "PHP",
        aliases: ["php3", "php4", "php5", "php7", "php8"],
        fileExtensions: ["php", "phtml", "php3", "php4", "php5", "php7", "phps", "phpt"],
        firstLinePattern: #"^(?:<\?php\b|#!.*\bphp\b)"#,
        states: Kit.merge(
            [
                "root": GrammarState(rules: Kit.rules(Kit.cComments, [
                    .match(#"<\?(?:php\b|=)?|\?>"#, .preprocessor),
                    .match(#"#\[[^\]]*\]"#, .attribute),
                    .match(#"#.*"#, .commentLine),
                    .push("\"", "double"),
                    .push(#"'"#, "single"),
                    .match(#"\$[A-Za-z_]\w*"#, .variable),
                    Kit.number,
                    .match(#"\b(function|fn)\s+&?([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(class|interface|trait|enum)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "else", "elseif", "endif", "switch", "case", "default", "endswitch", "for",
                            "endfor", "foreach", "endforeach", "as", "while", "endwhile", "do", "break", "continue",
                            "return", "throw", "try", "catch", "finally", "yield", "match", "goto", "declare",
                            "enddeclare", "include", "include_once", "require", "require_once"], .keywordControl),
                    .words(["function", "fn", "class", "interface", "trait", "enum", "extends", "implements",
                            "namespace", "use", "const", "var", "global", "echo", "print", "insteadof"],
                           .keywordDeclaration),
                    .words(["public", "private", "protected", "static", "abstract", "final", "readonly"], .modifier),
                    .words(["new", "clone", "instanceof", "and", "or", "xor", "isset", "unset", "empty", "list",
                            "array"], .keywordOperator),
                    .words(["true", "false", "null", "TRUE", "FALSE", "NULL"], .constant),
                    .words(["self", "parent", "static"], .variableBuiltin),
                    .words(["int", "float", "bool", "string", "void", "mixed", "never", "object", "iterable",
                            "callable"], .typeBuiltin),
                    Kit.functionCall,
                    .match(#"\b[A-Z]\w*"#, .type),
                    .match(#"(?<=->)[A-Za-z_]\w*"#, .property),
                ])),
                "double": Kit.stringState(close: "\"", singleLine: false, extra: [
                    .match(#"\$[A-Za-z_]\w*(?:->[A-Za-z_]\w*)?"#, .variable),
                    .push(#"\{(?=\$)"#, "interpolation", scope: .interpolation),
                ]),
                "single": Kit.stringState(close: "'", escape: #"\\[\\']"#, singleLine: false),
            ],
            Kit.interpolationStates(name: "interpolation"),
            Kit.cCommentStates
        )
    )

    // MARK: Lua

    static let lua = Grammar(
        name: "Lua",
        aliases: ["luau"],
        fileExtensions: ["lua", "luau", "rockspec"],
        firstLinePattern: #"^#!.*\blua\b"#,
        states: [
            "root": [
                .push(#"--\[(=*)\["#, "longComment", delimiter: 1),
                .match(#"--.*"#, .commentLine),
                .push(#"\[(=*)\["#, "longString", delimiter: 1),
                .push("\"", "double"),
                .push(#"'"#, "single"),
                .match(#"\b(?:0[xX][\h]*(?:\.\h*)?(?:[pP][+-]?\d+)?|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)\b"#, .number),
                .match(#"\b(function)\s+([A-Za-z_][\w.:]*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                .words(["if", "then", "else", "elseif", "end", "for", "in", "while", "do", "repeat", "until",
                        "break", "return", "goto"], .keywordControl),
                .words(["function", "local"], .keywordDeclaration),
                .words(["and", "or", "not"], .keywordOperator),
                .words(["true", "false", "nil"], .constant),
                .words(["self"], .variableBuiltin),
                .match(#"\b(?:assert|collectgarbage|dofile|error|getmetatable|ipairs|load|loadfile|next|pairs|pcall|print|rawequal|rawget|rawlen|rawset|require|select|setmetatable|tonumber|tostring|type|xpcall|unpack)\b"#,
                       .functionBuiltin),
                .match(#"[A-Za-z_]\w*(?=\s*[({"'])"#, .functionCall),
                .match(#"(?<=[.:])[A-Za-z_]\w*"#, .property),
            ],
            "longComment": GrammarState(scope: .commentBlock, rules: [.pop(#"\]\k\]"#)]),
            "longString": GrammarState(scope: .string, rules: [.pop(#"\]\k\]"#)]),
            "double": Kit.stringState(close: "\"", escape: #"\\(?:x\h{2}|u\{\h+\}|\d{1,3}|z|.)"#),
            "single": Kit.stringState(close: "'", escape: #"\\(?:x\h{2}|u\{\h+\}|\d{1,3}|z|.)"#),
        ]
    )

    // MARK: Shell

    static let shellKeywords = ["if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while",
                                "until", "do", "done", "in", "function", "time", "coproc"]
    static let shellBuiltins = ["echo", "printf", "read", "cd", "pwd", "pushd", "popd", "export", "local",
                                "declare", "typeset", "readonly", "unset", "set", "shift", "source", "alias",
                                "unalias", "eval", "exec", "exit", "return", "break", "continue", "trap", "test",
                                "type", "command", "builtin", "let", "mapfile", "readarray", "wait", "jobs", "kill",
                                "bg", "fg", "getopts", "hash", "umask", "ulimit", "shopt", "enable", "logout",
                                "disown", "suspend", "true", "false"]

    static let shellRules: [Rule] = [
        Kit.hashComment,
        .push(#"<<-?\s*(['"]?)([A-Za-z_]\w*)\1"#, "heredoc", scope: .keywordOperator, delimiter: 2),
        .push(#"\$'"#, "ansiString"),
        .push("\"", "double"),
        .push(#"'"#, "single"),
        .push("`", "backtick"),
        .push(#"\$\(\("#, "arithmetic", scope: .interpolation),
        .push(#"\$\("#, "subshell", scope: .interpolation),
        .push(#"\$\{"#, "expansion", scope: .interpolation),
        .match(#"\$(?:[A-Za-z_]\w*|[0-9#?@*$!-])"#, .variable),
        .match(#"^\s*([A-Za-z_]\w*)(?=\+?=)"#, captures: [1: .variable]),
        .match(#"\b(function)\s+([A-Za-z_][\w-]*)"#, captures: [1: .keywordDeclaration, 2: .function]),
        .match(#"^\s*([A-Za-z_][\w-]*)\s*(?=\(\)\s*\{?)"#, captures: [1: .function]),
        .words(shellKeywords, .keywordControl),
        .words(shellBuiltins, .functionBuiltin),
        .match(#"\b\d+\b"#, .number),
    ]

    static let shellStates: [String: GrammarState] = [
        "double": Kit.stringState(close: "\"", escape: #"\\[$`"\\\n]"#, singleLine: false, extra: [
            .push(#"\$\(\("#, "arithmetic", scope: .interpolation),
            .push(#"\$\("#, "subshell", scope: .interpolation),
            .push(#"\$\{"#, "expansion", scope: .interpolation),
            .match(#"\$(?:[A-Za-z_]\w*|[0-9#?@*$!-])"#, .variable),
            .push("`", "backtick"),
        ]),
        "single": Kit.stringState(close: "'", escape: nil, singleLine: false),
        "ansiString": Kit.stringState(close: "'", escape: #"\\(?:x\h{1,2}|u\h{1,4}|U\h{1,8}|[0-7]{1,3}|c.|.)"#,
                                      singleLine: false),
        "backtick": GrammarState(scope: .string, rules: [.pop("`"), .match(#"\\."#, .escape)]),
        "subshell": [
            .pop(#"\)"#, scope: .interpolation),
            .push(#"\("#, "parens"),
            .include("root"),
        ],
        "parens": [.push(#"\("#, "parens"), .pop(#"\)"#), .include("root")],
        "arithmetic": [.pop(#"\)\)"#, scope: .interpolation), .include("root")],
        "expansion": GrammarState(scope: .variable, rules: [
            .pop(#"\}"#, scope: .interpolation),
            .push(#"\$\{"#, "expansion", scope: .interpolation),
            .push("\"", "double"),
            .push(#"'"#, "single"),
        ]),
        "heredoc": GrammarState(scope: .string, rules: [.pop(#"^\s*\k$"#, scope: .keywordOperator)]),
    ]

    static let shell = Grammar(
        name: "Shell",
        id: "shell",
        aliases: ["sh", "bash", "zsh", "ksh", "fish", "console", "shellsession", "shell-session", "terminal",
                  "command", "shellscript", "env", "dotenv"],
        fileExtensions: ["sh", "bash", "zsh", "ksh", "fish", "command", "tool", "env", "envrc"],
        fileNames: [".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".profile", ".zshrc", ".zshenv",
                    ".zprofile", ".zlogin", ".zlogout", ".kshrc", ".env", ".envrc", "PKGBUILD", "APKBUILD"],
        firstLinePattern: #"^#!.*\b(?:ba|z|k|da|fi)?sh\b"#,
        wordCharacters: #"A-Za-z0-9_"#,
        states: Kit.merge(["root": GrammarState(rules: shellRules)], shellStates)
    )
}
