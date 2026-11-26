import SwiftUI

struct WideWidgetKey: LayoutValueKey { static let defaultValue = false }

/// Place each next card at the next available top edge. Wide cards start a new row.
struct DashboardLayout: Layout {
    var columns: Int
    var spacing: CGFloat = 18
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 700
        let frames = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let count = max(1, columns), columnWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var bottoms = Array(repeating: CGFloat(0), count: count), frames: [CGRect] = []
        for view in subviews {
            if count == 1 || view[WideWidgetKey.self] {
                let y = bottoms.max() ?? 0
                let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
                frames.append(CGRect(x: 0, y: y, width: width, height: size.height))
                bottoms = Array(repeating: y + size.height + spacing, count: count)
            } else {
                let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
                let size = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: bottoms[column], width: columnWidth, height: size.height))
                bottoms[column] += size.height + spacing
            }
        }
        return frames
    }
}
