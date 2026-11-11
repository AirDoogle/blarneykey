import AppKit
import Testing
@testable import BlarneyKey

private let paths = [
    "scripts/kb.py", "scripts/automation/tests/test_kb.py", "README.md", "docs/README.md",
    "Sources/BlarneyKey/DictationController.swift", "Sources/BlarneyKey/Store.swift",
    "Sources/BlarneyKey/Vocabulary.swift", "a/same.txt", "b/same.txt", "../../up/hq_panel.py"
]

@Test(arguments: [
    ("Have a look at KB.py and tell me what it does.", "Have a look @scripts/kb.py and tell me what it does."),
    ("Open at dictationcontroller.swift and fix the bug.", "Open @Sources/BlarneyKey/DictationController.swift and fix the bug."),
    ("Compare at file vocabulary with at readme.md please.", "Compare @Sources/BlarneyKey/Vocabulary.swift with @README.md please."),
    ("Check at hqpanel.py, then at kb dot py.", "Check @../../up/hq_panel.py, then @scripts/kb.py."),
    ("See @kb.py now", "See @scripts/kb.py now"),
    ("Read at kb.py.", "Read @scripts/kb.py."),
    ("Look at the store and fix it.", "Look at the store and fix it."),
    ("Meet at store at noon.", "Meet at store at noon."),
    ("Open at same.txt please", "Open at same.txt please"),
    ("Open at missing.py please", "Open at missing.py please"),
])
func tagsFiles(input: String, expected: String) {
    #expect(FileTagger.apply(to: input, paths: paths) == expected)
}

@Test func relativePaths() {
    #expect(ProjectFiles.relative(path: "/r/scripts/kb.py", from: "/r") == "scripts/kb.py")
    #expect(ProjectFiles.relative(path: "/r/scripts/kb.py", from: "/r/a/b") == "../../scripts/kb.py")
}

@Test func distinctiveNamesSkipPlainWords() {
    let names = ProjectFiles.distinctiveNames(from: "a/Store.swift\nb/DictationController.swift\nc/hq_panel.py\nd/hq_panel.py\ne/kb.py\nf/README.md\ng/.kb_links")
    #expect(names == ["DictationController", "hq_panel"])
}

private func ordinary(_ word: String) -> Bool { ["their", "there", "the"].contains(word.lowercased()) }

@Test func learnsReplacement() {
    let found = Vocabulary.learn(from: "Send it to Shivaun, please.", to: "Send it to Siobhan, please.", isOrdinaryWord: ordinary)
    #expect(found == [.init(heard: "Shivaun", write: "Siobhan", safe: true)])
}

@Test func learnsSeveralAndPhrases() {
    let found = Vocabulary.learn(from: "ask bally collig about home assist", to: "ask Ballincollig about HomeAssistant", isOrdinaryWord: ordinary)
    #expect(found.map(\.heard) == ["bally collig", "home assist"])
    #expect(found.map(\.write) == ["Ballincollig", "HomeAssistant"])
}

@Test func ordinaryWordIsNotSafe() {
    let found = Vocabulary.learn(from: "over their now", to: "over there now", isOrdinaryWord: ordinary)
    #expect(found.first?.safe == false)
}

@Test func additionsDeletionsAndPunctuationTeachNothing() {
    #expect(Vocabulary.learn(from: "one two", to: "one two three", isOrdinaryWord: ordinary).isEmpty)
    #expect(Vocabulary.learn(from: "one two three", to: "one three", isOrdinaryWord: ordinary).isEmpty)
    #expect(Vocabulary.learn(from: "one, two.", to: "one two", isOrdinaryWord: ordinary).isEmpty)
}

private func check(_ samples: [Float]) -> AudioCheck {
    samples.withUnsafeBufferPointer { AudioCheck.measure(samples: $0, sampleRate: 16_000) }
}

@Test func deadInput() {
    #expect(check([Float](repeating: 0, count: 16_000)).isDead)
}

@Test func quietRoomThankYouIsDropped() {
    let room = (0..<32_000).map { _ in Float.random(in: -0.002...0.002) }
    let result = check(room)
    #expect(!result.isDead)
    #expect(result.isPhantom("Thank you."))
    #expect(result.isPhantom("you"))
    #expect(!result.isPhantom("Thank you for the invoice."))
}

@Test func realThankYouIsKept() {
    let quiet = [Float](repeating: 0.0005, count: 8_000)
    let voice = (0..<8_000).map { Float(sin(Double($0) * 0.1)) * 0.1 }
    #expect(!check(quiet + voice).isPhantom("Thank you."))
}

@Test func noiseMarkers() {
    #expect(Transcriber.withoutNoise(" . ") == "")
    #expect(Transcriber.withoutNoise("Hello.") == "Hello.")
}

// Live checks need the on-device model and Accessibility, so they only run on request:
// BLARNEYKEY_LIVE=1 swift test
private let live = ProcessInfo.processInfo.environment["BLARNEYKEY_LIVE"] != nil

@Test(.enabled(if: live)) func rewriteFollowsInstruction() async throws {
    let text = "hey so I just wanted to say that the invoice is probably going to be late because we had some issues with the bank"
    let result = try await CommandMode.rewrite(text, instruction: "make this shorter and more formal")
    print("REWRITE:", result)
    #expect(!result.isEmpty && result.count < text.count)
}

@Test(.enabled(if: live)) func rewriteDoesNotAnswerTheText() async throws {
    let result = try await CommandMode.rewrite("What is the capital of France?", instruction: "make this more polite")
    print("POLITE:", result)
    #expect(result.contains("?"))
}

@Test(.enabled(if: live)) func readsTerminalFolderAndRepoFiles() throws {
    let terminal = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first)
    let folder = try #require(ProjectContext.folder(of: terminal))
    print("FOLDER:", folder.path)
    if let files = ProjectFiles.load(folder: folder) {
        print("FILES:", files.paths.count, "NAMES:", files.names.prefix(6))
        print("TAG:", FileTagger.apply(to: "Have a look at KB.py please", paths: files.paths))
    }
}

@Test(.enabled(if: live)) func escapeTapCanBeCreated() {
    let tap = EscapeTap()
    tap.setActive(true)
    #expect(tap.isInstalled)
    tap.setActive(false)
}

private func session(_ text: String, result: String? = nil, failure: String? = nil) -> Session {
    Session(date: .now, text: text, appName: "", bundleID: "", duration: 1, failure: failure, commandResult: result)
}

@Test func lastDeliveredIsNewestWithText() {
    #expect(Session.lastDelivered(in: []) == nil)
    #expect(Session.lastDelivered(in: [session(""), session("older")]) == "older")
    #expect(Session.lastDelivered(in: [session("newest"), session("older")]) == "newest")
}

@Test func lastDeliveredUsesRewriteAndIncludesFailures() {
    #expect(Session.lastDelivered(in: [session("shorter please", result: "Short.")]) == "Short.")
    #expect(Session.lastDelivered(in: [session("blocked", failure: "appNotAllowlisted")]) == "blocked")
}

@Test(.enabled(if: live)) func shortcutRegisters() {
    let shortcut = GlobalShortcut()
    shortcut.setEnabled(true)
    #expect(shortcut.isRegistered)
    shortcut.setEnabled(false)
    #expect(!shortcut.isRegistered)
}

private let screen = """
⏺ Here is some output from Claude.
  It spans two lines.

✻ Waiting
────────────────────────────
❯\u{00A0}make this sound more
  assertive please
────────────────────────────
  ◆ HQ  main
"""

private func range(of piece: String) -> NSRange { (screen as NSString).range(of: piece) }

@Test func draftFoundWhenHighlightIsInTheBox() throws {
    let draft = try #require(TerminalDraft.draft(in: screen, selection: range(of: "sound more")))
    #expect(draft.text == "make this sound more\nassertive please")
    #expect(draft.clearCount >= draft.text.count + 2)
}

@Test func noDraftForHighlightInOutput() {
    #expect(TerminalDraft.draft(in: screen, selection: range(of: "some output")) == nil)
    #expect(TerminalDraft.draft(in: screen, selection: range(of: "HQ")) == nil)
}

@Test func noDraftWhenBoxIsEmpty() {
    let empty = "out\n────────\n❯ \n────────\n"
    #expect(TerminalDraft.draft(in: empty, selection: NSRange(location: 13, length: 1)) == nil)
}

@Test func draftFoundFromCopiedText() throws {
    let draft = try #require(TerminalDraft.draft(in: screen, containing: "sound more assertive"))
    #expect(draft.text == "make this sound more\nassertive please")
    #expect(TerminalDraft.draft(in: screen, containing: "❯ make this sound") != nil)
}

@Test func copiedOutputIsNotTheDraft() {
    #expect(TerminalDraft.draft(in: screen, containing: "Here is some output") == nil)
}

@Test(.enabled(if: live), arguments: ["Capitalize all this.", "Make this more assertive.", "Correct the grammar."])
func rewriteVariety(instruction: String) async throws {
    let text = "To try it in Claude Code: highlight text with the mouse. me and him was going to the shop, i think maybe we could perhaps try it if you dont mind."
    let result = try await CommandMode.rewrite(text, instruction: instruction)
    print("CASE[\(instruction)]:", result)
    #expect(result != text)
}

@Test(arguments: [
    ("Capitalize all this.", "HELLO THERE, ME AND HIM."),
    ("Capitalise this", "HELLO THERE, ME AND HIM."),
    ("put it in all caps", "HELLO THERE, ME AND HIM."),
    ("make it lowercase", "hello there, me and him."),
    ("capitalise the first letter of each word", "Hello There, Me And Him."),
    ("title case please", "Hello There, Me And Him."),
])
func caseChanges(instruction: String, expected: String) {
    #expect(CommandMode.caseChange("Hello there, me and him.", instruction: instruction) == expected)
}

@Test func otherInstructionsGoToTheModel() {
    #expect(CommandMode.caseChange("text", instruction: "Make this more assertive.") == nil)
    #expect(CommandMode.caseChange("text", instruction: "Correct the grammar.") == nil)
}
