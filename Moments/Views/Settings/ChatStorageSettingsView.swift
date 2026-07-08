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
    @State private var conversationUsage: [ConversationStorageUsage] = []
    @State private var visibleCount = 10

    private struct ConversationStorageUsage: Identifiable {
        let id: String
        let userId: String
        let name: String
        let bytes: Int64
    }

    private var screenBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                summaryHeader

                if !conversationUsage.isEmpty {
                    manageStorageSection
                }

                preferencesSection
                actionsSection

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 24)
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

    // MARK: - Summary header (hero)
    private var summaryHeader: some View {
        let quota = ChatMediaDownloadPolicy.maxMediaBytes
        let used = breakdown.totalMediaBytes
        let fraction = quota > 0 ? min(1.0, Double(used) / Double(quota)) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text(formatBytes(used))
                .font(.system(size: legacyPoppinsSize(34), weight: .bold))
                .foregroundStyle(primaryText)
                .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(primaryText.opacity(0.1))
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: max(fraction > 0 ? 8 : 0, geo.size.width * fraction))
                }
            }
            .frame(height: 8)

            Text(String(
                format: NSLocalizedString("settings.chatStorage.summary.limit", comment: ""),
                formatBytes(quota)
            ))
            .font(.system(size: legacyPoppinsSize(13)))
            .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Manage storage (per conversation)
    private var manageStorageSection: some View {
        let visible = Array(conversationUsage.prefix(visibleCount))

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("settings.chatStorage.manage.title", comment: "").uppercased())
                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    .foregroundStyle(secondaryText.opacity(0.9))

                Text(NSLocalizedString("settings.chatStorage.manage.subtitle", comment: ""))
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(secondaryText)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, usage in
                    conversationRow(usage)

                    if index < visible.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }

            if conversationUsage.count > visibleCount {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visibleCount += 10
                    }
                } label: {
                    Text(NSLocalizedString("settings.chatStorage.manage.showMore", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func conversationRow(_ usage: ConversationStorageUsage) -> some View {
        HStack(spacing: 12) {
            StoryRingAvatarView(userId: usage.userId, size: 40, lineWidth: 2)

            Text(usage.name)
                .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                .foregroundStyle(primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(formatBytes(usage.bytes))
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundStyle(secondaryText)
                .monospacedDigit()

            Button {
                clearConversation(usage.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Preferences
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(NSLocalizedString("settings.chatStorage.preferences.title", comment: "").uppercased())
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundStyle(secondaryText.opacity(0.9))
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("settings.chatStorage.autoDownload.title", comment: ""))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
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
            .padding(.horizontal, 4)

            HStack {
                Text(NSLocalizedString("settings.chatStorage.retention.title", comment: ""))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(primaryText)

                Spacer()

                Picker("", selection: $retention) {
                    ForEach(ChatMediaRetention.allCases) { option in
                        Text(NSLocalizedString(option.titleKey, comment: "")).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(secondaryText)
                .onChange(of: retention) { _, newValue in
                    ChatMediaDownloadPolicy.retention = newValue
                    ChatCacheStore.enforceRetention()
                    refreshUsage()
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Clear actions
    private var actionsSection: some View {
        VStack(spacing: 0) {
            actionButton(
                title: NSLocalizedString("settings.chatStorage.clearMedia.action", comment: ""),
                subtitle: NSLocalizedString("settings.chatStorage.clearMedia.subtitle", comment: ""),
                destructive: false
            ) {
                showClearMediaConfirm = true
            }

            Divider().padding(.leading, 4)

            actionButton(
                title: NSLocalizedString("settings.chatStorage.clearAll.action", comment: ""),
                subtitle: NSLocalizedString("settings.chatStorage.clearAll.subtitle", comment: ""),
                destructive: true
            ) {
                showClearAllConfirm = true
            }
        }
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
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(destructive ? .red : primaryText)
                Text(subtitle)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshUsage() {
        breakdown = ChatCacheStore.storageBreakdown()

        let conversations = LocalPersistenceService.shared.loadConversations()
        let byId = Dictionary(conversations.compactMap { convo -> (String, Conversation)? in
            guard let id = convo.id else { return nil }
            return (id, convo)
        }, uniquingKeysWith: { first, _ in first })

        let bytesById = ChatCacheStore.bytesByConversation(for: Array(byId.keys))
        conversationUsage = bytesById
            .sorted { $0.value > $1.value }
            .map { id, bytes in
                let convo = byId[id]
                let name = convo?.otherParticipantUsername
                    ?? NSLocalizedString("common.user", value: "Usuario", comment: "Generic user fallback")
                return ConversationStorageUsage(
                    id: id,
                    userId: convo?.otherParticipantId ?? "",
                    name: name,
                    bytes: bytes
                )
            }
    }

    private func clearConversation(_ conversationId: String) {
        ChatCacheStore.deleteConversation(conversationId, messageIds: [])
        refreshUsage()
        statusMessage = NSLocalizedString("settings.chatStorage.clearMedia.done", comment: "")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
