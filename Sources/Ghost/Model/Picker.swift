import AppKit
import Observation

/// Index 0 is always a synthetic "From Clipboard" slot that resolves to the
/// pasteboard contents at confirm time and is NOT persisted to the library.
/// Indices 1...n map to library.snippets[i-1].
@MainActor
@Observable
final class Picker {
    private let library: SnippetLibrary
    private(set) var index: Int = 0

    init(library: SnippetLibrary) {
        self.library = library
    }

    private var slots: Int { library.snippets.count + 1 }

    var currentDisplayName: String {
        if index == 0 {
            let cb = NSPasteboard.general.string(forType: .string) ?? ""
            return cb.isEmpty ? "From Clipboard (empty)" : "From Clipboard"
        }
        return library.snippets[index - 1].name
    }

    /// Resolve the currently-selected slot to a Snippet. For the clipboard slot,
    /// reads NSPasteboard at call time; returns nil if the clipboard is empty.
    func resolveCurrent() -> Snippet? {
        if index == 0 {
            guard let text = NSPasteboard.general.string(forType: .string),
                  !text.isEmpty else { return nil }
            return Snippet(name: "From Clipboard", body: text)
        }
        return library.snippets[index - 1]
    }

    func next() {
        index = (index + 1) % slots
    }

    func prev() {
        index = (index - 1 + slots) % slots
    }

    /// Move selection to the library snippet with this ID. No-op if not found.
    func selectByID(_ id: UUID) {
        if let idx = library.snippets.firstIndex(where: { $0.id == id }) {
            // +1 because slot 0 is the synthetic "From Clipboard" entry.
            index = idx + 1
        }
    }

    /// Move selection to the synthetic "From Clipboard" slot.
    func selectClipboard() {
        index = 0
    }
}
