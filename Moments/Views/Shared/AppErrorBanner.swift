import SwiftUI

struct AppErrorBanner: View {
    let message: String
    var retryTitle: String = NSLocalizedString("maps.error.retry", comment: "Retry button text")
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }
}
