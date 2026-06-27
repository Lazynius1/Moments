import SwiftUI

struct ChatStorageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var breakdown = ChatCacheStore.storageBreakdown()
    @State private var autoDownload = ChatMediaDownloadPolicy.autoDownload
    @State private var retention = ChatMediaDownloadPolicy.retention
    @State private var showClearMediaConfirm = false
    @State private var showClearAllConfirm = false
    @State private var statusMessage: String?

    private var screenBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(hex: "FAF9F6").opacity(0.8)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                usageSection
                preferencesSection
                actionsSection

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background {
            screenBackground.ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("settings.chatStorage.title", comment: ""))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryText)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { refreshUsage() }
        .confirmationDialog(
            NSLocalizedString("settings.chatStorage.clearMedia.confirm", comment: ""),
            isPresented: $showClearMediaConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("settings.chatStorage.clearMedia.action", comment: ""), role: .destructive) {
                ChatCacheStore.clearAllMedia()
                refreshUsage()
                statusMessage = NSLocalizedString("settings.chatStorage.clearMedia.done", comment: "")
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(
            NSLocalizedString("settings.chatStorage.clearAll.confirm", comment: ""),
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("settings.chatStorage.clearAll.action", comment: ""), role: .destructive) {
                LocalPersistenceService.shared.clearAllChatCache()
                refreshUsage()
                statusMessage = NSLocalizedString("settings.chatStorage.clearAll.done", comment: "")
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        }
    }

    private var usageSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("settings.chatStorage.usage.title", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)

                usageRow(
                    title: NSLocalizedString("settings.chatStorage.usage.messages", comment: ""),
                    value: String(
                        format: NSLocalizedString("settings.chatStorage.usage.messagesCount", comment: ""),
                        breakdown.messageCount
                    )
                )
                usageRow(
                    title: NSLocalizedString("settings.chatStorage.usage.media", comment: ""),
                    value: formatBytes(breakdown.totalMediaBytes)
                )
            }
        }
    }

    private var preferencesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("settings.chatStorage.preferences.title", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.chatStorage.autoDownload.title", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(primaryText)
                    Picker("", selection: $autoDownload) {
                        ForEach(ChatMediaAutoDownload.allCases) { option in
                            Text(NSLocalizedString(option.titleKey, comment: "")).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: autoDownload) { _, newValue in
                        ChatMediaDownloadPolicy.autoDownload = newValue
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("settings.chatStorage.retention.title", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(primaryText)
                    Picker("", selection: $retention) {
                        ForEach(ChatMediaRetention.allCases) { option in
                            Text(NSLocalizedString(option.titleKey, comment: "")).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: retention) { _, newValue in
                        ChatMediaDownloadPolicy.retention = newValue
                        ChatCacheStore.enforceRetention()
                        refreshUsage()
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        settingsCard {
            VStack(spacing: 0) {
                actionButton(
                    title: NSLocalizedString("settings.chatStorage.clearMedia.action", comment: ""),
                    subtitle: NSLocalizedString("settings.chatStorage.clearMedia.subtitle", comment: ""),
                    destructive: false
                ) {
                    showClearMediaConfirm = true
                }

                Divider()
                    .opacity(colorScheme == .dark ? 0.22 : 0.16)
                    .padding(.leading, 4)

                actionButton(
                    title: NSLocalizedString("settings.chatStorage.clearAll.action", comment: ""),
                    subtitle: NSLocalizedString("settings.chatStorage.clearAll.subtitle", comment: ""),
                    destructive: true
                ) {
                    showClearAllConfirm = true
                }
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
    }

    private func usageRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(primaryText)
        }
        .font(.system(size: 14))
    }

    private func actionButton(
        title: String,
        subtitle: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? .red : primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func refreshUsage() {
        breakdown = ChatCacheStore.storageBreakdown()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
