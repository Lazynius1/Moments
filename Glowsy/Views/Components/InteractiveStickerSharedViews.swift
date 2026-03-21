import SwiftUI
import UIKit

func normalizedStickerURL(from raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let directURL = URL(string: trimmed),
       let scheme = directURL.scheme?.lowercased(),
       scheme == "https" || scheme == "http" {
        return directURL
    }

    return URL(string: "https://\(trimmed)")
}

func stickerHostLabel(from raw: String) -> String {
    guard let url = normalizedStickerURL(from: raw) else {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let host = url.host ?? raw
    return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
}

func linkStickerRenderingSize(for title: String) -> CGSize {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let measuredTitle = trimmedTitle.isEmpty ? "Link" : trimmedTitle
    let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    let textWidth = ceil((measuredTitle as NSString).size(withAttributes: [.font: font]).width)
    let horizontalChrome: CGFloat = 18 + 18 + 12 + 18
    let width = min(max(textWidth + horizontalChrome, 118), 280)
    return CGSize(width: width, height: 50)
}

func countdownClockString(targetAtMs: Double, now: Date) -> String {
    let targetDate = Date(timeIntervalSince1970: targetAtMs / 1000)
    let totalSeconds = max(Int(targetDate.timeIntervalSince(now)), 0)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

private struct StickerCountdownDigitBox: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 26, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

struct StickerLinkCardView: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 0.29, green: 0.72, blue: 0.98))

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

struct StickerCountdownCardView: View {
    let title: String
    let targetAtMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let countdownText = countdownClockString(targetAtMs: targetAtMs, now: timeline.date)
            let characters = countdownText.map(String.init)

            VStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                        if character == ":" {
                            Text(character)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 1)
                        } else {
                            StickerCountdownDigitBox(value: character)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.24, blue: 0.92).opacity(0.86),
                                Color(red: 0.86, green: 0.28, blue: 0.73).opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }
}
