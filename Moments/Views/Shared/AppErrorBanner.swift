import SwiftUI

struct AppErrorBanner: View {
    let message: String
    var retryTitle: String = NSLocalizedString("maps.error.retry", comment: "Retry button text")
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)

            Text(message)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.primary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(.custom("Poppins-SemiBold", size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }
}
