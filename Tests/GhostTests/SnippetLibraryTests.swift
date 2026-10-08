import Foundation
import Testing
@testable import Ghost

@MainActor
struct SnippetLibraryTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ghost-tests-\(UUID().uuidString)/snippets.json")
    }

    @Test func firstLaunchGetsSamples() {
        let lib = SnippetLibrary.load(from: tempURL())
        #expect(lib.snippets == SnippetLibrary.samples)
    }

    @Test func editsSurviveReload() {
        let url = tempURL()
        let lib = SnippetLibrary.load(from: url)
        lib.snippets.append(Snippet(name: "Mine", body: "kept"))
        lib.snippets[0].body = "edited"
        lib.snippets.remove(at: 1)
        let again = SnippetLibrary.load(from: url)
        #expect(again.snippets == lib.snippets)
        #expect(again.snippets.map(\.name) == ["Sample 1", "Mine"])
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let lib = SnippetLibrary.load(from: url)
        #expect(lib.snippets == SnippetLibrary.samples)
        let aside = try Data(contentsOf: url.appendingPathExtension("unreadable"))
        #expect(String(decoding: aside, as: UTF8.self) == "not json")
    }
}
