import Foundation
import Testing
@testable import Pulse

/// What a transcript says about itself: what the conversation was called, and
/// where it ran.
@Suite("Session titles")
struct SessionTitleTests {
    @Test("A title is one line of the opening prompt")
    func titlesAreCutToOneLine() {
        #expect(UsageLedgerReader.title(from: "  Fix the ring  ") == "Fix the ring")
        // Newlines would turn a row into a paragraph.
        #expect(UsageLedgerReader.title(from: "Fix the ring\nand the card") == "Fix the ring and the card")

        let long = String(repeating: "长", count: 200)
        let cut = UsageLedgerReader.title(from: long)
        #expect(cut?.count == 70)
        #expect(cut?.hasSuffix("…") == true)
    }

    @Test("An envelope is not a title")
    func envelopesAreRefused() {
        // Claude Code opens plenty of sessions with a command envelope or the
        // sandbox caveat. Either would title every session the same thing.
        #expect(UsageLedgerReader.title(from: "<command-name>/init</command-name>") == nil)
        #expect(UsageLedgerReader.title(from: "Caveat: The messages below were generated…") == nil)
        #expect(UsageLedgerReader.title(from: "   ") == nil)
        #expect(UsageLedgerReader.title(from: "") == nil)
    }

    @Test("A message body is a string, or a list of typed parts")
    func bodiesComeInTwoShapes() {
        #expect(UsageLedgerReader.text(in: "plain") == "plain")
        #expect(UsageLedgerReader.text(in: [["type": "text", "text": "rich"]]) == "rich")
        // A tool result carries no text of its own and must not stop the
        // search at the first part.
        #expect(UsageLedgerReader.text(in: [["type": "tool_result"], ["type": "text", "text": "after"]]) == "after")
        #expect(UsageLedgerReader.text(in: [["type": "tool_result"]]) == nil)
        #expect(UsageLedgerReader.text(in: nil) == nil)
    }

    @Test("The folder name is only the fallback for a missing directory")
    func folderNamesAreTheLastResort() {
        // Claude Code replaces every separator with a dash, so the folder name
        // cannot be turned back into a path — the stated `cwd` is preferred
        // wherever a transcript has one, and this is what is left when it does
        // not.
        let claude = URL(fileURLWithPath: "/Users/me/.claude/projects/-Users-me-Code-Pulse/abc.jsonl")
        #expect(UsageLedgerReader.project(of: claude, provider: .claudeCode) == "Pulse")

        let codex = URL(fileURLWithPath: "/Users/me/.codex/sessions/2026/09/14/rollout-x.jsonl")
        #expect(UsageLedgerReader.project(of: codex, provider: .codex) == nil)
    }
}
