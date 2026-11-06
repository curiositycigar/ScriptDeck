import SwiftUI
import AppKit

struct AppSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var runner: ProcessRunner

    var body: some View {
        TabView(selection: $preferences.settingsTab) {
            WorkspaceSettingsView(workspaces: workspaces, runner: runner)
                .tabItem { Label("Workspaces", systemImage: "square.stack.3d.up") }.tag(SettingsTab.workspaces)
            Form {
                Section {
                    WorkspaceSectionTitle(title: "终端外观", subtitle: "调整字体与滚动历史，适用于所有 Workspace。")
                }
                Section("显示") {
                    Stepper(value: $preferences.terminalFontSize, in: 10...24, step: 1) {
                        LabeledContent("字体大小", value: "\(Int(preferences.terminalFontSize)) pt")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("❯ ./script.sh").foregroundStyle(.secondary)
                        Text("Hello, 你好。")
                    }
                    .font(.system(size: preferences.terminalFontSize, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    Text("字体大小立即应用于终端。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("历史记录") {
                    Picker("滚动历史行数", selection: $preferences.terminalScrollback) {
                        ForEach(AppPreferences.historyOptions, id: \.self) { count in
                            Text("\(count) 行").tag(count)
                        }
                    }
                    Text("从下次运行开始生效，当前终端内容不受影响。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("终端", systemImage: "terminal") }.tag(SettingsTab.terminal)
        }
        .padding(20)
        .frame(width: 780, height: 560)
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var runner: ProcessRunner
    @Environment(\.openWindow) private var openWindow
    @State private var selectedID: String?
    @State private var editing: Workspace?
    @State private var draftName = ""
    @State private var pendingRemoval: Workspace?
    private var selected: Workspace? { workspaces.items.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WorkspaceSectionTitle(title: "Workspaces", subtitle: "管理独立的脚本库目录，切换时保留各自的运行参数。")
                Spacer()
                Button { WorkspaceDialogs.add(to: workspaces) } label: { Label("添加…", systemImage: "plus") }
            }
            List(selection: $selectedID) {
                ForEach(workspaces.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").font(.title2)
                            .foregroundStyle(selectedID == item.id ? Color.white : Color.accentColor)
                        VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).fontWeight(.medium)
                            if item.id == workspaces.selectedID { Text("当前").font(.caption).foregroundStyle(.secondary) }
                            if runner.isWorkspaceRunning(item.id) { Text("运行中").font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            if let issue = workspaces.availability[item.id] {
                                Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(item.directory).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(item.directory)
                        }
                    }.padding(.vertical, 9).tag(item.id)
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if workspaces.items.isEmpty {
                    WorkspaceEmptyState(symbol: "folder.badge.plus", title: "尚无 Workspace", message: "添加一个保存脚本库的文件夹。")
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button { if let selected { workspaces.move(selected.id, by: -1) } } label: { Image(systemName: "arrow.up") }
                    .disabled(selected == nil || workspaces.items.first?.id == selectedID)
                    .help("上移").accessibilityLabel("上移 Workspace")
                Button { if let selected { workspaces.move(selected.id, by: 1) } } label: { Image(systemName: "arrow.down") }
                    .disabled(selected == nil || workspaces.items.last?.id == selectedID)
                    .help("下移").accessibilityLabel("下移 Workspace")
                Spacer()
                if let selected {
                    Menu("更多") {
                        Button("重命名…") { draftName = selected.name; editing = selected }
                        Button("在 Finder 中打开") { NSWorkspace.shared.open(selected.directoryURL) }
                        Button("重新定位…") { WorkspaceDialogs.relocate(selected, in: workspaces, runner: runner) }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                        Divider()
                        Button("移除登记…", role: .destructive) { pendingRemoval = selected }
                            .disabled(runner.isWorkspaceRunning(selected.id))
                    }
                    Button("打开") { workspaces.select(selected.id); openWindow(id: "main") }
                        .workspacePrimaryAction()
                }
            }
            Text("移除登记不会删除目录或文件。运行中的 Workspace 需先结束任务，才能移除或重新定位。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .onAppear { selectedID = workspaces.selectedID ?? workspaces.items.first?.id }
        .onChange(of: workspaces.selectedID) { id in selectedID = id }
        .onChange(of: workspaces.items) { items in
            if !items.contains(where: { $0.id == selectedID }) { selectedID = workspaces.selectedID ?? items.first?.id }
        }
        .alert("重命名 Workspace", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("名称", text: $draftName)
            Button("取消", role: .cancel) { editing = nil }
            Button("保存") {
                do { if let editing { try workspaces.rename(editing.id, to: draftName) } }
                catch { workspaces.error = error.localizedDescription }
                editing = nil
            }.disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("移除 Workspace 登记？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("取消", role: .cancel) { pendingRemoval = nil }
            Button("移除", role: .destructive) {
                do { if let pendingRemoval { try workspaces.remove(pendingRemoval.id, protectedID: runner.protectedWorkspaceID(for: pendingRemoval.id)) } }
                catch { workspaces.error = error.localizedDescription }
                pendingRemoval = nil
            }
        } message: { Text("仅移除“\(pendingRemoval?.name ?? "")”的本机登记，目录、脚本和配置文件都会保留。") }
    }
}
