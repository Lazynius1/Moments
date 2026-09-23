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
    let width: CGFloat
    let height: CGFloat
    let settings: MomentGridPreviewSettings
    @ViewBuilder let content: () -> Content

    init(
        size: CGFloat,
        settings: MomentGridPreviewSettings,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(width: size, height: size, settings: settings, content: content)
    }

    init(
        width: CGFloat,
        height: CGFloat,
        settings: MomentGridPreviewSettings,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.settings = settings
        self.content = content
    }

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
                    x: settings.offsetX * width,
                    // Mantiene la escala histórica de los offsets guardados,
                    // que se definieron respecto al ancho del grid 1:1.
                    y: settings.offsetY * width
                )
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
