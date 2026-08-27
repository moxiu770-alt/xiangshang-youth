import SwiftUI

/// A compact wrapping layout for capability, risk and status chips. Unlike a
/// horizontal stack it keeps every label visible on compact phones and with
/// larger Dynamic Type sizes.
struct AdaptiveFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let availableWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0, cursorX + size.width > availableWidth {
                cursorX = 0
                cursorY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: cursorX, y: cursorY))
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            contentWidth = max(contentWidth, cursorX - spacing)
        }

        return (CGSize(width: min(contentWidth, availableWidth), height: cursorY + lineHeight), positions)
    }
}
