import SwiftUI

enum PermissionPrimerStage {
    case primer
    case denied
}

struct PermissionPrimerScaffold<Phone: View>: View {
    var stage: PermissionPrimerStage = .primer
    var tint: Color = .accentColor
    var iconSymbol: String
    var accentSymbol: String? = nil
    var title: String
    var description: String
    var primaryActionTitle: String
    var secondaryActionTitle: String
    var primaryAction: () -> Void
    var secondaryAction: () -> Void
    @ViewBuilder var phone: () -> Phone

    @Environment(\.colorScheme) private var colorScheme

    private var isDenied: Bool { stage == .denied }

    private var canvasColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    var body: some View {
        Rectangle()
            .fill(canvasColor)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 0) {
                    phone()
                        .padding(.top, 15)
                        .padding(.bottom, 25)

                    contentBlock
                }
            }
            .fontDesign(.rounded)
    }

    private var contentBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: iconSymbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fontWeight(.ultraLight)
                .frame(width: 80, height: 80)
                .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme).opacity(isDenied ? 0.72 : 1))
                .overlay(alignment: .topLeading) {
                    iconBadge
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
    private var iconBadge: some View {
        if isDenied {
            Image(systemName: "lock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(MomentsChromeGlass.contentColor(for: colorScheme))
        } else if let accentSymbol {
            Image(systemName: accentSymbol)
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
}

extension View {
    /// Dims and desaturates a permission phone mock when access is denied.
    @ViewBuilder
    func permissionMockDeniedChrome(_ denied: Bool) -> some View {
        if denied {
            self
                .saturation(0.35)
                .brightness(-0.05)
                .overlay(Color.black.opacity(0.18))
        } else {
            self
        }
    }
}
