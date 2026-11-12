import Foundation
import Combine
import Darwin

/// A private, per-run mailbox. Atomic files keep UI messages separate from PTY output.
/// The helper serializes exchanges; the app never blocks waiting for a script.
@MainActor
final class InteractiveChannel: ObservableObject {
    let directory: URL
    @Published private(set) var request: InteractiveRequest?
    @Published var inputs: [String: String] = [:]
    @Published var selections: [String: Set<String>] = [:]
    @Published private(set) var waiting = false
    @Published private(set) var ended = false
    @Published private(set) var issue: String?
    @Published private(set) var showsProcessingIndicator = false
    private var timer: Timer?
    private var processingIndicatorTask: Task<Void, Never>?

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("scriptdeck-ui-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            // Timer is installed only on the main run loop.
            MainActor.assumeIsolated { self?.receive() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func receive() {
        guard !ended else { return }
        let url = directory.appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= InteractiveView.maximumBytes * 2 + 1024 else {
                throw InteractiveProtocolError.invalid
            }
            let next = try JSONDecoder().decode(InteractiveRequest.self, from: Data(contentsOf: url))
            guard next.id != request?.id else { return }
            try next.view.validate()
            cancelProcessingIndicator()
            reconcileState(with: next.view)
            request = next
            issue = nil
            waiting = next.view.hasButtons
            if !waiting { try respond(event: nil) }
        } catch {
            issue = L("Interactive UI error: {0}", error.localizedDescription)
            // A malformed mailbox must not be retried on every timer tick.
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Named pages opt into retained form state; legacy views retain only compatible file choices.
    private func reconcileState(with view: InteractiveView) {
        let samePage = request?.view.pageID == view.pageID
        let retainsForm = samePage && view.pageID != nil
        let previous = Dictionary(uniqueKeysWithValues: (request?.view.blocks ?? []).compactMap { block in
            block.id.map { ($0, block) }
        })
        var nextSelections: [String: Set<String>] = [:]
        var nextInputs: [String: String] = [:]
        for block in view.blocks {
            guard let id = block.id else { continue }
            let old = previous[id]
            let compatible = samePage && block.reset != true && old?.type == block.type
            switch block.type {
            case .file:
                if compatible, (old?.mode ?? .file) == (block.mode ?? .file),
                   (old?.multiple ?? false) == (block.multiple ?? false),
                   let selected = selections[id], !selected.isEmpty {
                    nextSelections[id] = selected
                }
            case .list:
                if retainsForm && compatible && (old?.multiple ?? false) == (block.multiple ?? false) {
                    let selected = selections[id, default: []].intersection(Set((block.items ?? []).compactMap(\.id)))
                    if !selected.isEmpty { nextSelections[id] = selected }
                }
            case .input:
                let retain = retainsForm && compatible && block.secure != true && old?.secure != true
                    && (old?.multiline ?? false) == (block.multiline ?? false)
                nextInputs[id] = block.value ?? (retain ? inputs[id] : nil) ?? ""
            case .select:
                let retained = retainsForm && compatible ? inputs[id] : nil
                nextInputs[id] = block.value ?? (block.items?.contains(where: { $0.id == retained }) == true ? retained : nil)
                    ?? block.items?.first?.id ?? ""
            case .toggle:
                nextInputs[id] = block.checked.map { $0 ? "true" : "false" }
                    ?? (retainsForm && compatible ? inputs[id] : nil) ?? "false"
            default: break
            }
        }
        selections = nextSelections
        inputs = nextInputs
    }

    func activate(_ item: InteractiveItem, requestID: UUID) {
        guard !ended, waiting, let request, request.id == requestID,
              request.view.blocks.contains(where: { $0.type == .buttons && $0.items?.contains(item) == true }),
              canSubmit(item, values: selections) else { return }
        if let action = item.action {
            guard request.view.blocks.contains(where: { $0.id == action.target && $0.type == .input && $0.secure != true }) else { return }
            inputs[action.target] = action.value
        } else if let data = item.data {
            submit(data, values: selections, requestID: requestID)
        }
    }

    func canSubmit(_ item: InteractiveItem, values: [String: Set<String>]) -> Bool {
        guard item.disabled != true else { return false }
        guard let listID = item.requiresSelection else { return true }
        let validIDs = request?.view.blocks.first { $0.type == .list && $0.id == listID }?.items?.compactMap(\.id) ?? []
        return validIDs.contains { values[listID, default: []].contains($0) }
    }

    /// Both the native chooser and drops use the current request's selection rules.
    @discardableResult
    func selectFiles(_ urls: [URL], controlID: String, requestID: UUID) -> Bool {
        guard !ended, waiting, let request, request.id == requestID,
              let block = request.view.blocks.first(where: { $0.type == .file && $0.id == controlID }) else { return false }
        let paths = urls.filter { url in
            guard url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = values.isDirectory else { return false }
            return isDirectory == (block.mode == .directory)
        }.map(\.path)
        guard !paths.isEmpty else { return false }
        selections[controlID] = Set(block.multiple == true ? paths : Array(paths.prefix(1)))
        return true
    }

    func submit(_ data: String, values: [String: Set<String>], requestID: UUID) {
        guard !ended, waiting, let request, request.id == requestID,
              request.view.blocks.contains(where: { $0.type == .buttons && $0.items?.contains(where: { $0.data == data && canSubmit($0, values: values) }) == true }) else { return }
        var selections: [String: [String]] = [:]
        for block in request.view.blocks {
            guard let id = block.id else { continue }
            switch block.type {
            case .list:
                let selected = (block.items ?? []).compactMap(\.id).filter { values[id, default: []].contains($0) }
                selections[id] = block.multiple == true ? selected : Array(selected.prefix(1))
            case .file:
                let paths = values[id, default: []].filter { $0.hasPrefix("/") }.sorted()
                selections[id] = block.multiple == true ? paths : Array(paths.prefix(1))
            case .input: selections[id] = [inputs[id] ?? ""]
            case .toggle: selections[id] = [inputs[id] == "true" ? "true" : "false"]
            case .select:
                let value = inputs[id] ?? ""
                selections[id] = block.items?.contains(where: { $0.id == value }) == true ? [value] : []
            default: break
            }
        }
        do {
            try respond(event: InteractiveEvent(data: data, values: selections))
            waiting = false
            // Fast exchanges should not flash a spinner or move the current content.
            processingIndicatorTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
                guard let self, !self.ended, !self.waiting, self.request?.id == requestID else { return }
                self.showsProcessingIndicator = true
            }
        } catch { issue = L("Interactive UI error: {0}", error.localizedDescription) }
    }

    private func cancelProcessingIndicator() {
        processingIndicatorTask?.cancel()
        processingIndicatorTask = nil
        showsProcessingIndicator = false
    }

    private func respond(event: InteractiveEvent?) throws {
        guard let request else { return }
        try JSONEncoder().encode(InteractiveResponse(id: request.id, event: event))
            .write(to: directory.appendingPathComponent("response-\(request.id).json"), options: .atomic)
    }

    func finish() {
        guard !ended else { return }
        cancelProcessingIndicator()
        ended = true
        waiting = false
        timer?.invalidate()
        timer = nil
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        processingIndicatorTask?.cancel()
        timer?.invalidate()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Runs before the app entry point, so any language can use the bundled executable.
enum InteractiveClient {
    static func exchange(input: Data, directory: URL) throws -> InteractiveEvent? {
        let view = try InteractiveView.decode(input)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw InteractiveProtocolError.unavailable }
        let descriptor = open(directory.appendingPathComponent("client.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw InteractiveProtocolError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw InteractiveProtocolError.busy }
        defer { flock(descriptor, LOCK_UN) }
        let request = InteractiveRequest(id: UUID(), view: view)
        let responseURL = directory.appendingPathComponent("response-\(request.id).json")
        defer { try? FileManager.default.removeItem(at: responseURL) }
        try JSONEncoder().encode(request).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
        while FileManager.default.fileExists(atPath: directory.path) {
            if let data = try? Data(contentsOf: responseURL) {
                let response = try JSONDecoder().decode(InteractiveResponse.self, from: data)
                guard response.id == request.id else { throw InteractiveProtocolError.invalid }
                return response.event
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw InteractiveProtocolError.unavailable
    }

    static func run(actionOnly: Bool) -> Int32 {
        do {
            guard let path = ProcessInfo.processInfo.environment["SCRIPTDECK_UI_SESSION"] else { throw InteractiveProtocolError.unavailable }
            // Bounded read: an accidental stream must not consume unlimited memory.
            var input = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 8192), !chunk.isEmpty {
                input.append(chunk)
                guard input.count <= InteractiveView.maximumBytes else { throw InteractiveProtocolError.invalid }
            }
            if let event = try exchange(input: input, directory: URL(fileURLWithPath: path)) {
                let result = actionOnly ? Data(event.data.utf8) : try JSONEncoder().encode(event)
                FileHandle.standardOutput.write(result + Data([10]))
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return 1
        }
    }
}
