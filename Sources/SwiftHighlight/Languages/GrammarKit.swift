/// Shared building blocks for the built-in grammars.
enum Kit {
    // MARK: Comments

    /// `//` and `/* */` comments, with `///` and `/** */` as documentation.
    static let cComments: [Rule] = [
        .push(#"/\*\*(?![*/])"#, "docComment"),
        .push(#"/\*"#, "blockComment"),
        .match(#"///.*"#, "comment.line.documentation"),
        .match(#"//.*"#, .commentLine),
    ]

    static let cCommentStates: [String: GrammarState] = [
        "blockComment": GrammarState(scope: .commentBlock, rules: [.pop(#"\*/"#)]),
        "docComment": GrammarState(scope: .commentDocumentation, rules: [.pop(#"\*/"#)]),
    ]

    /// Block comments that nest (Swift, Rust, Kotlin, Dart, Scala).
    static let nestedCommentStates: [String: GrammarState] = [
        "blockComment": GrammarState(scope: .commentBlock, rules: [.push(#"/\*"#, "blockComment"), .pop(#"\*/"#)]),
        "docComment": GrammarState(scope: .commentDocumentation, rules: [.push(#"/\*"#, "blockComment"), .pop(#"\*/"#)]),
    ]

    /// `#` comments that must start a word (so `a#b` and `$#` are not comments).
    static let hashComment: Rule = .match(#"(?<=^|[\s;|&(){}])#.*"#, .commentLine)

    // MARK: Literals

    /// Decimal, hex, binary and octal numbers with `_` separators, exponents and type suffixes.
    static let number: Rule = .match(
        #"\b(?:0[xX][\h_]+(?:\.[\h_]+)?(?:[pP][+-]?[\d_]+)?|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?)(?:[A-Za-z_]\w*)?\b"#,
        .number
    )

    /// `.5`-style numbers that start with a dot.
    static let leadingDotNumber: Rule = .match(#"(?<![\w.])\.\d[\d_]*(?:[eE][+-]?\d+)?[A-Za-z]*\b"#, .number)

    /// A quoted string state: `open` pushes it; `close` pops it; `escape` (if any) is scoped as an
    /// escape; `extra` rules (interpolation) come first.
    static func stringState(close: String, escape: String? = #"\\(?:u\{[\h]{1,8}\}|u[\h]{4}|U[\h]{8}|x[\h]{2}|[0-7]{1,3}|.)"#,
                            scope: Scope = .string, singleLine: Bool = true, extra: [Rule] = []) -> GrammarState {
        var rules = extra
        if let escape { rules.append(.match(escape, .escape)) }
        rules.append(.pop(close))
        return GrammarState(scope: scope, popAtLineEnd: singleLine, rules: rules)
    }

    /// Code inside `open`/`close` interpolation (`${…}`, `#{…}`): the `close` pops back to the
    /// string; nested braces are balanced so `${ {a: 1} }` works.
    static func interpolationStates(name: String, close: String = #"\}"#, include root: String = "root") -> [String: GrammarState] {
        [
            name: [
                .pop(close, scope: .interpolation),
                .push(#"\{"#, name + "Braces"),
                .include(root),
            ],
            name + "Braces": [
                .push(#"\{"#, name + "Braces"),
                .pop(#"\}"#),
                .include(root),
            ],
        ]
    }

    // MARK: Identifiers

    /// `Name(` → function call.
    static let functionCall: Rule = .match(#"[A-Za-z_]\w*(?=\s*\()"#, .functionCall)

    /// Capitalized identifiers → types; ALL_CAPS → constants.
    static let constantsAndTypes: [Rule] = [
        .match(#"\b[A-Z][A-Z0-9_]*[A-Z0-9]\b(?!\s*\()"#, .constantOther),
        .match(#"\b[A-Z]\w*"#, .type),
    ]

    /// An identifier after `.` → property (after calls have been tried).
    static let property: Rule = .match(#"(?<=\.)[A-Za-z_]\w*"#, .property)

    /// Concatenates rule lists. (A long chain of `+` on arrays literals is slow to type-check.)
    static func rules(_ lists: [Rule]...) -> [Rule] {
        lists.flatMap { $0 }
    }

    static func merge(_ dictionaries: [String: GrammarState]...) -> [String: GrammarState] {
        var result: [String: GrammarState] = [:]
        for dictionary in dictionaries { result.merge(dictionary) { _, new in new } }
        return result
    }
}
