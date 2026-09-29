/// Options for HTML output.
public struct HTMLOptions: Sendable {
    /// Prefix for scope class names: scope `keyword.control` becomes class `hl-keyword-control`.
    public var classPrefix: String
    /// Wrap the output in `<pre><code>…</code></pre>`.
    public var wrapInPre: Bool
    /// Extra class on the `<pre>` element (always also given `classPrefix + "code"`).
    public var preClass: String?

    public init(classPrefix: String = "hl-", wrapInPre: Bool = true, preClass: String? = nil) {
        self.classPrefix = classPrefix
        self.wrapInPre = wrapInPre
        self.preClass = preClass
    }
}

public extension HighlightedCode {
    /// HTML with inline `style` attributes from `theme`: self-contained, no stylesheet needed.
    func html(theme: Theme, options: HTMLOptions = HTMLOptions()) -> String {
        var table = StyleTable<ResolvedStyle>(resolve: theme.resolvedStyle(for:))
        let preStyle = "background-color:\(theme.background.css);color:\(theme.foreground.css)"
        return renderHTML(options: options, preStyle: preStyle, table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs) {
            let css = $0.cssDeclarations(defaultForeground: theme.foreground)
            return css.isEmpty ? nil : "style=\"\(css)\""
        }
    }

    /// HTML with scope class names (`<span class="hl-string">`); style it with ``Theme/css(options:)``.
    func html(options: HTMLOptions = HTMLOptions()) -> String {
        var table = StyleTable<UInt32> { $0 }
        return renderHTML(options: options, preStyle: nil, table: &table, paintsOnlyGlyphs: { _ in false }) {
            $0 == 0 ? nil : "class=\"\(Scope(id: $0).cssClass(prefix: options.classPrefix))\""
        }
    }

    private func renderHTML<Style: Hashable>(options: HTMLOptions, preStyle: String?, table: inout StyleTable<Style>,
                                             paintsOnlyGlyphs: (Style) -> Bool,
                                             attribute: (Style) -> String?) -> String {
        var output: [UInt8] = []
        output.reserveCapacity(source.utf8.count * 2)
        if options.wrapInPre {
            var classes = options.classPrefix + "code"
            if let extra = options.preClass { classes += " " + extra }
            output += Array("<pre class=\"\(HTMLEscaping.attribute(classes))\"".utf8)
            if let preStyle { output += Array(" style=\"\(preStyle)\"".utf8) }
            output += Array("><code>".utf8)
        }
        var source = source
        source.withUTF8 { bytes in
            let runs = StyledRuns(tokens: tokens, bytes: bytes, table: &table, paintsOnlyGlyphs: paintsOnlyGlyphs)
            let openings = table.styles.map { style in attribute(style).map { Array("<span \($0)>".utf8) } }
            let close = Array("</span>".utf8)
            for (range, style) in zip(runs.ranges, runs.styles) {
                if let open = openings[style] { output += open }
                HTMLEscaping.appendEscaped(bytes, range, to: &output)
                if openings[style] != nil { output += close }
            }
        }
        if options.wrapInPre { output += Array("</code></pre>".utf8) }
        return String(decoding: output, as: UTF8.self)
    }
}

public extension Theme {
    /// A stylesheet for class-based HTML (``HighlightedCode/html(options:)``).
    ///
    /// Scope fallback is expressed with `[class|=…]` selectors, ordered from general to specific,
    /// so `hl-keyword-control` picks up `keyword` rules unless `keyword.control` overrides them.
    func css(options: HTMLOptions = HTMLOptions()) -> String {
        let root = "." + options.classPrefix + "code"
        var lines = ["\(root) { background-color: \(background.css); color: \(foreground.css); }"]
        let sorted = styles.sorted { lhs, rhs in
            let lhsDepth = lhs.key.name.split(separator: ".").count
            let rhsDepth = rhs.key.name.split(separator: ".").count
            return lhsDepth != rhsDepth ? lhsDepth < rhsDepth : lhs.key.name < rhs.key.name
        }
        for (scope, style) in sorted {
            let declarations = style.cssDeclarations
            guard !declarations.isEmpty else { continue }
            lines.append("\(root) [class|=\"\(scope.cssClass(prefix: options.classPrefix))\"] { \(declarations) }")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public extension AdaptiveTheme {
    /// A stylesheet that switches between the light and dark themes with `prefers-color-scheme`.
    func css(options: HTMLOptions = HTMLOptions()) -> String {
        light.css(options: options) + "@media (prefers-color-scheme: dark) {\n" + dark.css(options: options) + "}\n"
    }
}

extension Scope {
    func cssClass(prefix: String) -> String {
        prefix + name.replacingOccurrences(of: ".", with: "-")
    }
}

extension ThemeColor {
    var css: String {
        alpha == 255 ? hex : "rgba(\(red), \(green), \(blue), \(String(format: "%.3f", Double(alpha) / 255)))"
    }
}

extension Style {
    /// Declarations for the properties this style sets.
    var cssDeclarations: String {
        var parts: [String] = []
        if let foreground { parts.append("color: \(foreground.css)") }
        if let background { parts.append("background-color: \(background.css)") }
        if let bold { parts.append("font-weight: \(bold ? "bold" : "normal")") }
        if let italic { parts.append("font-style: \(italic ? "italic" : "normal")") }
        var decorations: [String] = []
        if underline == true { decorations.append("underline") }
        if strikethrough == true { decorations.append("line-through") }
        if !decorations.isEmpty {
            parts.append("text-decoration: \(decorations.joined(separator: " "))")
        } else if underline == false || strikethrough == false {
            parts.append("text-decoration: none")
        }
        return parts.joined(separator: "; ")
    }
}

extension ResolvedStyle {
    /// Inline declarations, omitting what matches the surrounding defaults.
    func cssDeclarations(defaultForeground: ThemeColor) -> String {
        var parts: [String] = []
        if foreground != defaultForeground { parts.append("color:\(foreground.css)") }
        if let background { parts.append("background-color:\(background.css)") }
        if bold { parts.append("font-weight:bold") }
        if italic { parts.append("font-style:italic") }
        var decorations: [String] = []
        if underline { decorations.append("underline") }
        if strikethrough { decorations.append("line-through") }
        if !decorations.isEmpty { parts.append("text-decoration:\(decorations.joined(separator: " "))") }
        return parts.joined(separator: ";")
    }
}

enum HTMLEscaping {
    static func appendEscaped(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, to output: inout [UInt8]) {
        var runStart = range.lowerBound
        var index = range.lowerBound
        while index < range.upperBound {
            let replacement: String? = switch bytes[index] {
            case UInt8(ascii: "&"): "&amp;"
            case UInt8(ascii: "<"): "&lt;"
            case UInt8(ascii: ">"): "&gt;"
            case UInt8(ascii: "\""): "&quot;"
            default: nil
            }
            if let replacement {
                output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                output += Array(replacement.utf8)
                runStart = index + 1
            }
            index += 1
        }
        output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<range.upperBound]))
    }

    static func attribute(_ text: String) -> String {
        var output: [UInt8] = []
        var text = text
        text.withUTF8 { appendEscaped($0, 0..<$0.count, to: &output) }
        return String(decoding: output, as: UTF8.self)
    }
}

#if canImport(Foundation)
import Foundation
#endif
