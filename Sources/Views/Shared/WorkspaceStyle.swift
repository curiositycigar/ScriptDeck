import SwiftUI
import AppKit

enum WorkspaceStyle {
    static let selectionColor = Color.accentColor.opacity(0.12)
}

// Materials belong to navigation and actions; readable content stays on solid system surfaces.
extension View {
    func workspaceListSelection(_ selected: Bool) -> some View {
        self
            .foregroundStyle(Color(nsColor: .labelColor))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? WorkspaceStyle.selectionColor : Color.clear)
            )
    }

    func workspaceListAppearance() -> some View {
        self.background(NativeListSelectionSuppression())
    }

    @ViewBuilder func workspaceGlass() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder func workspacePrimaryAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// List owns an AppKit selection highlight that listItemTint does not replace on macOS.
// Keep native selection and keyboard navigation, and draw the row background in SwiftUI.
private struct NativeListSelectionSuppression: NSViewRepresentable {
    func makeNSView(context: Context) -> SelectionView { SelectionView() }

    func updateNSView(_ nsView: SelectionView, context: Context) {
        nsView.suppressNativeHighlight()
    }

    final class SelectionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            suppressNativeHighlight()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleUpdate()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }

        private func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in self?.suppressNativeHighlight() }
        }

        func suppressNativeHighlight() {
            func table(in view: NSView) -> NSTableView? {
                if let table = view as? NSTableView { return table }
                for child in view.subviews {
                    if let found = table(in: child) { return found }
                }
                return nil
            }
            var ancestor = superview
            while let view = ancestor {
                if let table = table(in: view) {
                    if table.selectionHighlightStyle != .none {
                        table.selectionHighlightStyle = .none
                        table.needsDisplay = true
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

struct WorkspaceEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 80, height: 80)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.title2.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }.padding(24)
    }
}

struct WorkspaceSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}
