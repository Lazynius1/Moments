import SwiftUI

struct StickerPillFlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 14

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = makeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + max(0, CGFloat(rows.count - 1) * rowSpacing)

        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for (index, row) in rows.enumerated() {
            let rowWidth = row.items.reduce(CGFloat.zero) { result, item in
                result + item.size.width
            } + max(0, CGFloat(row.items.count - 1) * spacing)

            let centeredX = bounds.minX + max(0, (bounds.width - rowWidth) / 2)
            let rowShift: CGFloat
            switch index % 4 {
            case 0:
                rowShift = 0
            case 1:
                rowShift = 8
            case 2:
                rowShift = -6
            default:
                rowShift = 4
            }
            let currentRowY = currentY + (index.isMultiple(of: 2) ? 0 : 2)
            var currentX = min(
                max(bounds.minX, centeredX + rowShift),
                bounds.maxX - rowWidth
            )

            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: currentX, y: currentRowY + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                currentX += item.size.width + spacing
            }

            currentY += row.height + rowSpacing
        }
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard maxWidth > 0 else { return [] }

        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if proposedWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [FlowItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(subview: subview, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }
}

struct StickerEmojiSliderPillGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let normalized = (sin(t * 1.8) + 1) / 2
            let progress = 0.10 + (normalized * 0.80)

            GeometryReader { geometry in
                let size = geometry.size
                let trackHeight: CGFloat = 5
                let emojiSize: CGFloat = 19 + CGFloat(progress * 8)
                let horizontalInset: CGFloat = 3
                let trackWidth = max(size.width - emojiSize - (horizontalInset * 2), 12)
                let trackX = horizontalInset + (emojiSize / 2)
                let trackY = (size.height - trackHeight) / 2
                let emojiX = trackX + (trackWidth * progress) - (emojiSize / 2)
                let emojiY = (size.height - emojiSize) / 2

                ZStack(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.10))
                        .frame(width: trackWidth, height: trackHeight)
                        .offset(x: trackX, y: trackY)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: emojiSliderMomentsGradientColors(),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(trackWidth * progress, trackHeight), height: trackHeight)
                        .offset(x: trackX, y: trackY)

                    Text("😍")
                        .font(.system(size: 15 + CGFloat(progress * 5)))
                        .frame(width: emojiSize, height: emojiSize)
                        .shadow(color: Color.black.opacity(0.14), radius: 3, y: 1)
                        .offset(x: emojiX, y: emojiY)
                }
            }
        }
    }
}

