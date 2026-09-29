@testable import SwiftHighlight

/// `text → scope` pairs for readable expectations.
func pairs(_ code: String, _ language: Language) -> [String] {
    language.tokenize(code).map { "\($0.text(in: code))→\($0.scope.name)" }
}

/// The scope of the first token whose text is exactly `text`, or nil when that text is unscoped.
func scope(of text: String, in code: String, _ language: Language) -> String? {
    language.tokenize(code).first { $0.text(in: code) == text }?.scope.name
}

func builtin(_ id: String) -> Language {
    guard let language = LanguageRegistry.shared.language(named: id) else {
        fatalError("No built-in language \(id)")
    }
    return language
}

/// Checks the invariants every tokenization must hold: in order, non-overlapping, non-empty,
/// in bounds, and on scalar boundaries.
func validate(_ tokens: [Token], in code: String) -> Bool {
    let bytes = Array(code.utf8)
    var previous = 0
    for token in tokens {
        guard token.range.lowerBound >= previous, !token.range.isEmpty, token.range.upperBound <= bytes.count,
              token.scope.id != 0 else { return false }
        for edge in [token.range.lowerBound, token.range.upperBound] where edge < bytes.count {
            if bytes[edge] & 0xC0 == 0x80 { return false }
        }
        previous = token.range.upperBound
    }
    return true
}
