@testable import SwiftHighlight
import Testing

@Suite("Swift grammar")
struct SwiftGrammarTests {
    let swift = builtin("swift")

    @Test func basics() {
        let code = """
        import SwiftUI

        /// Docs
        @MainActor
        struct ContentView: View { // comment
            let count = 0x1F + 2.5e3
            func body(_ x: Int) -> some View {
                Text("Hello \\(name.uppercased()) world\\n")
                    .padding()
            }
        }
        """
        let tokens = swift.tokenize(code)
        #expect(validate(tokens, in: code))
        #expect(scope(of: "import", in: code, swift) == "storage.type")
        #expect(scope(of: "SwiftUI", in: code, swift) == "entity.name.type")
        #expect(scope(of: "/// Docs", in: code, swift) == "comment.line.documentation")
        #expect(scope(of: "@MainActor", in: code, swift) == "storage.modifier.attribute")
        #expect(scope(of: "ContentView", in: code, swift) == "entity.name.type")
        #expect(scope(of: "// comment", in: code, swift) == "comment.line")
        #expect(scope(of: "0x1F", in: code, swift) == "constant.numeric")
        #expect(scope(of: "2.5e3", in: code, swift) == "constant.numeric")
        #expect(scope(of: "body", in: code, swift) == "entity.name.function")
        #expect(scope(of: "some", in: code, swift) == "keyword")
        #expect(scope(of: "\"Hello ", in: code, swift) == "string")
        #expect(scope(of: "\\(", in: code, swift) == "punctuation.section.embedded")
        #expect(scope(of: "uppercased", in: code, swift) == "support.function")
        #expect(scope(of: "\\n", in: code, swift) == "constant.character.escape")
        #expect(scope(of: "padding", in: code, swift) == "support.function")
    }

    @Test func nestedInterpolationAndComments() {
        let code = #"let s = "a\(f(g(1)))b" /* x /* nested */ still */ let"#
        let pairs = pairs(code, swift)
        #expect(pairs.contains("b\"→string"))
        #expect(pairs.contains("/* x /* nested */ still */→comment.block"))
        #expect(pairs.last == "let→storage.type")
    }

    @Test func rawAndMultilineStrings() {
        let code = """
        let a = #"raw "quoted" \\#(x) \\n"#
        let b = \"\"\"
            multi "line"
            \"\"\"
        let c = 1
        """
        let tokens = swift.tokenize(code)
        #expect(validate(tokens, in: code))
        #expect(scope(of: #"#"raw "quoted" "#, in: code, swift) == "string")
        #expect(scope(of: "\\#(", in: code, swift) == "punctuation.section.embedded")
        #expect(scope(of: "1", in: code, swift) == "constant.numeric")
        #expect(pairs(code, swift).contains(#"    multi "line"→string"#))
    }

    @Test func unterminatedStringEndsAtLineEnd() {
        let code = "let s = \"open\nlet t = 1"
        #expect(scope(of: "let", in: "x\nlet", swift) == "storage.type")
        let pairs = pairs(code, swift)
        #expect(pairs.contains("\"open→string"))
        #expect(pairs.contains("1→constant.numeric"))
    }

    @Test func keywordsAreWholeWords() {
        #expect(scope(of: "iffy", in: "iffy", swift) == nil)
        #expect(scope(of: "letter", in: "letter", swift) == nil)
        #expect(scope(of: "x2", in: "x2", swift) == nil)
    }
}
