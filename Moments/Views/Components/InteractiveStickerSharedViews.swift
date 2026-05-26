import SwiftUI
import UIKit
import AVFoundation

func momentsStickerSurface(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(hex: "0B1215")
        : Color(hex: "FAF9F6")
}

func momentsStickerInk(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(hex: "FAF9F6")
        : Color(hex: "0B1215")
}

func momentsStickerInverseSurface(for colorScheme: ColorScheme) -> Color {
    momentsStickerInk(for: colorScheme)
}

func momentsStickerInverseInk(for colorScheme: ColorScheme) -> Color {
    momentsStickerSurface(for: colorScheme)
}

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
        ? CGSize(width: 260, height: 110)
        : CGSize(width: 260, height: 78)
}

func emojiSliderMomentsGradientColors() -> [Color] {
    [Color.blue, Color.purple, Color.pink]
}

func emojiSliderTrackMetrics(totalWidth: CGFloat, scale: CGFloat = 1.0) -> (leading: CGFloat, width: CGFloat, thumbBaseSize: CGFloat, trackHeight: CGFloat) {
    let thumbBaseSize: CGFloat = 48 * scale
    let horizontalInset: CGFloat = 16 * scale
    let trackWidth = max(totalWidth - (horizontalInset * 2) - thumbBaseSize, 1)
    return (leading: horizontalInset + (thumbBaseSize / 2), width: trackWidth, thumbBaseSize: thumbBaseSize, trackHeight: 12 * scale)
}

func emojiSliderThumbSize(for value: Double, baseSize: CGFloat, scale: CGFloat = 1.0) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return baseSize + (clamped * 22 * scale)
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

func emojiSliderTrackFrame(totalSize: CGSize, showsPrompt: Bool = true, scale: CGFloat = 1.0) -> CGRect {
    let metrics = emojiSliderTrackMetrics(totalWidth: totalSize.width, scale: scale)
    let centerY = totalSize.height * (showsPrompt ? 0.62 : 0.52)
    return CGRect(
        x: metrics.leading,
        y: centerY - (metrics.trackHeight / 2),
        width: metrics.width,
        height: metrics.trackHeight
    )
}

func emojiSliderThumbCenter(totalSize: CGSize, value: Double, showsPrompt: Bool = true, scale: CGFloat = 1.0) -> CGPoint {
    let clamped = min(max(value, 0), 1)
    let trackFrame = emojiSliderTrackFrame(totalSize: totalSize, showsPrompt: showsPrompt, scale: scale)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let ink = momentsStickerInk(for: colorScheme)

        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
            
            Text(title.uppercased())
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(surface)
        )
            .frame(height: 50)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerHashtagCardView: View {
    let hashtag: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let ink = momentsStickerInk(for: colorScheme)

        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(ink.opacity(0.58))
                .opacity(0.7)
            
            Text(hashtag.uppercased())
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(surface)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerTimeCardView: View {
    let timeText: String
    let dateText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let ink = momentsStickerInk(for: colorScheme)

        VStack(alignment: .center, spacing: 2) {
            Text(timeText)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)

            Text(dateText.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(ink.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(surface)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerCountdownCardView: View {
    let title: String
    let targetAtMs: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let ink = momentsStickerInk(for: colorScheme)
        let headerSurface = momentsStickerInverseSurface(for: colorScheme)
        let headerInk = momentsStickerInverseInk(for: colorScheme)

        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let countdownText = countdownClockString(targetAtMs: targetAtMs, now: timeline.date)
            let characters = countdownText.map(String.init)
            let isLong = characters.count > 8
            let digitSize: CGFloat = isLong ? 28 : 42
            let colonSize: CGFloat = isLong ? 20 : 32

            VStack(alignment: .center, spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(headerInk)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(headerSurface)

                HStack(spacing: 2) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                        if character == ":" {
                            Text(character)
                                .font(.system(size: colonSize, weight: .black, design: .rounded))
                                .foregroundStyle(ink.opacity(0.38))
                                .padding(.horizontal, 2)
                                .offset(y: -2)
                        } else {
                            Text(character)
                                .font(.system(size: digitSize, weight: .heavy, design: .rounded))
                                .foregroundStyle(ink)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(surface)
            )
        }
    }
}

struct StickerEmojiSliderCardView: View {
    let prompt: String
    let emoji: String
    let value: Double
    var averageValue: Double? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let ink = momentsStickerInk(for: colorScheme)
        let clampedValue = min(max(value, 0), 1)
        let showsPrompt = emojiSliderHasPrompt(prompt)
        let baseSize = emojiSliderRenderingSize(prompt: prompt)
        let size = baseSize
        let metrics = emojiSliderTrackMetrics(totalWidth: size.width)
        let trackFrame = emojiSliderTrackFrame(totalSize: size, showsPrompt: showsPrompt)
        let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
        let thumbSize = emojiSliderThumbSize(for: clampedValue, baseSize: metrics.thumbBaseSize)

        ZStack(alignment: .topLeading) {
            if showsPrompt {
                Text(prompt)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: size.width - 32)
                    .position(x: size.width / 2, y: 26)
            }

            Capsule(style: .continuous)
                .fill(ink.opacity(0.14))
                .frame(width: trackFrame.width, height: trackFrame.height)
                .position(x: trackFrame.midX, y: trackFrame.midY)

            Capsule(style: .continuous)
                .fill(ink.opacity(0.22))
                .frame(
                    width: max(trackFrame.width * clampedValue, trackFrame.height),
                    height: trackFrame.height
                )
                .position(
                    x: trackFrame.minX + (max(trackFrame.width * clampedValue, trackFrame.height) / 2),
                    y: trackFrame.midY
                )

            if let avg = averageValue {
                let avgClamped = min(max(avg, 0), 1)
                let avgCenter = emojiSliderThumbCenter(totalSize: size, value: avgClamped, showsPrompt: showsPrompt)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [ink.opacity(0.35), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 14
                            )
                        )
                        .frame(width: 28, height: 28)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.3, green: 0.1, blue: 0.5), Color.black.opacity(0.8)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 6
                            )
                        )
                        .frame(width: 11, height: 11)
                        .overlay(
                            Circle()
                                .stroke(surface.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.purple.opacity(0.5), radius: 4, x: 0, y: 0)
                }
                .position(x: avgCenter.x, y: avgCenter.y)
            }

            Text(emoji)
                .font(.system(size: 28 + (clampedValue * 14)))
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(1.0 + clampedValue * 0.15)
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.6), value: clampedValue)
                .allowsHitTesting(false)
                .position(x: thumbCenter.x, y: thumbCenter.y)
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(surface)
        )
    }
}

// MARK: - ✅ NEW: QUIZ STICKER VIEW
struct StickerQuizCardView: View {
    let question: String
    let options: [String]
    let selectedIndex: Int?
    let correctIndex: Int?
    let onSelect: (Int) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let surface = momentsStickerSurface(for: colorScheme)
        let headerSurface = momentsStickerInverseSurface(for: colorScheme)
        let headerInk = momentsStickerInverseInk(for: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            // — Pregunta —
            Text(question)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(headerInk)
                .multilineTextAlignment(.center) // ✅ Centrado
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity) // ✅ Asegurar que ocupe todo el ancho para el centrado
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(headerSurface)
            
            // — Opciones —
            VStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { index in
                    quizOptionRow(index: index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(surface)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(surface)
        )
    }
    
    @ViewBuilder
    private func quizOptionRow(index: Int) -> some View {
        let isSelected = selectedIndex == index
        let isCorrect = correctIndex == index
        let hasVoted = selectedIndex != nil
        
        Button(action: { onSelect(index) }) {
            HStack(spacing: 10) {
                // Letra de opción
                Text(["A", "B", "C", "D"][safe: index] ?? "\(index + 1)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(optionLetterColor(index: index, hasVoted: hasVoted, isCorrect: isCorrect, isSelected: isSelected))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(optionCircleColor(index: index, hasVoted: hasVoted, isCorrect: isCorrect, isSelected: isSelected))
                    )
                
                Text(options[index])
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(optionTextColor(index: index, hasVoted: hasVoted, isCorrect: isCorrect, isSelected: isSelected))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if hasVoted {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16, weight: .bold))
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.9))
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(optionBgColor(index: index, hasVoted: hasVoted, isCorrect: isCorrect, isSelected: isSelected))
            )
        }
        .buttonStyle(QuizOptionButtonStyle())
        .disabled(hasVoted)
    }
    
    // MARK: - Color helpers
    private func optionBgColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let ink = momentsStickerInk(for: colorScheme)
        if !hasVoted { return ink.opacity(0.08) }
        if isCorrect { return .green.opacity(0.78) }
        if isSelected { return .red.opacity(0.74) }
        return ink.opacity(0.06)
    }
    
    private func optionCircleColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let ink = momentsStickerInk(for: colorScheme)
        let surface = momentsStickerSurface(for: colorScheme)
        if !hasVoted { return ink.opacity(0.14) }
        if isCorrect { return surface.opacity(0.26) }
        if isSelected { return surface.opacity(0.24) }
        return ink.opacity(0.1)
    }
    
    private func optionLetterColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let ink = momentsStickerInk(for: colorScheme)
        let surface = momentsStickerSurface(for: colorScheme)
        if !hasVoted { return ink.opacity(0.82) }
        if isCorrect { return surface }
        if isSelected { return surface }
        return ink.opacity(0.48)
    }

    private func optionTextColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let ink = momentsStickerInk(for: colorScheme)
        let surface = momentsStickerSurface(for: colorScheme)
        if !hasVoted { return ink.opacity(0.9) }
        if isCorrect || isSelected { return surface }
        return ink.opacity(0.58)
    }
}

// Botón sin escala agresiva para las opciones del quiz
struct QuizOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}


// MARK: - ✅ NEW: POLAROID FRAME VIEW
struct StickerPolaroidFrameView: View {
    let image: UIImage?
    let progress: Double // 0.0 to 1.0 (revelado)
    let caption: String? // ✅ Nuevo: Texto opcional
    let contentScale: CGFloat
    let contentOffset: CGSize
    
    @State private var isShaking = false
    @State private var shakeTask: Task<Void, Never>? = nil

    private let imageViewportSize = CGSize(width: 180, height: 180)
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Fondo de emulsión fotosensible oscura inicial (plata/haluro)
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Brillo químico/metálico satinado inicial
                if progress < 1.0 {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)
                }

                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(
                            width: frameImageSize(for: image).width,
                            height: frameImageSize(for: image).height
                        )
                        .position(
                            x: imageViewportSize.width / 2 + clampedContentOffset(for: image).width,
                            y: imageViewportSize.height / 2 + clampedContentOffset(for: image).height
                        )
                        .opacity(progress > 0.05 ? min(1.0, (progress - 0.05) / 0.95) : 0.0)
                        .blur(radius: (1.0 - progress) * 16)
                        .brightness((progress - 1.0) * 0.42) // Comienza oscuro
                        .contrast(0.55 + (progress * 0.45)) // Comienza plano y gana contraste
                        .colorMultiply(
                            Color(
                                red: 1.0,
                                green: 0.88 + (0.12 * progress),
                                blue: 0.62 + (0.38 * progress)
                            )
                        ) // Transición química ámbar/sepia
                }
                
                // Efecto de "vaho" químico que se disuelve
                if progress < 1.0 {
                    Color.white.opacity((1.0 - progress) * 0.18)
                        .blendMode(.overlay)
                }
            }
            .frame(width: imageViewportSize.width, height: imageViewportSize.height)
            .clipped()
            .padding(10)
            .background(Color.white)
            
            // Área para escribir (estilo Polaroid)
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 200, height: 40)
                
                if let caption = caption, !caption.isEmpty {
                    let visibleCount = Int(Double(caption.count) * progress)
                    (
                        Text(caption.prefix(visibleCount))
                            .font(.custom("Caveat-Medium", size: 21))
                            .foregroundColor(.black.opacity(0.85))
                        +
                        Text(caption.dropFirst(visibleCount))
                            .font(.custom("Caveat-Medium", size: 21))
                            .foregroundColor(.clear)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 12)
                    .rotationEffect(.degrees(-1)) // Pequeño ángulo para naturalidad
                    .offset(y: -2)
                }
            }
        }
        .background(Color.white)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .rotationEffect(.degrees(-2)) // Un toque "tirado"
        .overlay {
            // El lienzo mágico cubre TODA la Polaroid y se extiende fuera de ella de forma circular/difuminada
            if progress < 1.0 {
                Canvas { context, size in
                    var rng = StickerSeededRandom(seed: 77)
                    let area = max(size.width * size.height, 1)
                    let particleCount = min(max(Int(area / 110), 90), 320)
                    
                    let timeFactor = progress * 30.0
                    
                    let centerX = size.width / 2.0
                    let centerY = size.height / 2.0
                    // Radio máximo para calcular la atenuación radial
                    let maxDist = sqrt(centerX * centerX + centerY * centerY)
                    
                    for _ in 0..<particleCount {
                        let baseX = CGFloat(rng.next()) * size.width
                        let baseY = CGFloat(rng.next()) * size.height
                        
                        let speedX = rng.next() * 3.5 + 1.5
                        let speedY = rng.next() * 4.0 + 2.0
                        let driftPhase = rng.next() * .pi * 2
                        
                        // Deriva mágica que fluye cruzando el marco
                        let offsetX = sin(timeFactor * 0.25 * speedX + driftPhase) * 22.0
                        let offsetY = cos(timeFactor * 0.18 * speedY + driftPhase) * 26.0
                        
                        let x = baseX + offsetX
                        let y = baseY + offsetY
                        
                        let dotSize = CGFloat(rng.next() * 2.5 + 1.0)
                        
                        // Hermoso decaimiento radial (Vignette) para evitar recortes cuadrados abruptos en los bordes
                        let dx = x - centerX
                        let dy = y - centerY
                        let dist = sqrt(dx * dx + dy * dy)
                        let edgeFade = max(0.0, min(1.0, 1.0 - pow(dist / maxDist, 2.5)))
                        
                        // Si no se está agitando, las motas se desvanecen completamente
                        let shakeOpacityFactor = isShaking ? 1.0 : 0.0
                        let opacity = (0.28 + rng.next() * 0.42) * (1.0 - progress) * shakeOpacityFactor * edgeFade
                        
                        let rect = CGRect(
                            x: x,
                            y: y,
                            width: dotSize,
                            height: dotSize
                        )
                        
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                    }
                }
                .blendMode(.screen)
                .allowsHitTesting(false)
                .padding(-36) // Amplio espacio para que el desvanecimiento ocurra 100% de forma natural
            }
        }
        .onChange(of: progress) { _, _ in
            // Al detectar cambio de progreso por sacudida, hacemos aparecer las motas
            withAnimation(.easeOut(duration: 0.25)) {
                isShaking = true
            }
            // Temporizador para desvanecerlas suavemente tras 0.4s sin movimiento
            shakeTask?.cancel()
            shakeTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) {
                    isShaking = false
                }
            }
        }
        .onDisappear {
            shakeTask?.cancel()
        }
    }

    private func frameImageSize(for image: UIImage) -> CGSize {
        let safeScale = max(contentScale, 1.0)
        let imageSize = image.size
        let imageRatio = imageSize.width / max(imageSize.height, 0.0001)
        let viewportRatio = imageViewportSize.width / max(imageViewportSize.height, 0.0001)

        let baseSize: CGSize
        if imageRatio > viewportRatio {
            let height = imageViewportSize.height
            baseSize = CGSize(width: height * imageRatio, height: height)
        } else {
            let width = imageViewportSize.width
            baseSize = CGSize(width: width, height: width / max(imageRatio, 0.0001))
        }

        return CGSize(width: baseSize.width * safeScale, height: baseSize.height * safeScale)
    }

    private func clampedContentOffset(for image: UIImage) -> CGSize {
        let drawSize = frameImageSize(for: image)
        let maxOffsetX = max(0, (drawSize.width - imageViewportSize.width) / 2)
        let maxOffsetY = max(0, (drawSize.height - imageViewportSize.height) / 2)

        return CGSize(
            width: min(max(contentOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(contentOffset.height, -maxOffsetY), maxOffsetY)
        )
    }
}

// Helper para aleatorios consistentes en Canvas del sticker
private struct StickerSeededRandom {
    var state: UInt64
    init(seed: Int) { state = UInt64(abs(seed)) }
    mutating func next() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double(z ^ (z >> 31)) / Double(UInt64.max)
    }
}



// MARK: - ✅ NEW: DITHER PATTERN (Reveal Surface)
struct StickerDitherPattern: View {
    let color: Color
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1/30)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            
            Canvas { context, size in
                let dotSize: CGFloat = 2.5
                let spacing: CGFloat = 6.0
                
                for y in stride(from: 0, to: size.height, by: spacing) {
                    for x in stride(from: 0, to: size.width, by: spacing) {
                        // Movimiento ondulado basado en el tiempo
                        let waveX = sin(time * 2 + y * 0.05) * 2
                        let waveY = cos(time * 2 + x * 0.05) * 2
                        
                        let offset = (Int(y / spacing) % 2 == 0) ? spacing / 2 : 0
                        let rect = CGRect(
                            x: x + offset + waveX,
                            y: y + waveY,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
        .opacity(0.85)
    }
}

// MARK: - ✅ NEW: AUDIO STICKER VIEW
struct InteractiveAudioStickerView: View {
    let audioURL: String
    let duration: Double

    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var animatedHeights: [CGFloat] = [10, 14, 10]
    @State private var previousAudioCategory: AVAudioSession.Category?
    @State private var previousAudioMode: AVAudioSession.Mode?
    @State private var previousAudioOptions: AVAudioSession.CategoryOptions = []
    @State private var didConfigureAudioSession = false

    var body: some View {
        ZStack {
            // Background with Liquid Glass effect
            Circle()
                .fill(Color.clear)
                .liquidGlass(in: Circle())

            // Progress Ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                // Mic/Pause Icon
                Image(systemName: isPlaying ? "pause.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))

                // 3 Wave Bars
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.white)
                            .frame(width: 3, height: isPlaying ? animatedHeights[i] : 10)
                    }
                }
            }
        }
        .frame(width: 72, height: 72)
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    togglePlayback()
                }
        )
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            if newValue {
                startWaveAnimation()
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    private func startPlayback() {
        guard let url = URL(string: audioURL) else { return }

        let session = AVAudioSession.sharedInstance()

        if !didConfigureAudioSession {
            previousAudioCategory = session.category
            previousAudioMode = session.mode
            previousAudioOptions = session.categoryOptions
            didConfigureAudioSession = true
        }

        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)

        Task {
            do {
                let player: AVAudioPlayer
                if url.scheme == "file" {
                    player = try AVAudioPlayer(contentsOf: url)
                } else {
                    let cachedURL = try await PersistentAudioCache.shared.localURL(for: url)
                    player = try AVAudioPlayer(contentsOf: cachedURL)
                }

                await MainActor.run {
                    self.audioPlayer = player
                    self.audioPlayer?.play()
                    self.isPlaying = true
                    self.startProgressTimer()
                }
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        withAnimation {
            progress = 0
        }
        timer?.invalidate()
        timer = nil
        restoreAudioSessionIfNeeded()
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func resumePlayback() {
        if let audioPlayer {
            audioPlayer.play()
            isPlaying = true
            startProgressTimer()
        } else {
            startPlayback()
        }
    }

    private func finishPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        withAnimation {
            progress = 0
        }
        timer?.invalidate()
        timer = nil
        restoreAudioSessionIfNeeded()
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let player = self.audioPlayer {
                withAnimation(.linear(duration: 0.05)) {
                    self.progress = player.currentTime / player.duration
                }
                if !player.isPlaying {
                    finishPlayback()
                }
            }
        }
    }

    private func startWaveAnimation() {
        guard isPlaying else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            animatedHeights = [
                CGFloat.random(in: 6...16),
                CGFloat.random(in: 10...20),
                CGFloat.random(in: 6...16)
            ]
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if self.isPlaying {
                self.startWaveAnimation()
            } else {
                withAnimation {
                    self.animatedHeights = [10, 14, 10]
                }
            }
        }
    }

    private func restoreAudioSessionIfNeeded() {
        guard didConfigureAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        if let previousAudioCategory, let previousAudioMode {
            try? session.setCategory(previousAudioCategory, mode: previousAudioMode, options: previousAudioOptions)
        }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        didConfigureAudioSession = false
    }
}
