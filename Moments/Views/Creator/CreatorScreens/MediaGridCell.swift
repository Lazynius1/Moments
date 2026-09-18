import Photos
import SwiftUI

struct MediaGridCell: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    let isSelected: Bool
    let isMultiSelect: Bool
    let selectionNumber: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.clear

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                } else {
                    ProgressView()
                        .tint(.white)
                }

                if isSelected && !isMultiSelect {
                    Rectangle()
                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                }

                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(asset.duration))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                                .padding(6)
                        }
                    }
                }

                if isMultiSelect {
                    VStack {
                        HStack {
                            Spacer()
                            if let number = selectionNumber {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "0095F6"))
                                        .frame(width: 22, height: 22)
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                        .frame(width: 22, height: 22)
                                    Text("\(number)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            } else {
                                Circle()
                                    .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
                                    .background(Circle().fill(Color.black.opacity(0.18)))
                                    .frame(width: 22, height: 22)
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
