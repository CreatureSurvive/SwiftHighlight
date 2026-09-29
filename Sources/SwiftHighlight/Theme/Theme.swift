import Foundation

/// An sRGB color with 8-bit channels. Encodes as `"#RRGGBB"` or `"#RRGGBBAA"`.
public struct ThemeColor: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`.
    public init(rgb: UInt32, alpha: UInt8 = 255) {
        self.init(red: UInt8((rgb >> 16) & 0xFF), green: UInt8((rgb >> 8) & 0xFF), blue: UInt8(rgb & 0xFF), alpha: alpha)
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 || digits.count == 4 { digits = String(digits.flatMap { [$0, $0] }) }
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(rgb: value)
        } else {
            self.init(rgb: value >> 8, alpha: UInt8(value & 0xFF))
        }
    }

    /// For literals in code; an invalid literal is a programming error.
    public init(stringLiteral value: String) {
        guard let color = ThemeColor(hex: value) else { preconditionFailure("Invalid color literal \(value)") }
        self = color
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when not opaque.
    public var hex: String {
        alpha == 255
            ? String(format: "#%02X%02X%02X", red, green, blue)
            : String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    public var description: String { hex }

    /// Channels as 0–1 values.
    public var components: (red: Double, green: Double, blue: Double, alpha: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255, Double(alpha) / 255)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = ThemeColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color \(string.debugDescription)")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// How one scope is drawn. Every property is optional: an unset property is inherited from a
/// less specific scope (`keyword` for `keyword.control`), then from the theme's defaults.
public struct Style: Hashable, Sendable, Codable {
    public var foreground: ThemeColor?
    public var background: ThemeColor?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?

    public init(foreground: ThemeColor? = nil, background: ThemeColor? = nil, bold: Bool? = nil, italic: Bool? = nil,
                underline: Bool? = nil, strikethrough: Bool? = nil) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// Shorthand: `Style("#FF7AB2", bold: true)`.
    public init(_ foreground: ThemeColor, background: ThemeColor? = nil, bold: Bool? = nil, italic: Bool? = nil,
                underline: Bool? = nil, strikethrough: Bool? = nil) {
        self.init(foreground: foreground, background: background, bold: bold, italic: italic, underline: underline,
                  strikethrough: strikethrough)
    }

    /// Properties set in `self`, falling back to `other`'s.
    public func filling(from other: Style) -> Style {
        Style(foreground: foreground ?? other.foreground, background: background ?? other.background,
              bold: bold ?? other.bold, italic: italic ?? other.italic, underline: underline ?? other.underline,
              strikethrough: strikethrough ?? other.strikethrough)
    }

    public var isEmpty: Bool { self == Style() }
}

/// A fully resolved style: what a renderer draws for one token.
public struct ResolvedStyle: Hashable, Sendable {
    public var foreground: ThemeColor
    public var background: ThemeColor?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
}

/// Colors and font styles for scopes, plus the editor chrome around them.
///
/// Styles are keyed by scope; a token takes the style of its most specific scope with an entry,
/// property by property (`keyword.control` can set only `bold` and inherit `keyword`'s color).
/// Themes are `Codable`, and ``init(vscodeTheme:)`` / ``init(textMateTheme:)`` import the
/// VS Code, TextMate and Sublime Text formats.
public struct Theme: Hashable, Sendable, Codable, Identifiable {
    public var name: String
    public var id: String { name }
    public var isDark: Bool
    public var foreground: ThemeColor
    public var background: ThemeColor
    public var selection: ThemeColor?
    public var lineHighlight: ThemeColor?
    public var lineNumber: ThemeColor?
    public var cursor: ThemeColor?
    public var styles: [Scope: Style]

    public init(name: String, isDark: Bool, foreground: ThemeColor, background: ThemeColor,
                selection: ThemeColor? = nil, lineHighlight: ThemeColor? = nil, lineNumber: ThemeColor? = nil,
                cursor: ThemeColor? = nil, styles: [Scope: Style]) {
        self.name = name
        self.isDark = isDark
        self.foreground = foreground
        self.background = background
        self.selection = selection
        self.lineHighlight = lineHighlight
        self.lineNumber = lineNumber
        self.cursor = cursor
        self.styles = styles
    }

    /// The style for `scope`, merged from its most specific entries outward and completed with
    /// the theme defaults.
    public func style(for scope: Scope) -> ResolvedStyle {
        var style = Style()
        var current: Scope? = scope.id == 0 ? nil : scope
        while let scope = current {
            if let entry = styles[scope] { style = style.filling(from: entry) }
            current = scope.parent
        }
        return ResolvedStyle(foreground: style.foreground ?? foreground, background: style.background,
                             bold: style.bold ?? false, italic: style.italic ?? false,
                             underline: style.underline ?? false, strikethrough: style.strikethrough ?? false)
    }

    /// The style of unscoped text.
    public var defaultStyle: ResolvedStyle {
        ResolvedStyle(foreground: foreground, background: nil, bold: false, italic: false, underline: false,
                      strikethrough: false)
    }

    /// Returns a copy with `style` merged over the existing entry for `scope`.
    public func setting(_ scope: Scope, _ style: Style) -> Theme {
        var copy = self
        copy.styles[scope] = style.filling(from: styles[scope] ?? Style())
        return copy
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case name, isDark, foreground, background, selection, lineHighlight, lineNumber, cursor, styles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isDark = try container.decodeIfPresent(Bool.self, forKey: .isDark) ?? false
        foreground = try container.decode(ThemeColor.self, forKey: .foreground)
        background = try container.decode(ThemeColor.self, forKey: .background)
        selection = try container.decodeIfPresent(ThemeColor.self, forKey: .selection)
        lineHighlight = try container.decodeIfPresent(ThemeColor.self, forKey: .lineHighlight)
        lineNumber = try container.decodeIfPresent(ThemeColor.self, forKey: .lineNumber)
        cursor = try container.decodeIfPresent(ThemeColor.self, forKey: .cursor)
        let raw = try container.decodeIfPresent([String: Style].self, forKey: .styles) ?? [:]
        styles = Dictionary(raw.map { (Scope($0.key), $0.value) }, uniquingKeysWith: { $1.filling(from: $0) })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(isDark, forKey: .isDark)
        try container.encode(foreground, forKey: .foreground)
        try container.encode(background, forKey: .background)
        try container.encodeIfPresent(selection, forKey: .selection)
        try container.encodeIfPresent(lineHighlight, forKey: .lineHighlight)
        try container.encodeIfPresent(lineNumber, forKey: .lineNumber)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encode(Dictionary(uniqueKeysWithValues: styles.map { ($0.key.name, $0.value) }), forKey: .styles)
    }

    /// Decodes a theme in this package's own JSON format.
    public init(json: Data) throws {
        self = try JSONDecoder().decode(Theme.self, from: json)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// A light and a dark theme used together: renderers that produce platform colors make them
/// dynamic, so highlighted text follows the system appearance without re-rendering.
public struct AdaptiveTheme: Hashable, Sendable, Codable {
    public var light: Theme
    public var dark: Theme

    public init(light: Theme, dark: Theme) {
        self.light = light
        self.dark = dark
    }

    /// The same theme in both appearances.
    public init(_ theme: Theme) {
        self.init(light: theme, dark: theme)
    }

    public func theme(isDark: Bool) -> Theme { isDark ? dark : light }
}

/// Caches resolved styles by scope for one render pass.
struct StyleResolver {
    let theme: Theme
    private var cache: [UInt32: ResolvedStyle] = [:]

    init(_ theme: Theme) {
        self.theme = theme
    }

    mutating func style(for scope: Scope) -> ResolvedStyle {
        if let cached = cache[scope.id] { return cached }
        let style = theme.style(for: scope)
        cache[scope.id] = style
        return style
    }
}
