import SwiftUI

struct WorkspaceRailView: View {
    @ObservedObject var navigation: WorkspaceNavigation

    var body: some View {
        VStack(spacing: 12) {
            railButton(.home, title: L("Home"), symbol: "house")
            railButton(.scripts, title: L("Workspaces"), symbol: "square.stack.3d.up")
            railButton(.schedules, title: L("Scheduled Tasks"), symbol: "calendar.badge.clock")
            railButton(.logs, title: L("Logs"), symbol: "doc.text")
            Spacer(minLength: 0)
            railButton(.settings, title: L("Settings"), symbol: "gearshape")
        }
        .padding(.vertical, 16)
        .frame(width: 64)
        .background(WorkspaceStyle.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Navigation"))
    }

    private func railButton(_ destination: WorkspaceNavigation.Destination, title: String, symbol: String) -> some View {
        let selected = navigation.destination == destination
        return Button {
            if destination == .logs { navigation.showHistory() }
            else { navigation.destination = destination }
        } label: {
            WorkspaceSymbol(symbol, size: .navigation)
                .frame(width: 40, height: 40)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(WorkspaceNavigationButtonStyle(selected: selected))
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? L("Selected") : L("Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
