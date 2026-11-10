import SwiftUI
import AppKit

enum WorkspaceStyle {
    // Shared semantic surfaces resolve against the current macOS appearance.
    static let canvasNSColor = NSColor.textBackgroundColor
    static let canvas = Color(nsColor: canvasNSColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor)
    static let chrome = Color(nsColor: .windowBackgroundColor)
    static let groupedSurface = Color.primary.opacity(0.025)
    static let selectionColor = Color.accentColor.opacity(0.10)
}

struct WorkspaceIconButtonStyle: ButtonStyle {
    var targetSize: CGFloat = WorkspaceControlMetrics.iconTarget
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, targetSize: targetSize, prominent: prominent)
    }

    private struct IconButton: View {
        let configuration: ButtonStyle.Configuration
        let targetSize: CGFloat
        let prominent: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        @ViewBuilder private var label: some View {
            if prominent {
                configuration.label.foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
            } else {
                configuration.label
            }
        }

        private var background: Color {
            if prominent {
                return Color.accentColor.opacity(configuration.isPressed ? 0.76 : hovered ? 0.88 : 1)
            }
            return Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.12 : hovered ? 0.06 : 0) : 0)
        }

        var body: some View {
            label
                .frame(width: targetSize, height: targetSize)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .workspaceAnimation(value: hovered)
                .workspaceAnimation(value: configuration.isPressed)
        }
    }
}

// Navigation, actions, and readable content use solid semantic system surfaces.
extension View {
    func workspaceListSelection(_ selected: Bool) -> some View {
        modifier(WorkspaceListRowStyle(selected: selected))
    }

    func workspaceListAppearance() -> some View {
        self.background(NativeListSelectionSuppression())
    }

    func workspacePrimaryAction() -> some View {
        self.buttonStyle(.borderedProminent)
    }

    func workspaceCard() -> some View {
        self.background(WorkspaceStyle.groupedSurface, in: RoundedRectangle(cornerRadius: 10))
    }

    func workspaceActionSurface() -> some View {
        self.background(WorkspaceStyle.chrome)
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
            WorkspaceSymbol(symbol, size: .emptyState)
                .foregroundStyle(.tint)
                .frame(width: WorkspaceControlMetrics.emptyTile, height: WorkspaceControlMetrics.emptyTile)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(WorkspaceTypography.pageTitle)
            Text(message).font(WorkspaceTypography.body).foregroundStyle(.secondary)
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
            Text(title).font(WorkspaceTypography.sectionTitle)
            Text(subtitle).font(WorkspaceTypography.body).foregroundStyle(.secondary)
        }
    }
}

// macOS 26 supplies a shared glass capsule unless the toolbar group opts out.
extension ToolbarContent {
    @ToolbarContentBuilder func workspaceToolbarAppearance() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct WorkspaceNavigationButtonStyle: ButtonStyle {
    let selected: Bool
    var cornerRadius: CGFloat = 9
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : selected || hovered ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovered = $0 }
            .workspaceAnimation(value: hovered)
            .workspaceAnimation(value: selected)
            .workspaceAnimation(value: configuration.isPressed)
    }
}

private struct WorkspaceListRowStyle: ViewModifier {
    let selected: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color(nsColor: .labelColor))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? WorkspaceStyle.selectionColor : Color.primary.opacity(hovered ? 0.04 : 0))
                    .workspaceAnimation(value: selected)
                    .workspaceAnimation(value: hovered)
            )
            .onHover { hovered = $0 }
    }
}
