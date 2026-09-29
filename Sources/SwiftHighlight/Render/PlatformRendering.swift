#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#endif

#if canImport(UIKit) || canImport(AppKit)
import Foundation

public extension ThemeColor {
    /// The color as a `UIColor` / `NSColor` in sRGB.
    var platformColor: PlatformColor {
        let (red, green, blue, alpha) = components
        #if canImport(UIKit)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// A color that resolves to `light` or `dark` with the system appearance.
    static func dynamic(light: ThemeColor, dark: ThemeColor) -> PlatformColor {
        if light == dark { return light.platformColor }
        let lightColor = light.platformColor
        let darkColor = dark.platformColor
        #if os(watchOS)
        return darkColor
        #elseif canImport(UIKit)
        return UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : lightColor }
        #else
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
        #endif
    }
}

public extension Theme {
    var platformForeground: PlatformColor { foreground.platformColor }
    var platformBackground: PlatformColor { background.platformColor }
}

public extension AdaptiveTheme {
    var platformForeground: PlatformColor { ThemeColor.dynamic(light: light.foreground, dark: dark.foreground) }
    var platformBackground: PlatformColor { ThemeColor.dynamic(light: light.background, dark: dark.background) }
}

/// Bold / italic variants of one base font, created once per render.
struct FontVariants {
    let regular: PlatformFont
    private(set) var bold: PlatformFont?
    private(set) var italic: PlatformFont?
    private(set) var boldItalic: PlatformFont?

    init(_ font: PlatformFont) {
        regular = font
    }

    mutating func font(bold isBold: Bool, italic isItalic: Bool) -> PlatformFont {
        switch (isBold, isItalic) {
        case (false, false):
            return regular
        case (true, false):
            if bold == nil { bold = Self.variant(regular, bold: true, italic: false) }
            return bold!
        case (false, true):
            if italic == nil { italic = Self.variant(regular, bold: false, italic: true) }
            return italic!
        case (true, true):
            if boldItalic == nil { boldItalic = Self.variant(regular, bold: true, italic: true) }
            return boldItalic!
        }
    }

    private static func variant(_ font: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }
}

public extension HighlightedCode {
    /// The code as an `NSAttributedString` for `UITextView`, `UILabel`, `NSTextView` and friends.
    ///
    /// Bold and italic scopes use variants of `font`. Unscoped text gets the theme foreground.
    func nsAttributedString(theme: Theme, font: PlatformFont) -> NSAttributedString {
        buildNSAttributedString(font: font, foreground: theme.foreground.platformColor) { scope in
            let style = scope == 0 ? theme.defaultStyle : theme.style(for: Scope(id: scope))
            return (style, style.foreground.platformColor, style.background?.platformColor)
        }
    }

    /// The code as an `NSAttributedString` whose colors follow the system appearance.
    ///
    /// Font weight and slant come from the light theme's styles.
    func nsAttributedString(theme: AdaptiveTheme, font: PlatformFont) -> NSAttributedString {
        buildNSAttributedString(font: font, foreground: theme.platformForeground) { scope in
            let light = scope == 0 ? theme.light.defaultStyle : theme.light.style(for: Scope(id: scope))
            let dark = scope == 0 ? theme.dark.defaultStyle : theme.dark.style(for: Scope(id: scope))
            let background: PlatformColor? = switch (light.background, dark.background) {
            case (nil, nil): nil
            case let (lightBackground, darkBackground):
                ThemeColor.dynamic(light: lightBackground ?? ThemeColor(rgb: 0, alpha: 0),
                                   dark: darkBackground ?? ThemeColor(rgb: 0, alpha: 0))
            }
            return (light, ThemeColor.dynamic(light: light.foreground, dark: dark.foreground), background)
        }
    }

    private func buildNSAttributedString(
        font: PlatformFont,
        foreground: PlatformColor,
        resolve: (UInt32) -> (ResolvedStyle, PlatformColor, PlatformColor?)
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: foreground])
        guard !tokens.isEmpty else { return result }
        var fonts = FontVariants(font)
        var cache: [UInt32: [NSAttributedString.Key: Any]] = [:]
        var utf16Position = 0
        var bytePosition = 0
        var source = source
        result.beginEditing()
        source.withUTF8 { bytes in
            for token in tokens {
                guard token.range.upperBound <= bytes.count, token.range.lowerBound >= bytePosition else { continue }
                utf16Position += utf16Length(bytes, bytePosition..<token.range.lowerBound)
                let length = utf16Length(bytes, token.range)
                bytePosition = token.range.upperBound
                defer { utf16Position += length }

                let attributes: [NSAttributedString.Key: Any]
                if let cached = cache[token.scope.id] {
                    attributes = cached
                } else {
                    let (style, color, background) = resolve(token.scope.id)
                    var built: [NSAttributedString.Key: Any] = [
                        .foregroundColor: color,
                        .font: fonts.font(bold: style.bold, italic: style.italic),
                    ]
                    if let background { built[.backgroundColor] = background }
                    if style.underline { built[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    if style.strikethrough { built[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    cache[token.scope.id] = built
                    attributes = built
                }
                result.addAttributes(attributes, range: NSRange(location: utf16Position, length: length))
            }
        }
        result.endEditing()
        return result
    }
}
#endif
