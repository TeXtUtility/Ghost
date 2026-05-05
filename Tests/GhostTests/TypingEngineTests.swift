import Testing
@testable import Ghost

@MainActor
struct TypingEngineTests {

    private func engine(_ body: String) -> TypingEngine {
        TypingEngine(snippet: Snippet(name: "t", body: body))
    }

    @Test func advancesOnMatch() {
        let e = engine("abc")
        #expect(e.handle(character: "a") == .advanced)
        #expect(e.position == 1)
        #expect(e.handle(character: "b") == .advanced)
        #expect(e.handle(character: "c") == .complete)
        #expect(e.isComplete)
        #expect(e.progress == 1.0)
    }

    @Test func mismatchDoesNotAdvance() {
        let e = engine("abc")
        #expect(e.handle(character: "x") == .mismatch)
        #expect(e.position == 0)
        #expect(e.handle(character: "a") == .advanced)
        #expect(e.handle(character: "x") == .mismatch)
        #expect(e.position == 1)
    }

    @Test func ignoresInputAfterComplete() {
        let e = engine("ab")
        e.handle(character: "a")
        e.handle(character: "b")
        #expect(e.isComplete)
        #expect(e.handle(character: "c") == .ignored)
    }

    @Test func backspaceDecrementsAndClampsAtZero() {
        let e = engine("ab")
        e.backspace()
        #expect(e.position == 0)
        e.handle(character: "a")
        e.handle(character: "b")
        #expect(e.position == 2)
        e.backspace()
        #expect(e.position == 1)
        e.backspace()
        #expect(e.position == 0)
        e.backspace()
        #expect(e.position == 0)
    }

    @Test func newlineRequiresNewlineKey() {
        let e = engine("a\nb")
        #expect(e.handle(character: "a") == .advanced)
        #expect(e.current == "\n")
        #expect(e.handle(character: "x") == .mismatch)
        #expect(e.handle(character: "\n") == .advanced)
        #expect(e.handle(character: "b") == .complete)
    }

    @Test func nextWordSkipsWhitespaceRun() {
        let e = engine("foo bar  baz")
        e.nextWord()
        #expect(e.position == 4) // 'b' of "bar"
        e.nextWord()
        #expect(e.position == 9) // 'b' of "baz" past two spaces
    }

    @Test func nextWordFromMidWord() {
        let e = engine("hello world")
        e.handle(character: "h"); e.handle(character: "e")
        e.nextWord()
        #expect(e.position == 6) // 'w' of "world"
    }

    @Test func nextWordAtEndStaysAtEnd() {
        let e = engine("one")
        for c in "one" { e.handle(character: c) }
        e.nextWord()
        #expect(e.position == 3)
    }

    @Test func prevWordFromMidWordGoesToStart() {
        let e = engine("hello world")
        for c in "hello wo" { e.handle(character: c) }
        #expect(e.position == 8)
        e.prevWord()
        #expect(e.position == 6)
    }

    @Test func prevWordAtWordStartGoesToPreviousWord() {
        let e = engine("hello world")
        for c in "hello " { e.handle(character: c) }
        #expect(e.position == 6)
        e.prevWord()
        #expect(e.position == 0)
    }

    @Test func progressFraction() {
        let e = engine("abcd")
        #expect(e.progress == 0.0)
        e.handle(character: "a")
        #expect(e.progress == 0.25)
        e.handle(character: "b")
        #expect(e.progress == 0.5)
    }

    @Test func resetWithNewSnippet() {
        let e = engine("abc")
        e.handle(character: "a")
        e.reset(to: Snippet(name: "x", body: "xyz"))
        #expect(e.position == 0)
        #expect(e.snippet.body == "xyz")
        #expect(e.handle(character: "x") == .advanced)
    }

    // MARK: - Mismatch + backspace interaction (the "uick brown rown" bug)

    @Test func backspaceAfterMismatchDoesNotMoveCursor() {
        // Source: "quick". User types 'z' (wrong) then backspace.
        // Cursor never advanced past 0, so backspace must NOT pull it negative
        // or otherwise corrupt position.
        let e = engine("quick")
        #expect(e.handle(character: "z") == .mismatch)
        #expect(e.position == 0)
        #expect(e.pendingMismatches == 1)
        e.backspace()
        #expect(e.position == 0)
        #expect(e.pendingMismatches == 0)
    }

    @Test func multipleMismatchesThenBackspacesResync() {
        // The exact scenario from the bug report: user types "uick" instead of
        // "quick" (4 wrong chars while engine sat at position 0 expecting 'q'),
        // then backspaces 4 times to fix it. After the 4 backspaces the engine
        // must still be at position 0, ready to accept 'q'.
        let e = engine("quick")
        for c in "uick" { e.handle(character: c) }
        #expect(e.position == 0)
        #expect(e.pendingMismatches == 4)
        for _ in 0..<4 { e.backspace() }
        #expect(e.position == 0)
        #expect(e.pendingMismatches == 0)
        // Now typing the correct sequence should advance normally.
        for c in "quick" { e.handle(character: c) }
        #expect(e.position == 5)
        #expect(e.isComplete)
    }

    @Test func backspaceUndoesMostRecentActionLIFO() {
        // Mixed correct + wrong then a single backspace should undo only
        // the last action (the wrong char), not the correct one before it.
        let e = engine("ab")
        e.handle(character: "a") // advance, pos=1
        e.handle(character: "z") // mismatch, pos=1, pending=1
        #expect(e.position == 1)
        #expect(e.pendingMismatches == 1)
        e.backspace()
        #expect(e.position == 1) // 'a' still consumed
        #expect(e.pendingMismatches == 0)
        e.backspace()
        #expect(e.position == 0) // now undoes the 'a'
    }

    @Test func wordSkipClearsHistorySoBackspaceDoesNotJumpBack() {
        let e = engine("hi world")
        e.handle(character: "h"); e.handle(character: "i")
        e.nextWord() // jumps cursor to "world"
        let posAfterJump = e.position
        e.backspace()
        // Backspace after a word jump should at most decrement once, not pop
        // pre-jump history.
        #expect(e.position == posAfterJump - 1)
    }

    // MARK: - Smart word resync

    @Test func resyncJumpsToLaterWord() {
        // User skips "quick brown", types "fox" instead. After the trailing
        // space the engine should jump past "fox " in the snippet so the user
        // can keep typing from "jumps".
        let e = engine("the quick brown fox jumps")
        for c in "the " { e.handle(character: c) }
        #expect(e.position == 4)
        for c in "fox " { e.handle(character: c) }
        #expect(e.position == 20) // right after "fox " in the snippet
        for c in "jumps" { e.handle(character: c) }
        #expect(e.position == 25)
        #expect(e.isComplete)
    }

    @Test func noResyncWhenWordsAlreadyMatch() {
        let e = engine("hello world")
        for c in "hello " { e.handle(character: c) }
        #expect(e.position == 6)
        #expect(e.pendingMismatches == 0)
    }

    @Test func noResyncWhenTypedWordNotInSnippet() {
        let e = engine("the cat sat")
        for c in "xyz " { e.handle(character: c) }
        #expect(e.position == 0)
        #expect(e.pendingMismatches == 4)
    }

    @Test func resyncIsCaseInsensitive() {
        let e = engine("the QUICK fox")
        for c in "the " { e.handle(character: c) }
        for c in "fox " { e.handle(character: c) }
        // "fox" is at the end of the snippet (offset 10); after the resync
        // jumps past it, position == snippet length and engine is complete.
        #expect(e.position == 13)
        #expect(e.isComplete)
    }

    // MARK: - Fuzzy substring resync (word substitution / freestyle)

    @Test func fuzzyResyncOnWordSubstitution() {
        // Target says "happily" at the cursor. User types "quickly there".
        // "quickly" isn't in the snippet, but " there" suffix is — engine
        // should snap forward.
        let e = engine("he ran happily there")
        for c in "he ran " { e.handle(character: c) }
        #expect(e.position == 7)
        for c in "quickly there" { e.handle(character: c) }
        #expect(e.isComplete)
    }

    @Test func fuzzyResyncOnFreestyleInsertion() {
        // Target: "he walked there". User adds an extra word "happily" between.
        // After typing "he walked happily there" the engine should be complete.
        let e = engine("he walked there")
        for c in "he walked happily there" { e.handle(character: c) }
        #expect(e.isComplete)
    }

    @Test func fuzzyResyncDoesNotFireOnCorrectTyping() {
        // No mismatches, no fuzzy jumps. Engine should track the user
        // character-by-character even when the snippet has internal repeats.
        let e = engine("abc abc abc")
        for c in "abc abc abc" { e.handle(character: c) }
        #expect(e.position == 11)
        #expect(e.isComplete)
    }

    @Test func fuzzyResyncRespectsMinSuffixLength() {
        // Single mismatch shouldn't trigger anything; even with a 3-char
        // suffix (below the 4-char floor) the engine must not jump.
        let e = engine("xxxx abc")
        // Type one wrong char — position should stay at 0.
        e.handle(character: "z")
        #expect(e.position == 0)
        #expect(e.consecutiveMismatches == 1)
        // Type "ab" — that's a 3-char trailing suffix "zab" not present
        // forward; even if it were, min length is 4 so no jump.
        e.handle(character: "a")
        e.handle(character: "b")
        #expect(e.position == 0)
    }

    @Test func fuzzyResyncJumpsToLongestSuffixMatch() {
        // The longest-matching suffix should win when multiple substrings
        // could match. Here "the green dog" only matches uniquely on "green".
        let e = engine("the red cat saw the green dog yesterday")
        for c in "the red " { e.handle(character: c) } // pos = 8 ("cat")
        for c in "blue green dog" { e.handle(character: c) }
        // Engine should have snapped forward past "green dog" via fuzzy resync.
        // Trailing snippet has " yesterday"; user is now positioned somewhere
        // inside or just after "dog".
        #expect(e.position >= 29) // at minimum past "the green dog"
    }

    @Test func fuzzyResyncResetsConsecutiveMismatchesAfterAdvance() {
        let e = engine("abc")
        e.handle(character: "x") // mismatch, consec=1
        e.handle(character: "a") // match, consec resets to 0
        #expect(e.consecutiveMismatches == 0)
    }

    @Test func resyncIgnoresMatchesFarAhead() {
        // A coincidental word match many hundreds of chars ahead must not
        // yank the cursor across the snippet. Resync is for small detours.
        let filler = String(repeating: "x ", count: 200) // 400 chars of noise
        let e = engine("the cat \(filler)the dog ran")
        for c in "the " { e.handle(character: c) }
        // User types a word that doesn't match "cat" and exists only far
        // ahead ("dog" appears once, well past the 200-char cap).
        for c in "dog " { e.handle(character: c) }
        // Engine should NOT have jumped — the only "dog" is past the cap.
        #expect(e.position == 4)
        #expect(e.pendingMismatches > 0)
    }

    @Test func fuzzyResyncIgnoresMatchesFarAhead() {
        // Long suffix matching a phrase ~500 chars ahead is almost always a
        // coincidence on common letter sequences. Don't jump.
        let filler = String(repeating: "abcd ", count: 100) // 500 chars
        let e = engine("hello world \(filler)goodbye world")
        for c in "hello " { e.handle(character: c) }
        // Type a word substitution that doesn't match "world" but whose
        // suffix " world" appears far past the cap.
        for c in "earth world" { e.handle(character: c) }
        // No jump — cursor stayed near the original position rather than
        // teleporting to the far "goodbye world".
        #expect(e.position < 100)
    }

    @Test func resyncFindsFirstOccurrenceAfterCursor() {
        // typedWord could match an earlier occurrence too — but resync only
        // searches forward from the cursor, so the earlier "fox" before the
        // cursor is ignored.
        let e = engine("fox a fox b cat")
        // Walk past first "fox " by typing it correctly. Cursor at position 4
        // ('a'). pendingMismatches is 0 here.
        for c in "fox " { e.handle(character: c) }
        #expect(e.position == 4)
        #expect(e.pendingMismatches == 0)
        // Now type "fox " — these are 4 mismatches against 'a','space','f',etc.
        // Because pendingMismatches > 0 at the trailing-space resync trigger,
        // the engine should jump to the SECOND "fox" (chars 6..<9), landing
        // the cursor at position 10 (right after that "fox" + its space).
        for c in "fox " { e.handle(character: c) }
        #expect(e.position == 10)
        #expect(e.pendingMismatches == 0)
    }
}
