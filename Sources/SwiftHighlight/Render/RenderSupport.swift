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
        if tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            let lower = min(max(token.range.lowerBound, position), byteCount)
            if lower > position {
                defer { position = lower }
                return (position..<lower, 0)
            }
            let upper = min(token.range.upperBound, byteCount)
            tokenIndex += 1
            guard upper > lower else { return next() }
            position = upper
            return (lower..<upper, token.scope.id)
        }
        defer { position = byteCount }
        return (position..<byteCount, 0)
    }
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
