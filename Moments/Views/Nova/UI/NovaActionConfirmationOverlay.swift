import SwiftUI

struct NovaActionConfirmationOverlay: View {
    let action: NovaPendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.62)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.20)
    }

    var body: some View {
        ZStack {
            scrimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(action.title)
                        .foregroundColor(primaryTextColor)
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("nova.confirm.subtitle", comment: ""))
                        .foregroundColor(secondaryTextColor)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .multilineTextAlignment(.center)
                }

                if let previewImage = action.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 0.5)
                        }
                }

                Text(action.detail)
                    .foregroundColor(secondaryTextColor)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text(NSLocalizedString("common.cancel", comment: "Cancel"))
                            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            .foregroundColor(primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onConfirm) {
                        Text(NSLocalizedString("nova.confirm.approve", comment: ""))
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }
}
