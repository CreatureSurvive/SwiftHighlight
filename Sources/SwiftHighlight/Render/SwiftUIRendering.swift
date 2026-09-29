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
        buildAttributedString { scope in
            let style = scope == 0 ? theme.defaultStyle : theme.style(for: Scope(id: scope))
            return Self.container(style, foreground: style.foreground.color, background: style.background?.color)
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    /// The code as an `AttributedString` whose colors follow the system appearance.
    ///
    /// Font weight and slant come from the light theme's styles.
    func attributedString(theme: AdaptiveTheme) -> AttributedString {
        buildAttributedString { scope in
            let light = scope == 0 ? theme.light.defaultStyle : theme.light.style(for: Scope(id: scope))
            let dark = scope == 0 ? theme.dark.defaultStyle : theme.dark.style(for: Scope(id: scope))
            let foreground = Color(platformColor: ThemeColor.dynamic(light: light.foreground, dark: dark.foreground))
            var background: Color?
            if light.background != nil || dark.background != nil {
                let clear = ThemeColor(rgb: 0, alpha: 0)
                background = Color(platformColor: ThemeColor.dynamic(light: light.background ?? clear,
                                                                     dark: dark.background ?? clear))
            }
            return Self.container(light, foreground: foreground, background: background)
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

    private func buildAttributedString(_ attributes: (UInt32) -> AttributeContainer) -> AttributedString {
        var cache: [UInt32: AttributeContainer] = [:]
        var result = AttributedString()
        let utf8 = source.utf8
        var index = utf8.startIndex
        var offset = 0
        var runs = RunIterator(tokens: tokens, byteCount: utf8.count)
        while let (range, scope) = runs.next() {
            let lower = utf8.index(index, offsetBy: range.lowerBound - offset)
            let upper = utf8.index(lower, offsetBy: range.count)
            index = upper
            offset = range.upperBound
            let container: AttributeContainer
            if let cached = cache[scope] {
                container = cached
            } else {
                container = attributes(scope)
                cache[scope] = container
            }
            result.append(AttributedString(source[lower..<upper], attributes: container))
        }
        return result
    }
}
#endif
