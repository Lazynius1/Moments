import SwiftUI
import UIKit
import AVFoundation

enum StoryPolaroidFrameStyle: String, CaseIterable {
    case classic
    case clean
    case vintage
    case album

    init(rawValueOrDefault rawValue: String?) {
        self = StoryPolaroidFrameStyle(rawValue: rawValue ?? "") ?? .classic
    }
}

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

func normalizedTapCycleStickerVariant(_ styleVariant: Int, count: Int = 4) -> Int {
    ((styleVariant % count) + count) % count
}

func momentsStickerRainbowGradient() -> LinearGradient {
    LinearGradient(
        colors: [
            Color(hex: "FF5F6D"),
            Color(hex: "FF8C42"),
            Color(hex: "FFD166"),
            Color(hex: "6BCB77"),
            Color(hex: "4D96FF"),
            Color(hex: "9D4EDD")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

func momentsTapCycleStickerBackground(for colorScheme: ColorScheme, styleVariant: Int) -> Color {
    let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)
    let surface = momentsStickerSurface(for: colorScheme)
    let ink = momentsStickerInk(for: colorScheme)

    switch normalizedVariant {
    case 1:
        return ink
    case 2:
        return colorScheme == .dark ? surface.opacity(0.78) : surface.opacity(0.96)
    case 3:
        return colorScheme == .dark ? surface.opacity(0.98) : .white
    default:
        return surface
    }
}

func momentsTapCycleStickerForegroundStyle(for colorScheme: ColorScheme, styleVariant: Int) -> AnyShapeStyle {
    let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)
    let surface = momentsStickerSurface(for: colorScheme)
    let ink = momentsStickerInk(for: colorScheme)

    switch normalizedVariant {
    case 1:
        return AnyShapeStyle(surface)
    case 3:
        return AnyShapeStyle(momentsStickerRainbowGradient())
    default:
        return AnyShapeStyle(ink)
    }
}

func momentsTapCycleStickerStroke(for colorScheme: ColorScheme, styleVariant: Int) -> Color {
    let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)
    let ink = momentsStickerInk(for: colorScheme)

    switch normalizedVariant {
    case 2:
        return ink.opacity(colorScheme == .dark ? 0.34 : 0.22)
    case 3:
        return Color(hex: "FF5F6D").opacity(colorScheme == .dark ? 0.24 : 0.18)
    default:
        return .clear
    }
}

func momentsTapCycleStickerStrokeWidth(styleVariant: Int) -> CGFloat {
    let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)
    return (normalizedVariant == 2 || normalizedVariant == 3) ? 1.25 : 0
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
    let measuredTitle = trimmedTitle.isEmpty
        ? NSLocalizedString("storyEditor.link.fallbackTitle", comment: "Fallback title for link sticker")
        : trimmedTitle
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
    var styleVariant: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
            
            Text(title.uppercased())
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(momentsTapCycleStickerForegroundStyle(for: colorScheme, styleVariant: styleVariant))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(momentsTapCycleStickerBackground(for: colorScheme, styleVariant: styleVariant))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    momentsTapCycleStickerStroke(for: colorScheme, styleVariant: styleVariant),
                    lineWidth: momentsTapCycleStickerStrokeWidth(styleVariant: styleVariant)
                )
        )
        .frame(height: 50)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct StickerHashtagCardView: View {
    @Binding var hashtag: String
    var styleVariant: Int = 0
    var isEditingInline: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    init(hashtag: Binding<String>, styleVariant: Int = 0, isEditingInline: Bool = false) {
        self._hashtag = hashtag
        self.styleVariant = styleVariant
        self.isEditingInline = isEditingInline
    }

    init(hashtag: String, styleVariant: Int = 0) {
        self._hashtag = .constant(hashtag)
        self.styleVariant = styleVariant
        self.isEditingInline = false
    }

    var body: some View {
        let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)
        let foregroundStyle = momentsTapCycleStickerForegroundStyle(for: colorScheme, styleVariant: styleVariant)

        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    normalizedVariant == 3
                        ? foregroundStyle
                        : AnyShapeStyle(momentsStickerInk(for: colorScheme).opacity(0.58))
                )
                .opacity(normalizedVariant == 3 ? 1.0 : 0.7)
            
            if isEditingInline {
                // The placeholder colour is driven by .secondary in the injected colorScheme.
                // Hashtag sticker uses momentsStickerInk which is dark on light backgrounds → inject .light.
                let fieldScheme: ColorScheme = normalizedVariant == 1 ? .dark : colorScheme
                TextField(NSLocalizedString("storyEditor.hashtag.placeholder", comment: "Hashtag placeholder"), text: $hashtag)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(foregroundStyle)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .lineLimit(1)
                    .focused($isFocused)
                    .frame(minWidth: 80, maxWidth: 260)
                    .environment(\.colorScheme, fieldScheme)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
            } else {
                Text(hashtag.uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(momentsTapCycleStickerBackground(for: colorScheme, styleVariant: styleVariant))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    momentsTapCycleStickerStroke(for: colorScheme, styleVariant: styleVariant),
                    lineWidth: momentsTapCycleStickerStrokeWidth(styleVariant: styleVariant)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: isEditingInline) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            } else {
                isFocused = false
            }
        }
    }
}

struct StickerTimeCardView: View {
    let timeText: String
    let dateText: String
    var styleVariant: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let foregroundStyle = momentsTapCycleStickerForegroundStyle(for: colorScheme, styleVariant: styleVariant)
        let ink = momentsStickerInk(for: colorScheme)
        let normalizedVariant = normalizedTapCycleStickerVariant(styleVariant)

        VStack(alignment: .center, spacing: 2) {
            Text(timeText)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(foregroundStyle)
                .lineLimit(1)

            Text(dateText.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(
                    normalizedVariant == 3
                        ? foregroundStyle
                        : AnyShapeStyle(ink.opacity(0.58))
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(momentsTapCycleStickerBackground(for: colorScheme, styleVariant: styleVariant))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    momentsTapCycleStickerStroke(for: colorScheme, styleVariant: styleVariant),
                    lineWidth: momentsTapCycleStickerStrokeWidth(styleVariant: styleVariant)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CountdownComponents {
    let days: String
    let hours: String
    let minutes: String
    let seconds: String
}

func getCountdownComponents(targetAtMs: Double, now: Date) -> CountdownComponents {
    let targetDate = Date(timeIntervalSince1970: targetAtMs / 1000)
    let totalSeconds = max(Int(targetDate.timeIntervalSince(now)), 0)
    
    let days = totalSeconds / 86400
    let hours = (totalSeconds % 86400) / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    
    return CountdownComponents(
        days: String(format: "%02d", days),
        hours: String(format: "%02d", hours),
        minutes: String(format: "%02d", minutes),
        seconds: String(format: "%02d", seconds)
    )
}

private struct CountdownSegment: View {
    let value: String
    let label: String
    let ink: Color
    let boxBg: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(boxBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ink.opacity(0.08), lineWidth: 0.5)
                        )
                )
            
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(ink.opacity(0.64))
        }
    }
}

struct StickerCountdownCardView: View {
    @Binding var title: String
    @Binding var targetAtMs: Double
    var styleVariant: Int = 0
    var isEditingInline: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDatePicker = false

    init(
        title: Binding<String>,
        targetAtMs: Binding<Double>,
        styleVariant: Int = 0,
        isEditingInline: Bool = false
    ) {
        self._title = title
        self._targetAtMs = targetAtMs
        self.styleVariant = styleVariant
        self.isEditingInline = isEditingInline
    }

    init(
        title: String,
        targetAtMs: Double,
        styleVariant: Int = 0
    ) {
        self._title = .constant(title)
        self._targetAtMs = .constant(targetAtMs)
        self.styleVariant = styleVariant
        self.isEditingInline = false
    }

    var body: some View {
        let isLight = styleVariant % 6 == 0
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        let headerInk = isLight
            ? momentsStickerInverseInk(for: colorScheme)
            : .white

        VStack(alignment: .center, spacing: 0) {
            if isEditingInline {
                // headerInk is light (white) when isLight==false, dark when isLight==true
                let fieldScheme: ColorScheme = isLight ? .light : .dark
                TextField(NSLocalizedString("storyEditor.countdown.eventTitle", comment: "Countdown event title placeholder"), text: $title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(headerInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .environment(\.colorScheme, fieldScheme)
                    .background(
                        AnimatedMomentsCardStickerHeaderSurface(
                            styleVariant: styleVariant,
                            colorScheme: colorScheme
                        )
                    )
            } else {
                Text(title.isEmpty ? NSLocalizedString("storyEditor.countdown.placeholder", comment: "Placeholder title") : title.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(headerInk)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        AnimatedMomentsCardStickerHeaderSurface(
                            styleVariant: styleVariant,
                            colorScheme: colorScheme
                        )
                    )
            }

            Button(action: {
                if isEditingInline {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingDatePicker.toggle()
                    }
                    HapticManager.shared.mediumImpact()
                }
            }) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let comps = getCountdownComponents(targetAtMs: targetAtMs, now: timeline.date)
                    let boxBg = isLight
                        ? Color.black.opacity(0.06)
                        : Color.white.opacity(0.15)

                    HStack(spacing: 8) {
                        CountdownSegment(value: comps.days, label: NSLocalizedString("storyEditor.countdown.days", comment: ""), ink: ink, boxBg: boxBg)
                        CountdownSegment(value: comps.hours, label: NSLocalizedString("storyEditor.countdown.hours", comment: ""), ink: ink, boxBg: boxBg)
                        CountdownSegment(value: comps.minutes, label: NSLocalizedString("storyEditor.countdown.minutes", comment: ""), ink: ink, boxBg: boxBg)
                        CountdownSegment(value: comps.seconds, label: NSLocalizedString("storyEditor.countdown.seconds", comment: ""), ink: ink, boxBg: boxBg)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(Color.clear)
            }
            .buttonStyle(.plain)
            .disabled(!isEditingInline)

            if isEditingInline && showingDatePicker {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { Date(timeIntervalSince1970: targetAtMs / 1000) },
                        set: { targetAtMs = $0.timeIntervalSince1970 * 1000 }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(ink)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            AnimatedMomentsCardStickerSurface(
                styleVariant: styleVariant,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct StickerEmojiSliderCardView: View {
    @Binding var prompt: String
    let emoji: String
    let value: Double
    var averageValue: Double? = nil
    var styleVariant: Int = 0
    var isEditingInline: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        prompt: Binding<String>,
        emoji: String,
        value: Double,
        averageValue: Double? = nil,
        styleVariant: Int = 0,
        isEditingInline: Bool = false
    ) {
        self._prompt = prompt
        self.emoji = emoji
        self.value = value
        self.averageValue = averageValue
        self.styleVariant = styleVariant
        self.isEditingInline = isEditingInline
    }

    init(
        prompt: String,
        emoji: String,
        value: Double,
        averageValue: Double? = nil,
        styleVariant: Int = 0
    ) {
        self._prompt = .constant(prompt)
        self.emoji = emoji
        self.value = value
        self.averageValue = averageValue
        self.styleVariant = styleVariant
        self.isEditingInline = false
    }

    var body: some View {
        let isLight = styleVariant % 6 == 0
        let textColor = momentsCardStickerTextColor(styleVariant: styleVariant, colorScheme: colorScheme)
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        let clampedValue = min(max(value, 0), 1)
        let showsPrompt = emojiSliderHasPrompt(prompt) || isEditingInline
        let baseSize = emojiSliderRenderingSize(
            prompt: showsPrompt
                ? NSLocalizedString("storyEditor.slider.questionPrompt", comment: "Slider question prompt")
                : ""
        )
        let size = baseSize
        let metrics = emojiSliderTrackMetrics(totalWidth: size.width)
        let trackFrame = emojiSliderTrackFrame(totalSize: size, showsPrompt: showsPrompt)
        let thumbCenter = emojiSliderThumbCenter(totalSize: size, value: clampedValue, showsPrompt: showsPrompt)
        let thumbSize = emojiSliderThumbSize(for: clampedValue, baseSize: metrics.thumbBaseSize)

        ZStack(alignment: .topLeading) {
            if showsPrompt {
                if isEditingInline {
                    // textColor comes from momentsCardStickerTextColor — inject matching scheme
                    let fieldScheme: ColorScheme = isLight ? .light : .dark
                    TextField(NSLocalizedString("storyEditor.slider.questionPrompt", comment: "Slider question prompt"), text: $prompt)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(textColor.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .frame(width: size.width - 32)
                        .environment(\.colorScheme, fieldScheme)
                        .position(x: size.width / 2, y: 26)
                } else {
                    Text(prompt)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(textColor.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: size.width - 32)
                        .position(x: size.width / 2, y: 26)
                }
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
                                .stroke(isLight ? momentsStickerSurface(for: colorScheme).opacity(0.4) : Color.white.opacity(0.4), lineWidth: 1)
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
            AnimatedMomentsCardStickerSurface(
                styleVariant: styleVariant,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - ✅ NEW: QUIZ STICKER
struct StickerQuizCardView: View {
    @Binding var question: String
    @Binding var options: [String]
    let selectedIndex: Int?
    @Binding var correctIndex: Int?
    let onSelect: (Int) -> Void
    var styleVariant: Int = 0
    var isEditingInline: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        question: Binding<String>,
        options: Binding<[String]>,
        selectedIndex: Int?,
        correctIndex: Binding<Int?>,
        styleVariant: Int = 0,
        isEditingInline: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) {
        self._question = question
        self._options = options
        self.selectedIndex = selectedIndex
        self._correctIndex = correctIndex
        self.styleVariant = styleVariant
        self.isEditingInline = isEditingInline
        self.onSelect = onSelect
    }

    init(
        question: String,
        options: [String],
        selectedIndex: Int?,
        correctIndex: Int?,
        styleVariant: Int = 0,
        onSelect: @escaping (Int) -> Void
    ) {
        self._question = .constant(question)
        self._options = .constant(options)
        self.selectedIndex = selectedIndex
        self._correctIndex = .constant(correctIndex)
        self.styleVariant = styleVariant
        self.isEditingInline = false
        self.onSelect = onSelect
    }

    var body: some View {
        let isLight = styleVariant % 6 == 0
        let textColor = momentsCardStickerTextColor(styleVariant: styleVariant, colorScheme: colorScheme)
        let headerInk = isLight
            ? momentsStickerInverseInk(for: colorScheme)
            : .white

        VStack(alignment: .leading, spacing: 0) {
            // — Pregunta —
            if isEditingInline {
                let fieldScheme: ColorScheme = isLight ? .light : .dark
                TextField(NSLocalizedString("storyEditor.quiz.questionPrompt", comment: "Quiz question placeholder"), text: $question)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(headerInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .environment(\.colorScheme, fieldScheme)
                    .background(
                        AnimatedMomentsCardStickerHeaderSurface(
                            styleVariant: styleVariant,
                            colorScheme: colorScheme
                        )
                    )
            } else {
                Text(question.isEmpty ? NSLocalizedString("quiz.question.placeholder", comment: "Placeholder question") : question)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(headerInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(
                        AnimatedMomentsCardStickerHeaderSurface(
                            styleVariant: styleVariant,
                            colorScheme: colorScheme
                        )
                    )
            }
            
            // — Opciones —
            VStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { index in
                    quizOptionRow(index: index)
                }

                if isEditingInline && options.count < 4 {
                    Button(action: {
                        options.append("")
                        HapticManager.shared.selection()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(NSLocalizedString("quiz.addOption", comment: "Add option"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(textColor.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(textColor.opacity(isLight ? 0.08 : 0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            AnimatedMomentsCardStickerSurface(
                styleVariant: styleVariant,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    @ViewBuilder
    private func quizOptionRow(index: Int) -> some View {
        let isSelected = selectedIndex == index
        let isCorrect = correctIndex == index
        let hasVoted = selectedIndex != nil
        
        if isEditingInline {
            HStack(spacing: 10) {
                // Letra de opción (Tocar para marcar correcta en modo edición)
                Button(action: {
                    correctIndex = index
                    HapticManager.shared.heavyImpact()
                }) {
                    Text(["A", "B", "C", "D"][safe: index] ?? "\(index + 1)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(optionLetterColor(index: index, hasVoted: true, isCorrect: correctIndex == index, isSelected: false))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(optionCircleColor(index: index, hasVoted: true, isCorrect: correctIndex == index, isSelected: false))
                        )
                }
                .buttonStyle(.plain)
                
                TextField(NSLocalizedString("storyEditor.quiz.optionPrompt", comment: "Quiz option placeholder") + " \(index + 1)...", text: Binding(
                    get: { options[safe: index] ?? "" },
                    set: { newValue in
                        if index < options.count {
                            options[index] = newValue
                        }
                    }
                ))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(optionTextColor(index: index, hasVoted: false, isCorrect: false, isSelected: false))
                .submitLabel(index == options.count - 1 ? .done : .next)
                .environment(\.colorScheme, styleVariant % 6 == 0 ? (colorScheme == .dark ? .dark : .light) : .dark)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(optionBgColor(index: index, hasVoted: true, isCorrect: correctIndex == index, isSelected: false))
            )
        } else {
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
    }
    
    // MARK: - Color helpers
    private func optionBgColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let isLight = styleVariant % 6 == 0
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        if !hasVoted { return ink.opacity(isLight ? 0.08 : 0.18) }
        if isCorrect { return .green.opacity(0.78) }
        if isSelected { return .red.opacity(0.74) }
        return ink.opacity(isLight ? 0.06 : 0.12)
    }
    
    private func optionCircleColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let isLight = styleVariant % 6 == 0
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        let surface = isLight ? momentsStickerSurface(for: colorScheme) : Color.black
        if !hasVoted { return ink.opacity(0.14) }
        if isCorrect { return surface.opacity(0.26) }
        if isSelected { return surface.opacity(0.24) }
        return ink.opacity(0.1)
    }
    
    private func optionLetterColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let isLight = styleVariant % 6 == 0
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        let surface = isLight ? momentsStickerSurface(for: colorScheme) : Color.black
        if !hasVoted { return ink.opacity(0.82) }
        if isCorrect { return surface }
        if isSelected { return surface }
        return ink.opacity(0.48)
    }
 
    private func optionTextColor(index: Int, hasVoted: Bool, isCorrect: Bool, isSelected: Bool) -> Color {
        let isLight = styleVariant % 6 == 0
        let ink = isLight ? momentsStickerInk(for: colorScheme) : Color.white
        let surface = isLight ? momentsStickerSurface(for: colorScheme) : Color.black
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
    let frameStyle: StoryPolaroidFrameStyle
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
            .padding(framePadding)
            .background(frameColor)
            .overlay(imageViewportDecoration)
            
            // Área para escribir (estilo Polaroid)
            ZStack {
                Rectangle()
                    .fill(frameColor)
                    .frame(width: 200, height: 40)
                
                if let caption = caption, !caption.isEmpty {
                    let visibleCount = Int(Double(caption.count) * progress)
                    (
                        Text(caption.prefix(visibleCount))
                            .font(captionFont)
                            .foregroundColor(captionColor)
                        +
                        Text(caption.dropFirst(visibleCount))
                            .font(captionFont)
                            .foregroundColor(.clear)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 12)
                    .rotationEffect(captionRotation)
                    .offset(y: captionVerticalOffset)
                }
            }
        }
        .background(frameColor)
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .overlay(frameBorderOverlay)
        .shadow(color: frameShadowColor, radius: frameShadowRadius, y: frameShadowYOffset)
        .rotationEffect(frameRotation)
        .overlay(frameStyleDecorationOverlay)
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

    private var frameColor: Color {
        switch frameStyle {
        case .classic:
            return .white
        case .clean:
            return Color.white.opacity(0.94)
        case .vintage:
            return Color(red: 0.95, green: 0.91, blue: 0.82)
        case .album:
            return Color(red: 0.985, green: 0.965, blue: 0.93)
        }
    }

    private var framePadding: CGFloat {
        switch frameStyle {
        case .classic:
            return 10
        case .clean:
            return 8
        case .vintage:
            return 13
        case .album:
            return 12
        }
    }

    private var outerCornerRadius: CGFloat {
        switch frameStyle {
        case .classic:
            return 0
        case .clean:
            return 18
        case .vintage:
            return 4
        case .album:
            return 20
        }
    }

    private var captionFont: Font {
        switch frameStyle {
        case .clean:
            return .system(size: 18, weight: .semibold, design: .rounded)
        case .vintage:
            return .system(size: 18, weight: .medium, design: .serif)
        case .album:
            return .system(size: 17, weight: .semibold, design: .rounded)
        case .classic:
            return .custom("Caveat-Medium", size: 21)
        }
    }

    private var captionColor: Color {
        switch frameStyle {
        case .vintage:
            return Color(red: 0.22, green: 0.18, blue: 0.14).opacity(0.82)
        case .album:
            return .black.opacity(0.78)
        default:
            return .black.opacity(0.85)
        }
    }

    private var captionRotation: Angle {
        switch frameStyle {
        case .clean, .album:
            return .degrees(0)
        default:
            return .degrees(-1)
        }
    }

    private var captionVerticalOffset: CGFloat {
        switch frameStyle {
        case .clean:
            return -1
        case .album:
            return 0
        default:
            return -2
        }
    }

    private var frameRotation: Angle {
        switch frameStyle {
        case .classic:
            return .degrees(-2)
        case .clean:
            return .degrees(0)
        case .vintage:
            return .degrees(-1.4)
        case .album:
            return .degrees(0.35)
        }
    }

    private var frameShadowColor: Color {
        switch frameStyle {
        case .clean:
            return .black.opacity(0.14)
        case .vintage:
            return Color(red: 0.18, green: 0.13, blue: 0.09).opacity(0.22)
        default:
            return .black.opacity(0.2)
        }
    }

    private var frameShadowRadius: CGFloat {
        switch frameStyle {
        case .clean:
            return 14
        case .vintage:
            return 6
        default:
            return 8
        }
    }

    private var frameShadowYOffset: CGFloat {
        switch frameStyle {
        case .clean:
            return 7
        case .vintage:
            return 5
        default:
            return 4
        }
    }

    private var frameBorderStrokeColor: Color {
        switch frameStyle {
        case .classic:
            return .clear
        case .clean:
            return Color.black.opacity(0.06)
        case .vintage:
            return Color(red: 0.48, green: 0.38, blue: 0.27).opacity(0.24)
        case .album:
            return Color.black.opacity(0.08)
        }
    }

    private var frameBorderLineWidth: CGFloat {
        switch frameStyle {
        case .classic:
            return 0
        case .vintage:
            return 1.2
        default:
            return 1
        }
    }

    @ViewBuilder
    private var frameBorderOverlay: some View {
        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            .stroke(frameBorderStrokeColor, lineWidth: frameBorderLineWidth)
    }

    @ViewBuilder
    private var imageViewportDecoration: some View {
        switch frameStyle {
        case .vintage:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color(red: 0.38, green: 0.29, blue: 0.19).opacity(0.14), lineWidth: 1)
                    .padding(4)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.05),
                                Color.clear,
                                Color(red: 0.42, green: 0.28, blue: 0.08).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(4)

                VStack {
                    HStack {
                        Color(red: 0.46, green: 0.33, blue: 0.19).opacity(0.10)
                            .frame(width: 30, height: 1)
                        Spacer()
                        Color(red: 0.36, green: 0.27, blue: 0.18).opacity(0.08)
                            .frame(width: 18, height: 1)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Color(red: 0.36, green: 0.27, blue: 0.18).opacity(0.09)
                            .frame(width: 24, height: 1)
                    }
                }
                .padding(10)
            }
        case .album:
            ZStack {
                StoryPolaroidCornerAccent(rotation: .degrees(0))
                    .position(x: 16, y: 16)
                StoryPolaroidCornerAccent(rotation: .degrees(90))
                    .position(x: imageViewportSize.width + (framePadding * 2) - 16, y: 16)
                StoryPolaroidCornerAccent(rotation: .degrees(-90))
                    .position(x: 16, y: imageViewportSize.height + (framePadding * 2) - 16)
                StoryPolaroidCornerAccent(rotation: .degrees(180))
                    .position(x: imageViewportSize.width + (framePadding * 2) - 16, y: imageViewportSize.height + (framePadding * 2) - 16)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var frameStyleDecorationOverlay: some View {
        switch frameStyle {
        case .vintage:
            ZStack {
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear,
                                Color(red: 0.36, green: 0.26, blue: 0.14).opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.multiply)

                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.44, green: 0.33, blue: 0.20).opacity(0.12),
                                Color.clear,
                                Color(red: 0.30, green: 0.22, blue: 0.14).opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.6
                    )
                    .padding(0.6)

                VintageWearOverlay(cornerRadius: outerCornerRadius)
                    .padding(2)
            }
        case .album:
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                .padding(2)
        default:
            EmptyView()
        }
    }
}

private struct StoryPolaroidCornerAccent: View {
    let rotation: Angle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(Color.black.opacity(0.16), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 14, height: 14)
        .rotationEffect(rotation)
    }
}

private struct VintageWearOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Circle()
                    .fill(Color(red: 0.48, green: 0.37, blue: 0.23).opacity(0.05))
                    .frame(width: 18, height: 18)
                    .position(x: 12, y: 14)

                Circle()
                    .fill(Color(red: 0.30, green: 0.22, blue: 0.14).opacity(0.04))
                    .frame(width: 14, height: 14)
                    .position(x: width - 14, y: height - 16)

                Capsule(style: .continuous)
                    .fill(Color(red: 0.40, green: 0.28, blue: 0.16).opacity(0.05))
                    .frame(width: 22, height: 1.2)
                    .rotationEffect(.degrees(-18))
                    .position(x: width - 28, y: 18)

                Capsule(style: .continuous)
                    .fill(Color(red: 0.30, green: 0.22, blue: 0.14).opacity(0.04))
                    .frame(width: 16, height: 1.2)
                    .rotationEffect(.degrees(24))
                    .position(x: 20, y: height - 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .allowsHitTesting(false)
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
    @State private var waveTask: Task<Void, Never>?
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
            waveTask?.cancel()
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = self.audioPlayer {
                self.progress = player.currentTime / max(player.duration, 0.001)
                if !player.isPlaying {
                    finishPlayback()
                }
            }
        }
    }

    private func startWaveAnimation() {
        waveTask?.cancel()
        guard isPlaying else {
            animatedHeights = [10, 14, 10]
            return
        }
        guard !MotionPolicy.reduceMotion else {
            animatedHeights = [12, 16, 12]
            return
        }

        waveTask = Task { @MainActor in
            while isPlaying && !Task.isCancelled {
                animatedHeights = [
                    CGFloat.random(in: 6...16),
                    CGFloat.random(in: 10...20),
                    CGFloat.random(in: 6...16)
                ]
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            animatedHeights = [10, 14, 10]
        }
    }

    private func restoreAudioSessionIfNeeded() {
        guard didConfigureAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        if let previousAudioCategory, let previousAudioMode {
            try? session.setCategory(previousAudioCategory, mode: previousAudioMode, options: previousAudioOptions)
        }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

// MARK: - Tarjeta de Sticker Adaptativa (Filtro e Gradiente)
func momentsCardStickerBackgroundGradient(styleVariant: Int, colorScheme: ColorScheme) -> AnyView {
    let normalizedVariant = styleVariant % 6
    switch normalizedVariant {
    case 1: // Sunset Coral
        return AnyView(
            LinearGradient(
                colors: [Color(hex: "FF5F6D"), Color(hex: "FFC371")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    case 2: // Neon Orchid
        return AnyView(
            LinearGradient(
                colors: [Color(hex: "9D4EDD"), Color(hex: "FF70A6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    case 3: // Ocean Indigo (No Teal)
        return AnyView(
            LinearGradient(
                colors: [Color(hex: "4A00E0"), Color(hex: "8E2DE2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    case 4: // Aurora Emerald (No Teal)
        return AnyView(
            LinearGradient(
                colors: [Color(hex: "00B09B"), Color(hex: "96C93D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    case 5: // Slate Carbon
        return AnyView(
            LinearGradient(
                colors: [Color(hex: "1E293B"), Color(hex: "0F172A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    default: // Classic Light/Dark card
        return AnyView(
            colorScheme == .dark
                ? Color(hex: "1C2529")
                : Color.white
        )
    }
}

func momentsCardStickerTextColor(styleVariant: Int, colorScheme: ColorScheme) -> Color {
    let normalizedVariant = styleVariant % 6
    if normalizedVariant == 0 {
        return colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215")
    }
    return .white
}

struct AnimatedMomentsCardStickerSurface: View {
    let styleVariant: Int
    let colorScheme: ColorScheme

    @State private var previousVariant: Int?
    @State private var overlayOpacity: Double = 1

    var body: some View {
        ZStack {
            momentsCardStickerBackgroundGradient(
                styleVariant: previousVariant ?? styleVariant,
                colorScheme: colorScheme
            )

            momentsCardStickerBackgroundGradient(
                styleVariant: styleVariant,
                colorScheme: colorScheme
            )
            .opacity(overlayOpacity)
        }
        .onAppear {
            previousVariant = styleVariant
            overlayOpacity = 1
        }
        .onChange(of: styleVariant) { oldValue, newValue in
            previousVariant = oldValue
            overlayOpacity = 0

            withAnimation(.easeInOut(duration: 0.22)) {
                overlayOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                previousVariant = newValue
            }
        }
    }
}

struct AnimatedMomentsCardStickerHeaderSurface: View {
    let styleVariant: Int
    let colorScheme: ColorScheme

    @State private var previousVariant: Int?
    @State private var overlayOpacity: Double = 1

    private func headerSurface(for variant: Int) -> AnyView {
        let isLight = variant % 6 == 0
        return isLight
            ? AnyView(momentsStickerInverseSurface(for: colorScheme))
            : AnyView(Color.white.opacity(0.12))
    }

    var body: some View {
        ZStack {
            headerSurface(for: previousVariant ?? styleVariant)
            headerSurface(for: styleVariant)
                .opacity(overlayOpacity)
        }
        .onAppear {
            previousVariant = styleVariant
            overlayOpacity = 1
        }
        .onChange(of: styleVariant) { oldValue, newValue in
            previousVariant = oldValue
            overlayOpacity = 0

            withAnimation(.easeInOut(duration: 0.22)) {
                overlayOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                previousVariant = newValue
            }
        }
    }
}
