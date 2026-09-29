@testable import SwiftHighlight
import Testing

/// Compiles `pattern` and runs it anchored at `offset` of `input`.
/// Returns the match length and captured group texts, or nil for no match.
func run(_ pattern: String, _ input: String, at offset: Int = 0, delimiter: String = "") throws -> (length: Int, groups: [String?])? {
    let (node, groups) = try PatternParser.parse(pattern)
    var generator = CodeGenerator(builder: ProgramBuilder(), groups: groups, pattern: pattern)
    try generator.generate(node)
    generator.builder.emit(Instruction(op: .match))
    let program = Program(builder: generator.builder)
    var text = input
    return text.withUTF8 { buffer -> (Int, [String?])? in
        let matcher = Matcher()
        let base = buffer.baseAddress ?? UnsafePointer(bitPattern: 1)!
        matcher.input = base
        matcher.lineStart = 0
        matcher.lineEnd = buffer.count
        matcher.steps = 1_000_000
        matcher.delimiter = Array(delimiter.utf8)
        let end = matcher.match(program.view, pc: 0, at: offset, slotCount: generator.nextHiddenSlot)
        guard end >= 0 else { return nil }
        var captured: [String?] = []
        for group in 0...groups {
            let lower = matcher.slots[group * 2]
            let upper = matcher.slots[group * 2 + 1]
            if lower >= 0, upper >= lower {
                captured.append(String(decoding: UnsafeBufferPointer(start: base + lower, count: upper - lower), as: UTF8.self))
            } else {
                captured.append(nil)
            }
        }
        return (end - offset, captured)
    }
}

func length(_ pattern: String, _ input: String, at offset: Int = 0) throws -> Int? {
    try run(pattern, input, at: offset)?.length
}

@Suite("Pattern engine")
struct PatternTests {
    @Test func literalsAndClasses() throws {
        #expect(try length("abc", "abcdef") == 3)
        #expect(try length("abc", "abx") == nil)
        #expect(try length("[a-c]+", "abcabd") == 5)
        #expect(try length(#"[^"\\]*"#, #"hello"world"#) == 5)
        #expect(try length(#"\d+\.\d+"#, "3.14!") == 4)
        #expect(try length(#"\w+"#, "héllo wörld") == "héllo".utf8.count)
        #expect(try length(#"[-a]+"#, "-a-b") == 3)
        #expect(try length(#"[a-]+"#, "a-a-b") == 4)
        #expect(try length(#"\x41\u{263A}"#, "A☺") == 4)
        #expect(try length(".", "☺x") == 3)
    }

    @Test func greedyBacktracking() throws {
        #expect(try length("a*ab", "aaaab") == 5)
        #expect(try length(#"".*""#, #""a" "b" c"#) == 7)
        #expect(try length(#"\w+ing"#, "going home") == 5)
        #expect(try length("(ab|a)c", "abc") == 3)
        #expect(try length("(a|ab)c", "abc") == 3)
        #expect(try length("x{2,3}", "xxxx") == 3)
        #expect(try length("x{2,3}", "x") == nil)
        #expect(try length("(?:ab){2}", "ababab") == 4)
    }

    @Test func lazyAndPossessive() throws {
        #expect(try length(#"".*?""#, #""a" "b""#) == 3)
        #expect(try length("<.+?>", "<a><b>") == 3)
        #expect(try length("(?:ab)*?c", "ababc") == 5)
        #expect(try length("a*+a", "aaa") == nil)
        #expect(try length("(?>a+)b", "aaab") == 4)
        #expect(try length("(?>a|ab)c", "abc") == nil)
    }

    @Test func anchorsAndBoundaries() throws {
        #expect(try length("^a", "ab") == 1)
        #expect(try length("^b", "ab", at: 1) == nil)
        #expect(try length("b$", "ab", at: 1) == 1)
        #expect(try length(#"\bif\b"#, "if x") == 2)
        #expect(try length(#"\bif\b"#, "iff") == nil)
        #expect(try length(#"\Bf"#, "iff", at: 1) == 1)
    }

    @Test func lookaround() throws {
        #expect(try length(#"\w+(?=\()"#, "call(x)") == 4)
        #expect(try length(#"\w+(?=\()"#, "call x") == nil)
        #expect(try length(#"\w+(?!\()"#, "abc(") == 2)
        #expect(try length(#"(?<=\.)\w+"#, "a.name", at: 2) == 4)
        #expect(try length(#"(?<=\.)\w+"#, "a name", at: 2) == nil)
        #expect(try length(#"(?<!\\)""#, #"a\""#, at: 2) == nil)
        #expect(try length(#"(?<!\\)""#, #"a""#, at: 1) == 1)
        #expect(try length(#"(?<=☺)x"#, "☺x", at: 3) == 1)
        #expect(throws: PatternError.self) { try length(#"(?<=a+)b"#, "ab") }
    }

    @Test func capturesAndBackreferences() throws {
        let result = try #require(try run(#"(func)\s+(\w+)"#, "func hello()"))
        #expect(result.groups == ["func hello", "func", "hello"])
        #expect(try length(#"(["'])[^"']*\1"#, #"'a' "b""#) == 3)
        #expect(try length(#"(["'])[^"']*\1"#, #"'a""#) == nil)
        let optional = try #require(try run("(a)?b", "b"))
        #expect(optional.groups == ["b", nil])
        // A failed branch must not leave its captures behind.
        let branch = try #require(try run("(?:(a)x|ay)", "ay"))
        #expect(branch.groups[1] == nil)
        let named = try #require(try run("(?<word>[a-z]+)", "abc1"))
        #expect(named.groups[1] == "abc")
    }

    @Test func caseInsensitive() throws {
        #expect(try length("(?i)select", "SeLeCt *") == 6)
        #expect(try length("(?i)[a-c]+", "AbC") == 3)
        #expect(try length("select", "SELECT") == nil)
    }

    @Test func delimiter() throws {
        #expect(try run("\"\\k", "\"##", delimiter: "##")?.length == 3)
        #expect(try run("\"\\k", "\"#", delimiter: "##") == nil)
    }

    @Test func emptyLoopsTerminate() throws {
        #expect(try length("(a?)*b", "aab") == 3)
        #expect(try length("(?:)*x", "x") == 1)
        #expect(try length("(a*)*", "aaa") == 3)
    }

    @Test func pathologicalPatternIsBounded() throws {
        // Classic catastrophic backtracking; the step budget must end it.
        let (node, groups) = try PatternParser.parse("(a+)+b")
        var generator = CodeGenerator(builder: ProgramBuilder(), groups: groups, pattern: "")
        try generator.generate(node)
        generator.builder.emit(Instruction(op: .match))
        let program = Program(builder: generator.builder)
        var text = String(repeating: "a", count: 64)
        text.withUTF8 { buffer in
            let matcher = Matcher()
            matcher.input = buffer.baseAddress!
            matcher.lineEnd = buffer.count
            matcher.steps = 100_000
            #expect(matcher.match(program.view, pc: 0, at: 0, slotCount: generator.nextHiddenSlot) == -1)
            #expect(matcher.exhausted)
        }
    }

    @Test func syntaxErrors() throws {
        for bad in ["(", "a)", "[abc", "*a", #"\"#, "a{3,1}", #"\q"#, #"\2(a)"#, "(?P<>a)"] {
            #expect(throws: PatternError.self, "\(bad)") { try PatternParser.parse(bad) }
        }
        #expect(try length("a{", "a{") == 2)
        #expect(try length("a{x}", "a{x}") == 4)
    }
}
