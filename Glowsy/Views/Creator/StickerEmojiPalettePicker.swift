import SwiftUI

private struct StickerEmojiOption: Identifiable, Hashable {
    let emoji: String
    let skinToneVariants: [String]
    let category: StickerEmojiCategory

    var id: String { emoji }
}

private enum StickerEmojiCategory: String, CaseIterable, Identifiable {
    case smileys
    case people
    case nature
    case food
    case activities
    case travel
    case objects
    case symbols
    case flags

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .smileys: return "stickerview.emojiPicker.category.smileys"
        case .people: return "stickerview.emojiPicker.category.people"
        case .nature: return "stickerview.emojiPicker.category.nature"
        case .food: return "stickerview.emojiPicker.category.food"
        case .activities: return "stickerview.emojiPicker.category.activities"
        case .travel: return "stickerview.emojiPicker.category.travel"
        case .objects: return "stickerview.emojiPicker.category.objects"
        case .symbols: return "stickerview.emojiPicker.category.symbols"
        case .flags: return "stickerview.emojiPicker.category.flags"
        }
    }

    var icon: String {
        switch self {
        case .smileys: return "face.smiling"
        case .people: return "person.2"
        case .nature: return "leaf"
        case .food: return "fork.knife"
        case .activities: return "gamecontroller"
        case .travel: return "car"
        case .objects: return "lightbulb"
        case .symbols: return "heart"
        case .flags: return "flag"
        }
    }
}

private enum IOSSystemEmojiCatalog {
    private static let toneModifiers: [UnicodeScalar] = [
        "\u{1F3FB}",
        "\u{1F3FC}",
        "\u{1F3FD}",
        "\u{1F3FE}",
        "\u{1F3FF}"
    ]

    static let options: [StickerEmojiOption] = build()

    private static func build() -> [StickerEmojiOption] {
        var result: [StickerEmojiOption] = []
        var seen = Set<String>()

        func append(_ emoji: String) {
            guard !emoji.isEmpty, !seen.contains(emoji) else { return }
            seen.insert(emoji)
            result.append(
                StickerEmojiOption(
                    emoji: emoji,
                    skinToneVariants: skinToneVariants(for: emoji),
                    category: category(for: emoji)
                )
            )
        }

        let scalarRanges: [ClosedRange<Int>] = [
            0x1F1E6...0x1F1FF,
            0x1F300...0x1F5FF,
            0x1F600...0x1F64F,
            0x1F680...0x1F6FF,
            0x1F700...0x1F77F,
            0x1F780...0x1F7FF,
            0x1F800...0x1F8FF,
            0x1F900...0x1F9FF,
            0x1FA70...0x1FAFF,
            0x2600...0x26FF,
            0x2700...0x27BF
        ]

        for range in scalarRanges {
            for value in range {
                guard let scalar = UnicodeScalar(value) else { continue }
                let properties = scalar.properties
                guard properties.isEmoji,
                      !properties.isEmojiModifier else { continue }

                append(String(Character(scalar)))
            }
        }

        let extras = [
            "❤️", "🩷", "🩵", "🩶", "🫶", "☠️", "☹️", "☺️", "✌️", "☝️",
            "✍️", "⭐", "✨", "⚡", "☄️", "☀️", "☁️", "⛅", "☔", "❄️",
            "☕", "⚽", "⚾", "⛳", "⌚", "☎️", "⌨️", "✈️", "⌛", "⏰",
            "⌛️", "⏳", "™️", "©️", "®️", "‼️", "⁉️", "〰️", "➕", "➖",
            "➗", "✖️", "♾️", "♻️", "⚠️", "❣️", "💟", "🗯️", "🫠", "🫨",
            "👨‍💻", "👩‍💻", "🧑‍💻", "👨‍🚀", "👩‍🚀", "🧑‍🚀", "👨‍🎤", "👩‍🎤",
            "🧑‍🎤", "👨‍🍳", "👩‍🍳", "🧑‍🍳", "👨‍🎨", "👩‍🎨", "🧑‍🎨", "👨‍⚕️",
            "👩‍⚕️", "🧑‍⚕️", "👨‍🏫", "👩‍🏫", "🧑‍🏫", "👨‍🌾", "👩‍🌾", "🧑‍🌾",
            "👨‍🔧", "👩‍🔧", "🧑‍🔧", "👨‍🚒", "👩‍🚒", "🧑‍🚒", "👨‍✈️", "👩‍✈️",
            "🧑‍✈️", "👨‍⚖️", "👩‍⚖️", "🧑‍⚖️", "👨‍🎓", "👩‍🎓", "🧑‍🎓", "👨‍🍼",
            "👩‍🍼", "🧑‍🍼", "👨‍🦽", "👩‍🦽", "🧑‍🦽", "👨‍🦯", "👩‍🦯", "🧑‍🦯",
            "👨‍🦼", "👩‍🦼", "🧑‍🦼", "👩‍❤️‍👨", "👨‍❤️‍👨", "👩‍❤️‍👩"
        ]

        extras.forEach(append)
        return result
    }

    private static func skinToneVariants(for emoji: String) -> [String] {
        guard supportsSkinTone(emoji) else { return [] }
        return toneModifiers.compactMap { modifier in
            applyingSkinTone(modifier, to: emoji)
        }
    }

    private static func category(for emoji: String) -> StickerEmojiCategory {
        let scalars = Array(emoji.unicodeScalars)

        if scalars.contains(where: { (0x1F1E6...0x1F1FF).contains(Int($0.value)) }) {
            return .flags
        }

        if supportsSkinTone(emoji) || emoji.contains("🧑") || emoji.contains("👨") || emoji.contains("👩") || emoji.contains("👶") {
            return .people
        }

        if let first = scalars.first {
            switch first.value {
            case 0x1F600...0x1F64F:
                return .smileys
            case 0x1F300...0x1F32C, 0x2600...0x26FF:
                return .nature
            case 0x1F32D...0x1F37F, 0x1F950...0x1F96F:
                return .food
            case 0x1F380...0x1F3CF, 0x1F93C...0x1F945:
                return .activities
            case 0x1F680...0x1F6FF, 0x1F30D...0x1F30F:
                return .travel
            case 0x1F4A1...0x1F5FF, 0x1F9F0...0x1F9FF:
                return .objects
            case 0x2764, 0x1F494...0x1F49F, 0x1F500...0x1F53D:
                return .symbols
            default:
                break
            }
        }

        if ["❤️", "🩷", "🩵", "🩶", "💟", "❣️", "‼️", "⁉️", "〰️", "➕", "➖", "➗", "✖️", "♾️", "♻️", "⚠️"].contains(emoji) {
            return .symbols
        }

        return .objects
    }

    private static func supportsSkinTone(_ emoji: String) -> Bool {
        emoji.unicodeScalars.contains { $0.properties.isEmojiModifierBase }
    }

    private static func applyingSkinTone(_ modifier: UnicodeScalar, to emoji: String) -> String? {
        let scalars = Array(emoji.unicodeScalars)
        guard let baseIndex = scalars.firstIndex(where: { $0.properties.isEmojiModifierBase }) else {
            return nil
        }

        var newScalars: [UnicodeScalar] = []
        var inserted = false

        for (index, scalar) in scalars.enumerated() {
            newScalars.append(scalar)

            if index == baseIndex {
                let nextIndex = index + 1
                if nextIndex < scalars.count, scalars[nextIndex].value == 0xFE0F {
                    continue
                }
                newScalars.append(modifier)
                inserted = true
            } else if inserted, scalar.value == 0xFE0F {
                continue
            }
        }

        if !inserted {
            return nil
        }

        return String(String.UnicodeScalarView(newScalars))
    }
}

struct StickerEmojiPalettePicker: View {
    @Binding var selectedEmoji: String
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeVariantSourceID: String?
    @State private var selectedCategory: StickerEmojiCategory = .smileys
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    private var backgroundFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var variantTrayFill: Color {
        colorScheme == .dark
            ? Color(red: 11 / 255, green: 18 / 255, blue: 21 / 255)
            : Color(red: 250 / 255, green: 249 / 255, blue: 246 / 255)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var cellBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var selectedBorder: Color {
        Color(red: 0.99, green: 0.56, blue: 0.21)
    }

    private var categoryText: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.82)
    }

    private var filteredOptions: [StickerEmojiOption] {
        IOSSystemEmojiCatalog.options.filter { $0.category == selectedCategory }
    }

    private var activeVariantOption: StickerEmojiOption? {
        IOSSystemEmojiCatalog.options.first(where: { $0.id == activeVariantSourceID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StickerEmojiCategory.allCases) { category in
                        Button {
                            activeVariantSourceID = nil
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(LocalizedStringKey(category.titleKey))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(selectedCategory == category ? .white : categoryText)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedCategory == category ? selectedBorder : .clear)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(selectedCategory == category ? selectedBorder : cellBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredOptions) { option in
                        Text(option.emoji)
                            .font(.system(size: 28))
                            .frame(width: 40, height: 40)
                            .scaleEffect(selectedEmoji == option.emoji ? 1.12 : 1.0)
                            .shadow(color: selectedEmoji == option.emoji ? selectedBorder.opacity(0.25) : .clear, radius: 6, y: 2)
                            .overlay(alignment: .bottom) {
                                Capsule(style: .continuous)
                                    .fill(selectedEmoji == option.emoji ? selectedBorder : .clear)
                                    .frame(width: 18, height: 3)
                                    .offset(y: 3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeVariantSourceID = nil
                                selectedEmoji = option.emoji
                                onSelect(option.emoji)
                            }
                            .onLongPressGesture(minimumDuration: 0.25) {
                                guard !option.skinToneVariants.isEmpty else { return }
                                activeVariantSourceID = option.id
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: .infinity)

            if let activeVariantOption, !activeVariantOption.skinToneVariants.isEmpty {
                HStack(spacing: 10) {
                    Text(activeVariantOption.emoji)
                        .font(.system(size: 22))
                        .frame(width: 28, height: 28)

                    ForEach(activeVariantOption.skinToneVariants, id: \.self) { variant in
                        Text(variant)
                            .font(.system(size: 26))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEmoji = variant
                                activeVariantSourceID = nil
                                onSelect(variant)
                            }
                    }

                    Spacer(minLength: 0)

                    Button {
                        activeVariantSourceID = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(categoryText.opacity(0.72))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(
                    Capsule(style: .continuous)
                        .fill(variantTrayFill)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(cellBorder, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: activeVariantOption == nil ? 320 : 384)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: activeVariantSourceID)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }
}
