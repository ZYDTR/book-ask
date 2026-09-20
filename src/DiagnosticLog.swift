import Foundation
import CryptoKit

/// Local, bounded diagnostics. History/wordbook data is never rotated here.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    let runID = UUID().uuidString
    let directory: URL
    let buildID: String
    private let queue = DispatchQueue(label: "com.zydtr.book-ask.diagnostics")
    private let maxBytes: Int
    private let generations: Int
    private var sequence = 0
    private var secrets: [String] = []
    private var recent: [[String: Any]] = []
    private var lastSampleSignature = ""
    private var lastSampleTime = -Double.infinity
    private let formatter: ISO8601DateFormatter
    private(set) var lastError: String?

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BookAsk/diagnostics"),
         maxBytes: Int = 10 * 1024 * 1024, generations: Int = 6) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.generations = max(2, generations)
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let executable = Bundle.main.executableURL, let bytes = try? Data(contentsOf: executable) {
            buildID = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        } else { buildID = "unknown" }
    }

    func registerSecret(_ secret: String) {
        queue.sync { if !secret.isEmpty && !secrets.contains(secret) { secrets.append(secret) } }
    }

    private func sanitized(_ value: Any, field: String = "") -> Any {
        if ["apikey", "api_key", "authorization", "credential", "token", "password"].contains(field.lowercased()) { return "[REDACTED]" }
        if let string = value as? String {
            return secrets.reduce(string) { $0.replacingOccurrences(of: $1, with: "[REDACTED]") }
        }
        if let object = value as? [String: Any] { return object.mapValues { $0 }.reduce(into: [String: Any]()) { $0[$1.key] = sanitized($1.value, field: $1.key) } }
        if let array = value as? [Any] { return array.map { sanitized($0) } }
        return value
    }

    func record(_ fields: [String: Any]) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let time = Date()
        queue.async { self.append(fields, time: time, uptime: uptime) }
    }

    // Keep every recent sample in memory. Persist changes and periodic unchanged
    // samples; flush the complete pre-trigger sequence when a selection is accepted.
    func sample(_ fields: [String: Any], signature: String, now: Double) {
        let time = Date()
        queue.async {
            var snapshot = fields
            snapshot["sampleTime"] = self.formatter.string(from: time)
            snapshot["sampleUptime"] = now
            self.recent.append(snapshot)
            if self.recent.count > 30 { self.recent.removeFirst(self.recent.count - 30) }
            if signature != self.lastSampleSignature || now - self.lastSampleTime >= 10 || fields["treeSnapshot"] as? Bool == true {
                self.append(snapshot, time: time, uptime: now)
                self.lastSampleSignature = signature
                self.lastSampleTime = now
            }
        }
    }

    func checkpoint(_ fields: [String: Any]) {
        let time = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async {
            for snapshot in self.recent {
                var replay = snapshot
                replay["event"] = "selection_trace"
                replay["checkpointID"] = fields["checkpointID"]
                self.append(replay, time: time, uptime: uptime)
            }
            self.append(fields, time: time, uptime: uptime)
        }
    }

    func flush() -> String? { queue.sync { lastError } }

    func preserveIncident(_ id: String) throws -> URL {
        try queue.sync {
            if let lastError { throw NSError(domain: "BookAsk", code: 10, userInfo: [NSLocalizedDescriptionKey: lastError]) }
            let fm = FileManager.default
            let folder = directory.appendingPathComponent("incidents").appendingPathComponent(id)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where file.lastPathComponent.hasPrefix("diagnostic") && file.pathExtension == "jsonl" {
                try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            return folder
        }
    }

    private func append(_ fields: [String: Any], time: Date, uptime: Double) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var value = sanitized(fields) as! [String: Any]
            sequence += 1
            value["schema"] = 1
            value["runID"] = runID
            value["buildID"] = buildID
            value["sequence"] = sequence
            value["time"] = formatter.string(from: time)
            value["uptime"] = uptime
            var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            bytes.append(10)
            let file = directory.appendingPathComponent("diagnostic.jsonl")
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 0 && size + bytes.count > maxBytes {
                let oldest = directory.appendingPathComponent("diagnostic.\(generations - 1).jsonl")
                if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
                for index in stride(from: generations - 2, through: 0, by: -1) {
                    let source = directory.appendingPathComponent(index == 0 ? "diagnostic.jsonl" : "diagnostic.\(index).jsonl")
                    if fm.fileExists(atPath: source.path) {
                        try fm.moveItem(at: source, to: directory.appendingPathComponent("diagnostic.\(index + 1).jsonl"))
                    }
                }
            }
            if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            lastError = nil
        } catch {
            lastError = "诊断日志写入失败：\(error.localizedDescription)"
            NSLog("BookAsk diagnostic log write failed: %@", error.localizedDescription)
        }
    }
}
