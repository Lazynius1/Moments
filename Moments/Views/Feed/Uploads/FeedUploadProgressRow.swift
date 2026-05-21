import SwiftUI
import UIKit

struct UploadProgressRow: View {
    @ObservedObject var uploadingMoment: UploadingMoment
    @EnvironmentObject var uploadService: BackgroundMomentUploadService
    @Environment(\.colorScheme) var colorScheme
    @State private var rotationAngle: Double = 0
    @State private var checkScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = uploadingMoment.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(uploadingMoment.content.isEmpty ? NSLocalizedString("feed.uploading.newMoment", comment: "New moment text") : uploadingMoment.content)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    uploadStatusView
                }

                if uploadingMoment.status == .uploading || uploadingMoment.status == .processing {
                    progressBarView
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(statusBorderColor, lineWidth: 0.5)
                    )

                if uploadingMoment.status == .completed || uploadingMoment.status == .moderated {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .scaleEffect(checkScale == 1.0 ? 1.0 : 1.1)
                        .opacity(checkScale == 1.0 ? 0 : 1)
                }
            }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    private var uploadStatusView: some View {
        HStack(spacing: 6) {
            switch uploadingMoment.status {
            case .uploading:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.blue)

                Text(String(format: NSLocalizedString("feed.uploading.progress", comment: "Upload progress"), Int(uploadingMoment.uploadProgress * 100)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)

            case .processing:
                Image(systemName: "gearshape.2")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }

                Text("feed.uploading.processing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)

            case .completed, .moderated:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .scaleEffect(checkScale)
                    .onAppear {
                        hapticNotification(.success)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            checkScale = 1.4
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                checkScale = 1.0
                            }
                        }
                    }

                Text("feed.uploading.published")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)

            case .failed:
                Button(action: {
                    uploadService.retryUpload(uploadingMoment)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .symbolEffect(.pulse, value: uploadingMoment.status)

                        Text("feed.uploading.retry")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red)
                }

                Button(action: {
                    uploadService.cancelUpload(uploadingMoment)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
    }

    private var progressBarView: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill((colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215")).opacity(0.1))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * uploadingMoment.uploadProgress, height: 3)
                        .shadow(color: (uploadingMoment.status == .uploading ? Color(hex: "007AFF") : Color.orange).opacity(0.5), radius: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: uploadingMoment.uploadProgress)
                }
            }
            .frame(height: 3)

            HStack {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                if uploadingMoment.mediaCount > 1 {
                    Text(String(format: NSLocalizedString("feed.uploading.files", comment: "Files count"), uploadingMoment.mediaCount))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusBorderColor: Color {
        switch uploadingMoment.status {
        case .uploading, .processing:
            return Color.white.opacity(0.15)
        case .completed, .moderated:
            return Color.green.opacity(0.3)
        case .failed:
            return Color.red.opacity(0.3)
        }
    }

    private func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private var progressColor: LinearGradient {
        switch uploadingMoment.status {
        case .uploading:
            return LinearGradient(
                colors: [Color(hex: "007AFF"), Color(hex: "00D2B4")],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .processing:
            return LinearGradient(
                colors: [.orange, .yellow],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [.green],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var statusText: String {
        switch uploadingMoment.status {
        case .uploading:
            return NSLocalizedString("feed.uploading.uploading", comment: "Uploading files status")
        case .processing:
            return NSLocalizedString("feed.uploading.creating", comment: "Creating moment status")
        case .completed, .moderated:
            return NSLocalizedString("feed.uploading.available", comment: "Moment available status")
        case .failed:
            return uploadingMoment.errorMessage ?? NSLocalizedString("feed.uploading.error", comment: "Upload error status")
        }
    }
}
