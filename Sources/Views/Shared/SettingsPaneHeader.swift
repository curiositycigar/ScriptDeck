import SwiftUI

struct SettingsPaneHeader: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var showsSymbol = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsSymbol {
                WorkspaceSymbol(symbol, size: .header)
                .foregroundStyle(.tint)
                .frame(width: WorkspaceControlMetrics.headerTile, height: WorkspaceControlMetrics.headerTile)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(WorkspaceTypography.dialogTitle)
                if let subtitle {
                    Text(subtitle).font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
