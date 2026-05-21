import SwiftUI
import UIKit

struct FilterOption: View {
    let image: UIImage
    let filter: FilterService.FilterType
    let isSelected: Bool
    let onTap: () -> Void

    @State private var previewImage: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Color.gray.opacity(0.2)
                            .frame(width: 80, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                            .frame(width: 80, height: 100)
                    }
                }
                .frame(width: 80, height: 100)
                .shadow(color: isSelected ? .pink.opacity(0.3) : .clear, radius: 8)

                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
        .onAppear {
            generatePreview()
        }
    }

    private func generatePreview() {
        let size = CGSize(width: 100, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        Task.detached(priority: .background) {
            let filtered = FilterService.shared.applyFilterToThumbnail(filter, to: thumb)
            await MainActor.run {
                withAnimation {
                    self.previewImage = filtered
                }
            }
        }
    }
}
