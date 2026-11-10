import SwiftUI

/// Animate explicit interaction state only; terminal output and timers stay immediate.
enum WorkspaceMotion {
    case feedback, layout

    func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch self {
        case .feedback: return .easeOut(duration: 0.14)
        case .layout: return .easeInOut(duration: 0.22)
        }
    }
}

private struct WorkspaceAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    let motion: WorkspaceMotion

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    func workspaceAnimation<Value: Equatable>(value: Value, motion: WorkspaceMotion = .feedback) -> some View {
        modifier(WorkspaceAnimation(value: value, motion: motion))
    }
}
