import Foundation
import SwiftHighlight

/// Usage: swift run -c release SwiftHighlightBenchmarks [file-or-directory ...]
/// With no arguments, benchmarks the package's own sources as Swift.

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func measure(_ label: String, bytes: Int, iterations: Int = Int(ProcessInfo.processInfo.environment["ITER"] ?? "5")!, _ body: () -> Int) {
    _ = body() // warm up
    var best = Double.infinity
    var result = 0
    for _ in 0..<iterations {
        let start = now()
        result = body()
        best = min(best, now() - start)
    }
    let megabytes = Double(bytes) / 1_048_576
    print(String(format: "%-34@ %8.2f ms  %8.1f MB/s  (%d)", label as NSString, best * 1000, megabytes / best, result))
}

func collect(_ path: String, extensions: Set<String>) -> [String] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
    if !isDirectory.boolValue { return [path] }
    let enumerator = FileManager.default.enumerator(atPath: path)
    var files: [String] = []
    while let item = enumerator?.nextObject() as? String {
        if item.contains(".build/") { continue }
        if extensions.contains((item as NSString).pathExtension) { files.append((path as NSString).appendingPathComponent(item)) }
    }
    return files.sorted()
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path]
}

var groups: [String: String] = [:]
for argument in arguments {
    for file in collect(argument, extensions: ["swift", "js", "ts", "py", "c", "h", "json", "md", "rs", "go", "css", "html"]) {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
        let language = LanguageRegistry.shared.language(forPath: file) ?? .plainText
        groups[language.id, default: ""] += text + "\n"
    }
}

for (id, corpus) in groups.sorted(by: { $0.key < $1.key }) {
    let language = Language.named(id)
    let bytes = corpus.utf8.count
    print("\n\(language.name): \(bytes / 1024) KB")
    measure("tokenize", bytes: bytes) { language.tokenize(corpus).count }
    var lines: [Substring] = []
    corpus.enumerateLines { line, _ in lines.append(Substring(line)) }
    measure("tokenizeLine (per line)", bytes: bytes) {
        var state = LineState(language: language)
        var count = 0
        for line in lines { count += language.tokenizeLine(line, state: &state).count }
        return count
    }
}
let corpusS = groups["swift"]!
measure("plaintext baseline", bytes: corpusS.utf8.count) { Language.plainText.tokenize(corpusS).count }
let commentsOnly = try! Language(Grammar(name: "c", states: ["root": [.match("//.*", .comment), .push("\"", "s")], "s": State(scope: .string, popAtLineEnd: true, rules: [.pop("\"")])]))
measure("comments+strings only", bytes: corpusS.utf8.count) { commentsOnly.tokenize(corpusS).count }
let wordsOnly = try! Language(Grammar(name: "w", states: ["root": [.words(["let","var","func","if"], .keyword)]]))
measure("words only", bytes: corpusS.utf8.count) { wordsOnly.tokenize(corpusS).count }
let identOnly = try! Language(Grammar(name: "i", states: ["root": [.match(#"[a-z_]\w*(?=\s*\()"#, .function)]]))
measure("call rule only", bytes: corpusS.utf8.count) { identOnly.tokenize(corpusS).count }
measure("OpenSwift legacy tokenizer", bytes: corpusS.utf8.count) {
    var inBlock = false
    var count = 0
    corpusS.enumerateLines { line, _ in count += LegacyHighlighter.tokenize(line, language: .swift, inBlockComment: &inBlock).count }
    return count
}
