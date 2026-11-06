import Foundation
import Darwin

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .once: return "一次性"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .interval: return "固定间隔"
        }
    }
}

struct ScheduledTask: Codable, Identifiable {
    var id = UUID().uuidString
    var revision = UUID().uuidString
    var name: String
    var enabled = true
    var workspaceID: String
    var workspaceName: String
    var item: ScriptItem
    var values: [String: String]
    var kind: ScheduleKind = .once
    var date: Date = Date().addingTimeInterval(3600)
    var weekday = 2 // Calendar: Sunday = 1
    var intervalMinutes = 60
    var timeZoneID = TimeZone.current.identifier
    var createdAt = Date()

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }
    func nextDate(after now: Date) -> Date? {
        switch kind {
        case .once: return date > now ? date : nil
        case .interval:
            let seconds = Double(max(1, intervalMinutes)) * 60
            let count = max(1, floor(now.timeIntervalSince(createdAt) / seconds) + 1)
            return createdAt.addingTimeInterval(count * seconds)
        case .daily, .weekly:
            var components = calendar.dateComponents([.hour, .minute], from: date)
            components.second = 0
            if kind == .weekly { components.weekday = weekday }
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime,
                                     repeatedTimePolicy: .first)
        }
    }
    var summary: String {
        let formatter = DateFormatter()
        formatter.timeZone = kind == .once ? .current : calendar.timeZone
        let zone = timeZoneID == TimeZone.current.identifier ? "" : "（\(timeZoneID)）"
        formatter.dateFormat = kind == .once ? "yyyy-MM-dd HH:mm" : "HH:mm"
        switch kind {
        case .once: return formatter.string(from: date)
        case .daily: return "每天 \(formatter.string(from: date))\(zone)"
        case .weekly: return "每周\(["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, weekday - 1))]) \(formatter.string(from: date))\(zone)"
        case .interval: return "每 \(intervalMinutes) 分钟"
        }
    }
    func validate(now: Date = Date(), requireFuture: Bool = true) throws {
        guard UUID(uuidString: id) != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...7).contains(weekday), (1...525600).contains(intervalMinutes),
              TimeZone(identifier: timeZoneID) != nil else {
            throw RunnerError(message: "定时任务配置无效。")
        }
        if requireFuture && kind == .once && date <= now {
            throw RunnerError(message: "请选择未来的执行时间。")
        }
        _ = try scriptArguments(for: item, values: values)
        _ = try executionCommand(item, arguments: [])
    }
}

struct ScheduleRuntime: Codable {
    var revision: String
    var nextFireAt: Date?
    var runID: String?
    var startedAt: Date?
    var endedAt: Date?
    var outcome: ExecutionOutcome?
    var message: String?
    var logPath: String?
    var metadataPath: String?
}

enum ScheduleFiles {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScriptDeck/Schedules", isDirectory: true)
    }
    static func definition(_ root: URL, _ id: String) -> URL { root.appendingPathComponent(id + ".json") }
    static func runtime(_ root: URL, _ id: String) -> URL { root.appendingPathComponent(id + ".state") }
    static func lock(_ root: URL, _ id: String) -> URL { root.appendingPathComponent(id + ".lock") }
    static func stop(_ root: URL, _ id: String) -> URL { root.appendingPathComponent(id + ".stop") }
    static func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    static func write<T: Encodable>(_ value: T, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RunnerError(message: "无法创建定时任务配置文件。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: encoder.encode(value))
        try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else { throw RunnerError(message: "无法保存定时任务配置。") }
    }
    static func isRunning(root: URL, id: String) -> Bool {
        let fd = open(lock(root, id).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { return errno == EWOULDBLOCK }
        flock(fd, LOCK_UN)
        return false
    }

    /// Read and repair under the same lock used by the executor, so a late UI refresh
    /// cannot overwrite a just-completed result or the next occurrence's claim.
    static func snapshot(root: URL, id: String) throws -> (state: ScheduleRuntime, running: Bool) {
        let fd = open(lock(root, id).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RunnerError(message: "无法读取定时任务锁。") }
        defer { close(fd) }
        let acquired = flock(fd, LOCK_EX | LOCK_NB) == 0
        guard acquired || errno == EWOULDBLOCK else { throw RunnerError(message: "无法读取定时任务状态。") }
        defer { if acquired { flock(fd, LOCK_UN) } }
        var state = try read(ScheduleRuntime.self, runtime(root, id))
        if acquired && state.outcome == .running {
            state.outcome = .failed
            state.message = "后台执行器未正常结束，请检查日志"
            state.endedAt = Date()
            try write(state, runtime(root, id))
        }
        return (state, !acquired)
    }
}
