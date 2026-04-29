import SwiftUI
import AppKit

/// Snippet library editor shown in the menu-bar popover.
/// - Snippets list on the left (selectable, with +/− buttons).
/// - Name field + big multiline editor on the right.
/// - Edits are live (no explicit "save"): typing into the name/body fields
///   updates the underlying SnippetLibrary directly.
/// - "Use ‹name›" button activates that snippet and starts typing mode.
struct PopoverContentView: View {
    @Bindable var library: SnippetLibrary
    let onActivate: (Snippet) -> Void
    let onClose: () -> Void

    @State private var selectedID: UUID?

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return library.snippets.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ghost").font(.headline)
                Spacer()
                Text("\(library.snippets.count) snippet\(library.snippets.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !AccessibilityPrompt.isTrusted {
                accessibilityBanner
            }

            HStack(alignment: .top, spacing: 8) {
                listColumn
                    .frame(width: 140)
                editorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button {
                    addNew()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(selectedIndex == nil)

                Spacer()

                if let idx = selectedIndex {
                    Button {
                        let snippet = library.snippets[idx]
                        onActivate(snippet)
                        onClose()
                    } label: {
                        Label("Use \"\(library.snippets[idx].name)\"", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(library.snippets[idx].body.isEmpty)
                }

                Button("Done") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 480, height: 380)
        .onAppear {
            if selectedID == nil { selectedID = library.snippets.first?.id }
        }
    }

    private var accessibilityBanner: some View {
        // Shown when Ghost doesn't have Accessibility permission yet. Without
        // it the global key monitor never fires and the typing engine sees
        // nothing — silent failure that's easy to mistake for a bug.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility permission needed")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Ghost can't read keystrokes from other apps until you grant it Accessibility. Click below, toggle Ghost on, then Quit & Relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") {
                    AccessibilityPrompt.openPrivacyPane()
                }
                Button("Quit & Relaunch") {
                    relaunchGhost()
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func relaunchGhost() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        // Detach so the new instance survives our termination.
        try? task.run()
        // Give the launch a moment to register, then exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private var listColumn: some View {
        List(selection: $selectedID) {
            ForEach(library.snippets) { snippet in
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.name).font(.body).lineLimit(1)
                    Text("\(snippet.body.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tag(snippet.id)
            }
        }
        .listStyle(.bordered)
    }

    @ViewBuilder
    private var editorColumn: some View {
        if let idx = selectedIndex {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: bindingForName(at: idx))
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: bindingForBody(at: idx))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )

                HStack {
                    Text("\(library.snippets[idx].body.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Paste from clipboard") { pasteFromClipboard(into: idx) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        } else {
            VStack {
                Spacer()
                Text("No snippet selected.")
                    .foregroundStyle(.secondary)
                Text("Click + to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bindings & mutations

    private func bindingForName(at idx: Int) -> Binding<String> {
        Binding(
            get: { library.snippets[idx].name },
            set: { library.snippets[idx].name = $0 }
        )
    }

    private func bindingForBody(at idx: Int) -> Binding<String> {
        Binding(
            get: { library.snippets[idx].body },
            set: { library.snippets[idx].body = $0 }
        )
    }

    private func addNew() {
        let new = Snippet(name: "New snippet", body: "")
        library.snippets.append(new)
        selectedID = new.id
    }

    private func deleteSelected() {
        guard let idx = selectedIndex else { return }
        library.snippets.remove(at: idx)
        selectedID = library.snippets.first?.id
    }

    private func pasteFromClipboard(into idx: Int) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        library.snippets[idx].body = text
    }
}
