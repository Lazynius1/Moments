import SwiftUI
import UIKit

struct EditableImageView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    let filteredImage: UIImage?
    let canvasSize: CGSize
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastRotation: Angle = .zero

    init(
        image: UIImage,
        scale: Binding<CGFloat>,
        offset: Binding<CGSize>,
        rotation: Binding<Angle>,
        filteredImage: UIImage? = nil,
        canvasSize: CGSize
    ) {
        self.image = image
        self._scale = scale
        self._offset = offset
        self._rotation = rotation
        self.filteredImage = filteredImage
        self.canvasSize = canvasSize
    }

    var displayImage: UIImage {
        filteredImage ?? image
    }

    var body: some View {
        ZStack {
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .blur(radius: 20)
                .scaleEffect(1.1)

            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: StoryMediaLayoutRules.presentationMode(for: displayImage.size, canvasSize: canvasSize).swiftUIContentMode)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
