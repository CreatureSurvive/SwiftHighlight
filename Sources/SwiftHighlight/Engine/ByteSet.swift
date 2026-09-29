/// A set of ASCII bytes plus one flag standing for every non-ASCII scalar.
///
/// Patterns run over UTF-8, and highlighting grammars only ever need to tell ASCII punctuation
/// and letters apart; anything beyond ASCII is treated as one class (identifier-like for `\w`,
/// "not one of these" for a negated class). Matching a set always consumes a whole scalar, so
/// tokens never split a multi-byte character.
struct ByteSet: Hashable, Sendable {
    var low: UInt64 = 0
    var high: UInt64 = 0
    var nonASCII = false

    static let empty = ByteSet()

    static var all: ByteSet {
        var set = ByteSet(low: .max, high: .max)
        set.nonASCII = true
        return set
    }

    init(low: UInt64 = 0, high: UInt64 = 0, nonASCII: Bool = false) {
        self.low = low
        self.high = high
        self.nonASCII = nonASCII
    }

    init(_ string: String) {
        for byte in string.utf8 where byte < 0x80 { insert(byte) }
    }

    @inline(__always)
    func contains(_ byte: UInt8) -> Bool {
        if byte < 64 { return low & (1 &<< UInt64(byte)) != 0 }
        if byte < 128 { return high & (1 &<< UInt64(byte &- 64)) != 0 }
        return nonASCII
    }

    mutating func insert(_ byte: UInt8) {
        if byte < 64 {
            low |= 1 << UInt64(byte)
        } else if byte < 128 {
            high |= 1 << UInt64(byte - 64)
        } else {
            nonASCII = true
        }
    }

    mutating func insert(_ range: ClosedRange<UInt8>) {
        for byte in range { insert(byte) }
    }

    mutating func formUnion(_ other: ByteSet) {
        low |= other.low
        high |= other.high
        nonASCII = nonASCII || other.nonASCII
    }

    func union(_ other: ByteSet) -> ByteSet {
        var copy = self
        copy.formUnion(other)
        return copy
    }

    var inverted: ByteSet {
        ByteSet(low: ~low, high: ~high, nonASCII: !nonASCII)
    }

    var isEmpty: Bool { low == 0 && high == 0 && !nonASCII }

    /// Adds the other case of every ASCII letter already in the set.
    var caseFolded: ByteSet {
        var copy = self
        for byte in UInt8(ascii: "A")...UInt8(ascii: "Z") where contains(byte) || contains(byte + 32) {
            copy.insert(byte)
            copy.insert(byte + 32)
        }
        return copy
    }

    static let digits: ByteSet = {
        var set = ByteSet()
        set.insert(UInt8(ascii: "0")...UInt8(ascii: "9"))
        return set
    }()

    static let hexDigits: ByteSet = {
        var set = digits
        set.insert(UInt8(ascii: "a")...UInt8(ascii: "f"))
        set.insert(UInt8(ascii: "A")...UInt8(ascii: "F"))
        return set
    }()

    /// `\w`: ASCII letters, digits, underscore, and every non-ASCII scalar.
    static let word: ByteSet = {
        var set = digits
        set.insert(UInt8(ascii: "a")...UInt8(ascii: "z"))
        set.insert(UInt8(ascii: "A")...UInt8(ascii: "Z"))
        set.insert(UInt8(ascii: "_"))
        set.nonASCII = true
        return set
    }()

    static let space: ByteSet = {
        var set = ByteSet()
        for byte: UInt8 in [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D] { set.insert(byte) }
        return set
    }()
}

/// Every byte value, 0–255, as a bitmap — the first-byte dispatch filter.
struct ByteMap: Hashable, Sendable {
    var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

    static func == (lhs: ByteMap, rhs: ByteMap) -> Bool {
        lhs.words == rhs.words
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(words.0)
        hasher.combine(words.1)
        hasher.combine(words.2)
        hasher.combine(words.3)
    }

    static var all: ByteMap {
        var map = ByteMap()
        map.words = (.max, .max, .max, .max)
        return map
    }

    init() {}

    /// Bytes that can begin a scalar in `set`: its ASCII members, plus every non-ASCII byte when
    /// the set admits non-ASCII scalars.
    init(_ set: ByteSet) {
        words = (set.low, set.high, set.nonASCII ? .max : 0, set.nonASCII ? .max : 0)
    }

    @inline(__always)
    func contains(_ byte: UInt8) -> Bool {
        let bit = UInt64(1) &<< UInt64(byte & 63)
        switch byte >> 6 {
        case 0: return words.0 & bit != 0
        case 1: return words.1 & bit != 0
        case 2: return words.2 & bit != 0
        default: return words.3 & bit != 0
        }
    }

    mutating func insert(_ byte: UInt8) {
        let bit = UInt64(1) << UInt64(byte & 63)
        switch byte >> 6 {
        case 0: words.0 |= bit
        case 1: words.1 |= bit
        case 2: words.2 |= bit
        default: words.3 |= bit
        }
    }

    mutating func formUnion(_ other: ByteMap) {
        words.0 |= other.words.0
        words.1 |= other.words.1
        words.2 |= other.words.2
        words.3 |= other.words.3
    }

    var isEmpty: Bool { words.0 == 0 && words.1 == 0 && words.2 == 0 && words.3 == 0 }

    func union(_ other: ByteMap) -> ByteMap {
        var copy = self
        copy.formUnion(other)
        return copy
    }

    func isDisjoint(with other: ByteMap) -> Bool {
        words.0 & other.words.0 == 0 && words.1 & other.words.1 == 0 && words.2 & other.words.2 == 0
            && words.3 & other.words.3 == 0
    }

    func isSubset(of other: ByteMap) -> Bool {
        words.0 & ~other.words.0 == 0 && words.1 & ~other.words.1 == 0 && words.2 & ~other.words.2 == 0
            && words.3 & ~other.words.3 == 0
    }
}

/// Length of the UTF-8 scalar introduced by `lead`; 1 for ASCII and for stray continuation bytes.
@inline(__always)
func scalarLength(_ lead: UInt8) -> Int {
    if lead < 0xC0 { return 1 }
    if lead < 0xE0 { return 2 }
    if lead < 0xF0 { return 3 }
    return 4
}
