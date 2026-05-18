import SwiftUI
import UIKit

struct FilterSelectorView: View {
    @Binding var selectedFilter: FilterService.FilterType
    let filters: [FilterService.FilterType]
    let baseImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filters, id: \.self) { filterType in
                        FilterItemView(
                            type: filterType,
                            isSelected: selectedFilter == filterType,
                            baseImage: baseImage
                        ) {
                            withAnimation(.spring()) {
                                selectedFilter = filterType
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Text(selectedFilter.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlass(in: Capsule())
        }
        .padding(.bottom, 8)
    }
}

struct FilterItemView: View {
    let type: FilterService.FilterType
    let isSelected: Bool
    let baseImage: UIImage?
    let action: () -> Void

    @State private var previewImage: UIImage? = nil

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    }
                }
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: isSelected ? 4 : 0)

                Text(type.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            }
        }
        .onAppear {
            generatePreview()
        }
    }

    private func generatePreview() {
        guard let base = baseImage else { return }

        // Generate a tiny thumbnail for the carousel to avoid filtering full-size media.
        let size = CGSize(width: 60, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }

        Task.detached(priority: .background) {
            let filtered = FilterService.shared.applyFilterToThumbnail(type, to: thumb)
            await MainActor.run {
                self.previewImage = filtered
            }
        }
    }
}
