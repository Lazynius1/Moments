import Photos
import SwiftUI

struct MediaGridCell: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    let isSelected: Bool
    let selectionNumber: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.3))
                        .clipped()
                        .contentShape(Rectangle())
                        .overlay(
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.clear, Color.black.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)

                    ProgressView()
                        .tint(Color(hex: "00A896"))
                }

                if isSelected {
                    Color.pink.opacity(0.3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.pink, lineWidth: 3)
                        )
                }

                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(formatDuration(asset.duration))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                VStack {
                    HStack {
                        Spacer()
                        if let number = selectionNumber {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 22, height: 22)
                                    .shadow(radius: 2)

                                Text("\(number)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(6)
                        } else {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 22, height: 22)
                                .padding(6)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
