import SwiftUI

struct MediaProgressRing: View {
    let progress: Double // 0.0 to 1.0
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4

    @Environment(\.colorScheme) private var colorScheme

    private var progressGradient: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [Color(hex: "8EB6CE"), Color(hex: "3F6F8F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [Color(hex: "5C8DA8"), Color(hex: "3F6F8F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color(hex: "3F6F8F").opacity(0.22) : Color.black.opacity(0.1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)

            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
                .frame(width: size - lineWidth, height: size - lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    progressGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)

            if size > 50 {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                    .foregroundStyle(labelColor)
            }
        }
        .shadow(color: shadowColor, radius: 4, x: 0, y: 1)
    }
}

struct MediaProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack {
                Color(hex: "0B1215").ignoresSafeArea()
                MediaProgressRing(progress: 0.65, size: 60)
            }
            .preferredColorScheme(.dark)

            ZStack {
                Color(hex: "FAF9F6").ignoresSafeArea()
                MediaProgressRing(progress: 0.65, size: 60)
            }
            .preferredColorScheme(.light)
        }
    }
}
