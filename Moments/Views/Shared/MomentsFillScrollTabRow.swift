import SwiftUI

/// Fila de tabs que rellena el ancho cuando el texto es corto (p. ej. coreano)
/// y hace scroll cuando no cabe (p. ej. español).
struct MomentsFillScrollTabRow<Item: Hashable, Tab: View>: View {
    let items: [Item]
    var spacing: CGFloat = 0
    var horizontalPadding: CGFloat = 16
    @ViewBuilder var tab: (Item) -> Tab

    @State private var containerWidth: CGFloat = UIApplication.shared.activeWindowSize.width

    private var minTabWidth: CGFloat {
        let count = CGFloat(max(items.count, 1))
        let gaps = spacing * max(count - 1, 0)
        let inner = max(containerWidth - horizontalPadding * 2 - gaps, 0)
        return inner / count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items, id: \.self) { item in
                    tab(item)
                        .frame(minWidth: minTabWidth, alignment: .center)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { applyWidth(geo.size.width) }
                    .onChange(of: geo.size.width) { _, width in applyWidth(width) }
            }
        }
    }

    private func applyWidth(_ width: CGFloat) {
        guard width > 1, abs(width - containerWidth) > 0.5 else { return }
        containerWidth = width
    }
}
