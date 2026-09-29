import Foundation

/// A dotted, TextMate-style name for what a piece of code is — `keyword.control`, `string`,
/// `constant.character.escape`.
///
/// Scopes are interned: comparing, hashing and storing one costs the same as an integer, and
/// tokens carry them without allocating. The names follow TextMate conventions, so themes written
/// for TextMate, Sublime Text or VS Code apply to them directly, and a theme resolves an unknown
/// scope by trimming trailing components (`string.quoted.double` → `string.quoted` → `string`).
public struct Scope: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// The interned identifier. `0` is reserved for "no scope".
    public let id: UInt32

    /// Interns `name`. Leading and trailing whitespace and empty components are dropped.
    public init(_ name: String) {
        id = ScopeRegistry.shared.intern(name)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    init(id: UInt32) {
        self.id = id
    }

    /// The scope's full dotted name.
    public var name: String { ScopeRegistry.shared.name(of: id) }

    /// The scope one level up (`string.quoted` for `string.quoted.double`), or `nil` at the top.
    public var parent: Scope? {
        let parentID = ScopeRegistry.shared.parent(of: id)
        return parentID == 0 ? nil : Scope(id: parentID)
    }

    /// Whether `self` is `other` or nested under it (`string.quoted` is within `string`).
    public func isWithin(_ other: Scope) -> Bool {
        var current: UInt32 = id
        while current != 0 {
            if current == other.id { return true }
            current = ScopeRegistry.shared.parent(of: current)
        }
        return false
    }

    public var description: String { name }

    public static func < (lhs: Scope, rhs: Scope) -> Bool { lhs.name < rhs.name }
}

extension Scope: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

// MARK: - Standard scopes

public extension Scope {
    static let comment: Scope = "comment"
    static let commentLine: Scope = "comment.line"
    static let commentBlock: Scope = "comment.block"
    static let commentDocumentation: Scope = "comment.block.documentation"

    static let string: Scope = "string"
    static let stringQuoted: Scope = "string.quoted"
    static let stringRegex: Scope = "string.regexp"
    static let stringSpecial: Scope = "string.other"
    static let escape: Scope = "constant.character.escape"
    /// The delimiters around an interpolated expression inside a string (`\(` … `)`, `${` … `}`).
    static let interpolation: Scope = "punctuation.section.embedded"

    static let number: Scope = "constant.numeric"
    static let constant: Scope = "constant.language"
    static let constantOther: Scope = "constant.other"
    static let character: Scope = "constant.character"

    static let keyword: Scope = "keyword"
    static let keywordControl: Scope = "keyword.control"
    static let keywordOperator: Scope = "keyword.operator"
    static let keywordDeclaration: Scope = "storage.type"
    static let modifier: Scope = "storage.modifier"
    static let attribute: Scope = "storage.modifier.attribute"
    static let preprocessor: Scope = "meta.preprocessor"

    static let type: Scope = "entity.name.type"
    static let typeBuiltin: Scope = "support.type"
    static let namespace: Scope = "entity.name.namespace"
    static let function: Scope = "entity.name.function"
    static let functionCall: Scope = "support.function"
    static let functionBuiltin: Scope = "support.function.builtin"

    static let variable: Scope = "variable"
    static let variableBuiltin: Scope = "variable.language"
    static let parameter: Scope = "variable.parameter"
    static let property: Scope = "variable.other.property"
    static let label: Scope = "entity.name.label"

    static let tag: Scope = "entity.name.tag"
    static let tagAttribute: Scope = "entity.other.attribute-name"
    /// Object keys in data formats (JSON, YAML, TOML), styled like VS Code's property names.
    static let key: Scope = "support.type.property-name"

    static let `operator`: Scope = "keyword.operator"
    static let punctuation: Scope = "punctuation"

    static let heading: Scope = "markup.heading"
    static let bold: Scope = "markup.bold"
    static let italic: Scope = "markup.italic"
    static let strikethrough: Scope = "markup.strikethrough"
    static let inlineCode: Scope = "markup.inline.raw"
    static let link: Scope = "markup.underline.link"
    static let quote: Scope = "markup.quote"
    static let listMarker: Scope = "punctuation.definition.list"

    static let inserted: Scope = "markup.inserted"
    static let deleted: Scope = "markup.deleted"
    static let changed: Scope = "markup.changed"
    static let diffHeader: Scope = "meta.diff.header"
    static let diffRange: Scope = "meta.diff.range"

    static let invalid: Scope = "invalid"
}

// MARK: - Registry

/// Process-wide intern table for scope names. Appends only; lookups by id never block writers
/// for long, and the hot tokenizer path never touches it.
final class ScopeRegistry: @unchecked Sendable {
    static let shared = ScopeRegistry()

    private let lock = NSLock()
    private var names: [String] = [""]
    private var parents: [UInt32] = [0]
    private var ids: [String: UInt32] = ["": 0]

    func intern(_ raw: String) -> UInt32 {
        let name = Self.normalize(raw)
        lock.lock()
        defer { lock.unlock() }
        return internLocked(name)
    }

    private func internLocked(_ name: String) -> UInt32 {
        if let existing = ids[name] { return existing }
        var parent: UInt32 = 0
        if let dot = name.lastIndex(of: ".") {
            parent = internLocked(String(name[..<dot]))
        }
        let id = UInt32(names.count)
        names.append(name)
        parents.append(parent)
        ids[name] = id
        return id
    }

    func name(of id: UInt32) -> String {
        lock.lock()
        defer { lock.unlock() }
        return Int(id) < names.count ? names[Int(id)] : ""
    }

    func parent(of id: UInt32) -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return Int(id) < parents.count ? parents[Int(id)] : 0
    }

    /// Snapshot of every scope's parent, indexed by id, for resolvers that walk many chains.
    func parentTable() -> [UInt32] {
        lock.lock()
        defer { lock.unlock() }
        return parents
    }

    private static func normalize(_ raw: String) -> String {
        raw.split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }
}
