import Foundation

/// A declarative language definition: named states, each an ordered list of rules.
///
/// Highlighting starts in the `root` state. At each position the current state's rules are tried
/// in order and the first that matches wins; its text is tokenized with the rule's scope, and it
/// may `push` a new state (entering a string or comment), `pop` back out, `set` the current state,
/// or `embed` another language. States persist across lines, so multi-line constructs need no
/// special handling, and every line can be tokenized from the state the previous line ended in —
/// which is what makes incremental re-highlighting cheap.
///
/// Grammars are plain `Codable` values: write them in Swift, or load them from JSON.
///
/// ```swift
/// let grammar = Grammar(
///     name: "INI",
///     fileExtensions: ["ini"],
///     states: [
///         "root": [
///             .match(#"[;#].*"#, .commentLine),
///             .match(#"^\s*(\[)([^\]]*)(\])"#, captures: [1: .punctuation, 2: .type, 3: .punctuation]),
///             .match(#"^\s*([\w.-]+)\s*(=)"#, captures: [1: .key, 2: .operator]),
///             .push(#"""#, "string", scope: .string),
///         ],
///         "string": GrammarState(scope: .string, popAtLineEnd: true, rules: [
///             .match(#"\\."#, .escape),
///             .pop(#"""#),
///         ]),
///     ]
/// )
/// ```
///
/// Patterns use a line-anchored regular-expression dialect; see ``Rule/match`` for the syntax.
public struct Grammar: Codable, Hashable, Sendable {
    /// Display name, like "Swift" or "Objective-C".
    public var name: String
    /// Canonical lookup key; defaults to the lowercased name.
    public var id: String
    /// Other names the language is known by, including Markdown fence labels (`js`, `sh`).
    public var aliases: [String]
    /// File extensions without the dot (`swift`, `tsx`).
    public var fileExtensions: [String]
    /// Exact file names (`Dockerfile`, `Makefile`, `.bashrc`).
    public var fileNames: [String]
    /// A pattern tested against a file's first line (shebangs, `<?xml`) when the name is not enough.
    public var firstLinePattern: String?
    /// Pattern for identifiers checked against `words` rules.
    /// Defaults to `[A-Za-z_]\w*`.
    public var identifierPattern: String?
    /// Class body (as inside `[…]`) of characters that make up a word; defaults to `\w`.
    /// Text that no rule matches is skipped a whole word at a time, so no rule ever starts in
    /// the middle of a word.
    public var wordCharacters: String?
    /// The states, keyed by name. Must contain `root`.
    public var states: [String: GrammarState]

    public init(
        name: String,
        id: String? = nil,
        aliases: [String] = [],
        fileExtensions: [String] = [],
        fileNames: [String] = [],
        firstLinePattern: String? = nil,
        identifierPattern: String? = nil,
        wordCharacters: String? = nil,
        states: [String: GrammarState]
    ) {
        self.name = name
        self.id = id ?? name.lowercased()
        self.aliases = aliases
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.firstLinePattern = firstLinePattern
        self.identifierPattern = identifierPattern
        self.wordCharacters = wordCharacters
        self.states = states
    }

    /// Decodes a grammar from JSON.
    public init(json: Data) throws {
        self = try JSONDecoder().decode(Grammar.self, from: json)
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case name, id, aliases, fileExtensions, fileNames, firstLinePattern, identifierPattern, wordCharacters, states
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? name.lowercased()
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        fileExtensions = try container.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []
        fileNames = try container.decodeIfPresent([String].self, forKey: .fileNames) ?? []
        firstLinePattern = try container.decodeIfPresent(String.self, forKey: .firstLinePattern)
        identifierPattern = try container.decodeIfPresent(String.self, forKey: .identifierPattern)
        wordCharacters = try container.decodeIfPresent(String.self, forKey: .wordCharacters)
        states = try container.decode([String: GrammarState].self, forKey: .states)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(id, forKey: .id)
        if !aliases.isEmpty { try container.encode(aliases, forKey: .aliases) }
        if !fileExtensions.isEmpty { try container.encode(fileExtensions, forKey: .fileExtensions) }
        if !fileNames.isEmpty { try container.encode(fileNames, forKey: .fileNames) }
        try container.encodeIfPresent(firstLinePattern, forKey: .firstLinePattern)
        try container.encodeIfPresent(identifierPattern, forKey: .identifierPattern)
        try container.encodeIfPresent(wordCharacters, forKey: .wordCharacters)
        try container.encode(states, forKey: .states)
    }
}

/// One lexical context of a grammar — the top level, inside a string, inside a comment.
public struct GrammarState: Codable, Hashable, Sendable, ExpressibleByArrayLiteral {
    /// Scope for text in this state that no rule matches (a string's body, a comment's text).
    public var scope: Scope?
    /// Leave this state at the end of every line. Use for single-line constructs (C strings,
    /// line comments with rules, preprocessor lines) so an unterminated one cannot run on.
    public var popAtLineEnd: Bool
    public var rules: [Rule]

    public init(scope: Scope? = nil, popAtLineEnd: Bool = false, rules: [Rule]) {
        self.scope = scope
        self.popAtLineEnd = popAtLineEnd
        self.rules = rules
    }

    public init(arrayLiteral rules: Rule...) {
        self.init(rules: rules)
    }

    private enum CodingKeys: String, CodingKey { case scope, popAtLineEnd, rules }

    public init(from decoder: any Decoder) throws {
        // A bare array is shorthand for a state with only rules.
        if let rules = try? decoder.singleValueContainer().decode([Rule].self) {
            self.init(rules: rules)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scope: try container.decodeIfPresent(Scope.self, forKey: .scope),
            popAtLineEnd: try container.decodeIfPresent(Bool.self, forKey: .popAtLineEnd) ?? false,
            rules: try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        if scope == nil, !popAtLineEnd {
            var container = encoder.singleValueContainer()
            try container.encode(rules)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(scope, forKey: .scope)
        if popAtLineEnd { try container.encode(true, forKey: .popAtLineEnd) }
        try container.encode(rules, forKey: .rules)
    }
}

/// One entry in a state: a pattern with a scope and an optional state change, or an include.
///
/// **Pattern syntax.** Patterns are matched against one line at a time (without its line break),
/// anchored at the current position, over UTF-8:
/// - Literals and `\`-escaped punctuation; `.` (any character); classes `[a-z_]`, `[^"\\]`
///   (ASCII members; a negated class also matches every non-ASCII character)
/// - `\d \D \w \W \s \S`, and `\h \H` for hex digits; `\w` includes all non-ASCII letters
/// - `\n \t \r \f \v \0 \e \xHH \u{HHHH}`
/// - Anchors `^` (line start), `$` (line end), `\b`, `\B`
/// - Groups `(…)`, `(?:…)`, `(?<name>…)`; atomic `(?>…)`; lookahead `(?=…) (?!…)`; lookbehind
///   `(?<=…) (?<!…)` of bounded length; backreferences `\1`–`\9`
/// - Quantifiers `* + ? {n} {n,} {n,m}`, lazy with `?`, possessive with `+`
/// - A leading `(?i)` makes the whole pattern ASCII case-insensitive
/// - `\k` matches the text a `push`/`embed` rule captured with `delimiter:` — for heredocs, raw
///   strings (`#"…"#`), and fences whose closing delimiter must repeat the opening one
public struct Rule: Codable, Hashable, Sendable {
    /// The pattern to match. Required unless the rule is a `words` or `include` rule.
    public var match: String?
    /// A keyword list: the rule matches an identifier (see ``Grammar/identifierPattern``) only
    /// when it is one of these words. Matching is a hash lookup, not an alternation.
    public var words: [String]?
    /// Compare `words` ignoring ASCII case (SQL).
    public var caseInsensitive: Bool?
    /// Scope for the whole match. `nil` means the scope of the state entered (for `push`,
    /// `set` and `embed`), left (for `pop`), or current (otherwise).
    public var scope: Scope?
    /// Scopes for capture groups, overriding `scope` over each group's text.
    public var captures: [Int: Scope]?
    /// Enter this state after the match.
    public var push: String?
    /// Replace the current state with this one after the match.
    public var set: String?
    /// Leave the current state after the match.
    public var pop: Bool?
    /// Switch to another language after the match, until `end` matches. The value is a language
    /// name or alias, or `$1`–`$9` to take it from a capture group (Markdown fences). An unknown
    /// language embeds plain text.
    public var embed: String?
    /// The pattern that ends an `embed`. It is tried before every token inside the embedded
    /// language, so the embedded code cannot run past it; use a lookahead to leave the closing
    /// text for the outer grammar.
    public var end: String?
    /// Scope for the text `end` matches.
    public var endScope: Scope?
    /// Capture scopes for `end`.
    public var endCaptures: [Int: Scope]?
    /// The capture group whose text `\k` matches inside the state entered (or in `end`).
    public var delimiter: Int?
    /// Splice in another state's rules at this position.
    public var include: String?

    public init(
        match: String? = nil,
        words: [String]? = nil,
        caseInsensitive: Bool? = nil,
        scope: Scope? = nil,
        captures: [Int: Scope]? = nil,
        push: String? = nil,
        set: String? = nil,
        pop: Bool? = nil,
        embed: String? = nil,
        end: String? = nil,
        endScope: Scope? = nil,
        endCaptures: [Int: Scope]? = nil,
        delimiter: Int? = nil,
        include: String? = nil
    ) {
        self.match = match
        self.words = words
        self.caseInsensitive = caseInsensitive
        self.scope = scope
        self.captures = captures
        self.push = push
        self.set = set
        self.pop = pop
        self.embed = embed
        self.end = end
        self.endScope = endScope
        self.endCaptures = endCaptures
        self.delimiter = delimiter
        self.include = include
    }

    // MARK: Builders

    /// Colors `pattern` with `scope` (and capture scopes), staying in the current state.
    public static func match(_ pattern: String, _ scope: Scope? = nil, captures: [Int: Scope]? = nil) -> Rule {
        Rule(match: pattern, scope: scope, captures: captures)
    }

    /// Colors any of `words` with `scope` when they appear as whole identifiers.
    public static func words(_ words: [String], _ scope: Scope, caseInsensitive: Bool = false) -> Rule {
        Rule(words: words, caseInsensitive: caseInsensitive ? true : nil, scope: scope)
    }

    /// Enters `state` after matching `pattern`.
    public static func push(_ pattern: String, _ state: String, scope: Scope? = nil, captures: [Int: Scope]? = nil,
                            delimiter: Int? = nil) -> Rule {
        Rule(match: pattern, scope: scope, captures: captures, push: state, delimiter: delimiter)
    }

    /// Leaves the current state after matching `pattern`.
    public static func pop(_ pattern: String, scope: Scope? = nil, captures: [Int: Scope]? = nil) -> Rule {
        Rule(match: pattern, scope: scope, captures: captures, pop: true)
    }

    /// Replaces the current state with `state` after matching `pattern`.
    public static func set(_ pattern: String, _ state: String, scope: Scope? = nil, captures: [Int: Scope]? = nil,
                           delimiter: Int? = nil) -> Rule {
        Rule(match: pattern, scope: scope, captures: captures, set: state, delimiter: delimiter)
    }

    /// Highlights with another language from after `pattern` until `end`.
    public static func embed(_ pattern: String, language: String, end: String, scope: Scope? = nil,
                             captures: [Int: Scope]? = nil, endScope: Scope? = nil,
                             endCaptures: [Int: Scope]? = nil, delimiter: Int? = nil) -> Rule {
        Rule(match: pattern, scope: scope, captures: captures, embed: language, end: end, endScope: endScope,
             endCaptures: endCaptures, delimiter: delimiter)
    }

    /// Splices in the rules of `state`.
    public static func include(_ state: String) -> Rule {
        Rule(include: state)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case match, words, caseInsensitive, scope, captures, push, set, pop, embed, end, endScope, endCaptures,
             delimiter, include
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeIfPresent(String.self, forKey: .match)
        words = try container.decodeIfPresent([String].self, forKey: .words)
        caseInsensitive = try container.decodeIfPresent(Bool.self, forKey: .caseInsensitive)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope)
        captures = try Self.decodeCaptures(container, .captures)
        push = try container.decodeIfPresent(String.self, forKey: .push)
        set = try container.decodeIfPresent(String.self, forKey: .set)
        pop = try container.decodeIfPresent(Bool.self, forKey: .pop)
        embed = try container.decodeIfPresent(String.self, forKey: .embed)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        endScope = try container.decodeIfPresent(Scope.self, forKey: .endScope)
        endCaptures = try Self.decodeCaptures(container, .endCaptures)
        delimiter = try container.decodeIfPresent(Int.self, forKey: .delimiter)
        include = try container.decodeIfPresent(String.self, forKey: .include)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(match, forKey: .match)
        try container.encodeIfPresent(words, forKey: .words)
        try container.encodeIfPresent(caseInsensitive, forKey: .caseInsensitive)
        try container.encodeIfPresent(scope, forKey: .scope)
        if let captures { try container.encode(Self.stringKeyed(captures), forKey: .captures) }
        try container.encodeIfPresent(push, forKey: .push)
        try container.encodeIfPresent(set, forKey: .set)
        try container.encodeIfPresent(pop, forKey: .pop)
        try container.encodeIfPresent(embed, forKey: .embed)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encodeIfPresent(endScope, forKey: .endScope)
        if let endCaptures { try container.encode(Self.stringKeyed(endCaptures), forKey: .endCaptures) }
        try container.encodeIfPresent(delimiter, forKey: .delimiter)
        try container.encodeIfPresent(include, forKey: .include)
    }

    /// JSON objects need string keys: captures are written `{"1": "keyword"}`.
    private static func decodeCaptures(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [Int: Scope]? {
        guard let raw = try container.decodeIfPresent([String: Scope].self, forKey: key) else { return nil }
        var result: [Int: Scope] = [:]
        for (group, scope) in raw {
            guard let index = Int(group) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container,
                                                       debugDescription: "Capture key \(group.debugDescription) is not a group number")
            }
            result[index] = scope
        }
        return result
    }

    private static func stringKeyed(_ captures: [Int: Scope]) -> [String: Scope] {
        Dictionary(uniqueKeysWithValues: captures.map { (String($0.key), $0.value) })
    }
}
