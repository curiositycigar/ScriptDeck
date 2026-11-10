import Foundation

func runScheduleHistorySelfTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let item = ScriptItem.importing(root.appendingPathComponent("fixture.sh"))
    let task = ScheduledTask(name: "Daily", workspaceID: "workspace", workspaceName: "Workspace", item: item, values: [:])
    let writer = try RunLogWriter(item: item, workspaceID: task.workspaceID, workspaceName: task.workspaceName,
                                  startedAt: Date(), scheduledTaskID: task.id) { _ in }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let initial = try decoder.decode(ExecutionRecord.self, from: Data(contentsOf: writer.metadataURL))
    check(initial.scheduledTaskID == task.id, "Scheduled history stores the task ID before execution")
    let completion = DispatchSemaphore(value: 0)
    writer.finish(outcome: .succeeded, exitCode: 0) { completion.signal() }
    check(completion.wait(timeout: .now() + 5) == .success, "Scheduled log finalization completes")
    let finished = try decoder.decode(ExecutionRecord.self, from: Data(contentsOf: writer.metadataURL))
    check(finished.scheduledTaskID == task.id, "Finalized metadata retains the task ID")
    let scope = ScheduleHistoryScope(task: task, latestRunID: initial.id, metadataPath: writer.metadataURL.path)
    check(scope.contains(finished), "Task history includes its own executions")
    var other = finished
    other.scheduledTaskID = UUID().uuidString
    check(!scope.contains(other), "Other schedules using the same script are excluded, even if the legacy run ID matches")
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: writer.metadataURL)) as! [String: Any]
    json.removeValue(forKey: "scheduledTaskID")
    let legacy = try decoder.decode(ExecutionRecord.self, from: JSONSerialization.data(withJSONObject: json))
    check(legacy.scheduledTaskID == nil && scope.contains(legacy), "Legacy records decode and the known latest run is included")
    var manual = legacy
    manual.id = UUID().uuidString
    check(!scope.contains(manual), "Unattributed manual and older runs are excluded")
    check(scope.directories.contains(writer.directory), "Task history discovers its script log directory")
}
