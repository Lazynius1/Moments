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
    let thumbBaseSize: CGFloat = 32
    let horizontalInset: CGFloat = 18
    let trackWidth = max(totalWidth - (horizontalInset * 2) - thumbBaseSize, 1)
    return (leading: horizontalInset + (thumbBaseSize / 2), width: trackWidth, thumbBaseSize: thumbBaseSize, trackHeight: 12)
}

func emojiSliderThumbSize(for value: Double, baseSize: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return baseSize + (clamped * 10)
}

func emojiSliderHasPrompt(_ prompt: String) -> Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        let colors = [
            UIColor.systemBlue.cgColor,
            UIColor.systemPurple.cgColor,
            UIColor.systemPink.cgColor
        ] as CFArray

        context.cgContext.saveGState()
        path.addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.58, 1]) {
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
        }
        context.cgContext.restoreGState()

        UIColor.white.withAlphaComponent(0.18).setStroke()
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
        UIColor.white.withAlphaComponent(0.20).setFill()
        trackPath.fill()

        let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: max(trackRect.width * clampedValue, trackRect.height), height: trackRect.height)
        let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: fillRect.height / 2)
        context.cgContext.saveGState()
        fillPath.addClip()
        if let fillGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.58, 1]
        ) {
            context.cgContext.drawLinearGradient(
                fillGradient,
                start: CGPoint(x: fillRect.minX, y: fillRect.midY),
                end: CGPoint(x: fillRect.maxX, y: fillRect.midY),
                options: []
            )
        }
        context.cgContext.restoreGState()

        let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
        let thumbRect = CGRect(
            x: thumbCenter.x - (thumbSize / 2),
            y: thumbCenter.y - (thumbSize / 2),
            width: thumbSize,
            height: thumbSize
        )
        let thumbPath = UIBezierPath(ovalIn: thumbRect)
        UIColor.white.setFill()
        thumbPath.fill()
        UIColor.black.withAlphaComponent(0.08).setStroke()
        thumbPath.lineWidth = 1
        thumbPath.stroke()

        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptText.isEmpty {
            (promptText as NSString).draw(
                in: CGRect(x: 20, y: 15, width: size.width - 40, height: 22),
                withAttributes: promptAttributes
            )
        }

        let emojiString = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "😍" : emoji
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20 + (clampedValue * 3)),
            .paragraphStyle: paragraphStyle
        ]
        (emojiString as NSString).draw(
            in: CGRect(x: thumbRect.minX, y: thumbRect.minY + ((thumbRect.height - 26) / 2), width: thumbRect.width, height: 26),
            withAttributes: emojiAttributes
        )
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

struct StickerEmojiSliderCardView: View {
    let prompt: String
    let emoji: String
    let value: Double

    var body: some View {
        let clampedValue = min(max(value, 0), 1)
        let showsPrompt = emojiSliderHasPrompt(prompt)

        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: emojiSliderMomentsGradientColors().map { $0.opacity(0.9) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

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
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: size.width - 36)
                        .position(x: size.width / 2, y: 25)
                    }

                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.20))
                        .frame(width: trackFrame.width, height: trackFrame.height)
                        .position(x: trackFrame.midX, y: trackFrame.midY)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: emojiSliderMomentsGradientColors(),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(trackFrame.width * clampedValue, trackFrame.height), height: trackFrame.height)
                        .position(
                            x: trackFrame.minX + (max(trackFrame.width * clampedValue, trackFrame.height) / 2),
                            y: trackFrame.midY
                        )

                    Text(emoji)
                        .font(.system(size: 19 + (clampedValue * 2.5)))
                        .frame(width: thumbSize, height: thumbSize)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                        .position(x: thumbCenter.x, y: thumbCenter.y)
                }
            }
        }
    }
}
