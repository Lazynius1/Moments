import SwiftUI

struct SettingsListRowBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                colorScheme == .dark ?
                Color(hex: "FAF9F6").opacity(0.05) :
                Color(hex: "0B1215").opacity(0.04)
            )
    }
}

// MARK: - Online Status Section
struct OnlineStatusSection: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var onlineStatusService = OnlineStatusService()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: onlineStatusService.currentUserStatus.icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(onlineStatusService.currentUserStatus.color)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("settings.onlineStatus.title", comment: "Online Status"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    Text(String(format: NSLocalizedString("settings.onlineStatus.current", comment: "Current status"), onlineStatusService.currentUserStatus.displayName))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Menu {
                    ForEach(OnlineStatus.allCases, id: \.self) { status in
                        Button(action: { onlineStatusService.setGlobalStatus(status) }) {
                            HStack {
                                Image(systemName: status.icon)
                                Text(status.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("settings.onlineStatus.select", comment: "Select"))
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        Image(systemName: "chevron.up.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(colorScheme == .dark ? .white : .black).opacity(0.08))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
        }
    }
}
