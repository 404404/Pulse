import Foundation

/// CommandCode's transcripts.
///
/// One JSONL per session under `projects/<slug>/`. The modern format is a
/// **tree**: every entry names a `parentId`, and `/rewind` moves the leaf while
/// the abandoned replies keep their usage on disk. Only the entries on the
/// branch ending at the last entry are real work; the orphans are skipped so a
/// rewind is not billed twice.
///
/// The modern `usage` object names all four buckets and is cache-exclusive.
/// The legacy flat format has no tree and may carry no usage at all; where it
/// does not, there is **no estimate** — token counts from string lengths are
/// not reported tokens, so those lines contribute nothing.
enum CommandCodeReader {
    static let supportedClients: Set<String> = ["commandcode"]

    static func inputs(home: URL) -> [URL] {
        [
            home.appending(path: ".commandcode/projects"),
            // The legacy model fallback lives here and is read, so it is an
            // input too.
            home.appending(path: ".commandcode/config.json"),
        ]
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        let configModel = configModel(in: roots)
        let files = AgentLogIO.files(in: roots, extensions: ["jsonl"])
            .filter { !$0.lastPathComponent.hasSuffix(".checkpoints.jsonl") }
        return files.sorted { $0.path < $1.path }.flatMap { parse($0, configModel: configModel) }
    }

    // MARK: - One session

    private struct Entry {
        let row: [String: Any]
        let index: Int
        let id: String?
        let parent: String?
        let type: String?
    }

    private static func parse(_ file: URL, configModel: String?) -> [AgentUsageRecord] {
        let stem = file.deletingPathExtension().lastPathComponent
        var headerSession: String?
        var entries: [Entry] = []

        for (index, row) in AgentLogIO.jsonLines(at: file).enumerated() {
            let type = AgentLogIO.text(row["type"])
            if type == "session" {
                headerSession = EditorLog.nonBlank(AgentLogIO.text(row["id"])) ?? headerSession
                continue
            }
            entries.append(
                Entry(
                    row: row,
                    index: index,
                    id: EditorLog.nonBlank(AgentLogIO.text(row["id"])),
                    parent: EditorLog.nonBlank(AgentLogIO.text(row["parentId"])),
                    type: type
                )
            )
        }

        let branch = activeBranch(of: entries)

        var records: [AgentUsageRecord] = []
        var currentModel: String?

        for entry in entries {
            // No tree at all (legacy flat lines, or a file with no ids) means
            // every line is on the active branch.
            let onBranch = branch.isEmpty
                || (entry.id.map { branch.contains($0) } ?? false)
            guard onBranch else { continue }

            if entry.type == "model_change" {
                if let model = EditorLog.modelID(AgentLogIO.text(entry.row["model"])) {
                    currentModel = model
                }
                continue
            }

            let message = AgentLogIO.object(entry.row["message"]) ?? [:]
            let role = EditorLog.nonBlank(AgentLogIO.text(message["role"]))
                ?? EditorLog.nonBlank(AgentLogIO.text(entry.row["role"]))
            guard role == "assistant" else { continue }

            let usage = AgentLogIO.object(entry.row["usage"])
            guard let usage else { continue }

            guard let timestamp = AgentLogIO.timestamp(entry.row["timestamp"]) else { continue }

            let tally = TokenTally(
                input: EditorLog.int(usage["inputTokens"]),
                cacheWrite: EditorLog.int(usage["cacheWriteTokens"]),
                cacheRead: EditorLog.int(usage["cacheReadTokens"]),
                output: EditorLog.int(usage["outputTokens"])
            )
            guard tally.total > 0 else { continue }

            guard
                let model = EditorLog.modelID(AgentLogIO.text(entry.row["model"]))
                    ?? currentModel
                    ?? configModel
            else { continue }

            let session = headerSession
                ?? EditorLog.nonBlank(AgentLogIO.text(entry.row["sessionId"]))
                ?? stem
            // The header's id is the session identity; a message's own id and
            // timestamp identify the message, so a replay into another file
            // collapses.
            let identity = entry.id.map { "commandcode:\(session):\($0):\(timestamp.timeIntervalSince1970)" }
                ?? "commandcode:\(session):line\(entry.index):\(timestamp.timeIntervalSince1970)"

            records.append(
                EditorLog.record(
                    timestamp: timestamp,
                    model: model,
                    tally: tally,
                    sessionID: session,
                    deduplicationID: identity
                )
            )
        }
        return records
    }

    /// The ids reachable from the last entry by following `parentId` back.
    ///
    /// Empty when there is no tree to follow, which is how the legacy flat
    /// format keeps every line.
    private static func activeBranch(of entries: [Entry]) -> Set<String> {
        guard let last = entries.last(where: { $0.id != nil })?.id else { return [] }

        var parents: [String: String] = [:]
        for entry in entries {
            if let id = entry.id, let parent = entry.parent {
                parents[id] = parent
            }
        }

        var branch: Set<String> = []
        var cursor: String? = last
        while let id = cursor, branch.insert(id).inserted {
            cursor = parents[id]
        }
        return branch
    }

    private static func configModel(in roots: [URL]) -> String? {
        for root in roots where root.lastPathComponent == "config.json" {
            if let object = AgentLogIO.object(AgentLogIO.json(at: root)),
               let model = EditorLog.modelID(AgentLogIO.text(object["model"])) {
                return model
            }
        }
        return nil
    }
}
