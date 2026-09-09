import SwiftUI

/// Fila de tabs que abraza el contenido y hace scroll si no cabe.
struct MomentsFillScrollTabRow<Item: Hashable, Tab: View>: View {
    let items: [Item]
    var spacing: CGFloat = 8
    var horizontalPadding: CGFloat = 16
    @ViewBuilder var tab: (Item) -> Tab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items, id: \.self) { item in
                    tab(item)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
