import Foundation
import SwiftHighlight
import Testing
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The README's examples, compiled and run, so the documentation cannot drift from the API.
@Suite("README examples")
struct ReadmeTests {
    let source = "fn main() { println!(\"hi\"); }"

    @Test @MainActor func quickStart() {
        let code = Language.swift.highlight("let x = 1")
        #if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
        _ = CodeView("let x = 1", language: "swift", theme: .github)
        _ = Text(code.attributedString(theme: .xcode))
        _ = code.nsAttributedString(theme: .one, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        #endif
        #expect(code.html(theme: .githubDark).contains("<span"))
        #expect(code.ansi(theme: .dracula).contains("\u{1B}["))
    }

    @Test func findingALanguage() {
        #expect(Language.named("ts").id == "typescript")
        #expect(LanguageRegistry.shared.language(forPath: "Sources/App/View.swift") == .swift)
        #expect(LanguageRegistry.shared.language(named: "```python title=x") == .python)
        #expect(LanguageRegistry.shared.detect(path: "script", content: "#!/usr/bin/env python3\n") == .python)
    }

    @Test func streaming() {
        let session = HighlightSession(language: .markdown)
        for chunk in ["# Ti", "tle\n", "```swift\nlet", " x = 1\n```\n"] {
            let changedLines = session.append(chunk)
            #expect(!changedLines.isEmpty)
        }
        #expect(session.highlightedCode.tokens == Language.markdown.tokenize(session.text))
        session.replace(utf8Range: 2..<7, with: "Heading")
        #expect(session.text.hasPrefix("# Heading"))
        #expect(!session.tokens(inLine: 3).isEmpty)
        #expect(session.lineRelativeTokens(inLine: 0).first?.range.lowerBound == 0)
    }

    @Test func tokens() {
        let tokens = Language.rust.tokenize(source)
        #expect(tokens.map { "\($0.text(in: source)) \($0.scope)" }.prefix(2) == ["fn storage.type", "main entity.name.function"])
    }

    @Test func html() {
        let code = Language.swift.highlight("if x {}")
        #expect(code.html(options: HTMLOptions(classPrefix: "hl-")).contains("class=\"hl-keyword-control\""))
        #expect(AdaptiveTheme.github.css().contains("prefers-color-scheme"))
    }

    @Test func themes() throws {
        let theme = Theme.oneDark
            .setting(.keywordControl, Style(bold: true))
            .setting(.comment, Style("#7F848E", italic: false))
            .setting("support.function.builtin", Style("#56B6C2"))
        #expect(theme.style(for: .keywordControl).bold)
        #expect(theme.style(for: .keywordControl).foreground == Theme.oneDark.style(for: .keyword).foreground)
        _ = AdaptiveTheme(light: .githubLight, dark: theme)

        let json = """
        {
          "name": "Paper", "isDark": false, "foreground": "#333333", "background": "#FFFFF8",
          "styles": {
            "comment": { "foreground": "#999988", "italic": true },
            "keyword": { "foreground": "#0000AA", "bold": true },
            "string":  { "foreground": "#008800" }
          }
        }
        """
        let paper = try Theme(json: Data(json.utf8))
        #expect(paper.style(for: .keywordControl).foreground == "#0000AA")
    }

    @Test func addingALanguage() throws {
        let grammar = Grammar(
            name: "Conf",
            aliases: ["myconf"],
            fileExtensions: ["conf"],
            states: [
                "root": [
                    .match(#"[;#].*"#, .commentLine),
                    .match(#"^\s*(\[)([^\]]*)(\])"#, captures: [1: .punctuation, 2: .type, 3: .punctuation]),
                    .match(#"^\s*([\w.-]+)\s*(=)"#, captures: [1: .key, 2: .operator]),
                    .words(["true", "false", "on", "off"], .constant),
                    .match(#"\b\d+(?:\.\d+)?\b"#, .number),
                    .push("\"", "string"),
                ],
                "string": GrammarState(scope: .string, popAtLineEnd: true, rules: [
                    .match(#"\\."#, .escape),
                    .push(#"\$\{"#, "interpolation", scope: .interpolation),
                    .pop("\""),
                ]),
                "interpolation": [
                    .pop(#"\}"#, scope: .interpolation),
                    .include("root"),
                ],
            ]
        )
        let registry = LanguageRegistry()
        let language = try registry.register(grammar)
        let code = "key = \"a ${on} b\""
        let scopes = language.tokenize(code, registry: registry).map { "\($0.text(in: code)) \($0.scope)" }
        #expect(scopes == ["key support.type.property-name", "= keyword.operator", "\"a  string",
                           "${ punctuation.section.embedded", "on constant.language", "} punctuation.section.embedded",
                           " b\" string"])

        let json = #"""
        {
          "name": "Conf",
          "fileExtensions": ["conf"],
          "states": {
            "root": [
              { "match": "[;#].*", "scope": "comment.line" },
              { "match": "^\\s*([\\w.-]+)\\s*(=)", "captures": { "1": "support.type.property-name" } },
              { "words": ["true", "false"], "scope": "constant.language" },
              { "match": "\"", "push": "string" }
            ],
            "string": { "scope": "string", "popAtLineEnd": true, "rules": [
              { "match": "\\\\.", "scope": "constant.character.escape" },
              { "match": "\"", "pop": true }
            ] }
          }
        }
        """#
        let fromJSON = try LanguageRegistry(includingBuiltins: false).register(json: Data(json.utf8))
        #expect(fromJSON.tokenize("k = \"x\\n\"").count == 4)

        var swift = try #require(Grammar.builtin("swift"))
        swift.states["root"]?.rules.insert(.words(["TODO", "FIXME"], "keyword.todo"), at: 0)
        try LanguageRegistry().register(swift)
    }
}
