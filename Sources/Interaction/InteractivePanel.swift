import SwiftUI
import AppKit

/// Selections belong to the channel so switching tabs preserves them.
private struct InteractiveBlocksView: View {
    @ObservedObject var channel: InteractiveChannel
    let request: InteractiveRequest
    var region: InteractiveBlock.Region = .body

    var body: some View {
        VStack(alignment: .leading, spacing: InteractivePanelMetrics.blockSpacing) {
            ForEach(request.view.elements.filter { ($0.value.region ?? .body) == region }) { element in
                let index = element.index
                let block = element.value
                switch block.type {
                case .text:
                    Text(block.text ?? "")
                        .font(block.style == .secondary ? WorkspaceTypography.caption :
                              (block.style == .title || (block.style == nil && index == 0) ? WorkspaceTypography.sectionTitle : WorkspaceTypography.body))
                        .foregroundStyle(block.style == .secondary ? Color.secondary : Color.primary)
                        .lineSpacing(1)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .buttons:
                    InteractiveButtonLayout {
                        ForEach(block.elements) { element in
                            let item = element.value
                            Button(role: item.style == .destructive ? .destructive : nil) {
                                channel.activate(item, requestID: request.id)
                            } label: {
                                Text(item.text)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(WorkspaceTypography.caption)
                            .disabled(!channel.waiting || channel.ended || !channel.canSubmit(item, values: channel.selections))
                        }
                    }
                case .input, .file, .select, .toggle, .progress:
                    InteractiveFormControl(channel: channel, block: block, requestID: request.id)
                        .disabled(block.type != .progress && (!channel.waiting || channel.ended))
                case .list:
                    if let id = block.id {
                        InteractiveSelectionList(channel: channel, block: block, listID: id)
                            .disabled(!channel.waiting || channel.ended)
                    }
                }
            }
        }
    }
}

/// Form state is retained by the channel, including across tab switches.
private struct InteractiveFormControl: View {
    @ObservedObject var channel: InteractiveChannel
    let block: InteractiveBlock
    let requestID: UUID

    @State private var isDropTargeted = false

    private var id: String { block.id ?? "" }
    private var input: Binding<String> {
        Binding(get: { channel.inputs[id] ?? "" }, set: { channel.inputs[id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = block.label, block.type != .toggle {
                Text(label).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch block.type {
            case .input:
                if block.secure == true {
                    SecureField(block.placeholder ?? "", text: input)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(block.label ?? block.placeholder ?? L("Text input"))
                } else {
                    TextField(block.placeholder ?? "", text: input, axis: block.multiline == true ? .vertical : .horizontal)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(block.label ?? block.placeholder ?? L("Text input"))
                }
            case .select:
                Picker(block.label ?? L("Select an option"), selection: input) {
                    ForEach(block.items ?? [], id: \.id) { item in
                        Text(item.text).tag(item.id ?? "")
                    }
                }
                .labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .toggle:
                Toggle(block.label ?? "", isOn: Binding(
                    get: { channel.inputs[id] == "true" },
                    set: { channel.inputs[id] = $0 ? "true" : "false" }
                )).toggleStyle(.checkbox)
            case .file:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                        Button(L("Choose…"), action: chooseFiles).buttonStyle(.bordered)
                        if !channel.selections[id, default: []].isEmpty {
                            Button(L("Clear")) { channel.clearFiles(controlID: id, requestID: requestID) }.buttonStyle(.bordered)
                        }
                    }
                    Text(L(block.mode == .directory ? "Drop folders here" : "Drop files here"))
                        .foregroundStyle(.secondary)
                    if channel.selections[id, default: []].isEmpty {
                        Text(L("Nothing selected")).foregroundStyle(.secondary)
                    } else {
                        ForEach(channel.selections[id, default: []].sorted(), id: \.self) { path in
                            Text(path).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDropTargeted ? WorkspaceStyle.selectionColor : WorkspaceStyle.groupedSurface,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .dropDestination(for: URL.self) { urls, _ in
                    channel.selectFiles(urls, controlID: id, requestID: requestID)
                } isTargeted: { targeted in
                    isDropTargeted = targeted && channel.waiting && !channel.ended
                }
            case .progress:
                if let value = block.progress {
                    ProgressView(value: value, total: 1).progressViewStyle(.linear)
                    Text("\(Int(value * 100))%").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            default: EmptyView()
            }
        }
        .font(WorkspaceTypography.caption)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = block.mode != .directory
        panel.canChooseDirectories = block.mode == .directory
        panel.allowsMultipleSelection = block.multiple == true
        panel.canCreateDirectories = false
        panel.prompt = L("Choose")
        // Capture the originating request; a late panel result must not edit a new view.
        let controlID = id
        let apply: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, channel.request?.id == requestID,
                  channel.waiting, !channel.ended else { return }
            channel.selectFiles(panel.urls, controlID: controlID, requestID: requestID)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: apply) }
        else { panel.begin(completionHandler: apply) }
    }
}

/// Rows expand naturally; the panel owns the only scroll container.
private struct InteractiveSelectionList: View {
    @ObservedObject var channel: InteractiveChannel
    let block: InteractiveBlock
    let listID: String

    private var items: [InteractiveItem] { block.items ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("{0} items · {1} selected", "\(items.count)", "\(channel.selections[listID, default: []].count)"))
                .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 2) {
                if items.isEmpty {
                    Text(L("No items to display"))
                        .foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(items, id: \.id) { item in
                    if let itemID = item.id {
                        let selected = channel.selections[listID, default: []].contains(itemID)
                        Toggle(isOn: Binding(get: { selected }, set: { enabled in
                            if block.multiple == true {
                                if enabled { channel.selections[listID, default: []].insert(itemID) }
                                else { channel.selections[listID, default: []].remove(itemID) }
                            } else { channel.selections[listID] = enabled ? [itemID] : [] }
                        })) {
                            InteractiveItemLabel(item: item)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: InteractivePanelMetrics.rowHeight, alignment: .leading)
                        .background(selected ? WorkspaceStyle.selectionColor : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(4)
            .background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 8))

        }
    }
}

/// Keep metadata aligned on wide panels and wrap below the name when space is tight.
private struct InteractiveItemLabel: View {
    let item: InteractiveItem

    var body: some View {
        if let detail = item.detail, !detail.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(item.text).fixedSize()
                    Spacer(minLength: 8)
                    Text(detail).font(WorkspaceTypography.caption).foregroundStyle(.secondary).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(item.text).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InteractivePanel: View {
    @ObservedObject var channel: InteractiveChannel

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                if let request = channel.request, hasRegion(.header, in: request) {
                    fixedRegion(.header, request: request)
                    Divider()
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: InteractivePanelMetrics.blockSpacing) {
                        if let request = channel.request {
                            InteractiveBlocksView(channel: channel, request: request)
                        } else {
                            status(L("Waiting for the script interface…"), symbol: "rectangle.and.hand.point.up.left")
                        }
                        if let issue = channel.issue {
                            Label(issue, systemImage: "exclamationmark.triangle")
                                .font(WorkspaceTypography.caption).foregroundStyle(.red)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if channel.ended {
                            status(L("This session has ended. Interface controls are disabled."), symbol: "checkmark.circle")
                        }
                    }
                    .padding(.horizontal, InteractivePanelMetrics.inset)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if channel.showsProcessingIndicator {
                        HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                            ProgressView().controlSize(.small)
                            Text(L("Waiting for the script…"))
                        }
                        .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(InteractivePanelMetrics.inset)
                        .allowsHitTesting(false)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                if let request = channel.request, hasRegion(.footer, in: request) {
                    Divider()
                    fixedRegion(.footer, request: request)
                }
            }
            .font(WorkspaceTypography.body)
            .id(channel.request?.view.pageID)
        }
    }

    private func hasRegion(_ region: InteractiveBlock.Region, in request: InteractiveRequest) -> Bool {
        request.view.blocks.contains { $0.region == region }
    }

    private func fixedRegion(_ region: InteractiveBlock.Region, request: InteractiveRequest) -> some View {
        InteractiveBlocksView(channel: channel, request: request, region: region)
            .padding(.horizontal, InteractivePanelMetrics.inset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private func status(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Retained per execution, including its chosen tab when switching between tasks.
struct SessionOutputPane: View {
    @ObservedObject var session: ExecutionSession
    var onHiddenInput: (() -> Void)? = nil
    var showsViewPicker = true

    var body: some View {
        VStack(spacing: 0) {
            if let channel = session.interactiveChannel {
                if showsViewPicker {
                    Picker(L("Output View"), selection: $session.showingTerminalLog) {
                        Text(L("Interactive UI")).tag(false)
                        Text(L("Terminal Log")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, InteractivePanelMetrics.inset)
                    .padding(.vertical, 6)
                    Divider()
                }
                if session.showingTerminalLog { terminal }
                else {
                    VStack(spacing: 0) {
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            if session.needsHiddenInputNotice {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(L("The script may be waiting for a password or other hidden input."),
                                          systemImage: "exclamationmark.triangle.fill")
                                        .font(WorkspaceTypography.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let onHiddenInput {
                                        Button(L("Enter Hidden Input…"), action: onHiddenInput)
                                            .buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, InteractivePanelMetrics.inset).padding(.top, 8)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        InteractivePanel(channel: channel)
                    }
                }
            } else { terminal }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas)
    }

    private var terminal: some View {
        EmbeddedTerminalView(session: session)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .overlay {
                if !session.hasOutput && !session.isRunning {
                    VStack(spacing: 6) {
                        Text(L("Terminal Ready")).font(WorkspaceTypography.bodyStrong)
                        Text(L("Run a script to view output and type here. Password input usually does not display characters."))
                            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .padding(20).allowsHitTesting(false)
                }
            }
    }
}
