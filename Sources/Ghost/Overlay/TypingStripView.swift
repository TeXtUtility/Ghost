import SwiftUI
import AppKit

struct TypingStripView: View {
    let engine: TypingEngine
    let settings: Settings

    private var font: Font { .system(size: settings.fontSize, design: .monospaced) }
    private var nsFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
    }
    private var charWidth: CGFloat {
        let s = NSAttributedString(string: "M", attributes: [.font: nsFont]).size()
        return s.width
    }

    var body: some View {
        let chars = Array(engine.snippet.body)
        let total = chars.count
        let win = max(8, settings.windowChars)
        // ~5 chars before the cursor, the rest ahead.
        let lead = min(5, win / 3)
        let maxStart = max(0, total - win)
        let start = max(0, min(engine.position - lead, maxStart))
        let end = min(total, start + win)
        let cursorIndex = engine.position - start
        let visible = Array(chars[start..<end])

        ZStack(alignment: .topLeading) {
            Text(attributed(visible, cursorIndex: cursorIndex))
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            // Cursor underline
            Rectangle()
                .fill(Color.primary)
                .frame(width: charWidth, height: 1.5)
                .offset(x: CGFloat(cursorIndex) * charWidth, y: settings.fontSize + 2)
                .animation(.linear(duration: 0.06), value: engine.position)

            // Mismatch flash
            if engine.lastOutcome == .mismatch {
                Rectangle()
                    .fill(Color.red.opacity(0.35))
                    .frame(width: charWidth, height: settings.fontSize + 2)
                    .offset(x: CGFloat(cursorIndex) * charWidth, y: 0)
                    .transition(.opacity)
            }
        }
        .frame(width: CGFloat(win) * charWidth, alignment: .leading)
    }

    private func attributed(_ visible: [Character], cursorIndex: Int) -> AttributedString {
        var result = AttributedString()
        for (i, ch) in visible.enumerated() {
            // Render newline as a visible glyph so the strip stays one line.
            // ⏎ (U+23CE) reads more clearly than ↵; rendered larger and bold
            // and always yellow so it stands out as a "press Return" cue.
            let isNewline = ch == "\n"
            let glyph: String = isNewline ? "⏎" : String(ch)
            var piece = AttributedString(glyph)
            if isNewline {
                piece.font = .system(size: settings.fontSize + 4, design: .monospaced)
                    .weight(.bold)
                piece.foregroundColor = (i == cursorIndex)
                    ? .yellow
                    : .yellow.opacity(0.6)
            } else {
                piece.font = font
                if i < cursorIndex {
                    piece.foregroundColor = .primary.opacity(0.25)
                } else if i == cursorIndex {
                    piece.foregroundColor = .primary
                } else {
                    piece.foregroundColor = .primary.opacity(0.85)
                }
            }
            result += piece
        }
        return result
    }
}
