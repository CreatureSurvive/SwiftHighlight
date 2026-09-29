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

struct AdaptiveStyle: Hashable {
    var light: ResolvedStyle
    var dark: ResolvedStyle

    var paintsOnlyGlyphs: Bool { light.paintsOnlyGlyphs && dark.paintsOnlyGlyphs }
}

extension AdaptiveTheme {
    func adaptiveStyle(for scope: UInt32) -> AdaptiveStyle {
        scope == 0
            ? AdaptiveStyle(light: light.defaultStyle, dark: dark.defaultStyle)
            : AdaptiveStyle(light: light.style(for: Scope(id: scope)), dark: dark.style(for: Scope(id: scope)))
    }
}

extension Theme {
    func resolvedStyle(for scope: UInt32) -> ResolvedStyle {
        scope == 0 ? defaultStyle : style(for: Scope(id: scope))
    }
}

public extension HighlightedCode {
    /// The code as an `NSAttributedString` for `UITextView`, `UILabel`, `NSTextView` and friends.
    ///
    /// Bold and italic scopes use variants of `font`. Unscoped text gets the theme foreground.
    func nsAttributedString(theme: Theme, font: PlatformFont) -> NSAttributedString {
        var fonts = FontVariants(font)
        var table = StyleTable<ResolvedStyle>(resolve: theme.resolvedStyle(for:))
        return buildAttributed(table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs) { style in
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: style.foreground.platformColor,
                .font: fonts.font(bold: style.bold, italic: style.italic),
            ]
            if let background = style.background { attributes[.backgroundColor] = background.platformColor }
            if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return attributes
        }
    }

    /// The code as an `NSAttributedString` whose colors follow the system appearance.
    ///
    /// Font weight and slant come from the light theme's styles.
    func nsAttributedString(theme: AdaptiveTheme, font: PlatformFont) -> NSAttributedString {
        var fonts = FontVariants(font)
        var table = StyleTable<AdaptiveStyle>(resolve: theme.adaptiveStyle(for:))
        return buildAttributed(table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs) { style in
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: ThemeColor.dynamic(light: style.light.foreground, dark: style.dark.foreground),
                .font: fonts.font(bold: style.light.bold, italic: style.light.italic),
            ]
            if style.light.background != nil || style.dark.background != nil {
                let clear = ThemeColor(rgb: 0, alpha: 0)
                attributes[.backgroundColor] = ThemeColor.dynamic(light: style.light.background ?? clear,
                                                                  dark: style.dark.background ?? clear)
            }
            if style.light.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if style.light.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return attributes
        }
    }

    /// Builds an attributed string run by run. Attribute dictionaries are made once per distinct
    /// style and applied through CoreFoundation, which skips per-call dictionary bridging.
    internal func buildAttributed<Style: Hashable>(
        table: inout StyleTable<Style>,
        paintsOnlyGlyphs: (Style) -> Bool,
        attributes: (Style) -> [NSAttributedString.Key: Any]
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: source)
        var source = source
        let runs = source.withUTF8 { bytes in
            StyledRuns(tokens: tokens, bytes: bytes, table: &table, paintsOnlyGlyphs: paintsOnlyGlyphs)
        }
        let dictionaries = table.styles.map { attributes($0) as CFDictionary }
        let target = result as CFMutableAttributedString
        result.beginEditing()
        source.withUTF8 { bytes in
            var location = 0
            for (range, style) in zip(runs.ranges, runs.styles) {
                let length = utf16Length(bytes, range)
                CFAttributedStringSetAttributes(target, CFRange(location: location, length: length),
                                                dictionaries[style], true)
                location += length
            }
        }
        result.endEditing()
        return result
    }
}
#endif
