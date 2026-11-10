import SwiftUI

/// Adapts a label, control, and optional validation message without duplicating controls or focus.
struct ParameterRowLayout: Layout {
    let labelWidth: CGFloat
    private let columnSpacing: CGFloat = 12
    private let stackedSpacing: CGFloat = 8
    private let validationSpacing: CGFloat = 6
    private let minimumControlWidth: CGFloat = 240

    private func measurements(width: CGFloat, subviews: Subviews) -> (horizontal: Bool, label: CGSize, control: CGSize, issue: CGSize, rowHeight: CGFloat) {
        let horizontal = width >= labelWidth + columnSpacing + minimumControlWidth
        let controlWidth = horizontal ? max(0, width - labelWidth - columnSpacing) : width
        let label = subviews[0].sizeThatFits(.init(width: horizontal ? labelWidth : width, height: nil))
        let control = subviews[1].sizeThatFits(.init(width: controlWidth, height: nil))
        let issue = subviews.count > 2 ? subviews[2].sizeThatFits(.init(width: controlWidth, height: nil)) : .zero
        let rowHeight = horizontal ? max(label.height, control.height) : label.height + stackedSpacing + control.height
        return (horizontal, label, control, issue, rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count >= 2 else { return .zero }
        let width = max(0, proposal.width ?? labelWidth + columnSpacing + minimumControlWidth)
        let measured = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: measured.rowHeight + (subviews.count > 2 ? validationSpacing + measured.issue.height : 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let measured = measurements(width: bounds.width, subviews: subviews)
        let controlX = measured.horizontal ? bounds.minX + labelWidth + columnSpacing : bounds.minX
        let controlY = measured.horizontal ? bounds.minY : bounds.minY + measured.label.height + stackedSpacing
        let controlWidth = measured.horizontal ? max(0, bounds.width - labelWidth - columnSpacing) : bounds.width
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + (measured.horizontal ? max(0, (measured.control.height - measured.label.height) / 2) : 0)),
                          anchor: .topLeading, proposal: .init(width: measured.horizontal ? labelWidth : bounds.width, height: measured.label.height))
        subviews[1].place(at: CGPoint(x: controlX, y: controlY), anchor: .topLeading,
                          proposal: .init(width: controlWidth, height: measured.control.height))
        if subviews.count > 2 {
            subviews[2].place(at: CGPoint(x: controlX, y: bounds.minY + measured.rowHeight + validationSpacing), anchor: .topLeading,
                              proposal: .init(width: controlWidth, height: measured.issue.height))
        }
    }
}
