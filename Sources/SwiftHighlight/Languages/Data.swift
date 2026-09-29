// YAML, TOML, INI, SQL, Protocol Buffers, Dockerfile, Makefile, Diff, Markdown.

extension BuiltinGrammars {
    // MARK: YAML

    static let yaml = Grammar(
        name: "YAML",
        aliases: ["yml"],
        fileExtensions: ["yaml", "yml"],
        fileNames: [".clang-format", ".clang-tidy", ".swiftlint.yml", ".spi.yml"],
        firstLinePattern: #"^%YAML\b"#,
        states: [
            "root": [
                .match(#"(?<=^|\s)#.*"#, .commentLine),
                .match(#"^(?:---|\.\.\.)(?=\s|$)"#, .punctuation),
                .match(#"^%\w+.*"#, .preprocessor),
                .match(#"^(\s*)(-\s+)?("(?:[^"\\]|\\.)*"|'(?:[^']|'')*')\s*(:)(?=\s|$)"#,
                       captures: [2: .listMarker, 3: .key, 4: .punctuation]),
                .match(#"^(\s*)(-\s+)?([^\s#'"\-?:,\[\]{}&*!|>%@`][^#]*?|[\-?:][^\s#][^#]*?)\s*(:)(?=\s|$)"#,
                       captures: [2: .listMarker, 3: .key, 4: .punctuation]),
                .match(#"^\s*-(?=\s|$)"#, .listMarker),
                .match(#"&[^\s,\[\]{}]+"#, .variable),
                .match(#"\*[^\s,\[\]{}]+"#, .variable),
                .match(#"!!?[\w/.:-]*"#, .typeBuiltin),
                .push("\"", "double"),
                .push(#"'"#, "single"),
                .match(#"[|>][+-]?\d*(?=\s*(?:#.*)?$)"#, .keywordOperator),
                .match(#"(?<![\w.-])[-+]?(?:0x\h+|0o[0-7]+|\d[\d_]*(?:\.\d*)?(?:[eE][+-]?\d+)?|\.inf|\.nan)(?![\w.-])"#,
                       .number),
                .match(#"(?<![\w.-])(?:true|false|True|False|TRUE|FALSE|yes|no|Yes|No|YES|NO|on|off|On|Off|ON|OFF|null|Null|NULL|~)(?![\w.-])"#,
                       .constant),
            ],
            "double": Kit.stringState(close: "\"", escape: #"\\(?:x\h{2}|u\h{4}|U\h{8}|.)"#, singleLine: false),
            "single": Kit.stringState(close: "'", escape: "''", singleLine: false),
        ]
    )

    // MARK: TOML

    static let toml = Grammar(
        name: "TOML",
        fileExtensions: ["toml"],
        fileNames: ["Cargo.lock", "Pipfile", "poetry.lock", "uv.lock"],
        states: [
            "root": [
                .match(#"#.*"#, .commentLine),
                .match(#"^\s*(\[\[?)\s*([^\]]+?)\s*(\]\]?)"#, captures: [1: .punctuation, 2: .type, 3: .punctuation]),
                .match(#"(?:[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|'[^']*')(?:\s*\.\s*(?:[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|'[^']*'))*(?=\s*=)"#,
                       .key),
                .push("\"\"\"", "multiBasic"),
                .push(#"'''"#, "multiLiteral"),
                .push("\"", "basic"),
                .push(#"'"#, "literal"),
                .match(#"\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?)?|\d{2}:\d{2}:\d{2}(?:\.\d+)?"#,
                       .constantOther),
                .match(#"(?<![\w.])[+-]?(?:0x[\h_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?|inf|nan)(?![\w.])"#,
                       .number),
                .words(["true", "false"], .constant),
            ],
            "basic": Kit.stringState(close: "\"", escape: #"\\(?:u\h{4}|U\h{8}|.)"#),
            "multiBasic": Kit.stringState(close: "\"\"\"(?!\")", escape: #"\\(?:u\h{4}|U\h{8}|.)"#, singleLine: false),
            "literal": Kit.stringState(close: "'", escape: nil),
            "multiLiteral": Kit.stringState(close: "'''(?!')", escape: nil, singleLine: false),
        ]
    )

    // MARK: INI

    static let ini = Grammar(
        name: "INI",
        aliases: ["cfg", "conf", "properties", "gitconfig", "editorconfig", "desktop", "systemd"],
        fileExtensions: ["ini", "cfg", "conf", "properties", "prefs", "desktop", "service", "socket", "timer",
                         "inf", "reg", "editorconfig", "gitconfig", "npmrc", "pylintrc", "flake8"],
        fileNames: [".gitconfig", ".editorconfig", ".npmrc", ".gitmodules", ".pylintrc", ".flake8", "setup.cfg",
                    "tox.ini"],
        states: [
            "root": [
                .match(#"^\s*[;#].*"#, .commentLine),
                .match(#"^\s*(\[)([^\]]*)(\])"#, captures: [1: .punctuation, 2: .type, 3: .punctuation]),
                .match(#"^\s*([^=:\s;#\[][^=:]*?)\s*(?=[=:])"#, captures: [1: .key]),
                .push("\"", "double"),
                .push(#"'"#, "single"),
                .match(#"(?<![\w.])[+-]?\d+(?:\.\d+)?(?![\w.])"#, .number),
                .match(#"(?i)(?<![\w.])(?:true|false|yes|no|on|off|none|null)(?![\w.])"#, .constant),
                .match(#"\$\{[^}]*\}|%\([^)]*\)[sdif]|%[A-Za-z]+%"#, .variable),
            ],
            "double": Kit.stringState(close: "\""),
            "single": Kit.stringState(close: "'", escape: nil),
        ]
    )

    // MARK: SQL

    static let sql = Grammar(
        name: "SQL",
        aliases: ["mysql", "postgres", "postgresql", "psql", "pgsql", "sqlite", "plsql", "tsql", "mssql", "mariadb",
                  "hql", "bigquery", "snowflake"],
        fileExtensions: ["sql", "psql", "pgsql", "ddl", "dml", "hql", "cql"],
        states: [
            "root": [
                .match(#"--.*"#, .commentLine),
                .match(#"(?<=^|\s)#.*"#, .commentLine),
                .push(#"/\*"#, "blockComment"),
                .push(#"(?i)[en]?'"#, "single"),
                .push(#"\$(\w*)\$"#, "dollarQuoted", delimiter: 1),
                .match(#""(?:[^"]|"")*"|`[^`]*`|\[[A-Za-z_][^\]]*\]"#, .variable),
                .match(#"[:@$?]\w+|\$\d+|\?"#, .variable),
                .match(#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
                .words(sqlKeywords, .keyword, caseInsensitive: true),
                .words(sqlTypes, .typeBuiltin, caseInsensitive: true),
                .words(["true", "false", "null", "unknown"], .constant, caseInsensitive: true),
                Kit.functionCall,
            ],
            "blockComment": GrammarState(scope: .commentBlock, rules: [.pop(#"\*/"#)]),
            "single": GrammarState(scope: .string, rules: [.match("''", .escape), .match(#"\\."#, .escape), .pop("'")]),
            "dollarQuoted": GrammarState(scope: .string, rules: [.pop(#"\$\k\$"#)]),
        ]
    )

    private static let sqlKeywords = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "drop",
        "alter", "add", "column", "index", "view", "primary", "key", "foreign", "references", "constraint", "unique",
        "check", "default", "join", "inner", "left", "right", "full", "outer", "cross", "natural", "on", "using",
        "and", "or", "not", "is", "in", "as", "between", "like", "ilike", "exists", "all", "any", "some", "distinct",
        "order", "by", "group", "having", "limit", "offset", "fetch", "first", "next", "rows", "only", "union",
        "intersect", "except", "case", "when", "then", "else", "end", "asc", "desc", "nulls", "last", "with",
        "recursive", "returning", "begin", "commit", "rollback", "transaction", "savepoint", "grant", "revoke",
        "to", "database", "schema", "if", "replace", "temporary", "temp", "trigger", "function", "procedure",
        "returns", "return", "declare", "language", "cascade", "restrict", "truncate", "explain", "analyze",
        "vacuum", "pragma", "over", "partition", "window", "range", "preceding", "following", "unbounded",
        "current", "row", "lateral", "conflict", "do", "nothing", "merge", "matched", "upsert", "sequence",
        "extension", "type", "enum", "domain", "materialized", "refresh", "concurrently", "collate", "escape",
        "filter", "within", "ignore", "respect", "qualify", "pivot", "unpivot", "top", "auto_increment",
        "autoincrement", "identity", "generated", "always", "stored", "virtual", "use", "show", "describe",
        "exec", "execute", "call", "loop", "while", "for", "foreach", "raise", "exception", "perform", "open",
        "close", "cursor", "deallocate", "prepare", "listen", "notify", "lock", "share", "nowait", "skip",
        "locked", "of", "without", "zone", "at", "interval", "cast", "convert",
    ]

    private static let sqlTypes = [
        "int", "integer", "smallint", "bigint", "tinyint", "mediumint", "serial", "bigserial", "smallserial",
        "decimal", "numeric", "real", "double", "precision", "float", "money", "char", "character", "varchar",
        "nchar", "nvarchar", "text", "tinytext", "mediumtext", "longtext", "clob", "blob", "bytea", "binary",
        "varbinary", "boolean", "bool", "bit", "date", "time", "timestamp", "timestamptz", "datetime", "datetime2",
        "year", "uuid", "json", "jsonb", "xml", "array", "hstore", "inet", "cidr", "macaddr", "point", "geometry",
        "geography", "tsvector", "tsquery", "varying", "unsigned", "signed", "string",
    ]

    // MARK: Protocol Buffers

    static let protobuf = Grammar(
        name: "Protocol Buffers",
        id: "protobuf",
        aliases: ["proto", "proto3", "proto2"],
        fileExtensions: ["proto"],
        states: Kit.merge(
            [
                "root": GrammarState(rules: Kit.rules(Kit.cComments, [
                    .push("\"", "double"),
                    .push(#"'"#, "single"),
                    Kit.number,
                    .match(#"\b(message|enum|service|extend|oneof)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .match(#"\b(rpc)\s+([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                    .words(["syntax", "edition", "package", "import", "option", "message", "enum", "service", "rpc",
                            "returns", "stream", "oneof", "map", "reserved", "extend", "extensions", "to", "max",
                            "public", "weak"], .keywordDeclaration),
                    .words(["repeated", "optional", "required"], .modifier),
                    .words(["double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
                            "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes"], .typeBuiltin),
                    .words(["true", "false", "inf", "nan"], .constant),
                    .match(#"\b[A-Z]\w*"#, .type),
                ])),
                "double": Kit.stringState(close: "\""),
                "single": Kit.stringState(close: "'"),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: Dockerfile

    static let dockerfile = Grammar(
        name: "Dockerfile",
        aliases: ["docker", "containerfile"],
        fileExtensions: ["dockerfile", "containerfile"],
        fileNames: ["Dockerfile", "Containerfile"],
        states: Kit.merge(
            [
                "root": GrammarState(rules: Kit.rules([
                    .match(#"^\s*#\s*(?:syntax|escape|check)\s*=.*"#, .preprocessor),
                    .match(#"^\s*#.*"#, .commentLine),
                    .match(#"(?i)^\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#,
                           .keyword),
                    .match(#"(?i)\bAS\b(?=\s+\w)"#, .keyword),
                    .match(#"--[A-Za-z-]+(?==)"#, .tagAttribute),
                ], shellRules)),
            ],
            shellStates
        )
    )

    // MARK: Makefile

    static let makefile = Grammar(
        name: "Makefile",
        aliases: ["make", "mk", "bsdmake", "gnumake"],
        fileExtensions: ["mk", "mak", "make"],
        fileNames: ["Makefile", "makefile", "GNUmakefile", "BSDmakefile", "Kbuild"],
        states: [
            "root": [
                .match(#"(?<=^|\s)#.*"#, .commentLine),
                .match(#"^\s*-?(?:include|sinclude|ifeq|ifneq|ifdef|ifndef|else|endif|define|endef|export|unexport|override|undefine|vpath)\b"#,
                       .keyword),
                .match(#"^([A-Za-z0-9_.\-/%$(){} ]+?)\s*(?=::?(?!=))"#, captures: [1: .function]),
                .match(#"^\s*([A-Za-z_][\w.-]*)\s*(?=(?:[:+?!]|::)?=)"#, captures: [1: .variable]),
                .push(#"\$\("#, "reference", scope: .interpolation),
                .push(#"\$\{"#, "braceReference", scope: .interpolation),
                .match(#"\$[@<^+?*%|$]|\$\w"#, .variable),
                .push("\"", "double"),
                .push(#"'"#, "single"),
            ],
            "reference": GrammarState(scope: .variable, rules: [
                .match(#"(?<=\$\()(?:subst|patsubst|strip|findstring|filter|filter-out|sort|word|words|wordlist|firstword|lastword|dir|notdir|suffix|basename|addsuffix|addprefix|join|wildcard|realpath|abspath|if|or|and|foreach|file|call|value|eval|origin|flavor|error|warning|info|shell|guile)\b"#,
                       .functionBuiltin),
                .push(#"\$\("#, "reference", scope: .interpolation),
                .pop(#"\)"#, scope: .interpolation),
            ]),
            "braceReference": GrammarState(scope: .variable, rules: [.pop(#"\}"#, scope: .interpolation)]),
            "double": Kit.stringState(close: "\"", extra: [.push(#"\$\("#, "reference", scope: .interpolation)]),
            "single": Kit.stringState(close: "'", escape: nil),
        ]
    )

    // MARK: Diff

    static let diff = Grammar(
        name: "Diff",
        aliases: ["patch", "udiff"],
        fileExtensions: ["diff", "patch", "rej"],
        firstLinePattern: #"^(?:diff --git |--- |Index: )"#,
        states: [
            "root": [
                .match(#"^(?:diff|index|similarity|rename|copy|new file|deleted file|old mode|new mode|Only in|Binary files)\b.*"#,
                       .diffHeader),
                .match(#"^(?:\+\+\+|---)(?: .*|$)"#, .diffHeader),
                .match(#"^(@@[^@]*@@)(.*)"#, captures: [1: .diffRange, 2: .comment]),
                .match(#"^\+.*"#, .inserted),
                .match(#"^-.*"#, .deleted),
                .match(#"^!.*"#, .changed),
                .match(#"^\\ .*"#, .comment),
                .match(#"^[<].*"#, .deleted),
                .match(#"^[>].*"#, .inserted),
                .match(#"^\*\*\*.*"#, .diffHeader),
            ],
        ]
    )

    // MARK: Markdown

    static let markdown = Grammar(
        name: "Markdown",
        aliases: ["md", "mdown", "mkd", "mdx", "gfm", "commonmark"],
        fileExtensions: ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "ronn", "workbook"],
        fileNames: ["README", "CHANGELOG", "LICENSE.md"],
        wordCharacters: #"A-Za-z0-9"#,
        states: [
            "root": [
                .embed(#"^\s{0,3}(`{3,}|~{3,})[ \t]*([\w+#.-]*)[^`\n]*$"#, language: "$2", end: #"^\s{0,3}\k[`~]*\s*$"#,
                       captures: [1: .punctuation, 2: .label], endScope: .punctuation, delimiter: 1),
                .match(#"^\s{0,3}#{1,6}(?:\s.*)?$"#, .heading),
                .match(#"^\s{0,3}(?:={3,}|-{3,}|\*{3,}|_{3,})\s*$"#, .punctuation),
                .push(#"^\s{0,3}>\s?"#, "quote", scope: .punctuation),
                .match(#"^\s*(?:[-*+]|\d{1,9}[.)])(?=\s)"#, .listMarker),
                .match(#"^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*$"#, .punctuation),
                .include("inline"),
            ],
            "quote": GrammarState(scope: .quote, popAtLineEnd: true, rules: [.include("inline")]),
            "inline": [
                .match(#"(`+)[^`](?:.*?[^`])?\1(?!`)|``"#, .inlineCode),
                .match(#"!?(\[)((?:[^\[\]\\]|\\.)*)(\])(\()([^()\s]*(?:\([^()\s]*\)[^()\s]*)*)(?:(\s+)("[^"]*"|'[^']*'))?(\))"#,
                       captures: [1: .punctuation, 2: .stringSpecial, 3: .punctuation, 4: .punctuation, 5: .link,
                                  7: .string, 8: .punctuation]),
                .match(#"!?(\[)((?:[^\[\]\\]|\\.)*)(\])(\[)([^\]]*)(\])"#,
                       captures: [1: .punctuation, 2: .stringSpecial, 3: .punctuation, 4: .punctuation, 5: .constantOther,
                                  6: .punctuation]),
                .match(#"^\s{0,3}(\[)([^\]]+)(\]):\s*(\S+)"#,
                       captures: [1: .punctuation, 2: .constantOther, 3: .punctuation, 4: .link]),
                .match(#"<(?:https?|ftp|mailto):[^\s>]+>|\bhttps?://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"]"#, .link),
                .match(#"(\*\*|(?<![A-Za-z0-9])__)(?=\S)(?:[^*_\\]|\\.|\*(?!\*)|_(?!_))+?(?<=\S)\1"#, .bold),
                .match(#"(\*|(?<![A-Za-z0-9])_)(?=[^\s*_])(?:[^*_\\]|\\.)+?(?<=\S)\1(?!\w)"#, .italic),
                .match(#"~~(?=\S).+?(?<=\S)~~"#, .strikethrough),
                .match(#"</?[A-Za-z][\w-]*(?:\s[^<>]*)?/?>|<!--.*?-->"#, .tag),
                .match(#"\\[\\`*_{}\[\]()#+\-.!|<>~]"#, .escape),
            ],
        ]
    )
}
