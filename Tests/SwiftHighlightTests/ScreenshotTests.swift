#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftHighlight
import SwiftUI
import Testing

/// Renders the README screenshots. Runs only when `SCREENSHOTS_DIR` is set:
/// `SCREENSHOTS_DIR=$PWD/Screenshots swift test --filter Screenshots`
@Suite("Screenshots", .enabled(if: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] != nil))
@MainActor
struct ScreenshotTests {
    static let swiftSample = """
    import SwiftUI

    /// A row in the transcript.
    @MainActor
    struct MessageRow: View {
        let message: Message
        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("\\(message.author) · \\(message.date, style: .relative)")
                    .font(.caption.weight(.semibold))
                if isExpanded || message.text.count < 280 {
                    Text(message.text) // full text
                }
            }
            .onTapGesture { withAnimation { isExpanded.toggle() } }
        }
    }
    """

    static let samples: [(String, String)] = [
        ("python", """
        @dataclass(frozen=True)
        class Point:
            x: float = 0.0
            y: float = 0.0

            def distance(self, other: "Point") -> float:
                \"\"\"Euclidean distance.\"\"\"
                return math.hypot(self.x - other.x, self.y - other.y)

        print(f"{Point(3, 4).distance(Point()):.2f}")  # 5.00
        """),
        ("typescript", """
        interface User { id: number; name?: string }

        export async function load(id: number): Promise<User> {
          const res = await fetch(`/api/users/${id}?v=${VERSION}`);
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          return (await res.json()) as User; // typed
        }
        """),
        ("rust", """
        #[derive(Debug, Clone)]
        pub struct Config<'a> { name: &'a str, retries: u32 }

        impl<'a> Config<'a> {
            pub fn new(name: &'a str) -> Self {
                println!("config {name}");
                Self { name, retries: 3 }
            }
        }
        """),
    ]

    func render(_ view: some View, to name: String) throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }

    func card(_ code: String, _ language: Language, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(theme.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.foregroundColor.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.top, 10)
            Text(language.highlight(code).attributedString(theme: theme))
                .font(.system(size: 12, design: .monospaced))
                .fixedSize()
                .padding(14)
        }
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @Test func themes() throws {
        let themes: [Theme] = [.xcodeDark, .githubLight, .oneDark, .catppuccinMocha, .solarizedLight, .dracula]
        let grid = VStack(spacing: 16) {
            ForEach(0..<3) { row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<2) { column in
                        card(Self.swiftSample, .swift, themes[row * 2 + column])
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.5))
        try render(grid, to: "themes")
    }

    @Test func languages() throws {
        let row = HStack(alignment: .top, spacing: 16) {
            ForEach(Self.samples, id: \.0) { sample in
                card(sample.1, .named(sample.0), .githubDark)
            }
        }
        .padding(20)
        .background(Color(white: 0.2))
        try render(row, to: "languages")
    }
}
#endif
