import SwiftUI

struct PermissionPhoneMotion {
    var progress: CGFloat = 0
    var reveal: CGFloat = 0
}

enum PermissionPhoneIslandPlacement {
    /// Privacy dots (camera / mic) sit inside the Dynamic Island.
    case inside
    /// Status icons (location arrow) sit left of the island, near the time.
    case leading
}

/// Classic Apple marketing status-bar clock (always 9:41).
struct PermissionPhoneStatusBarTime: View {
    var ratio: CGFloat
    var color: Color = .white

    var body: some View {
        Text(verbatim: "9:41")
            .font(.system(size: 15 * ratio, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}

struct PermissionPhoneFrame<Screen: View, Island: View>: View {
    var screenBackground: Color = .black
    var animated: Bool = true
    var islandPlacement: PermissionPhoneIslandPlacement = .inside
    /// Lock-screen mocks already show a large clock; hide the status-bar duplicate there.
    var showsStatusBarTime: Bool = true
    /// Privacy / location status indicators inside or beside the island.
    var showsIslandIndicators: Bool = true
    /// Applies shared denied dim/desaturate over the phone screen content.
    var appliesDeniedChrome: Bool = false
    @ViewBuilder var screen: (CGSize, PermissionPhoneMotion) -> Screen
    @ViewBuilder var island: (CGFloat, PermissionPhoneMotion) -> Island

    private let iPhoneRatio: CGFloat = 390 / 870
    private let cornerRadius: CGFloat = 47

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let ratio = min(size.width / 390, size.height / 870)

            Group {
                if animated {
                    KeyframeAnimator(initialValue: AnimatedFrame(), repeating: true) { frame in
                        phoneBody(frame: frame, size: size, ratio: ratio)
                    } keyframes: { _ in
                        MoveKeyframe(AnimatedFrame())
                        LinearKeyframe(AnimatedFrame(), duration: 0.5)

                        CubicKeyframe(AnimatedFrame(scale: 0.95, reveal: 1), duration: 0.5)
                        LinearKeyframe(AnimatedFrame(scale: 0.95, reveal: 1), duration: 0.5)

                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, reveal: 1, progress: -1),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )
                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, reveal: 1, progress: 1),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )
                        SpringKeyframe(
                            AnimatedFrame(scale: 0.95, reveal: 1, progress: 0),
                            duration: 1.5,
                            spring: .smooth(duration: 1, extraBounce: 0)
                        )

                        CubicKeyframe(AnimatedFrame(), duration: 0)
                        LinearKeyframe(AnimatedFrame(), duration: 0.5)
                    }
                } else {
                    phoneBody(
                        frame: AnimatedFrame(scale: 1, reveal: 1, progress: 0),
                        size: size,
                        ratio: ratio
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(iPhoneRatio, contentMode: .fit)
    }

    private func phoneBody(frame: AnimatedFrame, size: CGSize, ratio: CGFloat) -> some View {
        let motion = PermissionPhoneMotion(progress: frame.progress, reveal: frame.reveal)
        let islandWidth = 120 * ratio
        let islandHeight = 36 * ratio
        let leadingIconSize = 14 * ratio
        let leadingSpacing = 5 * ratio

        return Rectangle()
            .fill(.fill)
            .overlay {
                Rectangle()
                    .fill(screenBackground)
                    .overlay {
                        screen(size, motion)
                            .permissionMockDeniedChrome(appliesDeniedChrome)
                    }
                    .clipped()
                    .offset(y: size.height - (size.height * frame.reveal))
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(.black)
                        .stroke(.fill, lineWidth: 1)
                        .frame(width: islandWidth, height: islandHeight)
                        .overlay(alignment: .center) {
                            if showsIslandIndicators, islandPlacement == .inside {
                                island(ratio, motion)
                            }
                        }
                        .padding(.top, 11 * ratio)

                    HStack(alignment: .center, spacing: leadingSpacing) {
                        if showsStatusBarTime {
                            PermissionPhoneStatusBarTime(ratio: ratio)
                        }

                        if showsIslandIndicators, islandPlacement == .leading {
                            island(ratio, motion)
                                .frame(width: leadingIconSize, height: leadingIconSize)
                                .opacity(motion.reveal)
                        }

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
                .degrees(frame.progress * 15),
                axis: (x: 0, y: abs(frame.progress), z: abs(frame.progress / 4)),
                anchor: .center
            )
            .offset(x: frame.progress * 80)
    }

    @Animatable
    struct AnimatedFrame {
        var scale: CGFloat = 1
        var reveal: CGFloat = 0
        var progress: CGFloat = 0
    }
}
