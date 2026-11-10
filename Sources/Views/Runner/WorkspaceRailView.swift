import SwiftUI

/// Persistent workspace and global actions; script navigation stays in the sidebar.
struct WorkspaceRailView: View {
    @ObservedObject var workspaces: WorkspaceStore
    @ObservedObject var navigation: WorkspaceNavigation
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(workspaces.items) { workspace in
                        railButton(workspace.name,
                                   selected: workspaces.selectedID == workspace.id && navigation.destination == .scripts) {
                            workspaces.select(workspace.id)
                            navigation.destination = .scripts
                        } label: {
                            Text(String(workspace.name.prefix(2)).uppercased())
                                .font(WorkspaceTypography.sectionLabel)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    railButton(L("Add Workspace…")) { WorkspaceDialogs.add(to: workspaces) } label: {
                        WorkspaceSymbol("plus", size: .navigation)
                    }
                }.padding(.vertical, 2)
            }
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 12)
            railButton(L("All Scheduled Tasks"), selected: navigation.destination == .schedules) {
                navigation.destination = .schedules
            } label: { WorkspaceSymbol("calendar.badge.clock", size: .navigation) }
            railButton(L("Settings"), action: showSettings) {
                WorkspaceSymbol("gearshape", size: .navigation)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .background(WorkspaceStyle.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Workspaces"))
    }

    private func railButton<Content: View>(_ title: String, selected: Bool = false,
                                           action: @escaping () -> Void,
                                           @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .frame(width: WorkspaceControlMetrics.navigationTarget, height: WorkspaceControlMetrics.navigationTarget)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(WorkspaceNavigationButtonStyle(selected: selected))
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? L("Selected") : L("Not selected"))
    }
}
