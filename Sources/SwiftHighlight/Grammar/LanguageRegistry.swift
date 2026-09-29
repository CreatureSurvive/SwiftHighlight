import Foundation

/// The set of languages available for lookup by name, alias, file name, extension or first line,
/// and for embedding (`embed:` rules and Markdown fences).
///
/// `LanguageRegistry.shared` holds every built-in language; grammars compile lazily on first use.
/// Register your own grammars there (or in a registry of your own) to add languages or to
/// replace a built-in one — registering a grammar with an existing `id` replaces it.
public final class LanguageRegistry: @unchecked Sendable {
    /// Every built-in language, plus anything registered at runtime.
    public static let shared = LanguageRegistry()

    private struct Entry {
        var grammar: Grammar
        var language: Language?
    }

    private let lock = NSRecursiveLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var names: [String: String] = [:]
    private var extensions: [String: String] = [:]
    private var fileNames: [String: String] = [:]

    /// A registry with the built-in languages, or an empty one.
    public init(includingBuiltins: Bool = true) {
        if includingBuiltins {
            for grammar in BuiltinGrammars.all { add(grammar, language: nil) }
        }
    }

    /// Compiles and registers `grammar`, replacing any language with the same `id`.
    @discardableResult
    public func register(_ grammar: Grammar) throws(GrammarError) -> Language {
        let language = try Language(grammar)
        register(language)
        return language
    }

    /// Registers an already-compiled language, replacing any language with the same `id`.
    public func register(_ language: Language) {
        lock.lock()
        defer { lock.unlock() }
        add(language.grammar, language: language)
    }

    /// Registers a grammar decoded from JSON.
    @discardableResult
    public func register(json: Data) throws -> Language {
        try register(try Grammar(json: json))
    }

    /// Removes the language with `id`. Returns whether one was registered.
    @discardableResult
    public func unregister(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = id.lowercased()
        guard entries.removeValue(forKey: key) != nil else { return false }
        order.removeAll { $0 == key }
        rebuildIndexes()
        return true
    }

    private func add(_ grammar: Grammar, language: Language?) {
        let key = grammar.id.lowercased()
        if entries[key] == nil { order.append(key) }
        entries[key] = Entry(grammar: grammar, language: language)
        rebuildIndexes()
    }

    /// Later registrations win ties, so a user grammar can claim an extension from a built-in.
    private func rebuildIndexes() {
        names = [:]
        extensions = [:]
        fileNames = [:]
        for key in order {
            guard let grammar = entries[key]?.grammar else { continue }
            names[key] = key
            names[grammar.name.lowercased()] = key
            for alias in grammar.aliases { names[alias.lowercased()] = key }
            for ext in grammar.fileExtensions { extensions[ext.lowercased()] = key }
            for name in grammar.fileNames { fileNames[name.lowercased()] = key }
        }
    }

    private func compiled(_ key: String) -> Language? {
        guard let entry = entries[key] else { return nil }
        if let language = entry.language { return language }
        do {
            let language = try Language(entry.grammar)
            entries[key]?.language = language
            return language
        } catch {
            assertionFailure("Grammar failed to compile: \(error)")
            return nil
        }
    }

    // MARK: Lookup

    /// The grammars of every registered language, in registration order.
    public var grammars: [Grammar] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { entries[$0]?.grammar }
    }

    /// The language with this id, name or alias (case-insensitive) — `swift`, `JS`, `c++`.
    /// A Markdown fence label's extra words (`swift title="x"`) and braces (`{python}`) are ignored.
    public func language(named name: String) -> Language? {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let label = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).first.map(String.init) ?? ""
        let cleaned = label.trimmingCharacters(in: CharacterSet(charactersIn: "{}.")).lowercased()
        if let key = names[cleaned] ?? names[trimmed.lowercased()] ?? extensions[cleaned] {
            return compiled(key)
        }
        return nil
    }

    /// The language for a file path, by exact file name first, then extension.
    public func language(forPath path: String) -> Language? {
        lock.lock()
        defer { lock.unlock() }
        let name = (path as NSString).lastPathComponent.lowercased()
        if let key = fileNames[name] { return compiled(key) }
        var candidate = name
        // Try compound extensions longest first: `d.ts`, then `ts`.
        while let dot = candidate.firstIndex(of: ".") {
            candidate = String(candidate[candidate.index(after: dot)...])
            if let key = extensions[candidate] { return compiled(key) }
        }
        return nil
    }

    /// The language whose `firstLinePattern` matches the start of `text` (shebangs, `<?xml`).
    public func language(forContent text: String) -> Language? {
        let firstLine = text.prefix(while: { $0 != "\n" && $0 != "\r" })
        guard !firstLine.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        for key in order.reversed() {
            guard entries[key]?.grammar.firstLinePattern != nil, let language = compiled(key) else { continue }
            if language.matchesFirstLine(String(firstLine.prefix(512))) { return language }
        }
        return nil
    }

    /// Best guess for a file: by path, then by content. Falls back to plain text.
    public func detect(path: String? = nil, content: String? = nil) -> Language {
        if let path, let language = language(forPath: path) { return language }
        if let content, let language = language(forContent: content) { return language }
        return .plainText
    }
}
