import Foundation
import Observation

@MainActor
@Observable
final class SnippetLibrary {
    var snippets: [Snippet]

    init(snippets: [Snippet] = []) {
        self.snippets = snippets
    }

    static func withSamples() -> SnippetLibrary {
        SnippetLibrary(snippets: [
            Snippet(
                name: "Sample 1",
                body: "Hello, world! This is a quick test of the ghost typing overlay."
            ),
            Snippet(
                name: "Sample 2",
                body: "The quick brown fox jumps over the lazy dog.\nSecond line here for newline practice."
            )
        ])
    }
}
