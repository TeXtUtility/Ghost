import Foundation
import Observation

/// The user's snippets, saved to `url` as JSON on every change so they survive quitting.
@MainActor
@Observable
final class SnippetLibrary {
    // ponytail: rewrites the whole file per edit; fine for text snippets, debounce if libraries reach many MB.
    var snippets: [Snippet] { didSet { save() } }
    @ObservationIgnored private let url: URL?

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Ghost/snippets.json")

    init(snippets: [Snippet] = [], url: URL? = nil) {
        self.snippets = snippets
        self.url = url
    }

    /// The saved library, or the samples on first launch. A file that can't be read is moved aside to
    /// snippets.json.unreadable rather than overwritten, so a bad save never costs the user their snippets.
    static func load(from url: URL = defaultURL) -> SnippetLibrary {
        if let data = try? Data(contentsOf: url) {
            if let snippets = try? JSONDecoder().decode([Snippet].self, from: data) {
                return SnippetLibrary(snippets: snippets, url: url)
            }
            let aside = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return SnippetLibrary(snippets: samples, url: url)
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snippets).write(to: url, options: .atomic)
        } catch {
            NSLog("Ghost: couldn't save snippets: \(error)")
        }
    }

    static let samples = [
        Snippet(
            name: "Sample 1",
            body: "Hello, world! This is a quick test of the ghost typing overlay."
        ),
        Snippet(
            name: "Sample 2",
            body: "The quick brown fox jumps over the lazy dog.\nSecond line here for newline practice."
        )
    ]

}
