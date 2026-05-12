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
        ? CGSize(width: 260, height: 110)
        : CGSize(width: 260, height: 78)
}

func emojiSliderMomentsGradientColors() -> [Color] {
    [Color.blue, Color.purple, Color.pink]
}

func emojiSliderTrackMetrics(totalWidth: CGFloat) -> (leading: CGFloat, width: CGFloat, thumbBaseSize: CGFloat, trackHeight: CGFloat) {
    let thumbBaseSize: CGFloat = 48
    let horizontalInset: CGFloat = 16
    let trackWidth = max(totalWidth - (horizontalInset * 2) - thumbBaseSize, 1)
    return (leading: horizontalInset + (thumbBaseSize / 2), width: trackWidth, thumbBaseSize: thumbBaseSize, trackHeight: 12)
}

func emojiSliderThumbSize(for value: Double, baseSize: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return baseSize + (clamped * 22)
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
    let centerY = totalSize.height * (showsPrompt ? 0.62 : 0.52)
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
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
            
            Text(title.uppercased())
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Color.clear.liquidGlass(in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .frame(height: 50)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerHashtagCardView: View {
    let hashtag: String

    var body: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .opacity(0.7)
            
            Text(hashtag.uppercased())
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color.clear.liquidGlass(in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerTimeCardView: View {
    let timeText: String
    let dateText: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(timeText)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                .lineLimit(1)

            Text(dateText.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color.clear.liquidGlass(in: Capsule(style: .continuous))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerCountdownCardView: View {
    let title: String
    let targetAtMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let countdownText = countdownClockString(targetAtMs: targetAtMs, now: timeline.date)
            let characters = countdownText.map(String.init)
            let isLong = characters.count > 8
            let digitSize: CGFloat = isLong ? 28 : 42
            let colonSize: CGFloat = isLong ? 20 : 32

            VStack(alignment: .center, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                HStack(spacing: 2) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                        if character == ":" {
                            Text(character)
                                .font(.system(size: colonSize, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 2)
                                .offset(y: -2)
                        } else {
                            Text(character)
                                .font(.system(size: digitSize, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
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

        GeometryReader { geometry in
            let size = geometry.size
            let metrics = emojiSliderTrackMetrics(totalWidth: size.width)
            let trackFrame = emojiSliderTrackFrame(totalSize: size, showsPrompt: showsPrompt)
            let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
            let thumbSize = emojiSliderThumbSize(for: clampedValue, baseSize: metrics.thumbBaseSize)

            ZStack(alignment: .topLeading) {
                // Prompt text
                if showsPrompt {
                    Text(prompt)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                        .frame(width: size.width - 32)
                        .position(x: size.width / 2, y: 26)
                }

                // Track background — thick pill
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: trackFrame.width, height: trackFrame.height)
                    .position(x: trackFrame.midX, y: trackFrame.midY)

                // Progress fill
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
                    .frame(
                        width: max(trackFrame.width * clampedValue, trackFrame.height),
                        height: trackFrame.height
                    )
                    .position(
                        x: trackFrame.minX + (max(trackFrame.width * clampedValue, trackFrame.height) / 2),
                        y: trackFrame.midY
                    )

                // Average marker — dark glow dot, contrasts against white track
                if let avg = averageValue {
                    let avgClamped = min(max(avg, 0), 1)
                    let avgCenter = emojiSliderThumbCenter(totalSize: size, value: avgClamped, showsPrompt: showsPrompt)
                    ZStack {
                        // Outer halo
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.black.opacity(0.35), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 14
                                )
                            )
                            .frame(width: 28, height: 28)
                        // Inner core — dark with subtle purple tint
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
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: Color.purple.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                    .position(x: avgCenter.x, y: avgCenter.y)
                }

                // Emoji thumb — allowsHitTesting false so gesture overlay captures all touches
                Text(emoji)
                    .font(.system(size: 28 + (clampedValue * 14)))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
                    .scaleEffect(1.0 + clampedValue * 0.15)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.6), value: clampedValue)
                    .allowsHitTesting(false)
                    .position(x: thumbCenter.x, y: thumbCenter.y)
            }
        }
        .background(
            Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        VStack(alignment: .leading, spacing: 0) {
            // — Pregunta —
            Text(question)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center) // ✅ Centrado
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity) // ✅ Asegurar que ocupe todo el ancho para el centrado
                .padding(.horizontal, 16)
                .padding(.top, 20) // ✅ Padding superior para compensar la falta de cabecera
                .padding(.bottom, 12)
            
            // — Separador —
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 12)
            
            // — Opciones —
            VStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { index in
                    quizOptionRow(index: index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
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
                    .foregroundStyle(.white)
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
        if !hasVoted { return .white.opacity(0.12) }
        if isCorrect { return .green.opacity(0.45) }       // Verde sólido — correcta siempre verde
        if isSelected { return .red.opacity(0.40) }        // Rojo — elegida incorrecta
        return .white.opacity(0.06)
    }
    
    private func optionCircleColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        if !hasVoted { return .white.opacity(0.2) }
        if isCorrect { return .green.opacity(0.7) }
        if isSelected { return .red.opacity(0.6) }
        return .white.opacity(0.1)
    }
    
    private func optionLetterColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        if !hasVoted { return .white }
        if isCorrect { return .white }
        if isSelected { return .white }
        return .white.opacity(0.4)
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
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.black)
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(progress)
                        .blur(radius: (1.0 - progress) * 20)
                }
                
                // Efecto de "vaho" o revelado químico
                if progress < 1.0 {
                    Color.white.opacity((1.0 - progress) * 0.2)
                        .blendMode(.overlay)
                }
            }
            .frame(width: 180, height: 180)
            .clipped()
            .padding(10)
            .background(Color.white)
            
            // Área para escribir (estilo Polaroid)
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 200, height: 40)
                
                if let caption = caption, !caption.isEmpty {
                    Text(caption)
                        .font(.custom("MarkerFelt-Wide", size: 15)) // Fuente tipo rotulador
                        .foregroundColor(.black.opacity(0.85))
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
