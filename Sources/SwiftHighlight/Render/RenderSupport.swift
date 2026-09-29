/// Walks a source string's UTF-8 alongside token boundaries, yielding each run of text with its
/// scope (0 for unscoped gaps). Shared by every renderer so all of them agree on runs.
struct RunIterator {
    let tokens: [Token]
    let byteCount: Int
    private var tokenIndex = 0
    private var position = 0

    init(tokens: [Token], byteCount: Int) {
        self.tokens = tokens
        self.byteCount = byteCount
    }

    /// The next run as (byte range, scope id), or nil at the end.
    mutating func next() -> (range: Range<Int>, scope: UInt32)? {
        guard position < byteCount else { return nil }
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            let lower = min(max(token.range.lowerBound, position), byteCount)
            if lower > position {
                defer { position = lower }
                return (position..<lower, 0)
            }
            let upper = min(token.range.upperBound, byteCount)
            tokenIndex += 1
            guard upper > lower else { continue }
            position = upper
            return (lower..<upper, token.scope.id)
        }
        defer { position = byteCount }
        return (position..<byteCount, 0)
    }
}

/// Resolved styles for one render, deduplicated: scopes that draw identically share a style
/// index, so their runs merge. Index 0 is always unscoped text.
struct StyleTable<Style: Hashable> {
    private(set) var styles: [Style]
    private var indexByScope: [UInt32: Int] = [:]
    private var indexByStyle: [Style: Int] = [:]
    private let resolve: (UInt32) -> Style

    init(resolve: @escaping (UInt32) -> Style) {
        self.resolve = resolve
        let base = resolve(0)
        styles = [base]
        indexByScope[0] = 0
        indexByStyle[base] = 0
    }

    mutating func index(for scope: UInt32) -> Int {
        if let index = indexByScope[scope] { return index }
        let style = resolve(scope)
        let index: Int
        if let existing = indexByStyle[style] {
            index = existing
        } else {
            index = styles.count
            styles.append(style)
            indexByStyle[style] = index
        }
        indexByScope[scope] = index
        return index
    }
}

/// Runs of text in the same style, with whitespace between runs folded into the run before it
/// when that cannot change what is drawn (the style paints only glyphs, no background or lines).
struct StyledRuns {
    var ranges: [Range<Int>] = []
    var styles: [Int] = []

    init<Style: Hashable>(tokens: [Token], bytes: UnsafeBufferPointer<UInt8>, table: inout StyleTable<Style>,
                          paintsOnlyGlyphs: (Style) -> Bool) {
        var runs = RunIterator(tokens: tokens, byteCount: bytes.count)
        ranges.reserveCapacity(tokens.count * 2 + 1)
        styles.reserveCapacity(tokens.count * 2 + 1)
        while let (range, scope) = runs.next() {
            let style = table.index(for: scope)
            if let lastStyle = styles.last {
                let lastRange = ranges[ranges.count - 1]
                if lastStyle == style {
                    ranges[ranges.count - 1] = lastRange.lowerBound..<range.upperBound
                    continue
                }
                // Spaces and tabs look the same in any foreground color.
                if style == 0, paintsOnlyGlyphs(table.styles[lastStyle]), Self.isBlank(bytes, range) {
                    ranges[ranges.count - 1] = lastRange.lowerBound..<range.upperBound
                    continue
                }
            }
            ranges.append(range)
            styles.append(style)
        }
    }

    private static func isBlank(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            if byte != 0x20, byte != 0x09 { return false }
            index += 1
        }
        return true
    }
}

extension ResolvedStyle {
    var paintsOnlyGlyphs: Bool { background == nil && !underline && !strikethrough }
}

/// UTF-16 length of UTF-8 bytes, for NSRange conversion.
@inline(__always)
func utf16Length(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Int {
    var count = 0
    var index = range.lowerBound
    while index < range.upperBound {
        let byte = bytes[index]
        if byte & 0xC0 != 0x80 { count &+= byte >= 0xF0 ? 2 : 1 }
        index &+= 1
    }
    return count
}
