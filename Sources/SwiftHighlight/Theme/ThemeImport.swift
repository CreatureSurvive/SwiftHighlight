import Foundation

/// A theme file that could not be read.
public struct ThemeImportError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public var description: String { message }
}

public extension Theme {
    /// Imports a VS Code color theme (`*-color-theme.json`, JSON with comments allowed).
    ///
    /// Reads `editor.background`/`editor.foreground` and related chrome colors, and `tokenColors`.
    /// Selectors are mapped onto this package's scopes: a descendant selector
    /// (`source.js keyword`) uses its last scope, a comma list sets each scope, exclusions
    /// (`string - string.regexp`) keep only the included part, and a trailing language suffix
    /// (`keyword.control.swift`) is dropped when it names a registered language.
    ///
    /// Themes that `include` a parent theme file need the parent merged in first; use
    /// ``merging(_:)``.
    init(vscodeTheme data: Data, name fallbackName: String? = nil) throws {
        let json: Any
        do {
            // Twice: the first pass removes comments that can hide a trailing comma.
            json = try JSONSerialization.jsonObject(with: JSONC.strip(JSONC.strip(data)))
        } catch {
            throw ThemeImportError(message: "Not a JSON theme: \(error.localizedDescription)")
        }
        guard let root = json as? [String: Any] else { throw ThemeImportError(message: "Theme is not a JSON object") }
        let colors = root["colors"] as? [String: Any] ?? [:]
        func color(_ key: String) -> ThemeColor? { (colors[key] as? String).flatMap(ThemeColor.init(hex:)) }

        let type = (root["type"] as? String)?.lowercased()
        var tokenColors: [[String: Any]] = root["tokenColors"] as? [[String: Any]] ?? []
        if tokenColors.isEmpty, let settings = root["settings"] as? [[String: Any]] {
            tokenColors = settings
        }
        let (styles, global) = ThemeRules.parse(tokenColors)

        let background = color("editor.background") ?? global.background
        let isDark = type.map { $0.contains("dark") || $0 == "hc" } ?? background.map(ThemeRules.isDark) ?? true
        let foreground = color("editor.foreground") ?? global.foreground ?? (isDark ? "#D4D4D4" : "#333333")
        self.init(
            name: root["name"] as? String ?? fallbackName ?? "Imported Theme",
            isDark: isDark,
            foreground: foreground,
            background: background ?? (isDark ? "#1E1E1E" : "#FFFFFF"),
            selection: color("editor.selectionBackground") ?? global.selection,
            lineHighlight: color("editor.lineHighlightBackground") ?? global.lineHighlight,
            lineNumber: color("editorLineNumber.foreground"),
            cursor: color("editorCursor.foreground") ?? global.caret,
            styles: styles
        )
    }

    /// Imports a TextMate / Sublime Text `.tmTheme` (property list).
    init(textMateTheme data: Data) throws {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw ThemeImportError(message: "Not a property list theme: \(error.localizedDescription)")
        }
        guard let root = plist as? [String: Any], let settings = root["settings"] as? [[String: Any]] else {
            throw ThemeImportError(message: "Theme has no settings array")
        }
        let (styles, global) = ThemeRules.parse(settings)
        let background = global.background ?? "#FFFFFF"
        let isDark = ThemeRules.isDark(background)
        self.init(
            name: root["name"] as? String ?? "Imported Theme",
            isDark: isDark,
            foreground: global.foreground ?? (isDark ? "#D4D4D4" : "#333333"),
            background: background,
            selection: global.selection,
            lineHighlight: global.lineHighlight,
            lineNumber: global.gutterForeground,
            cursor: global.caret,
            styles: styles
        )
    }

    /// This theme with `other`'s styles layered on top (for VS Code themes that `include` a
    /// base theme: import the base, then merge the child into it).
    func merging(_ other: Theme) -> Theme {
        var copy = other
        for (scope, style) in styles {
            copy.styles[scope] = copy.styles[scope].map { $0.filling(from: style) } ?? style
        }
        return copy
    }
}

enum ThemeRules {
    struct Globals {
        var foreground: ThemeColor?
        var background: ThemeColor?
        var selection: ThemeColor?
        var lineHighlight: ThemeColor?
        var caret: ThemeColor?
        var gutterForeground: ThemeColor?
    }

    static func isDark(_ color: ThemeColor) -> Bool {
        let (red, green, blue, _) = color.components
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.5
    }

    /// TextMate-style rules: `{scope, settings: {foreground, background, fontStyle}}`. A rule
    /// without a scope holds the global colors. Later rules win over earlier ones for the same
    /// scope, property by property.
    static func parse(_ rules: [[String: Any]]) -> (styles: [Scope: Style], globals: Globals) {
        var styles: [Scope: Style] = [:]
        var globals = Globals()
        for rule in rules {
            guard let settings = rule["settings"] as? [String: Any] else { continue }
            func color(_ key: String) -> ThemeColor? { (settings[key] as? String).flatMap(ThemeColor.init(hex:)) }

            let selectors: [String]
            if let scope = rule["scope"] as? String {
                selectors = scope.split(separator: ",").map(String.init)
            } else if let scopes = rule["scope"] as? [String] {
                selectors = scopes
            } else {
                globals.foreground = color("foreground") ?? globals.foreground
                globals.background = color("background") ?? globals.background
                globals.selection = color("selection") ?? globals.selection
                globals.lineHighlight = color("lineHighlight") ?? globals.lineHighlight
                globals.caret = color("caret") ?? globals.caret
                globals.gutterForeground = color("gutterForeground") ?? globals.gutterForeground
                continue
            }

            var style = Style(foreground: color("foreground"), background: color("background"))
            if let fontStyle = settings["fontStyle"] as? String {
                let words = Set(fontStyle.lowercased().split(separator: " ").map(String.init))
                // An explicit empty fontStyle clears inherited styles.
                style.bold = words.contains("bold")
                style.italic = words.contains("italic")
                style.underline = words.contains("underline")
                style.strikethrough = words.contains("strikethrough")
            }
            guard !style.isEmpty else { continue }
            for selector in selectors {
                guard let scope = scope(fromSelector: selector) else { continue }
                styles[scope] = style.filling(from: styles[scope] ?? Style())
            }
        }
        return (styles, globals)
    }

    /// The scope a selector applies to, as far as this package's flat scopes can express it.
    static func scope(fromSelector selector: String) -> Scope? {
        var text = selector
        if let exclusion = text.range(of: " -") ?? text.range(of: "-", options: .anchored) {
            text = String(text[..<exclusion.lowerBound])
        }
        guard let last = text.split(whereSeparator: { $0 == " " || $0 == ">" }).last else { return nil }
        var components = last.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return nil }
        if components.count > 1, LanguageRegistry.shared.isLanguageName(components[components.count - 1]) {
            components.removeLast()
        }
        // Top-level language scopes (`source`, `text`) describe whole documents, not tokens.
        if components.count == 1, ["source", "text", "meta"].contains(components[0]) { return nil }
        return Scope(components.joined(separator: "."))
    }
}

extension LanguageRegistry {
    /// Whether `name` is a registered language id, name, alias or extension.
    func isLanguageName(_ name: String) -> Bool {
        language(named: name) != nil
    }
}

/// Minimal JSON-with-comments support: strips `//` and `/* */` comments and trailing commas.
enum JSONC {
    static func strip(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        var inString = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                output.append(byte)
                if byte == UInt8(ascii: "\\"), index + 1 < bytes.count {
                    output.append(bytes[index + 1])
                    index += 2
                    continue
                }
                if byte == UInt8(ascii: "\"") { inString = false }
                index += 1
                continue
            }
            if byte == UInt8(ascii: "\"") {
                inString = true
                output.append(byte)
                index += 1
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) {
                    index += 1
                }
                index += 2
            } else if byte == UInt8(ascii: ",") {
                // Drop a comma followed only by whitespace and a closing bracket.
                var lookahead = index + 1
                while lookahead < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[lookahead]) { lookahead += 1 }
                if lookahead < bytes.count, bytes[lookahead] == UInt8(ascii: "}") || bytes[lookahead] == UInt8(ascii: "]") {
                    index += 1
                } else {
                    output.append(byte)
                    index += 1
                }
            } else {
                output.append(byte)
                index += 1
            }
        }
        return Data(output)
    }
}
