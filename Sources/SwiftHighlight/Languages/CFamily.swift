// C, C++, Objective-C, C#, Java, Kotlin, Dart, Go, Rust.

extension BuiltinGrammars {
    // MARK: C

    private static let cControl = ["break", "case", "continue", "default", "do", "else", "for", "goto", "if",
                                   "return", "switch", "while"]
    private static let cTypes = ["char", "double", "enum", "float", "int", "long", "short", "signed", "struct",
                                 "typedef", "union", "unsigned", "void", "bool", "_Bool", "_Complex", "_Imaginary"]
    private static let cModifiers = ["auto", "const", "extern", "inline", "register", "restrict", "static",
                                     "volatile", "_Atomic", "_Noreturn", "_Thread_local", "thread_local",
                                     "constexpr", "_Alignas", "alignas"]
    private static let cOperators = ["sizeof", "alignof", "_Alignof", "typeof", "_Generic", "_Static_assert",
                                     "static_assert", "defined"]
    private static let cConstants = ["true", "false", "NULL", "nullptr"]
    private static let cBuiltinTypes = #"\b(?:u?int(?:8|16|32|64|ptr|max|_least(?:8|16|32|64)|_fast(?:8|16|32|64))_t|s?size_t|ptrdiff_t|wchar_t|char(?:8|16|32)_t|off_t|pid_t|FILE|va_list|max_align_t)\b"#

    private static let cPreprocessor: [Rule] = [
        .match(#"^\s*(#\s*(?:include|import|include_next))\s*(<[^>]*>|"[^"]*")"#,
               captures: [1: .preprocessor, 2: .string]),
        .match(#"^\s*#\s*(?:if|ifdef|ifndef|elif|elifdef|elifndef|else|endif|define|undef|pragma|error|warning|line|include|import)\b"#,
               .preprocessor),
        .match(#"^\s*#\s*[A-Za-z_]\w*"#, .preprocessor),
    ]

    private static let cStrings: [Rule] = [
        .push(#"(?:u8|[uUL])?""#, "string"),
        .match(#"(?:u8|[uUL])?'(?:\\(?:x\h+|[0-7]{1,3}|u\h{4}|U\h{8}|.)|[^'\\])'"#, .character),
    ]

    static let c = Grammar(
        name: "C",
        aliases: [],
        fileExtensions: ["c"],
        states: Kit.merge(
            [
                "root": State(rules: cPreprocessor + Kit.cComments + cStrings + [
                    Kit.number,
                    .words(cControl, .keywordControl),
                    .words(cTypes, .keywordDeclaration),
                    .words(cModifiers, .modifier),
                    .words(cOperators, .keywordOperator),
                    .words(cConstants, .constant),
                    .match(cBuiltinTypes, .typeBuiltin),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\""),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: C++

    static let cpp = Grammar(
        name: "C++",
        id: "cpp",
        aliases: ["c++", "cplusplus", "cxx", "cc", "hpp"],
        fileExtensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp", "inl", "ino", "cu", "cuh"],
        states: Kit.merge(
            [
                "root": State(rules: cPreprocessor + Kit.cComments + [
                    .push(#"(?:u8|[uUL])?R"([^()\\\s]{0,16})\("#, "rawString", delimiter: 1),
                ] + cStrings + [
                    Kit.number,
                    .match(#"\b(class|struct|union|enum(?:\s+class)?|namespace|concept)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .words(cControl + ["try", "catch", "throw", "co_await", "co_return", "co_yield"], .keywordControl),
                    .words(cTypes + ["class", "namespace", "template", "typename", "using", "concept", "requires",
                                     "operator", "friend", "module", "import", "export", "wchar_t", "char8_t",
                                     "char16_t", "char32_t"], .keywordDeclaration),
                    .words(cModifiers + ["public", "private", "protected", "virtual", "override", "final", "explicit",
                                         "mutable", "noexcept", "consteval", "constinit"], .modifier),
                    .words(cOperators + ["new", "delete", "decltype", "static_cast", "dynamic_cast", "const_cast",
                                         "reinterpret_cast", "typeid", "and", "or", "not", "xor", "bitand", "bitor",
                                         "compl", "and_eq", "or_eq", "xor_eq", "not_eq"], .keywordOperator),
                    .words(cConstants, .constant),
                    .words(["this"], .variableBuiltin),
                    .match(cBuiltinTypes, .typeBuiltin),
                    .match(#"\bstd\b"#, .namespace),
                    .match(#"[A-Za-z_]\w*(?=::)"#, .namespace),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\""),
                "rawString": State(scope: .string, rules: [.pop(#"\)\k""#)]),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: Objective-C

    static let objectiveC = Grammar(
        name: "Objective-C",
        id: "objective-c",
        aliases: ["objc", "obj-c", "objectivec", "objective-c++", "objc++", "objectivecpp"],
        fileExtensions: ["m", "mm", "h"],
        states: Kit.merge(
            [
                "root": State(rules: cPreprocessor + Kit.cComments + [
                    .push(#"@""#, "string"),
                    .match(#"@(?:interface|implementation|end|protocol|property|synthesize|dynamic|class|selector|encode|optional|required|public|private|protected|package|try|catch|finally|throw|autoreleasepool|synchronized|import|available|compatibility_alias|defs)\b"#,
                           .keyword),
                    .match(#"@(?=[\[{(\d])"#, .keyword),
                ] + cStrings + [
                    Kit.number,
                    .words(cControl + ["in"], .keywordControl),
                    .words(cTypes + ["id", "instancetype", "Class", "SEL", "IMP", "BOOL", "class", "namespace",
                                     "template", "typename", "using"], .keywordDeclaration),
                    .words(cModifiers + ["nonatomic", "atomic", "strong", "weak", "copy", "assign", "retain",
                                         "readonly", "readwrite", "getter", "setter", "nullable", "nonnull",
                                         "null_unspecified", "null_resettable", "_Nullable", "_Nonnull",
                                         "__nullable", "__nonnull", "__block", "__weak", "__strong",
                                         "__unsafe_unretained", "__autoreleasing", "__kindof", "__bridge",
                                         "__bridge_transfer", "__bridge_retained", "__covariant", "__contravariant",
                                         "public", "private", "protected", "virtual", "override"], .modifier),
                    .words(cOperators + ["new", "delete"], .keywordOperator),
                    .words(cConstants + ["nil", "Nil", "YES", "NO"], .constant),
                    .words(["self", "super", "this", "_cmd"], .variableBuiltin),
                    .match(cBuiltinTypes, .typeBuiltin),
                    .match(#"[A-Za-z_]\w*(?=:)"#, .functionCall),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\""),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: C#

    static let csharp = Grammar(
        name: "C#",
        id: "csharp",
        aliases: ["cs", "c#", "dotnet"],
        fileExtensions: ["cs", "csx"],
        states: Kit.merge(
            [
                "root": State(rules: Kit.cComments + [
                    .match(#"^\s*#\s*[a-z]+"#, .preprocessor),
                    .match(#"^\s*\[\s*([A-Z]\w*)"#, captures: [1: .attribute]),
                    .push("\"\"\"", "rawString"),
                    .push(#"(?:\$@|@\$)""#, "verbatimInterpolated"),
                    .push(#"\$""#, "interpolated"),
                    .push(#"@""#, "verbatim"),
                    .push("\"", "string"),
                    .match(#"'(?:\\(?:x\h{1,4}|u\h{4}|U\h{8}|.)|[^'\\])'"#, .character),
                    Kit.number,
                    .match(#"\b(class|struct|interface|enum|record|namespace)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "else", "switch", "case", "default", "for", "foreach", "while", "do", "break",
                            "continue", "return", "goto", "throw", "try", "catch", "finally", "yield", "await",
                            "when", "lock", "using", "checked", "unchecked", "fixed", "in"], .keywordControl),
                    .words(["class", "struct", "interface", "enum", "record", "namespace", "delegate", "event",
                            "var", "void", "get", "set", "init", "add", "remove", "operator", "implicit",
                            "explicit", "where", "global", "let", "from", "select", "group", "into", "orderby",
                            "join", "on", "equals", "by", "ascending", "descending"], .keywordDeclaration),
                    .words(["public", "private", "protected", "internal", "static", "readonly", "const", "sealed",
                            "abstract", "virtual", "override", "new", "extern", "unsafe", "volatile", "async",
                            "partial", "ref", "out", "params", "required", "file", "scoped", "this"], .modifier),
                    .words(["is", "as", "typeof", "sizeof", "nameof", "default", "stackalloc", "with", "and", "or",
                            "not"], .keywordOperator),
                    .words(["true", "false", "null", "value"], .constant),
                    .words(["base"], .variableBuiltin),
                    .words(["bool", "byte", "sbyte", "char", "decimal", "double", "float", "int", "uint", "long",
                            "ulong", "short", "ushort", "object", "string", "dynamic", "nint", "nuint"], .typeBuiltin),
                    Kit.functionCall,
                    .match(#"\b[A-Z]\w*"#, .type),
                    Kit.property,
                ]),
                "string": Kit.stringState(close: "\""),
                "verbatim": Kit.stringState(close: "\"", escape: "\"\"", singleLine: false),
                "rawString": Kit.stringState(close: "\"\"\"", escape: nil, singleLine: false),
                "interpolated": Kit.stringState(close: "\"", extra: [
                    .match(#"\{\{|\}\}"#, .escape),
                    .push(#"\{"#, "interpolation", scope: .interpolation),
                ]),
                "verbatimInterpolated": Kit.stringState(close: "\"", escape: "\"\"", singleLine: false, extra: [
                    .match(#"\{\{|\}\}"#, .escape),
                    .push(#"\{"#, "interpolation", scope: .interpolation),
                ]),
            ],
            Kit.interpolationStates(name: "interpolation"),
            Kit.cCommentStates
        )
    )

    // MARK: Java

    static let java = Grammar(
        name: "Java",
        aliases: ["jav"],
        fileExtensions: ["java", "jsh"],
        states: Kit.merge(
            [
                "root": State(rules: Kit.cComments + [
                    .match(#"@(?!interface\b)[A-Za-z_][\w.]*"#, .attribute),
                    .push("\"\"\"", "textBlock"),
                    .push("\"", "string"),
                    .match(#"'(?:\\(?:u+\h{4}|[0-7]{1,3}|.)|[^'\\])'"#, .character),
                    Kit.number,
                    .match(#"\b(class|interface|enum|record|@interface)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "else", "switch", "case", "default", "for", "while", "do", "break", "continue",
                            "return", "throw", "try", "catch", "finally", "yield", "assert"], .keywordControl),
                    .words(["class", "interface", "enum", "record", "extends", "implements", "import", "package",
                            "throws", "var", "void", "permits", "module", "requires", "exports", "opens", "uses",
                            "provides", "with", "to"], .keywordDeclaration),
                    .words(["public", "private", "protected", "static", "final", "abstract", "native",
                            "synchronized", "transient", "volatile", "strictfp", "default", "sealed", "non"],
                           .modifier),
                    .words(["new", "instanceof"], .keywordOperator),
                    .words(["true", "false", "null"], .constant),
                    .words(["this", "super"], .variableBuiltin),
                    .words(["boolean", "byte", "char", "short", "int", "long", "float", "double"], .typeBuiltin),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\""),
                "textBlock": Kit.stringState(close: "\"\"\"", singleLine: false),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: Kotlin

    static let kotlin = Grammar(
        name: "Kotlin",
        aliases: ["kt", "kts"],
        fileExtensions: ["kt", "kts"],
        states: Kit.merge(
            [
                "root": State(rules: Kit.cComments + [
                    .match(#"@(?:[A-Za-z_]\w*:)?[A-Za-z_][\w.]*"#, .attribute),
                    .push("\"\"\"", "rawString"),
                    .push("\"", "string"),
                    .match(#"'(?:\\(?:u\h{4}|.)|[^'\\])'"#, .character),
                    Kit.number,
                    .match(#"\b(fun)\s+(?:<[^>]*>\s*)?(?:[A-Za-z_][\w.]*\.)?([A-Za-z_]\w*|`[^`]+`)"#,
                           captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(class|interface|object|typealias)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .match(#"!(?:in|is)\b"#, .keywordOperator),
                    .match(#"\bas\?"#, .keywordOperator),
                    .words(["if", "else", "when", "for", "while", "do", "break", "continue", "return", "throw",
                            "try", "catch", "finally"], .keywordControl),
                    .words(["fun", "val", "var", "class", "interface", "object", "typealias", "package", "import",
                            "constructor", "init", "get", "set", "by", "where", "companion", "enum", "annotation",
                            "data", "sealed", "value"], .keywordDeclaration),
                    .words(["public", "private", "protected", "internal", "open", "final", "abstract", "override",
                            "lateinit", "const", "suspend", "inline", "noinline", "crossinline", "reified",
                            "tailrec", "operator", "infix", "external", "vararg", "inner", "expect", "actual",
                            "out"], .modifier),
                    .words(["in", "is", "as"], .keywordOperator),
                    .words(["true", "false", "null"], .constant),
                    .words(["this", "super", "it", "field"], .variableBuiltin),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\"", extra: [
                    .push(#"\$\{"#, "interpolation", scope: .interpolation),
                    .match(#"\$[A-Za-z_]\w*"#, .variable),
                ]),
                "rawString": Kit.stringState(close: "\"\"\"(?!\")", escape: nil, singleLine: false, extra: [
                    .push(#"\$\{"#, "interpolation", scope: .interpolation),
                    .match(#"\$[A-Za-z_]\w*"#, .variable),
                ]),
            ],
            Kit.interpolationStates(name: "interpolation"),
            Kit.nestedCommentStates
        )
    )

    // MARK: Dart

    static let dart = Grammar(
        name: "Dart",
        fileExtensions: ["dart"],
        states: Kit.merge(
            [
                "root": State(rules: Kit.cComments + [
                    .match(#"@[A-Za-z_][\w.]*"#, .attribute),
                    .push(#"r'''"#, "rawTripleSingle"),
                    .push(#"r""""#, "rawTripleDouble"),
                    .push(#"r'"#, "rawSingle"),
                    .push(#"r""#, "rawDouble"),
                    .push(#"'''"#, "tripleSingle"),
                    .push("\"\"\"", "tripleDouble"),
                    .push(#"'"#, "single"),
                    .push("\"", "double"),
                    Kit.number,
                    .match(#"\b(class|mixin|enum|extension|typedef)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "else", "switch", "case", "default", "for", "while", "do", "break", "continue",
                            "return", "throw", "rethrow", "try", "catch", "finally", "on", "yield", "await", "assert",
                            "when", "in"], .keywordControl),
                    .words(["class", "enum", "extension", "mixin", "typedef", "import", "export", "library",
                            "part", "show", "hide", "deferred", "as", "var", "void", "dynamic", "get", "set",
                            "operator", "with", "extends", "implements", "interface", "base", "sealed", "Function"],
                           .keywordDeclaration),
                    .words(["abstract", "async", "sync", "const", "covariant", "external", "factory", "final",
                            "late", "required", "static"], .modifier),
                    .words(["new", "is"], .keywordOperator),
                    .words(["true", "false", "null"], .constant),
                    .words(["this", "super"], .variableBuiltin),
                    .words(["int", "double", "num", "bool", "String", "List", "Map", "Set", "Object", "Never",
                            "Future", "Stream", "Iterable"], .typeBuiltin),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "single": Kit.stringState(close: "'", extra: dartInterpolation),
                "double": Kit.stringState(close: "\"", extra: dartInterpolation),
                "tripleSingle": Kit.stringState(close: "'''", singleLine: false, extra: dartInterpolation),
                "tripleDouble": Kit.stringState(close: "\"\"\"", singleLine: false, extra: dartInterpolation),
                "rawSingle": Kit.stringState(close: "'", escape: nil),
                "rawDouble": Kit.stringState(close: "\"", escape: nil),
                "rawTripleSingle": Kit.stringState(close: "'''", escape: nil, singleLine: false),
                "rawTripleDouble": Kit.stringState(close: "\"\"\"", escape: nil, singleLine: false),
            ],
            Kit.interpolationStates(name: "interpolation"),
            Kit.nestedCommentStates
        )
    )

    private static let dartInterpolation: [Rule] = [
        .push(#"\$\{"#, "interpolation", scope: .interpolation),
        .match(#"\$[A-Za-z_]\w*"#, .variable),
    ]

    // MARK: Go

    static let go = Grammar(
        name: "Go",
        aliases: ["golang"],
        fileExtensions: ["go"],
        states: Kit.merge(
            [
                "root": State(rules: Kit.cComments + [
                    .push("\"", "string"),
                    .push(#"`"#, "rawString"),
                    .match(#"'(?:\\(?:x\h{2}|u\h{4}|U\h{8}|[0-7]{3}|.)|[^'\\])'"#, .character),
                    Kit.number,
                    Kit.leadingDotNumber,
                    .match(#"\b(func)\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(type)\s+([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .type]),
                    .words(["if", "else", "switch", "case", "default", "for", "range", "break", "continue",
                            "return", "goto", "fallthrough", "defer", "go", "select"], .keywordControl),
                    .words(["func", "var", "const", "type", "struct", "interface", "map", "chan", "package",
                            "import"], .keywordDeclaration),
                    .words(["true", "false", "nil", "iota"], .constant),
                    .words(["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8",
                            "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32",
                            "uint64", "uintptr", "any", "comparable"], .typeBuiltin),
                    .match(#"\b(?:append|cap|clear|close|complex|copy|delete|imag|len|make|max|min|new|panic|print|println|real|recover)(?=\s*\()"#,
                           .functionBuiltin),
                    Kit.functionCall,
                    .match(#"\b[A-Z]\w*"#, .type),
                    Kit.property,
                ]),
                "string": Kit.stringState(close: "\""),
                "rawString": Kit.stringState(close: "`", escape: nil, singleLine: false),
            ],
            Kit.cCommentStates
        )
    )

    // MARK: Rust

    static let rust = Grammar(
        name: "Rust",
        aliases: ["rs"],
        fileExtensions: ["rs"],
        states: Kit.merge(
            [
                "root": State(rules: [
                    .push(#"/\*[*!](?![*/])"#, "docComment"),
                    .push(#"/\*"#, "blockComment"),
                    .match(#"//[/!].*"#, "comment.line.documentation"),
                    .match(#"//.*"#, .commentLine),
                    .match(#"#!?\[[^\]]*\]"#, .attribute),
                    .push(#"b?r(#+)""#, "rawString", delimiter: 1),
                    .push(#"b?r""#, "rawStringPlain"),
                    .push(#"b?""#, "string"),
                    .match(#"b?'(?:\\(?:x\h{2}|u\{\h{1,6}\}|.)|[^'\\])'"#, .character),
                    .match(#"'[A-Za-z_]\w*(?!')"#, .label),
                    Kit.number,
                    .match(#"\b(fn)\s+([A-Za-z_]\w*)"#, captures: [1: .keywordDeclaration, 2: .function]),
                    .match(#"\b(struct|enum|trait|union|type|mod)\s+([A-Za-z_]\w*)"#,
                           captures: [1: .keywordDeclaration, 2: .type]),
                    .match(#"[A-Za-z_]\w*!(?=\s*[(\[{])"#, .functionCall),
                    .words(["if", "else", "match", "for", "while", "loop", "break", "continue", "return", "in",
                            "await", "yield", "try"], .keywordControl),
                    .words(["fn", "let", "struct", "enum", "trait", "impl", "type", "mod", "use", "extern",
                            "crate", "union", "macro_rules", "where", "const", "static"], .keywordDeclaration),
                    .words(["pub", "mut", "ref", "move", "unsafe", "async", "dyn", "default"], .modifier),
                    .words(["as"], .keywordOperator),
                    .words(["true", "false", "Some", "None", "Ok", "Err"], .constant),
                    .words(["self", "Self", "super"], .variableBuiltin),
                    .words(["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize",
                            "f32", "f64", "bool", "char", "str"], .typeBuiltin),
                    .match(#"[A-Za-z_]\w*(?=::)"#, .namespace),
                    Kit.functionCall,
                ] + Kit.constantsAndTypes + [Kit.property]),
                "string": Kit.stringState(close: "\"", escape: #"\\(?:x\h{2}|u\{\h{1,6}\}|.)"#, singleLine: false),
                "rawString": Kit.stringState(close: #""\k"#, escape: nil, singleLine: false),
                "rawStringPlain": Kit.stringState(close: "\"", escape: nil, singleLine: false),
            ],
            Kit.nestedCommentStates
        )
    )
}
