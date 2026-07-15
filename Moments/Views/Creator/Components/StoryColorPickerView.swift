import SwiftUI

struct StoryColorPickerPanel: View {
    @Binding var selectedColor: Color
    @Binding var isPresented: Bool
    let swatchColors: [Color]
    let suggestedColors: [Color]
    var onPickFromCanvas: (() -> Void)?

    @State private var hue: Double = 0.58
    @State private var saturation: Double = 0.85
    @State private var brightness: Double = 0.95

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 52, height: 52)
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateHue(from: value.location, in: 52)
                            applyHSB()
                        }
                )

                VStack(spacing: 6) {
                    sliderRow(label: "S", value: $saturation, onChange: applyHSB)
                    sliderRow(label: "B", value: $brightness, onChange: applyHSB)
                }
            }

            if !suggestedColors.isEmpty {
                suggestedRow(title: NSLocalizedString("storyTextEditor.suggestedColors", comment: "Suggested"), colors: suggestedColors)
            }

            suggestedRow(title: nil, colors: swatchColors)

            if let onPickFromCanvas {
                Button(action: onPickFromCanvas) {
                    Label(
                        NSLocalizedString("storyTextEditor.eyedropper", comment: "Pick from photo"),
                        systemImage: "eyedropper"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .onAppear { syncHSBFromSelected() }
        .onChange(of: selectedColor) { _, _ in syncHSBFromSelected() }
    }

    private func sliderRow(label: String, value: Binding<Double>, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 12)
            Slider(value: value, in: 0...1)
                .tint(.white)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
    }

    private func suggestedRow(title: String?, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        ColorOption(color: color, isSelected: selectedColor == color) {
                            selectedColor = color
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
            }
        }
    }

    private func updateHue(from location: CGPoint, in diameter: CGFloat) {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        hue = angle / (2 * .pi)
    }

    private func applyHSB() {
        selectedColor = Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func syncHSBFromSelected() {
        let ui = UIColor(selectedColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }
}
