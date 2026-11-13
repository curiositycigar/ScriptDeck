import SwiftUI
import AppKit

/// Selections belong to the channel so switching tabs preserves them.
private struct InteractiveBlocksView: View {
    @ObservedObject var channel: InteractiveChannel
    let request: InteractiveRequest
    var region: InteractiveBlock.Region = .body
    var inputFocus: FocusState<String?>.Binding

    private var primaryAction: (block: InteractiveElementID, item: InteractiveElementID)? {
        guard region == .footer else { return nil }
        let candidates = request.view.elements.filter { $0.value.region == .footer && $0.value.type == .buttons }
            .flatMap { block in
                block.value.elements.filter { $0.value.data != nil && $0.value.style != .destructive }
                    .map { (block: block.id, item: $0.id) }
            }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        let primary = primaryAction
        let elements = request.view.elements.filter { ($0.value.region ?? .body) == region }
        VStack(alignment: .leading, spacing: InteractivePanelMetrics.blockSpacing) {
            ForEach(elements) { element in
                let block = element.value
                switch block.type {
                case .text:
                    if let notice = block.notice {
                        InteractiveNotice(kind: notice, message: block.text ?? "")
                    } else if block.section == true {
                        VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
                            Divider()
                            Text(block.text ?? "")
                                .font(WorkspaceTypography.sectionLabel)
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(block.text ?? "")
                            .font(textFont(block, implicitTitle: region == .header
                                ? element.id == elements.first?.id : element.index == 0))
                            .foregroundStyle(block.style == .secondary ? Color.secondary : Color.primary)
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .buttons:
                    InteractiveButtonLayout {
                        ForEach(block.elements) { action in
                            actionButton(action.value, prominent: primary?.block == element.id && primary?.item == action.id)
                        }
                    }
                case .input, .file, .select, .toggle, .progress:
                    InteractiveFormControl(channel: channel, block: block, requestID: request.id, inputFocus: inputFocus)
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

    private func textFont(_ block: InteractiveBlock, implicitTitle: Bool) -> Font {
        if block.style == .secondary { return WorkspaceTypography.caption }
        if block.style == .title || (block.style == nil && implicitTitle) {
            return region == .header ? WorkspaceTypography.scriptTitle : WorkspaceTypography.sectionTitle
        }
        return WorkspaceTypography.body
    }

    private func actionButton(_ item: InteractiveItem, prominent: Bool) -> some View {
        let button = Button(role: item.style == .destructive ? .destructive : nil) {
            channel.activate(item, requestID: request.id)
        } label: {
            Text(item.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        return Group {
            if prominent { button.buttonStyle(.borderedProminent) }
            else { button.buttonStyle(.bordered) }
        }
        .controlSize(.regular)
        .font(WorkspaceTypography.captionStrong)
        .disabled(!channel.waiting || channel.ended || !channel.canSubmit(item, values: channel.selections))
    }
}

/// Form state is retained by the channel, including across tab switches.
private struct InteractiveFormControl: View {
    @ObservedObject var channel: InteractiveChannel
    let block: InteractiveBlock
    let requestID: UUID
    var inputFocus: FocusState<String?>.Binding

    @State private var isDropTargeted = false
    @State private var revealsPassword = false

    private var id: String { block.id ?? "" }
    private var input: Binding<String> {
        Binding(get: { channel.inputs[id] ?? "" }, set: { channel.inputs[id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
            if let label = block.label, block.type != .toggle && block.type != .progress {
                Text(label).font(WorkspaceTypography.captionStrong).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch block.type {
            case .input:
                if block.secure == true {
                    HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                        Group {
                            if revealsPassword { TextField(block.placeholder ?? "", text: input) }
                            else { SecureField(block.placeholder ?? "", text: input) }
                        }
                        .textFieldStyle(.roundedBorder)
                        .focused(inputFocus, equals: id)
                        .accessibilityLabel(block.label ?? block.placeholder ?? L("Password"))
                        Button {
                            revealsPassword.toggle()
                            inputFocus.wrappedValue = id
                        } label: {
                            Image(systemName: revealsPassword ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(L(revealsPassword ? "Hide password" : "Show password"))
                        .help(L(revealsPassword ? "Hide password" : "Show password"))
                    }
                    .onChange(of: requestID) { _ in revealsPassword = false }
                    .onChange(of: channel.waiting) { waiting in
                        if !waiting { revealsPassword = false }
                    }
                } else {
                    TextField(block.placeholder ?? "", text: input, axis: block.multiline == true ? .vertical : .horizontal)
                        .textFieldStyle(.roundedBorder)
                        .focused(inputFocus, equals: id)
                        .accessibilityLabel(block.label ?? block.placeholder ?? L("Text input"))
                }
            case .select:
                InteractiveSelect(block: block, selection: input, requestID: requestID)
            case .toggle:
                Toggle(block.label ?? "", isOn: Binding(
                    get: { channel.inputs[id] == "true" },
                    set: { channel.inputs[id] = $0 ? "true" : "false" }
                )).toggleStyle(.checkbox)
            case .file:
                VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
                    InteractiveButtonLayout {
                        Button(L("Choose…"), action: chooseFiles).buttonStyle(.bordered)
                        if !channel.selections[id, default: []].isEmpty {
                            Button(L("Clear")) { channel.clearFiles(controlID: id, requestID: requestID) }.buttonStyle(.bordered)
                        }
                    }
                    Label(L(block.mode == .directory ? "Drop folders here" : "Drop files here"),
                          systemImage: "arrow.down.to.line")
                        .foregroundStyle(.secondary)
                    if channel.selections[id, default: []].isEmpty {
                        Text(L("Nothing selected")).foregroundStyle(.secondary)
                    } else {
                        Text(L("{0} selected", String(channel.selections[id, default: []].count)))
                            .foregroundStyle(.secondary)
                        ForEach(channel.selections[id, default: []].sorted(), id: \.self) { path in
                            Text(path).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(InteractivePanelMetrics.blockSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDropTargeted ? WorkspaceStyle.selectionColor : WorkspaceStyle.groupedSurface,
                            in: RoundedRectangle(cornerRadius: InteractivePanelMetrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: InteractivePanelMetrics.controlRadius)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .dropDestination(for: URL.self) { urls, _ in
                    channel.selectFiles(urls, controlID: id, requestID: requestID)
                } isTargeted: { targeted in
                    isDropTargeted = targeted && channel.waiting && !channel.ended
                }
            case .progress:
                InteractiveProgress(block: block)
            default: EmptyView()
            }
        }
        .font(WorkspaceTypography.caption)
        .controlSize(.regular)
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

private struct InteractiveProgress: View {
    let block: InteractiveBlock

    var body: some View {
        if let value = block.progress {
            ProgressView(value: value) {
                Text(block.label ?? L("Progress")).font(WorkspaceTypography.captionStrong)
            } currentValueLabel: {
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
        } else {
            HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(block.label ?? L("Progress")).font(WorkspaceTypography.captionStrong)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        if let detail = block.text, !detail.isEmpty {
            Text(detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InteractiveNotice: View {
    let kind: InteractiveBlock.Notice
    let message: String

    private var style: (title: String, symbol: String, color: Color) {
        switch kind {
        case .success: return (L("Success"), "checkmark.circle.fill", Color(nsColor: .systemGreen))
        case .warning: return (L("Warning"), "exclamationmark.triangle.fill", Color(nsColor: .systemOrange))
        case .error: return (L("Error"), "exclamationmark.circle.fill", Color(nsColor: .systemRed))
        case .info: return (L("Information"), "info.circle.fill", Color(nsColor: .systemBlue))
        }
    }

    var body: some View {
        let style = style
        Label {
            VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
                Text(style.title).font(WorkspaceTypography.captionStrong)
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: style.symbol).foregroundStyle(style.color).accessibilityHidden(true)
        }
        .font(WorkspaceTypography.caption)
        .padding(InteractivePanelMetrics.blockSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: InteractivePanelMetrics.controlRadius))
    }
}

private struct InteractiveSelect: View {
    let block: InteractiveBlock
    @Binding var selection: String
    let requestID: UUID
    @State private var query = ""

    private var items: [InteractiveItem] { block.items ?? [] }

    var body: some View {
        let selected = items.first { $0.id == selection }
        let search = items.count >= 12 ? query.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let matchingIDs = Set(items.filter { search.isEmpty || $0.text.localizedStandardContains(search) ||
            $0.detail?.localizedStandardContains(search) == true }.compactMap(\.id))
        let options = items.filter { item in item.id == selection || item.id.map(matchingIDs.contains) == true }
        if items.count >= 12 {
            TextField(L("Search options"), text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: requestID) { _ in query = "" }
        }
        Picker(block.label ?? L("Select an option"), selection: $selection) {
            ForEach(options, id: \.id) { item in
                Text(item.text).tag(item.id ?? "")
                    .disabled(item.disabled == true)
            }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        if matchingIDs.isEmpty {
            Text(L("No matching options")).foregroundStyle(.secondary)
        } else if let detail = selected?.detail, !detail.isEmpty {
            Text(detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rows expand naturally; the panel owns the only scroll container.
private struct InteractiveSelectionList: View {
    @ObservedObject var channel: InteractiveChannel
    let block: InteractiveBlock
    let listID: String

    private var items: [InteractiveItem] { block.items ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
            Text(L("{0} items · {1} selected", "\(items.count)", "\(channel.selections[listID, default: []].count)"))
                .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                .padding(.horizontal, InteractivePanelMetrics.blockSpacing)
            VStack(alignment: .leading, spacing: 0) {
                if let columns = block.columns, !items.isEmpty {
                    HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                        Image(systemName: "square").hidden().accessibilityHidden(true)
                        tableCells(columns)
                            .font(WorkspaceTypography.sectionLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    Divider()
                }
                if items.isEmpty {
                    Label(L("No items to display"), systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(items, id: \.id) { item in
                    if let itemID = item.id {
                        let selected = channel.selections[listID, default: []].contains(itemID)
                        Button {
                            if block.multiple == true {
                                if selected { channel.selections[listID, default: []].remove(itemID) }
                                else { channel.selections[listID, default: []].insert(itemID) }
                            } else { channel.selections[listID] = selected ? [] : [itemID] }
                        } label: {
                            HStack(spacing: InteractivePanelMetrics.actionSpacing) {
                                Image(systemName: selected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                    .accessibilityHidden(true)
                                if let columns = block.columns, let cells = item.cells {
                                    tableCells([item.text] + cells, badge: item.badge)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(zip(columns, [item.text] + cells)
                                            .map { "\($0.0): \($0.1)" }.joined(separator: ", ") +
                                            (item.badge.map { ", " + InteractiveBadge.title($0) } ?? ""))
                                } else {
                                    VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
                                        InteractiveItemLabel(item: item)
                                        if let badge = item.badge { InteractiveBadge(badge: badge) }
                                    }
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, minHeight: InteractivePanelMetrics.rowHeight, alignment: .leading)
                            .background(selected ? WorkspaceStyle.selectionColor : .clear,
                                        in: RoundedRectangle(cornerRadius: InteractivePanelMetrics.controlRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func tableCells(_ cells: [String], badge: InteractiveItem.Badge? = nil) -> some View {
        HStack(alignment: .top, spacing: InteractivePanelMetrics.actionSpacing) {
            ForEach(cells.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
                    Text(cells[index]).fixedSize(horizontal: false, vertical: true)
                    if index == 0, let badge { InteractiveBadge(badge: badge) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct InteractiveBadge: View {
    let badge: InteractiveItem.Badge

    static func title(_ badge: InteractiveItem.Badge) -> String {
        switch badge {
        case .running: return L("Running")
        case .completed: return L("Completed")
        case .failed: return L("Failed")
        }
    }

    var body: some View {
        let color: Color = switch badge {
        case .running: Color(nsColor: .systemBlue)
        case .completed: Color(nsColor: .systemGreen)
        case .failed: Color(nsColor: .systemRed)
        }
        Text(Self.title(badge))
            .font(WorkspaceTypography.badge)
            .padding(.horizontal, InteractivePanelMetrics.blockSpacing)
            .padding(.vertical, InteractivePanelMetrics.inlineSpacing)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: InteractivePanelMetrics.controlRadius))
            .fixedSize(horizontal: false, vertical: true)
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
                VStack(alignment: .leading, spacing: InteractivePanelMetrics.inlineSpacing) {
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
    @FocusState private var focusedInput: String?
    @State private var lastFocusedInput: String?

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                if let request = channel.request, hasRegion(.header, in: request) {
                    fixedRegion(.header, request: request)
                    Divider()
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: InteractivePanelMetrics.groupSpacing) {
                        if let request = channel.request {
                            if request.view.blocks.isEmpty && !channel.ended {
                                status(L("No content to display"), symbol: "tray")
                            } else {
                                InteractiveBlocksView(channel: channel, request: request, inputFocus: $focusedInput)
                            }
                        } else if !channel.ended && channel.issue == nil {
                            status(L("Waiting for the script interface…"), symbol: "rectangle.and.hand.point.up.left")
                        }
                        if let issue = channel.issue {
                            InteractiveNotice(kind: .error, message: issue)
                        }
                        if channel.ended {
                            status(L("This session has ended. Interface controls are disabled."), symbol: "checkmark.circle")
                        }
                    }
                    .padding(.horizontal, InteractivePanelMetrics.inset)
                    .padding(.vertical, InteractivePanelMetrics.inset)
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
            .onChange(of: focusedInput) { id in
                if id != nil || channel.waiting { lastFocusedInput = id }
            }
            .onChange(of: channel.request?.view.pageID) { _ in
                lastFocusedInput = nil
                focusedInput = nil
            }
            .onChange(of: channel.request?.id) { _ in
                guard channel.waiting, let id = lastFocusedInput,
                      channel.request?.view.blocks.contains(where: { $0.id == id && $0.type == .input }) == true else {
                    lastFocusedInput = nil
                    return
                }
                focusedInput = id
            }
        }
    }

    private func hasRegion(_ region: InteractiveBlock.Region, in request: InteractiveRequest) -> Bool {
        request.view.blocks.contains { $0.region == region }
    }

    private func fixedRegion(_ region: InteractiveBlock.Region, request: InteractiveRequest) -> some View {
        InteractiveBlocksView(channel: channel, request: request, region: region, inputFocus: $focusedInput)
            .padding(.horizontal, InteractivePanelMetrics.inset)
            .padding(.vertical, InteractivePanelMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceStyle.chrome)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private func status(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SessionOutputPicker: View {
    @Binding var showingTerminalLog: Bool

    var body: some View {
        Picker(L("Output View"), selection: $showingTerminalLog) {
            Text(L("Interactive UI")).tag(false)
            Text(L("Terminal Log")).tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(L("Output View"))
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
                    SessionOutputPicker(showingTerminalLog: $session.showingTerminalLog)
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
            .onAppear { session.focusTerminal() }
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
