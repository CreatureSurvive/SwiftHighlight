import Foundation
@testable import SwiftHighlight
import Testing

@Suite("Registry and custom grammars")
struct RegistryTests {
    @Test func lookupByNameAliasPathAndContent() {
        let registry = LanguageRegistry.shared
        #expect(registry.language(named: "JS")?.id == "javascript")
        #expect(registry.language(named: "c++")?.id == "cpp")
        #expect(registry.language(named: "swift title=\"Example\"")?.id == "swift")
        #expect(registry.language(named: "{python}")?.id == "python")
        #expect(registry.language(named: "nope") == nil)
        #expect(registry.language(forPath: "/a/b/View.swift")?.id == "swift")
        #expect(registry.language(forPath: "types.d.ts")?.id == "typescript")
        #expect(registry.language(forPath: "Dockerfile")?.id == "dockerfile")
        #expect(registry.language(forPath: "Podfile")?.id == "ruby")
        #expect(registry.language(forPath: "App.TSX")?.id == "tsx")
        #expect(registry.language(forPath: "notes") == nil)
        #expect(registry.language(forContent: "#!/usr/bin/env python3\nprint(1)")?.id == "python")
        #expect(registry.language(forContent: "#!/bin/zsh\n")?.id == "shell")
        #expect(registry.language(forContent: "<?xml version=\"1.0\"?>")?.id == "xml")
        #expect(registry.detect(path: "script", content: "#!/usr/bin/env node").id == "javascript")
        #expect(registry.detect(path: "unknown.zzz").id == "plaintext")
    }

    static let iniLike = Grammar(
        name: "Conf",
        aliases: ["myconf"],
        fileExtensions: ["myconf"],
        states: [
            "root": [
                .match(#"[;#].*"#, .commentLine),
                .match(#"^\s*(\[)([^\]]*)(\])"#, captures: [1: .punctuation, 2: .type, 3: .punctuation]),
                .match(#"^\s*([\w.-]+)\s*(=)"#, captures: [1: .key, 2: .operator]),
                .push("\"", "string", scope: .string),
            ],
            "string": State(scope: .string, popAtLineEnd: true, rules: [.match(#"\\."#, .escape), .pop("\"")]),
        ]
    )

    @Test func customGrammarInPrivateRegistry() throws {
        let registry = LanguageRegistry(includingBuiltins: false)
        #expect(registry.language(named: "swift") == nil)
        let language = try registry.register(Self.iniLike)
        #expect(registry.language(forPath: "x.myconf") === language)
        let code = "[main]\nkey = \"a\\\"b\" ; note"
        #expect(pairs(code, language) == ["[→punctuation", "main→entity.name.type", "]→punctuation",
                                           "key→support.type.property-name", "=→keyword.operator",
                                           "\"a→string", "\\\"→constant.character.escape", "b\"→string",
                                           "; note→comment.line"])
    }

    @Test func grammarJSONRoundTrip() throws {
        for grammar in BuiltinGrammars.all + [Self.iniLike] {
            let data = try grammar.jsonData()
            let decoded = try Grammar(json: data)
            #expect(decoded == grammar, "\(grammar.id) did not round-trip")
        }
    }

    @Test func grammarFromHandwrittenJSON() throws {
        let json = #"""
        {
          "name": "Tiny",
          "fileExtensions": ["tiny"],
          "states": {
            "root": [
              { "words": ["let", "in"], "scope": "keyword" },
              { "match": "(\\w+)(\\()", "captures": { "1": "entity.name.function" } },
              { "match": "\"", "push": "string", "scope": "string" }
            ],
            "string": { "scope": "string", "popAtLineEnd": true, "rules": [ { "match": "\"", "pop": true } ] }
          }
        }
        """#
        let registry = LanguageRegistry(includingBuiltins: false)
        let language = try registry.register(json: Data(json.utf8))
        #expect(pairs("let f(\"x\")", language) == ["let→keyword", "f→entity.name.function", "\"x\"→string"])
    }

    @Test func extendingABuiltin() throws {
        var grammar = try #require(Grammar.builtin("swift"))
        grammar.states["root"]?.rules.insert(.words(["TODO"], "keyword.todo"), at: 0)
        let registry = LanguageRegistry()
        try registry.register(grammar)
        let language = try #require(registry.language(named: "swift"))
        #expect(pairs("TODO let", language) == ["TODO→keyword.todo", "let→storage.type"])
        // The shared registry is untouched.
        #expect(pairs("TODO", builtin("swift")) == ["TODO→entity.name.type"])
    }

    @Test func grammarErrorsAreDescriptive() {
        func error(_ states: [String: State]) -> GrammarError? {
            do {
                _ = try Language(Grammar(name: "Bad", states: states))
                return nil
            } catch {
                return error
            }
        }
        #expect(error([:])?.message.contains("root") == true)
        #expect(error(["root": [.match("(", .keyword)]])?.patternError != nil)
        #expect(error(["root": [.push("x", "missing")]])?.message.contains("Unknown state") == true)
        #expect(error(["root": [.include("root")]])?.message.contains("cycle") == true)
        #expect(error(["root": [.match("(a)", captures: [2: .keyword])]])?.message.contains("Capture 2") == true)
        #expect(error(["root": [.embed("x", language: "swift", end: "(")]])?.patternError != nil)
        #expect(error(["root": [Rule(match: "x", push: "root", pop: true)]]) != nil)
        let located = error(["root": [.match("ok", .keyword), .match("[", .keyword)]])
        #expect(located?.state == "root")
        #expect(located?.rule == 1)
    }

    @Test func dynamicEmbedResolvesThroughTheRegistry() throws {
        let registry = LanguageRegistry()
        try registry.register(Self.iniLike)
        let markdown = try #require(registry.language(named: "markdown"))
        let code = "```myconf\n[x]\n```"
        let tokens = markdown.tokenize(code, registry: registry)
        #expect(tokens.contains { $0.text(in: code) == "x" && $0.scope == .type })
    }
}

@Suite("Themes")
struct ThemeTests {
    @Test func colorParsing() {
        #expect(ThemeColor(hex: "#FF8000") == ThemeColor(red: 255, green: 128, blue: 0))
        #expect(ThemeColor(hex: "f80") == ThemeColor(red: 255, green: 136, blue: 0))
        #expect(ThemeColor(hex: "#11223344")?.alpha == 0x44)
        #expect(ThemeColor(hex: "#12345") == nil)
        #expect(ThemeColor(hex: "zzzzzz") == nil)
        #expect(ThemeColor(rgb: 0xABCDEF).hex == "#ABCDEF")
    }

    @Test func styleFallsBackThroughParents() {
        let theme = Theme(name: "T", isDark: false, foreground: "#000000", background: "#FFFFFF", styles: [
            "keyword": Style("#FF0000", bold: true),
            "keyword.control": Style(italic: true),
        ])
        let control = theme.style(for: "keyword.control.flow")
        #expect(control.foreground == "#FF0000")
        #expect(control.bold && control.italic)
        #expect(theme.style(for: "string").foreground == "#000000")
        #expect(!theme.style(for: "string").bold)
    }

    @Test func builtinThemesCoverTheStandardScopes() {
        let essential: [Scope] = [.comment, .string, .number, .keyword, .type, .function, .inserted, .deleted]
        for theme in Theme.builtins {
            for scope in essential {
                #expect(theme.style(for: scope).foreground != theme.foreground || scope == .function,
                        "\(theme.name) leaves \(scope) unstyled")
            }
            #expect(theme.isDark == ThemeRules.isDark(theme.background), "\(theme.name) isDark disagrees with background")
        }
        #expect(Theme.named("dracula") == .dracula)
    }

    @Test func themeJSONRoundTrip() throws {
        for theme in Theme.builtins {
            #expect(try Theme(json: theme.jsonData()) == theme)
        }
    }

    @Test func vscodeImport() throws {
        let json = """
        {
          // VS Code themes allow comments
          "name": "Sample Dark",
          "type": "dark",
          "colors": { "editor.background": "#1e1e1e", "editor.foreground": "#d4d4d4",
                      "editor.selectionBackground": "#264f78", },
          "tokenColors": [
            { "settings": { "foreground": "#cccccc" } },
            { "scope": "comment", "settings": { "foreground": "#6A9955", "fontStyle": "italic" } },
            { "scope": ["keyword.control", "storage.type"], "settings": { "foreground": "#C586C0" } },
            { "scope": "string.quoted.double.swift, source.js string", "settings": { "foreground": "#CE9178" } },
            { "scope": "keyword.control.flow", "settings": { "fontStyle": "bold underline" } },
            { "scope": "comment.block", "settings": { "fontStyle": "" } },
            /* trailing comma below */
          ],
        }
        """
        let theme = try Theme(vscodeTheme: Data(json.utf8))
        #expect(theme.name == "Sample Dark")
        #expect(theme.isDark)
        #expect(theme.background == "#1E1E1E")
        #expect(theme.selection == "#264F78")
        #expect(theme.style(for: .commentLine).foreground == "#6A9955")
        #expect(theme.style(for: .commentLine).italic)
        #expect(!theme.style(for: .commentBlock).italic)
        #expect(theme.style(for: .keywordDeclaration).foreground == "#C586C0")
        // `.swift` suffix dropped; descendant selector keeps its last scope.
        #expect(theme.styles["string.quoted.double"]?.foreground == "#CE9178")
        #expect(theme.styles["string"]?.foreground == "#CE9178")
        let flow = theme.style(for: "keyword.control.flow")
        #expect(flow.foreground == "#C586C0" && flow.bold && flow.underline)
    }

    @Test func textMateImport() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>name</key><string>Paper</string>
          <key>settings</key><array>
            <dict><key>settings</key><dict>
              <key>background</key><string>#FFFFF8</string>
              <key>foreground</key><string>#333333</string>
              <key>caret</key><string>#000000</string>
            </dict></dict>
            <dict><key>scope</key><string>keyword</string>
              <key>settings</key><dict><key>foreground</key><string>#0000FF</string>
              <key>fontStyle</key><string>bold</string></dict></dict>
          </array>
        </dict></plist>
        """
        let theme = try Theme(textMateTheme: Data(plist.utf8))
        #expect(theme.name == "Paper")
        #expect(!theme.isDark)
        #expect(theme.cursor == "#000000")
        #expect(theme.style(for: .keywordControl).foreground == "#0000FF")
        #expect(theme.style(for: .keywordControl).bold)
        #expect(throws: ThemeImportError.self) { try Theme(textMateTheme: Data("nope".utf8)) }
        #expect(throws: ThemeImportError.self) { try Theme(vscodeTheme: Data("[1]".utf8)) }
    }
}

@Suite("Renderers")
struct RendererTests {
    let code = "let s = \"<a & b>\" // é😀\n"

    @Test func htmlInlineStyles() {
        let html = builtin("swift").highlight(code).html(theme: .xcodeLight)
        #expect(html.hasPrefix("<pre class=\"hl-code\" style=\"background-color:#FFFFFF;color:#262626\"><code>"))
        #expect(html.contains("<span style=\"color:#9B2393;font-weight:bold\">let</span>"))
        #expect(html.contains("&quot;&lt;a &amp; b&gt;&quot;"))
        #expect(html.contains("é😀"))
        #expect(html.hasSuffix("</code></pre>"))
    }

    @Test func htmlClassesAndCSS() {
        let html = builtin("swift").highlight(code).html(options: HTMLOptions(classPrefix: "x-", wrapInPre: false))
        #expect(html.hasPrefix("<span class=\"x-storage-type\">let</span>"))
        let css = AdaptiveTheme.github.css(options: HTMLOptions(classPrefix: "x-"))
        #expect(css.contains(".x-code [class|=\"x-keyword\"] { color: #CF222E }"))
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        // General rules come before specific ones so the cascade resolves fallbacks.
        let general = css.range(of: "[class|=\"x-string\"]")!.lowerBound
        let specific = css.range(of: "[class|=\"x-string-regexp\"]")!.lowerBound
        #expect(general < specific)
    }

    @Test func ansi() {
        let output = builtin("swift").highlight("let x = 1").ansi(theme: .dracula)
        #expect(output.hasPrefix("\u{1B}[3;38;2;139;233;253mlet\u{1B}[0m x = "))
        #expect(output.hasSuffix("\u{1B}[38;2;189;147;249m1\u{1B}[0m"))
        let indexed = builtin("swift").highlight("let").ansi(theme: .dracula, colors: .xterm256)
        #expect(indexed.contains("38;5;"))
        #expect(HighlightedCode.xterm256Index("#000000") == 16)
        #expect(HighlightedCode.xterm256Index("#FFFFFF") == 231)
        #expect(HighlightedCode.xterm256Index("#808080") == 244)
    }

    #if canImport(SwiftUI)
    @Test func attributedStringRuns() {
        let highlighted = builtin("swift").highlight(code)
        let attributed = highlighted.attributedString(theme: .xcodeDark)
        #expect(String(attributed.characters) == code)
        let keyword = attributed.runs.first { String(attributed[$0.range].characters) == "let" }
        #expect(keyword?.inlinePresentationIntent == .stronglyEmphasized)
        #if canImport(UIKit) || canImport(AppKit)
        let adaptive = highlighted.attributedString(theme: .xcode)
        #expect(String(adaptive.characters) == code)
        #endif
    }
    #endif

    #if canImport(UIKit) || canImport(AppKit)
    @Test func nsAttributedStringRanges() {
        let highlighted = builtin("swift").highlight(code)
        let font = PlatformFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = highlighted.nsAttributedString(theme: .xcodeDark, font: font)
        #expect(attributed.string == code)
        // The comment (after the emoji-free string) is colored with the comment color.
        let nsString = attributed.string as NSString
        let commentRange = nsString.range(of: "// é😀")
        let color = attributed.attribute(.foregroundColor, at: commentRange.location, effectiveRange: nil) as? PlatformColor
        #expect(color == ThemeColor("#7F8C98").platformColor)
        let keywordFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(keywordFont != font)
        var effective = NSRange()
        _ = attributed.attribute(.foregroundColor, at: commentRange.location, effectiveRange: &effective)
        #expect(effective == commentRange)
    }
    #endif
}
