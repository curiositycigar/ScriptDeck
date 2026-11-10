import SwiftUI

struct ParameterHistoryRow: View {
    let entry: ParameterCallHistory.Entry
    let parameters: [ScriptParameter]
    let selected: Bool
    let select: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    (Text(entry.calledAt, style: .date) + Text(" · ") + Text(entry.calledAt, style: .time))
                        .font(WorkspaceTypography.bodyStrong).lineLimit(1)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(parameters) { parameter in
                            HStack(spacing: 8) {
                                Text(parameter.name)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: 100, alignment: .leading)
                                ParameterHistoryValue(value: displayValue(parameter))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help(displayValue(parameter))
                            }
                            .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button(action: remove) {
                WorkspaceSymbol("trash", size: .toolbar)
            }
            .buttonStyle(WorkspaceIconButtonStyle()).foregroundStyle(.secondary)
            .help(L("Delete Record")).accessibilityLabel(L("Delete Record"))
            .padding(.top, 4).padding(.trailing, 4)
        }
        .background(selected ? WorkspaceStyle.selectionColor : hovered ? Color.primary.opacity(0.05) : WorkspaceStyle.groupedSurface,
                    in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .workspaceAnimation(value: hovered)
        .workspaceAnimation(value: selected)
    }

    private func displayValue(_ parameter: ScriptParameter) -> String {
        let value = entry.values[parameter.id] ?? ""
        if parameter.passing == .flag { return value == "true" ? L("On") : L("Off") }
        return value.isEmpty ? L("Empty") : value
    }
}

/// Keep a short identifying prefix and give the remaining space to the value's tail.
private struct ParameterHistoryValue: View {
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(value).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 0) {
                Text(String(value.prefix(4))).fixedSize(horizontal: true, vertical: false)
                Text(String(value.dropFirst(4)))
                    .lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value)
    }
}
