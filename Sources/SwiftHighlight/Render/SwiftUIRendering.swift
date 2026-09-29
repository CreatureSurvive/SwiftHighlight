#if canImport(SwiftUI)
import SwiftUI

public extension ThemeColor {
    /// The color as a SwiftUI `Color` in sRGB.
    var color: Color {
        let (red, green, blue, alpha) = components
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public extension Theme {
    var foregroundColor: Color { foreground.color }
    var backgroundColor: Color { background.color }
}

#if canImport(UIKit) || canImport(AppKit)
public extension AdaptiveTheme {
    /// Foreground that follows the system appearance.
    var foregroundColor: Color { Color(platformColor: platformForeground) }
    /// Background that follows the system appearance.
    var backgroundColor: Color { Color(platformColor: platformBackground) }
}

extension Color {
    init(platformColor: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: platformColor)
        #else
        self.init(nsColor: platformColor)
        #endif
    }
}
#endif

public extension HighlightedCode {
    /// The code as an `AttributedString` for SwiftUI `Text`, colored with `theme`.
    ///
    /// Bold and italic use inline presentation intents, so they combine with whatever font the
    /// `Text` uses (typically `.monospaced()`).
    func attributedString(theme: Theme) -> AttributedString {
        var table = StyleTable<ResolvedStyle>(resolve: theme.resolvedStyle(for:))
        return buildAttributedString(table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs) { style in
            Self.container(style, foreground: style.foreground.color, background: style.background?.color)
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    /// The code as an `AttributedString` whose colors follow the system appearance.
    ///
    /// Font weight and slant come from the light theme's styles.
    func attributedString(theme: AdaptiveTheme) -> AttributedString {
        var table = StyleTable<AdaptiveStyle>(resolve: theme.adaptiveStyle(for:))
        return buildAttributedString(table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs) { style in
            let foreground = Color(platformColor: ThemeColor.dynamic(light: style.light.foreground,
                                                                     dark: style.dark.foreground))
            var background: Color?
            if style.light.background != nil || style.dark.background != nil {
                let clear = ThemeColor(rgb: 0, alpha: 0)
                background = Color(platformColor: ThemeColor.dynamic(light: style.light.background ?? clear,
                                                                     dark: style.dark.background ?? clear))
            }
            return Self.container(style.light, foreground: foreground, background: background)
        }
    }
    #endif

    private static func container(_ style: ResolvedStyle, foreground: Color, background: Color?) -> AttributeContainer {
        var container = AttributeContainer()
        container.swiftUI.foregroundColor = foreground
        if let background { container.swiftUI.backgroundColor = background }
        var intent: InlinePresentationIntent = []
        if style.bold { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if !intent.isEmpty { container.inlinePresentationIntent = intent }
        if style.underline { container.swiftUI.underlineStyle = .single }
        if style.strikethrough { container.swiftUI.strikethroughStyle = .single }
        return container
    }

    #if canImport(UIKit) || canImport(AppKit)
    /// Builds through `NSAttributedString` and converts once: several times faster than
    /// assembling an `AttributedString` run by run.
    private func buildAttributedString<Style: Hashable>(
        table: inout StyleTable<Style>,
        paintsOnlyGlyphs: (Style) -> Bool,
        container: (Style) -> AttributeContainer
    ) -> AttributedString {
        let built = buildAttributed(table: &table, paintsOnlyGlyphs: paintsOnlyGlyphs) { style in
            // Let Foundation name each attribute the way SwiftUI's scope expects.
            let sample = AttributedString(" ", attributes: container(style))
            guard let converted = try? NSAttributedString(sample, including: \.swiftUI), converted.length > 0 else {
                return [:]
            }
            return converted.attributes(at: 0, effectiveRange: nil)
        }
        return (try? AttributedString(built, including: \.swiftUI)) ?? AttributedString(source)
    }
    #else
    private func buildAttributedString<Style: Hashable>(
        table: inout StyleTable<Style>,
        paintsOnlyGlyphs: (Style) -> Bool,
        container: (Style) -> AttributeContainer
    ) -> AttributedString {
        var containers: [Int: AttributeContainer] = [:]
        var result = AttributedString()
        var text = source
        let runs = text.withUTF8 { bytes in
            StyledRuns(tokens: tokens, bytes: bytes, table: &table, paintsOnlyGlyphs: paintsOnlyGlyphs)
        }
        let utf8 = source.utf8
        var index = utf8.startIndex
        var offset = 0
        for (range, style) in zip(runs.ranges, runs.styles) {
            let lower = utf8.index(index, offsetBy: range.lowerBound - offset)
            let upper = utf8.index(lower, offsetBy: range.count)
            index = upper
            offset = range.upperBound
            if containers[style] == nil { containers[style] = container(table.styles[style]) }
            result.append(AttributedString(source[lower..<upper], attributes: containers[style]!))
        }
        return result
    }
    #endif
}
#endif
