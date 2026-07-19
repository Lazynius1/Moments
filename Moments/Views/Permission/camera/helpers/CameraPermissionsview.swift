import SwiftUI

struct CameraPermissionsview: View {
    var tint: Color = .accentColor
    var title: String
    var description: String
    var primaryActionTitle: String
    var secondaryActionTitle: String
    var showsShutterUI: Bool = false
    var isDenied: Bool = false
    var primaryAction: () -> ()
    var secondaryAction: () -> ()
    var panorama: () -> Image

    @Environment(\.colorScheme) private var colorScheme

    private var canvasColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    var body: some View {
        Rectangle()
            .fill(canvasColor)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 0) {
                    PermissionAnimation()
                        .padding(.top, 15)
                        .padding(.bottom, 25)

                    PermissionContent()
                }
            }
            .fontDesign(.rounded)
    }

    @ViewBuilder
    private func PermissionContent() -> some View {
        VStack(spacing: 10) {
            ZStack {
                Image(systemName: "camera")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .fontWeight(.ultraLight)

                // `camera.slash` no pinta bien con ultraLight/resizable; slash manual.
                if isDenied {
                    PermissionDeniedIconSlash()
                        .stroke(
                            MomentsChromeGlass.contentColor(for: colorScheme),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 76, height: 76)
                }
            }
            .frame(width: 80, height: 80)
            .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme).opacity(isDenied ? 0.72 : 1))
            .overlay(alignment: .topLeading) {
                if isDenied {
                    Image(systemName: "lock.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme))
                } else {
                    Image(systemName: "chevron.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .keyframeAnimator(initialValue: -5.0, repeating: true) { content, offset in
                            content.offset(y: offset)
                        } keyframes: { _ in
                            CubicKeyframe(0, duration: 1)
                            CubicKeyframe(-5, duration: 1)
                            CubicKeyframe(-5, duration: 0.5)
                        }
                }
            }
            .padding(.bottom, 10)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if #available(iOS 26.0, *) {
                    Button(action: primaryAction) {
                        Text(primaryActionTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                } else {
                    Button(action: primaryAction) {
                        Text(primaryActionTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .tint(tint)
            .padding(.top, 10)

            Button(secondaryActionTitle, action: secondaryAction)
                .tint(.secondary)
                .padding(.top, 5)
        }
        .frame(maxWidth: 330)
        .padding(.bottom, 15)
    }

    @ViewBuilder
    private func PermissionAnimation() -> some View {
        let iPhoneRatio: CGFloat = 390 / 870
        let IphoneCornerRadius: CGFloat = 47
        GeometryReader {
            let size = $0.size
            let ratio = min(size.width / 390, size.height / 870)

            Group {
                if isDenied {
                    phoneBody(
                        frame: AnimatedFrame(scale: 1, camOpacity: 1, progress: 0),
                        size: size,
                        ratio: ratio,
                        cornerRadius: IphoneCornerRadius
                    )
                } else {
                    KeyframeAnimator(initialValue: AnimatedFrame(), repeating: true) { frame in
                        phoneBody(frame: frame, size: size, ratio: ratio, cornerRadius: IphoneCornerRadius)
                    } keyframes: { _ in
                        MoveKeyframe(AnimatedFrame())
                        LinearKeyframe(AnimatedFrame(), duration: 0.5)

                        CubicKeyframe(AnimatedFrame(scale: 0.95, camOpacity: 1), duration: 0.5)
                        LinearKeyframe(AnimatedFrame(scale: 0.95, camOpacity: 1), duration: 0.5)

                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, camOpacity: 1, progress: -1),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )
                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, camOpacity: 1, progress: 1),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )
                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, camOpacity: 1, progress: 0),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )

                        CubicKeyframe(AnimatedFrame(), duration: 0)
                        LinearKeyframe(AnimatedFrame(), duration: 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(iPhoneRatio, contentMode: .fit)
    }

    private func phoneBody(
        frame: AnimatedFrame,
        size: CGSize,
        ratio: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let islandWidth = 120 * ratio
        let islandHeight = 36 * ratio

        return Rectangle()
            .fill(.fill)
            .overlay {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.black)
                        .overlay {
                            panorama()
                                .aspectRatio(contentMode: .fill)
                                .frame(
                                    width: size.width * 3,
                                    height: size.height
                                )
                                .offset(x: isDenied ? 0 : -frame.progress * size.width)
                                .permissionMockDeniedChrome(isDenied)
                        }

                    if showsShutterUI {
                        HStack(spacing: 0) {
                            Circle()
                                .fill(.white.secondary)
                                .frame(width: size.height * 0.05)

                            Circle()
                                .fill(.white)
                                .frame(width: size.height * 0.2, height: size.height * 0.1)

                            Circle()
                                .fill(.white.secondary)
                                .frame(width: size.height * 0.05)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: size.height * 0.17)
                        .background(.black.opacity(0.5))
                    }
                }
                .clipped()
                .offset(y: size.height - (size.height * frame.camOpacity))
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(.black)
                        .stroke(.fill, lineWidth: 1)
                        .frame(width: islandWidth, height: islandHeight)
                        .overlay(alignment: .center) {
                            if !isDenied {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 10 * ratio, height: 10 * ratio)
                                    .offset(x: 12 * ratio)
                                    .opacity(frame.camOpacity)
                            }
                        }
                        .padding(.top, 11 * ratio)

                    HStack {
                        PermissionPhoneStatusBarTime(ratio: ratio)
                            .opacity(max(frame.camOpacity, 0.35))
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 22 * ratio)
                    .padding(.trailing, islandWidth / 2 + 16 * ratio)
                    .frame(height: islandHeight)
                    .padding(.top, 11 * ratio)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius * ratio))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius * ratio)
                    .stroke(.fill, lineWidth: 2)
            }
            .compositingGroup()
            .scaleEffect(frame.scale, anchor: .center)
            .rotation3DEffect(
                .degrees(isDenied ? 0 : frame.progress * 15),
                axis: (x: 0, y: abs(frame.progress), z: abs(frame.progress / 4)),
                anchor: .center
            )
            .offset(x: isDenied ? 0 : frame.progress * 80)
    }

    @Animatable
    struct AnimatedFrame {
        var scale: CGFloat = 1
        var camOpacity: CGFloat = 0
        var progress: CGFloat = 0
    }
}

private struct PermissionDeniedIconSlash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = min(rect.width, rect.height) * 0.12
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        return path
    }
}

#Preview("Primer") {
    CameraPermissionsview(
        title: NSLocalizedString("permission.camera.primer.title", comment: "Camera primer title"),
        description: NSLocalizedString("permission.camera.primer.subtitle", comment: "Camera primer subtitle"),
        primaryActionTitle: NSLocalizedString("permission.camera.primer.allow", comment: "Allow camera"),
        secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
        showsShutterUI: true,
        isDenied: false,
        primaryAction: {},
        secondaryAction: {},
        panorama: { Image(.pic1).resizable() }
    )
}

#Preview("Denied") {
    CameraPermissionsview(
        title: NSLocalizedString("permission.camera.denied.title", comment: "Camera denied title"),
        description: NSLocalizedString("permission.camera.denied.subtitle", comment: "Camera denied subtitle"),
        primaryActionTitle: NSLocalizedString("permission.camera.denied.openSettings", comment: "Open Settings"),
        secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
        showsShutterUI: false,
        isDenied: true,
        primaryAction: {},
        secondaryAction: {},
        panorama: { Image(.pic1).resizable() }
    )
}
