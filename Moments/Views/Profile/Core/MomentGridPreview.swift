import SwiftUI

enum MomentGridPreviewFitMode: String, Codable, Equatable {
    case fill
    case fit
}

enum MomentGridPreviewBackground: String, Codable, Equatable {
    case black
    case white
}

struct MomentGridPreviewSettings: Equatable {
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var fitMode: MomentGridPreviewFitMode
    var background: MomentGridPreviewBackground

    static let `default` = MomentGridPreviewSettings(
        scale: 1,
        offsetX: 0,
        offsetY: 0,
        fitMode: .fill,
        background: .black
    )

    var isDefault: Bool {
        abs(scale - 1) < 0.001
            && abs(offsetX) < 0.001
            && abs(offsetY) < 0.001
            && fitMode == .fill
    }
}

extension Moment {
    var gridPreviewSettings: MomentGridPreviewSettings {
        MomentGridPreviewSettings(
            scale: CGFloat(gridPreviewScale ?? 1),
            offsetX: CGFloat(gridPreviewOffsetX ?? 0),
            offsetY: CGFloat(gridPreviewOffsetY ?? 0),
            fitMode: MomentGridPreviewFitMode(rawValue: gridPreviewFitMode ?? "fill") ?? .fill,
            background: MomentGridPreviewBackground(rawValue: gridPreviewBackground ?? "black") ?? .black
        )
    }

    var canAdjustGridPreview: Bool {
        previewImageURLString != nil
    }
}

struct GridPreviewThumbnailFrame<Content: View>: View {
    let size: CGFloat
    let settings: MomentGridPreviewSettings
    @ViewBuilder let content: () -> Content

    private var backgroundColor: Color {
        settings.background == .black ? .black : .white
    }

    var body: some View {
        ZStack {
            if settings.fitMode == .fit {
                backgroundColor
            }

            content()
                .aspectRatio(contentMode: settings.fitMode == .fit ? .fit : .fill)
                .scaleEffect(settings.scale)
                .offset(
                    x: settings.offsetX * size,
                    y: settings.offsetY * size
                )
        }
        .frame(width: size, height: size)
        .clipped()
    }
}
