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
        var cache: [UInt32: String?] = [:]
        return renderHTML(options: options, preStyle: "background-color:\(theme.background.css);color:\(theme.foreground.css)") { scope in
            if let cached = cache[scope] { return cached }
            let style = theme.style(for: Scope(id: scope))
            let css = style.cssDeclarations(defaultForeground: theme.foreground)
            let attribute: String? = css.isEmpty ? nil : "style=\"\(css)\""
            cache[scope] = attribute
            return attribute
        }
    }

    /// HTML with scope class names (`<span class="hl-string">`); style it with ``Theme/css(options:)``.
    func html(options: HTMLOptions = HTMLOptions()) -> String {
        var cache: [UInt32: String] = [:]
        return renderHTML(options: options, preStyle: nil) { scope in
            if let cached = cache[scope] { return cached }
            let attribute = "class=\"\(Scope(id: scope).cssClass(prefix: options.classPrefix))\""
            cache[scope] = attribute
            return attribute
        }
    }

    private func renderHTML(options: HTMLOptions, preStyle: String?, attribute: (UInt32) -> String?) -> String {
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
            var runs = RunIterator(tokens: tokens, byteCount: bytes.count)
            while let (range, scope) = runs.next() {
                let open = scope == 0 ? nil : attribute(scope)
                if let open {
                    output += Array("<span ".utf8)
                    output += Array(open.utf8)
                    output.append(UInt8(ascii: ">"))
                }
                HTMLEscaping.appendEscaped(bytes, range, to: &output)
                if open != nil { output += Array("</span>".utf8) }
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
