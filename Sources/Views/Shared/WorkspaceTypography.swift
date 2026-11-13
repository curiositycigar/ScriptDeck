import SwiftUI
import AppKit

/// Point sizes are shared by English and Simplified Chinese. System fonts supply fallback glyphs.
enum WorkspaceTypography {
    static let bodySize: CGFloat = 13
    static let captionSize: CGFloat = 12

    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let scriptTitle = Font.system(size: 17, weight: .semibold)
    static let dialogTitle = Font.system(size: 17, weight: .semibold)
    static let sectionTitle = Font.system(size: bodySize, weight: .semibold)
    static let body = Font.system(size: bodySize)
    static let bodyStrong = Font.system(size: bodySize, weight: .medium)
    static let caption = Font.system(size: captionSize)
    static let captionStrong = Font.system(size: captionSize, weight: .medium)
    static let sectionLabel = Font.system(size: captionSize, weight: .semibold)
    static let code = Font.system(size: captionSize, design: .monospaced)
    static let badge = Font.system(size: 11, weight: .semibold)

    // Use the exact rendered fonts when measuring parameter labels in AppKit.
    static let parameterLabelNSFont = NSFont.systemFont(ofSize: bodySize, weight: .medium)
    static let bodyNSFont = NSFont.systemFont(ofSize: bodySize, weight: .regular)

    static func terminal(size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

/// Compact spacing shared by interactive content, actions, and its tab strip.
enum InteractivePanelMetrics {
    static let inlineSpacing: CGFloat = 4
    static let inset: CGFloat = 12
    static let blockSpacing: CGFloat = 8
    static let actionSpacing: CGFloat = 8
    static let groupSpacing: CGFloat = 16
    static let rowHeight = WorkspaceControlMetrics.compactTarget
    static let controlRadius: CGFloat = 8
}

enum WorkspaceIconSize: CGFloat {
    case disclosure = 10
    case inline = 13
    case toolbar = 14
    case navigation = 16
    case header = 20
    case emptyState = 32

    var footprint: CGFloat {
        switch self {
        case .disclosure: return 12
        case .inline, .toolbar: return 16
        case .navigation: return 20
        case .header: return 24
        case .emptyState: return 40
        }
    }
}

enum WorkspaceControlMetrics {
    static let titleActionTarget: CGFloat = 24
    static let compactTarget: CGFloat = 28
    static let iconTarget: CGFloat = 30
    static let navigationTarget: CGFloat = 36
    static let headerTile: CGFloat = 40
    static let emptyTile: CGFloat = 72
}

/// A consistent glyph size and alignment slot, independent of its button's hit area.
struct WorkspaceSymbol: View {
    let name: String
    var size: WorkspaceIconSize = .inline

    init(_ name: String, size: WorkspaceIconSize = .inline) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size.rawValue, weight: size == .emptyState ? .light : .medium))
            .frame(width: size.footprint, height: size.footprint)
    }
}

private struct WorkspaceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: WorkspaceIconSize.inline.rawValue, weight: .medium))
                .frame(width: WorkspaceIconSize.inline.footprint)
            configuration.title
        }
    }
}

extension View {
    func workspaceTypography() -> some View {
        self.font(WorkspaceTypography.body)
            .controlSize(.regular)
            .labelStyle(WorkspaceLabelStyle())
    }

    func workspaceCompactTarget() -> some View {
        self.frame(minWidth: WorkspaceControlMetrics.compactTarget,
                   minHeight: WorkspaceControlMetrics.compactTarget)
            .contentShape(Rectangle())
    }
}
