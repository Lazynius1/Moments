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

func emojiSliderRenderingSize(prompt: String = "") -> CGSize {
    emojiSliderHasPrompt(prompt)
        ? CGSize(width: 248, height: 108)
        : CGSize(width: 216, height: 78)
}

func emojiSliderMomentsGradientColors() -> [Color] {
    [Color.blue, Color.purple, Color.pink]
}

func emojiSliderTrackMetrics(totalWidth: CGFloat) -> (leading: CGFloat, width: CGFloat, thumbBaseSize: CGFloat, trackHeight: CGFloat) {
    let thumbBaseSize: CGFloat = 46
    let horizontalInset: CGFloat = 18
    let trackWidth = max(totalWidth - (horizontalInset * 2) - thumbBaseSize, 1)
    return (leading: horizontalInset + (thumbBaseSize / 2), width: trackWidth, thumbBaseSize: thumbBaseSize, trackHeight: 4)
}

func emojiSliderThumbSize(for value: Double, baseSize: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return baseSize + (clamped * 18)
}

func emojiSliderHasPrompt(_ prompt: String) -> Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct NeutralStickerCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 5)
            )
    }
}

struct NeutralStickerAccentPill: View {
    let symbolName: String
    let title: String
    let fill: Color
    var foreground: Color = .white
    var usesUppercase = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(usesUppercase ? title.uppercased() : title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(usesUppercase ? 0.2 : 0)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
    }
}

func emojiSliderTrackFrame(totalSize: CGSize, showsPrompt: Bool = true) -> CGRect {
    let metrics = emojiSliderTrackMetrics(totalWidth: totalSize.width)
    let centerY = totalSize.height * (showsPrompt ? 0.56 : 0.50)
    return CGRect(
        x: metrics.leading,
        y: centerY - (metrics.trackHeight / 2),
        width: metrics.width,
        height: metrics.trackHeight
    )
}

func emojiSliderThumbCenter(totalSize: CGSize, value: Double, showsPrompt: Bool = true) -> CGPoint {
    let clamped = min(max(value, 0), 1)
    let trackFrame = emojiSliderTrackFrame(totalSize: totalSize, showsPrompt: showsPrompt)
    return CGPoint(x: trackFrame.minX + (trackFrame.width * clamped), y: trackFrame.midY)
}

func createEmojiSliderFallbackImage(prompt: String, emoji: String, value: Double = 0.5) -> UIImage {
    let size = emojiSliderRenderingSize(prompt: prompt)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 24)

        context.cgContext.saveGState()
        context.cgContext.setShadow(offset: CGSize(width: 0, height: 8), blur: 20, color: UIColor.black.withAlphaComponent(0.12).cgColor)
        UIColor.white.withAlphaComponent(0.96).setFill()
        path.fill()
        context.cgContext.restoreGState()

        UIColor.black.withAlphaComponent(0.06).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let promptAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let clampedValue = min(max(value, 0), 1)
        let metrics = emojiSliderTrackMetrics(totalWidth: size.width)
        let showsPrompt = emojiSliderHasPrompt(prompt)
        let trackRect = emojiSliderTrackFrame(totalSize: size, showsPrompt: showsPrompt)
        let thumbSize = emojiSliderThumbSize(for: clampedValue, baseSize: metrics.thumbBaseSize)

        let trackPath = UIBezierPath(roundedRect: trackRect, cornerRadius: trackRect.height / 2)
        UIColor(white: 0.93, alpha: 1).setFill()
        trackPath.fill()

        let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: max(trackRect.width * clampedValue, trackRect.height), height: trackRect.height)
        let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: fillRect.height / 2)
        UIColor(red: 0.98, green: 0.73, blue: 0.18, alpha: 1).setFill()
        fillPath.fill()

        let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
        let thumbRect = CGRect(
            x: thumbCenter.x - (thumbSize / 2),
            y: thumbCenter.y - (thumbSize / 2),
            width: thumbSize,
            height: thumbSize
        )

        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptText.isEmpty {
            (promptText as NSString).draw(
                in: CGRect(x: 20, y: 15, width: size.width - 40, height: 22),
                withAttributes: promptAttributes.merging([.foregroundColor: UIColor.black.withAlphaComponent(0.92)]) { _, new in new }
            )
        }

        let emojiString = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "😍" : emoji
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28 + (clampedValue * 8)),
            .paragraphStyle: paragraphStyle
        ]
        
        context.cgContext.saveGState()
        context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.16).cgColor)
        (emojiString as NSString).draw(
            in: CGRect(x: thumbRect.minX, y: thumbRect.minY + ((thumbRect.height - 34) / 2), width: thumbRect.width, height: 34),
            withAttributes: emojiAttributes
        )
        context.cgContext.restoreGState()
    }
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
        NeutralStickerCard(cornerRadius: 24) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.72, blue: 0.98))
                        .frame(width: 30, height: 30)

                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct StickerHashtagCardView: View {
    let hashtag: String

    var body: some View {
        NeutralStickerCard(cornerRadius: 22) {
            HStack(spacing: 0) {
                Text("#\(hashtag)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct StickerTimeCardView: View {
    let timeText: String
    let dateText: String

    var body: some View {
        NeutralStickerCard(cornerRadius: 22) {
            VStack(alignment: .center, spacing: 2) {
                Text(timeText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                    .lineLimit(1)

                Text(dateText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.39, green: 0.41, blue: 0.47))
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct StickerCountdownCardView: View {
    let title: String
    let targetAtMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let countdownText = countdownClockString(targetAtMs: targetAtMs, now: timeline.date)
            let characters = countdownText.map(String.init)

            NeutralStickerCard(cornerRadius: 22) {
                VStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                            if character == ":" {
                                Text(character)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.43, green: 0.16, blue: 0.44))
                                    .padding(.horizontal, 1)
                            } else {
                                Text(character)
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                                    .frame(width: 26, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(red: 0.95, green: 0.95, blue: 0.96))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }
}

struct StickerEmojiSliderCardView: View {
    let prompt: String
    let emoji: String
    let value: Double
    var averageValue: Double? = nil

    var body: some View {
        let clampedValue = min(max(value, 0), 1)
        let showsPrompt = emojiSliderHasPrompt(prompt)

        NeutralStickerCard(cornerRadius: 24) {
            GeometryReader { geometry in
                let size = geometry.size
                let metrics = emojiSliderTrackMetrics(totalWidth: size.width)
                let trackFrame = emojiSliderTrackFrame(totalSize: size, showsPrompt: showsPrompt)
                let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
                let thumbSize = emojiSliderThumbSize(for: clampedValue, baseSize: metrics.thumbBaseSize)

                ZStack(alignment: .topLeading) {
                    if showsPrompt {
                        Text(prompt)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: size.width - 36)
                            .position(x: size.width / 2, y: 25)
                    }

                    Capsule(style: .continuous)
                        .fill(Color(red: 0.93, green: 0.93, blue: 0.94))
                        .frame(width: trackFrame.width, height: trackFrame.height)
                        .position(x: trackFrame.midX, y: trackFrame.midY)

                    Capsule(style: .continuous)
                        .fill(Color(red: 0.98, green: 0.73, blue: 0.18))
                        .frame(width: max(trackFrame.width * clampedValue, trackFrame.height), height: trackFrame.height)
                        .position(
                            x: trackFrame.minX + (max(trackFrame.width * clampedValue, trackFrame.height) / 2),
                            y: trackFrame.midY
                        )

                    if let avg = averageValue {
                        let avgClamped = min(max(avg, 0), 1)
                        let avgCenter = emojiSliderThumbCenter(totalSize: size, value: avgClamped, showsPrompt: showsPrompt)
                        Circle()
                            .stroke(Color.black.opacity(0.15), lineWidth: 2)
                            .background(Circle().fill(Color.white))
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                            .position(x: avgCenter.x, y: avgCenter.y)
                    }

                    Text(emoji)
                        .font(.system(size: 30 + (clampedValue * 8)))
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
                        .position(x: thumbCenter.x, y: thumbCenter.y)
                }
            }
        }
    }
}
