#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI

/// Highlighted code as SwiftUI `Text`, following the system appearance.
///
/// Small snippets are highlighted synchronously (and cached, so re-rendering is free); code
/// larger than ``synchronousLimit`` is highlighted off the main actor and shown unstyled until
/// it is ready.
///
/// ```swift
/// CodeView(source, language: "swift", theme: .github)
///     .padding()
/// ```
public struct CodeView: View {
    public let code: String
    public let language: Language
    public let theme: AdaptiveTheme
    public let font: Font
    public let showsBackground: Bool

    /// Code larger than this many UTF-8 bytes is highlighted asynchronously.
    public static let synchronousLimit = 32 * 1024

    @SwiftUI.State private var rendered: Rendered?

    public init(_ code: String, language: Language, theme: AdaptiveTheme = .xcode,
                font: Font = .system(.body, design: .monospaced), showsBackground: Bool = true) {
        self.code = code
        self.language = language
        self.theme = theme
        self.font = font
        self.showsBackground = showsBackground
    }

    /// Looks `language` up by name, alias or file extension in the shared registry.
    public init(_ code: String, language name: String, theme: AdaptiveTheme = .xcode,
                font: Font = .system(.body, design: .monospaced), showsBackground: Bool = true) {
        self.init(code, language: .named(name), theme: theme, font: font, showsBackground: showsBackground)
    }

    private struct Rendered: Equatable {
        var key: RenderKey
        var text: AttributedString
    }

    private var key: RenderKey { RenderKey(code: code, language: language.id, theme: theme) }

    public var body: some View {
        let key = key
        let text: AttributedString = if code.utf8.count <= Self.synchronousLimit {
            RenderCache.shared.attributedString(for: key) { language.highlight(code).attributedString(theme: theme) }
        } else if let rendered, rendered.key == key {
            rendered.text
        } else {
            AttributedString(code)
        }
        Text(text)
            .font(font)
            .foregroundColor(theme.foregroundColor)
            .background(showsBackground ? theme.backgroundColor : Color.clear)
            .task(id: key) {
                guard code.utf8.count > Self.synchronousLimit else { return }
                let (code, language, theme) = (code, language, theme)
                let text = await Task.detached(priority: .userInitiated) {
                    language.highlight(code).attributedString(theme: theme)
                }.value
                rendered = Rendered(key: key, text: text)
            }
    }
}

struct RenderKey: Hashable, Sendable {
    var code: String
    var language: String
    var theme: AdaptiveTheme
}

/// A small, thread-safe cache of rendered snippets so views re-render without re-highlighting.
final class RenderCache: @unchecked Sendable {
    static let shared = RenderCache()

    private final class Box {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private final class KeyBox: NSObject {
        let key: RenderKey
        init(_ key: RenderKey) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private let cache: NSCache<KeyBox, Box> = {
        let cache = NSCache<KeyBox, Box>()
        cache.countLimit = 256
        return cache
    }()

    func attributedString(for key: RenderKey, make: () -> AttributedString) -> AttributedString {
        let box = KeyBox(key)
        if let cached = cache.object(forKey: box) { return cached.value }
        let value = make()
        cache.setObject(Box(value), forKey: box)
        return value
    }
}
#endif
