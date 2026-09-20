import Foundation

@main struct DiagnosticTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bookask-log-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root, maxBytes: 12000, generations: 3)
        log.registerSecret("fake-test-key-0123456")
        for i in 0..<35 {
            log.sample(["event":"selection_sample", "sampleID":"s\(i)", "rawText":"er, forci",
                "source":["range":["location":440,"length":9],"api_key":"fake-test-key-0123456"],
                "error":"test fake-test-key-0123456"], signature:"unchanged", now:Double(i)/3)
        }
        log.checkpoint(["event":"selection_accepted", "checkpointID":"s34", "sampleID":"s34"])
        log.record(["event":"request_started", "sampleID":"s34", "sessionID":"session", "requestID":"request"])
        precondition(log.flush() == nil)
        var files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys:nil)
        let all = try files.map { try Data(contentsOf:$0) }.reduce(Data(),+)
        let text = String(decoding:all,as:UTF8.self)
        precondition(!text.contains("fake-test-key-0123456") && text.contains("[REDACTED]"), "Secret redaction applies recursively")
        let rows = all.split(separator:10).compactMap { try? JSONSerialization.jsonObject(with:Data($0)) as? [String:Any] }
        let trace = rows.filter { $0["event"] as? String == "selection_trace" }
        precondition(trace.count == 30 && trace.contains { $0["sampleID"] as? String == "s5" }, "Every recent sample survives de-duplication at trigger")
        precondition(rows.contains { $0["requestID"] as? String == "request" && $0["sampleID"] as? String == "s34" })
        precondition(rows.allSatisfy { $0["runID"] != nil && $0["buildID"] != nil && ($0["time"] as? String)?.contains(".") == true })
        let incident = try log.preserveIncident("test-incident")
        precondition(FileManager.default.fileExists(atPath:incident.path))
        for i in 0..<100 { log.record(["event":"rotation_test", "index":i, "payload":String(repeating:"x",count:1000)]) }
        precondition(log.flush() == nil)
        files = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "jsonl" }
        precondition(files.count <= 3)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath:file.path)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            precondition((attributes[.size] as? NSNumber)!.intValue <= 12000)
        }
        print("PASS: pre-trigger trace, event correlation, millisecond timestamps, secret redaction, private permissions, bounded rotation and incident preservation")
    }
}
