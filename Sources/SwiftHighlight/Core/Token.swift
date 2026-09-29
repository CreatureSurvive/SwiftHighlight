/// A run of source text and its scope.
///
/// Ranges are UTF-8 byte offsets into the source string, always on `Unicode.Scalar` boundaries.
/// Text between tokens has no scope and renders in the theme's default foreground.
public struct Token: Hashable, Sendable, CustomStringConvertible {
    public var range: Range<Int>
    public var scope: Scope

    public init(range: Range<Int>, scope: Scope) {
        self.range = range
        self.scope = scope
    }

    public var description: String { "\(range.lowerBound)..<\(range.upperBound) \(scope.name)" }

    /// The token's range as indices into `source`, which must be the string it was produced from.
    public func range(in source: String) -> Range<String.Index> {
        let utf8 = source.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
        let upper = utf8.index(lower, offsetBy: range.count)
        return lower..<upper
    }

    /// The token's text within `source`.
    public func text(in source: String) -> Substring {
        source[range(in: source)]
    }
}

/// Where tokenizing stands at a line boundary: the stack of states (and embedded languages)
/// that the next line starts in.
///
/// States are compared structurally, so an editor re-highlighting after a change can stop as
/// soon as a line ends in the same state it did before the change — everything after it is
/// unaffected. See ``HighlightSession``.
public struct LineState: Hashable, Sendable {
    var frames: [Frame]

    /// The state at the start of a document in `language`.
    public init(language: Language) {
        frames = [Frame(language: language, state: 0, embedParent: nil, embedRule: -1, delimiter: [])]
    }

    init(frames: [Frame]) {
        self.frames = frames
    }

    /// The language the next line starts in — the innermost embedded language, if any.
    public var language: Language { frames[frames.count - 1].language }

    /// The document's own language.
    public var rootLanguage: Language { frames[0].language }

    /// Names of the states on the stack, outermost first (`["root", "string"]`).
    public var stateNames: [String] {
        frames.map { $0.language.tables.stateNames[Int($0.state)] }
    }

    /// Whether the next line starts at the top level of the document's language.
    public var isRoot: Bool { frames.count == 1 && frames[0].state == 0 }
}

struct Frame: Hashable, Sendable {
    var language: Language
    var state: Int32
    /// For the root frame of an embedded language: the language holding the embed rule.
    var embedParent: Language?
    /// For the root frame of an embedded language: the embed rule's index in its parent.
    var embedRule: Int32
    /// Text `\k` matches in this frame's rules (and in the embed's `end`).
    var delimiter: [UInt8]

    static func == (lhs: Frame, rhs: Frame) -> Bool {
        lhs.language === rhs.language && lhs.state == rhs.state && lhs.embedParent === rhs.embedParent
            && lhs.embedRule == rhs.embedRule && lhs.delimiter == rhs.delimiter
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(language))
        hasher.combine(state)
        hasher.combine(embedRule)
        hasher.combine(delimiter)
    }
}
