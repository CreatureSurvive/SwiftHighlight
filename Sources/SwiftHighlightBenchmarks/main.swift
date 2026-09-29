import Foundation
import SwiftHighlight

// Usage: swift run -c release SwiftHighlightBenchmarks [--legacy] [--renderers] [path ...]
// Each path (file or directory) contributes files by extension; each language's files are
// concatenated into one corpus (capped at 4 MB) and tokenized whole.
// With no paths, benchmarks this package's own sources.

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

let iterations = Int(ProcessInfo.processInfo.environment["ITER"] ?? "5") ?? 5

@discardableResult
func measure(_ label: String, bytes: Int, _ body: () -> Int) -> Double {
    _ = body()
    var best = Double.infinity
    var result = 0
    for _ in 0..<iterations {
        let start = now()
        result = body()
        best = min(best, now() - start)
    }
    let megabytes = Double(bytes) / 1_048_576
    print(String(format: "  %-28@ %9.2f ms %9.1f MB/s  %9d", label as NSString, best * 1000, megabytes / best, result))
    return megabytes / best
}

var arguments = Array(CommandLine.arguments.dropFirst())
let legacy = arguments.contains("--legacy")
let renderers = arguments.contains("--renderers")
arguments.removeAll { $0.hasPrefix("--") }
if arguments.isEmpty {
    arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path]
}

let cap = 4 * 1_048_576
var corpora: [String: String] = [:]
for argument in arguments {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory) else { continue }
    var files: [String] = []
    if isDirectory.boolValue {
        let enumerator = FileManager.default.enumerator(atPath: argument)
        while let item = enumerator?.nextObject() as? String {
            if item.contains(".build/") || item.contains("node_modules/") || item.contains(".git/")
                || item.contains(".min.") || item.contains("dist/") { continue }
            files.append((argument as NSString).appendingPathComponent(item))
        }
    } else {
        files = [argument]
    }
    for file in files.sorted() {
        guard let language = LanguageRegistry.shared.language(forPath: file), language.id != "plaintext",
              corpora[language.id, default: ""].utf8.count < cap,
              let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
        corpora[language.id, default: ""] += text + "\n"
    }
}

print(String(format: "  %-28@ %12@ %14@  %9@", "" as NSString, "best" as NSString, "throughput" as NSString, "tokens" as NSString))
var totalBytes = 0
var totalSeconds = 0.0
for (id, corpus) in corpora.sorted(by: { $0.key < $1.key }) {
    let language = Language.named(id)
    let bytes = corpus.utf8.count
    print("\(language.name) — \(bytes / 1024) KB")
    let speed = measure("tokenize", bytes: bytes) { language.tokenize(corpus).count }
    totalBytes += bytes
    totalSeconds += Double(bytes) / 1_048_576 / speed
    if id == "swift", legacy {
        measure("OpenSwift legacy tokenizer", bytes: bytes) {
            var inBlock = false
            var count = 0
            corpus.enumerateLines { line, _ in
                count += LegacyHighlighter.tokenize(line, language: .swift, inBlockComment: &inBlock).count
            }
            return count
        }
    }
    if renderers {
        let highlighted = language.highlight(corpus)
        measure("session (build)", bytes: bytes) { HighlightSession(language: language, text: corpus).lineCount }
        let session = HighlightSession(language: language, text: corpus)
        let middle = session.lineRange(session.lineCount / 2).lowerBound
        var edits = 0
        let editStart = now()
        while now() - editStart < 0.5 {
            session.replace(utf8Range: middle..<middle, with: "x")
            session.replace(utf8Range: middle..<middle + 1, with: "")
            edits += 2
        }
        print(String(format: "  %-28@ %9.2f µs per edit (%d lines)", "session edit (1 char)" as NSString,
                     (now() - editStart) / Double(edits) * 1e6, session.lineCount))
        measure("html (inline styles)", bytes: bytes) { highlighted.html(theme: .githubDark).utf8.count }
        measure("html (classes)", bytes: bytes) { highlighted.html().utf8.count }
        measure("ansi", bytes: bytes) { highlighted.ansi(theme: .dracula).utf8.count }
        #if canImport(AppKit) || canImport(UIKit)
        let font = PlatformFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        measure("NSAttributedString", bytes: bytes) { highlighted.nsAttributedString(theme: .xcode, font: font).length }
        #endif
        #if canImport(SwiftUI)
        measure("AttributedString", bytes: bytes) { highlighted.attributedString(theme: .xcodeDark).runs.count }
        #endif
    }
}
if totalSeconds > 0 {
    print(String(format: "\nOverall: %.1f MB in %.1f ms — %.1f MB/s", Double(totalBytes) / 1_048_576, totalSeconds * 1000,
                 Double(totalBytes) / 1_048_576 / totalSeconds))
}
