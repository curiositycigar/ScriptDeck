import Foundation

/// The public protocol intentionally describes content rather than arbitrary view trees.
struct InteractiveView: Codable, Equatable {
    var blocks: [InteractiveBlock]
    var pageID: String? = nil

    static let maximumBytes = 256 * 1024

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw InteractiveProtocolError.invalid }
        let view = try JSONDecoder().decode(Self.self, from: data)
        try view.validate()
        return view
    }

    func validate() throws {
        guard pageID == nil || !pageID!.isEmpty, blocks.count <= 100 else { throw InteractiveProtocolError.invalid }
        var blockIDs = Set<String>()
        for block in blocks {
            if let id = block.id {
                guard !id.isEmpty, blockIDs.insert(id).inserted else { throw InteractiveProtocolError.invalid }
            }
            if block.reset != nil && ![.input, .file, .list, .select, .toggle].contains(block.type) {
                throw InteractiveProtocolError.invalid
            }
            switch block.type {
            case .text:
                guard block.text != nil else { throw InteractiveProtocolError.invalid }
            case .list:
                guard let id = block.id, !id.isEmpty,
                      let items = block.items, items.count <= 1000 else { throw InteractiveProtocolError.invalid }
                var ids = Set<String>()
                for item in items {
                    guard let id = item.id, !id.isEmpty, ids.insert(id).inserted else { throw InteractiveProtocolError.invalid }
                }
            case .input, .file, .select, .toggle:
                guard let id = block.id, !id.isEmpty else { throw InteractiveProtocolError.invalid }
                if block.type == .input && block.multiline == true && block.secure == true { throw InteractiveProtocolError.invalid }
                if block.type == .select {
                    guard let items = block.items, !items.isEmpty, items.count <= 1000 else { throw InteractiveProtocolError.invalid }
                    let ids = items.compactMap(\.id)
                    guard ids.count == items.count, !ids.contains(""), Set(ids).count == ids.count,
                          block.value == nil || ids.contains(block.value!) else { throw InteractiveProtocolError.invalid }
                }
            case .progress:
                if let progress = block.progress, !progress.isFinite || !(0...1).contains(progress) { throw InteractiveProtocolError.invalid }
            case .buttons:
                guard let items = block.items, (1...8).contains(items.count),
                      items.allSatisfy({ ($0.data != nil) != ($0.action != nil) }) else { throw InteractiveProtocolError.invalid }
                let ids = items.compactMap(\.id)
                guard !ids.contains(""), Set(ids).count == ids.count else { throw InteractiveProtocolError.invalid }
            }
        }
        let listIDs = Set(blocks.filter { $0.type == .list }.compactMap(\.id))
        for item in blocks.filter({ $0.type == .buttons }).flatMap({ $0.items ?? [] }) {
            if let id = item.requiresSelection, !listIDs.contains(id) { throw InteractiveProtocolError.invalid }
            if let action = item.action {
                guard blocks.contains(where: { $0.id == action.target && $0.type == .input && $0.secure != true }) else {
                    throw InteractiveProtocolError.invalid
                }
            }
        }
        // Local actions cannot complete a helper exchange on their own.
        if hasButtons && !blocks.filter({ $0.type == .buttons }).flatMap({ $0.items ?? [] }).contains(where: { $0.data != nil }) {
            throw InteractiveProtocolError.invalid
        }
    }

    var hasButtons: Bool { blocks.contains { $0.type == .buttons } }
}

struct InteractiveBlock: Codable, Equatable {
    enum Kind: String, Codable { case text, list, buttons, input, file, select, toggle, progress }
    var type: Kind
    var id: String?
    var text: String?
    var multiple: Bool?
    var items: [InteractiveItem]?
    var label: String?
    var placeholder: String?
    var value: String?
    var multiline: Bool?
    var secure: Bool?
    enum FileMode: String, Codable { case file, directory }
    var mode: FileMode?
    var checked: Bool?
    var progress: Double?
    enum TextStyle: String, Codable { case title, body, secondary }
    var style: TextStyle?
    enum Region: String, Codable { case header, body, footer }
    var region: Region?
    var reset: Bool? = nil
}

struct InteractiveItem: Codable, Equatable {
    var id: String?
    var text: String
    var data: String?
    var detail: String?
    enum ActionStyle: String, Codable { case `default`, destructive }
    var style: ActionStyle?
    var disabled: Bool?
    var requiresSelection: String?
    var action: InteractiveLocalAction? = nil
}

/// A bounded local form operation; never executes script code or submits an event.
struct InteractiveLocalAction: Codable, Equatable {
    enum Kind: String, Codable { case setValue }
    var type: Kind
    var target: String
    var value: String
}

/// Explicit IDs and positional fallbacks occupy separate namespaces.
enum InteractiveElementID: Hashable {
    case named(String)
    case position(Int)
}

struct InteractiveElement<Value>: Identifiable {
    let id: InteractiveElementID
    let index: Int
    let value: Value
}

extension InteractiveView {
    var elements: [InteractiveElement<InteractiveBlock>] {
        blocks.enumerated().map { index, block in
            InteractiveElement(id: block.id.map(InteractiveElementID.named) ?? .position(index), index: index, value: block)
        }
    }
}

extension InteractiveBlock {
    var elements: [InteractiveElement<InteractiveItem>] {
        (items ?? []).enumerated().map { index, item in
            InteractiveElement(id: item.id.map(InteractiveElementID.named) ?? .position(index), index: index, value: item)
        }
    }
}

struct InteractiveEvent: Codable, Equatable {
    var data: String
    var values: [String: [String]]
}

struct InteractiveRequest: Codable {
    var id: UUID
    var view: InteractiveView
}

struct InteractiveResponse: Codable {
    var id: UUID
    var event: InteractiveEvent?
}

enum InteractiveProtocolError: LocalizedError {
    case invalid, unavailable, busy
    var errorDescription: String? {
        switch self {
        case .invalid: return L("Invalid interactive UI JSON. Check block types, IDs, items, and size limits.")
        case .unavailable: return L("The interactive UI session is unavailable or has ended.")
        case .busy: return L("Only one interactive UI request may be active at a time.")
        }
    }
}
