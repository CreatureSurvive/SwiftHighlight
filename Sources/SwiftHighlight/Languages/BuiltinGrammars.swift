/// The grammars `LanguageRegistry.shared` starts with.
///
/// Every one is also available as a public `Grammar` value (`Grammar.swift`, `Grammar.python`…),
/// so an app can copy one and adjust it — add keywords, change scopes — then register the result
/// under the same id to replace the original.
enum BuiltinGrammars {
    static let all: [Grammar] = [
        swift, objectiveC, c, cpp, csharp, java, kotlin, dart, go, rust,
        javascript, typescript, tsx, json, html, xml, css, scss, graphql,
        python, ruby, php, lua, shell,
        yaml, toml, ini, sql, protobuf, dockerfile, makefile, diff, markdown,
    ]
}

public extension Grammar {
    /// Every built-in grammar.
    static var builtins: [Grammar] { BuiltinGrammars.all }

    /// The built-in grammar with this id (`swift`, `python`, `typescript`…).
    static func builtin(_ id: String) -> Grammar? {
        BuiltinGrammars.all.first { $0.id == id.lowercased() }
    }
}
