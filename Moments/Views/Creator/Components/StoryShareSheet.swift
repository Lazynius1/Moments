import SwiftUI

struct StoryShareSheet: View {
    let preview: UIImage?
    let audienceTitle: String
    let audience: ContentAudience
    let isChain: Bool
    let chainTitle: String
    let isPublishing: Bool
    var hasAudio = false
    var hasOriginalAudio = false
    var canShareOriginalAudio = false
    @Binding var allowOriginalAudioReuse: Bool
    @Binding var expirationHours: Int
    @Binding var allowMessages: Bool
    @Binding var allowReactions: Bool
    @Binding var allowEphemeralPhotos: Bool
    let onAudience: () -> Void
    let onChainSettings: () -> Void
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("storyShare.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("storyShare.close"))
                            .disabled(isPublishing)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    shareButton
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
        }
        .tint(Color.primary)
        .interactiveDismissDisabled(isPublishing)
    }

    @ViewBuilder private var content: some View {
        if #available(iOS 26.0, *) {
            shareForm.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            shareForm
        }
    }

    private var shareForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                previewHeader.padding(.top, 12).padding(.bottom, 22)
                Button(action: onAudience) {
                    HStack(spacing: 12) {
                        AudienceIconView(audience: audience, size: AudienceIconMetrics.storyCapsule, colorScheme: colorScheme)
                            .frame(width: 22, height: 22)
                        Text("storyShare.audience")
                        Spacer(minLength: 8)
                        Text(audienceTitle).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        if !isChain { rowChevron }
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isChain || isPublishing)
                Divider()
                HStack(spacing: 12) {
                    rowIcon("clock")
                    Text("storyShare.expiration")
                    Spacer()
                    if isChain {
                        Text("48 h").foregroundStyle(.secondary)
                    } else {
                        Picker("storyShare.expiration", selection: $expirationHours) {
                            Text("24 h").tag(24)
                            Text("48 h").tag(48)
                        }.labelsHidden().pickerStyle(.menu)
                    }
                }
                .frame(minHeight: 60)
                .disabled(isChain || isPublishing)
                .opacity(isChain ? 0.4 : 1)
                Divider()
                if isChain {
                    Button(action: onChainSettings) {
                        HStack(spacing: 12) {
                            rowIcon("link")
                            Text("storyShare.chainSettings")
                            Spacer()
                            rowChevron
                        }.frame(minHeight: 60).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
                NavigationLink {
                    interactionsForm
                } label: {
                    HStack(spacing: 12) {
                        rowIcon("bubble.left.and.bubble.right")
                        Text("storyShare.interactions")
                        Spacer(minLength: 8)
                        Text(allowMessages || allowReactions || allowEphemeralPhotos ? "storyShare.customize" : "storyShare.disabled")
                            .font(.subheadline).foregroundStyle(.secondary)
                        rowChevron
                    }.frame(minHeight: 60).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if hasOriginalAudio {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("story.audio.allowReuse", isOn: Binding(
                            get: { canShareOriginalAudio && allowOriginalAudioReuse },
                            set: { allowOriginalAudioReuse = $0 }
                        ))
                            .tint(SettingsProfileColors.toggleTint)
                            .disabled(!canShareOriginalAudio)
                        Text(canShareOriginalAudio ? "story.audio.allowReuse.detail" : "story.audio.restricted.audience")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                }
                Text(isChain ? "storyShare.chainAudience" : "storyShare.onlyThisStory")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.bottom, 20)
            }
            .disabled(isPublishing)
            .padding(.horizontal, 24)
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 20) {
            Group {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(0.06))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 100, height: 160)
            .clipShape(.rect(cornerRadius: 17))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(isChain ? chainTitle : NSLocalizedString("storyShare.yourStory", comment: "Your story"))
                    .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text("storyShare.review").font(.subheadline).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { previewBadges }
                    VStack(alignment: .leading, spacing: 8) { previewBadges }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var previewBadges: some View {
        Label("\(isChain ? 48 : expirationHours) h", systemImage: "clock")
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        if hasAudio || hasOriginalAudio {
            Label("story.audio.title", systemImage: "waveform")
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        }
    }

    private var interactionsForm: some View {
        Form {
            Section {
                Toggle("contentVisibility.interactions.messages.title", isOn: $allowMessages)
                    .tint(SettingsProfileColors.toggleTint)
                Toggle("contentVisibility.interactions.reactions.title", isOn: $allowReactions)
                    .tint(SettingsProfileColors.toggleTint)
                Toggle("contentVisibility.interactions.ephemeralPhotos.title", isOn: $allowEphemeralPhotos)
                    .tint(SettingsProfileColors.toggleTint)
            } footer: {
                Text("storyShare.onlyThisStory")
            }
        }
        .disabled(isPublishing)
        .navigationTitle("storyShare.interactions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).frame(width: 22, height: 22)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder private var shareButton: some View {
        if #available(iOS 26.0, *) {
            buttonContent.buttonStyle(.glassProminent)
                .tint(colorScheme == .dark ? Color.white : Color(hex: "0B1215"))
        } else {
            buttonContent.buttonStyle(.borderedProminent)
                .tint(colorScheme == .dark ? Color.white : Color(hex: "0B1215"))
        }
    }

    private var buttonContent: some View {
        Button(action: onShare) {
            HStack {
                if isPublishing { ProgressView() }
                Text("storyEditor.share")
                Image(systemName: "arrow.up")
            }
            .font(.headline)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isPublishing)
    }
}
