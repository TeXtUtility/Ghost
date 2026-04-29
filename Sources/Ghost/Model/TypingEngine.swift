import Foundation
import Observation

enum TypingOutcome: Equatable {
    case advanced
    case mismatch
    case complete
    case ignored
}

@MainActor
@Observable
final class TypingEngine {
    private(set) var snippet: Snippet
    private(set) var position: Int = 0
    private(set) var lastOutcome: TypingOutcome = .ignored
    private(set) var pendingMismatches: Int = 0
    /// Streak of consecutive mismatches at the cursor. Cleared on any advance.
    /// Used as a confidence signal for the fuzzy resync — we only look for
    /// forward jumps once the user is clearly off course.
    private(set) var consecutiveMismatches: Int = 0

    private enum Action { case advance, mismatch }
    private var history: [Action] = []
    /// Recent typed characters, used by the smart-resync heuristics to find
    /// either the last word the user typed (whole-word resync) or the
    /// longest recent suffix that matches a substring further in the snippet
    /// (fuzzy resync, for word substitutions/insertions).
    private var inputBuffer: [Character] = []
    private let inputBufferMax = 64

    private var chars: [Character]

    init(snippet: Snippet) {
        self.snippet = snippet
        self.chars = Array(snippet.body)
    }

    var total: Int { chars.count }
    var isComplete: Bool { position >= chars.count }
    var progress: Double {
        guard !chars.isEmpty else { return 1 }
        return Double(position) / Double(chars.count)
    }
    var current: Character? { isComplete ? nil : chars[position] }

    func reset(to snippet: Snippet? = nil) {
        if let snippet { self.snippet = snippet; self.chars = Array(snippet.body) }
        position = 0
        pendingMismatches = 0
        consecutiveMismatches = 0
        history.removeAll()
        inputBuffer.removeAll()
        lastOutcome = .ignored
    }

    @discardableResult
    func handle(character: Character) -> TypingOutcome {
        guard !isComplete else { lastOutcome = .ignored; return .ignored }
        let outcome: TypingOutcome
        if character == chars[position] {
            position += 1
            history.append(.advance)
            outcome = isComplete ? .complete : .advanced
            consecutiveMismatches = 0
        } else {
            pendingMismatches += 1
            history.append(.mismatch)
            outcome = .mismatch
            consecutiveMismatches += 1
        }
        lastOutcome = outcome

        inputBuffer.append(character)
        if inputBuffer.count > inputBufferMax {
            inputBuffer.removeFirst(inputBuffer.count - inputBufferMax)
        }

        // On word boundary: try a whole-word resync (cheap, high-precision —
        // jumps to a later occurrence of the just-typed word).
        if character.isWhitespace { attemptResync() }

        // Continuous fuzzy resync: after the user has typed 2+ wrong chars in
        // a row, look for the longest recent suffix that appears as a
        // substring further in the snippet and jump there. This handles
        // word substitutions ("happily" → "quickly") and insertions because
        // the trailing characters (e.g. " there") usually match.
        if outcome == .mismatch && consecutiveMismatches >= 2 {
            attemptFuzzyResync()
        }

        return outcome
    }

    func backspace() {
        if let last = history.popLast() {
            switch last {
            case .advance:
                if position > 0 { position -= 1 }
            case .mismatch:
                if pendingMismatches > 0 { pendingMismatches -= 1 }
            }
        } else if position > 0 {
            position -= 1
        }
        if !inputBuffer.isEmpty { inputBuffer.removeLast() }
        lastOutcome = .ignored
    }

    func nextWord() {
        guard !isComplete else { return }
        var i = position
        while i < chars.count, !chars[i].isWhitespace { i += 1 }
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        position = i
        clearTransientState()
    }

    func prevWord() {
        guard position > 0 else { return }
        var i = position - 1
        while i > 0, chars[i].isWhitespace { i -= 1 }
        while i > 0, !chars[i - 1].isWhitespace { i -= 1 }
        position = i
        clearTransientState()
    }

    private func clearTransientState() {
        history.removeAll()
        pendingMismatches = 0
        consecutiveMismatches = 0
        inputBuffer.removeAll()
        lastOutcome = .ignored
    }

    // MARK: - Smart word resync

    /// If the user just typed a word (terminated by whitespace) that doesn't
    /// match the snippet word at the cursor but DOES appear later in the
    /// snippet, jump the cursor to right after that later occurrence.
    private func attemptResync() {
        guard let typed = lastWordInBuffer(), typed.count >= 2 else { return }
        let typedLower = lowercased(typed)

        // If the user has no pending wrong characters AND the just-typed
        // word matches the snippet word at the cursor, they're typing
        // correctly — don't jump. Otherwise (pending mismatches present),
        // the typed word is "extra" and we should look for a forward match
        // even if it incidentally matches the previous word.
        if pendingMismatches == 0, let curRange = wordEndingAtCursor() {
            let curLower = lowercased(Array(chars[curRange]))
            if curLower == typedLower { return }
        }

        // Search forward, starting after the current word, for typedLower.
        let searchStart = wordEndingAtCursor()?.upperBound ?? position
        guard let foundRange = findWord(typedLower, from: searchStart) else { return }

        var newPos = foundRange.upperBound
        // Consume one trailing whitespace, since the user already typed the
        // word-ending whitespace as part of this resync trigger.
        if newPos < chars.count, chars[newPos].isWhitespace { newPos += 1 }

        position = newPos
        pendingMismatches = 0
        consecutiveMismatches = 0
        history.removeAll()
        // Don't clear inputBuffer — keep it for the next resync attempt.
        lastOutcome = .advanced
    }

    // MARK: - Fuzzy substring resync

    /// Try to recover from a sustained mismatch streak by finding the longest
    /// recent input suffix (case-insensitive) that appears as a substring of
    /// the snippet ahead of the cursor, then jumping the cursor to right
    /// after that match. Handles cases like:
    ///
    ///   target: "he ran happily there"
    ///   typed:  "he ran quickly there"   → suffix " there" matches ahead
    ///
    ///   target: "he walked there"
    ///   typed:  "he walked happily there" → suffix " there" matches ahead
    ///
    /// Tries longest suffix first; min length 4 to avoid noisy short matches.
    private func attemptFuzzyResync() {
        let minLen = 4
        let maxLookback = 16
        // Require the match to start at least this far past the cursor. A
        // distance of 1 means "user dropped a leading character" (e.g. typed
        // "uick" against "quick"); they probably want to backspace, not
        // skip the rest of the snippet. distance ≥ 2 keeps the fuzzy jump
        // honest while still firing easily on real divergences.
        let minJumpDistance = 2

        let lookback = min(inputBuffer.count, maxLookback)
        guard lookback >= minLen else { return }
        let recent = Array(inputBuffer.suffix(lookback))
        let recentLower = lowercased(recent)

        // startIdx = 0 → full lookback (longest suffix). Increasing startIdx
        // shortens the suffix from the FRONT. Stop once we'd go below minLen.
        let upperStart = recent.count - minLen
        guard upperStart >= 0 else { return }
        for startIdx in 0...upperStart {
            let needle = Array(recentLower[startIdx...])
            if let foundEnd = findSubstring(needle, from: position) {
                let foundStart = foundEnd - needle.count
                guard foundStart - position >= minJumpDistance else { continue }
                position = foundEnd
                pendingMismatches = 0
                consecutiveMismatches = 0
                history.removeAll()
                lastOutcome = .advanced
                return
            }
        }
    }

    /// Linear case-insensitive substring search starting at `start` in `chars`.
    /// Returns the index just after the match, or nil if not found.
    private func findSubstring(_ needleLower: [Character], from start: Int) -> Int? {
        guard !needleLower.isEmpty, start <= chars.count else { return nil }
        let nLen = needleLower.count
        guard chars.count - start >= nLen else { return nil }
        for i in start...(chars.count - nLen) {
            var ok = true
            for j in 0..<nLen {
                let cLower = Character(String(chars[i + j]).lowercased())
                if cLower != needleLower[j] { ok = false; break }
            }
            if ok { return i + nLen }
        }
        return nil
    }

    private func lastWordInBuffer() -> [Character]? {
        guard !inputBuffer.isEmpty else { return nil }
        var i = inputBuffer.count - 1
        while i >= 0, inputBuffer[i].isWhitespace { i -= 1 }
        let end = i + 1
        while i >= 0, !inputBuffer[i].isWhitespace { i -= 1 }
        let start = i + 1
        guard start < end else { return nil }
        return Array(inputBuffer[start..<end])
    }

    /// The range of the snippet word that ends at or just before `position`.
    /// Returns nil if there is no such word (e.g., cursor at start).
    private func wordEndingAtCursor() -> Range<Int>? {
        var e = position
        while e > 0, chars[e - 1].isWhitespace { e -= 1 }
        var s = e
        while s > 0, !chars[s - 1].isWhitespace { s -= 1 }
        guard e > s else { return nil }
        return s..<e
    }

    private func findWord(_ lowerWord: [Character], from start: Int) -> Range<Int>? {
        var i = start
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            let wordStart = i
            while i < chars.count, !chars[i].isWhitespace { i += 1 }
            let wordEnd = i
            guard wordEnd > wordStart else { break }
            if wordEnd - wordStart == lowerWord.count {
                let snipWord = lowercased(Array(chars[wordStart..<wordEnd]))
                if snipWord == lowerWord {
                    return wordStart..<wordEnd
                }
            }
        }
        return nil
    }

    private func lowercased(_ word: [Character]) -> [Character] {
        word.flatMap { Array(String($0).lowercased()) }
    }
}
