import Foundation
import Testing
@testable import Pulse

/// The tree transcript: only the active branch is billed, and a legacy line
/// with no usage contributes nothing rather than an estimate.
@Suite("CommandCode reader")
struct CommandCodeReaderTests {
    @Test("Rewind orphans are excluded and the model follows the last model_change")
    func activeBranch() throws {
        let home = try EditorTestSupport.temporary("commandcode")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".commandcode/projects/slug/session.jsonl")

        func stamp(_ hour: Int) -> String { EditorTestSupport.iso(EditorTestSupport.at(hour: hour)) }

        try EditorTestSupport.jsonLines([
            ["type": "session", "version": 3, "id": "sess-1"],
            ["type": "message", "id": "u1", "parentId": NSNull(), "timestamp": stamp(9),
             "message": ["role": "user", "content": "hi"]],
            ["type": "message", "id": "a1", "parentId": "u1", "timestamp": stamp(9),
             "message": ["role": "assistant", "content": "x"],
             "usage": ["inputTokens": 100, "outputTokens": 40, "cacheReadTokens": 30, "cacheWriteTokens": 20],
             "model": "anthropic/claude-sonnet"],
            // An abandoned reply: on disk, off the active branch.
            ["type": "message", "id": "orphan", "parentId": "zz", "timestamp": stamp(10),
             "message": ["role": "assistant", "content": "rewound"],
             "usage": ["inputTokens": 999, "outputTokens": 999, "cacheReadTokens": 0, "cacheWriteTokens": 0],
             "model": "anthropic/claude-sonnet"],
            ["type": "model_change", "id": "mc1", "parentId": "a1", "timestamp": stamp(11),
             "model": "openai/gpt-5"],
            ["type": "message", "id": "a2", "parentId": "mc1", "timestamp": stamp(11),
             "message": ["role": "assistant", "content": "y"],
             "usage": ["inputTokens": 5, "outputTokens": 6, "cacheReadTokens": 1, "cacheWriteTokens": 0]],
        ], to: file)

        let roots = EditorLogReaders.inputs(client: "commandcode", home: home)
        let records = EditorLogReaders.records(client: "commandcode", roots: roots)
        #expect(records.count == 2)

        let first = try #require(records.first { $0.tally.input == 100 })
        #expect(first.model == "claude-sonnet")
        #expect(first.sessionID == "sess-1")
        #expect(first.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))

        let second = try #require(records.first { $0.tally.input == 5 })
        // No model on the line: the last model_change on the branch supplies it.
        #expect(second.model == "gpt-5")
        #expect(second.tally == TokenTally(input: 5, cacheRead: 1, output: 6))
    }

    @Test("Legacy flat lines read their usage, take the config model, and never estimate")
    func legacyFlat() throws {
        let home = try EditorTestSupport.temporary("commandcode-legacy")
        defer { try? FileManager.default.removeItem(at: home) }

        try EditorTestSupport.write(
            ["model": "openai/gpt-5"],
            to: home.appending(path: ".commandcode/config.json")
        )
        try EditorTestSupport.jsonLines([
            // Modern file whose whole branch is skipped by the checkpoint name.
            ["type": "message", "id": "x", "parentId": NSNull(), "timestamp": "2026-01-02T03:00:00Z",
             "message": ["role": "assistant"],
             "usage": ["inputTokens": 1, "outputTokens": 1, "cacheReadTokens": 0, "cacheWriteTokens": 0]],
        ], to: home.appending(path: ".commandcode/projects/slug/s.checkpoints.jsonl"))

        try EditorTestSupport.jsonLines([
            ["role": "assistant", "content": "x", "sessionId": "legacy-1", "timestamp": "2026-01-02T03:05:00Z",
             "model": "gpt-5",
             "usage": ["inputTokens": 7, "outputTokens": 3, "cacheReadTokens": 2, "cacheWriteTokens": 1]],
            // No usage block: no estimate, no record.
            ["role": "assistant", "content": "some reply that is quite long",
             "sessionId": "legacy-1", "timestamp": "2026-01-02T03:06:00Z", "model": "gpt-5"],
            // No model on the line and none in an earlier message: the config.
            ["role": "assistant", "content": "y", "sessionId": "legacy-2", "timestamp": "2026-01-02T03:07:00Z",
             "usage": ["inputTokens": 4, "outputTokens": 1, "cacheReadTokens": 0, "cacheWriteTokens": 0]],
        ], to: home.appending(path: ".commandcode/projects/slug/legacy.jsonl"))

        let roots = EditorLogReaders.inputs(client: "commandcode", home: home)
        let records = EditorLogReaders.records(client: "commandcode", roots: roots)
        #expect(records.count == 2)

        #expect(records.contains { $0.tally == TokenTally(input: 7, cacheWrite: 1, cacheRead: 2, output: 3) })
        let configured = try #require(records.first { $0.tally.input == 4 })
        #expect(configured.model == "gpt-5")
        #expect(configured.sessionID == "legacy-2")
    }
}
