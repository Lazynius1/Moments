import SwiftUI

enum StoryEditorChromeColor {
    static func icon(_ colorScheme: ColorScheme) -> Color {
        MomentsChromeGlass.contentColor(for: colorScheme)
    }
}

struct EditingToolButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
    }
}

struct EditingToolIcon: View {
    let icon: String
    var usesCustomStickerGlyph: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Group {
                if usesCustomStickerGlyph {
                    Image("MomentsStickerTool")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                }
            }
                .foregroundStyle(StoryEditorChromeColor.icon(colorScheme))
                .frame(width: 44, height: 44)
                .momentsChromeGlass(in: Circle(), interactive: true)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.1 : 0.08), radius: 4, x: 0, y: 2)
        }
    }
}

struct OptionRow: View {
    let icon: String
    let title: String
    let value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 30)

                Text(title)
                    .foregroundStyle(.white)

                Spacer()

                if let value = value {
                    Text(value)
                        .foregroundStyle(.gray)
                        .font(.system(size: 14))
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    }
}

struct ShareOptionToggle: View {
    let platform: String
    let icon: String
    let color: Color
    @State private var isOn = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)

            Text(platform)
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}
