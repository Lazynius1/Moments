import SwiftUI
import Lottie

private func sheetCopy(_ key: String) -> String { NSLocalizedString("groups." + key, comment: "Group invitation sheet") }

struct GroupJoinLinkView: View {
    let link: GroupInviteLink
    let onJoined: () -> Void
    let onViewRequests: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = GroupJoinSheetStore()

    var body: some View {
        ChatRecoveryGateView(onCancel: { dismiss() }) {
            GroupJoinSheetLayout {
                GroupJoinSheetHeader(phase: store.phase, name: store.name, image: store.image,
                    requiresApproval: store.requiresApproval, errorTitle: store.errorTitle, errorBody: store.errorBody)
            } actions: {
                GroupJoinSheetActions(phase: store.phase, busy: store.busy, requiresApproval: store.requiresApproval,
                    onSubmit: { Task { await store.submit() } },
                    onRetry: { Task { await store.retry() } },
                    onCancel: { Task { await store.cancel() } },
                    onClose: { dismiss() },
                    onOpenChat: { dismiss(); onJoined() },
                    onRequests: { dismiss(); onViewRequests() })
            }
            .task(id: link.id) { await store.load(link) }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onChange(of: store.joined) { _, joined in
            if joined { dismiss(); onJoined() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshPending() } }
        }
        .onDisappear { store.stop() }
    }
}

/// The body scrolls independently; actions stay at the bottom of the medium sheet.
private struct GroupJoinSheetLayout<Header: View, Actions: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                header().frame(maxWidth: .infinity)
                    .padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            actions().padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}

private struct GroupJoinSheetHeader: View {
    let phase: GroupJoinSheetPhase
    let name: String
    let image: String
    let requiresApproval: Bool
    let errorTitle: String
    let errorBody: String
    @Environment(\.colorScheme) private var colorScheme
    private var title: String {
        switch phase {
        case .loading: return sheetCopy("sheet.loadingTitle")
        case .sent: return sheetCopy("sheet.sentTitle")
        case .pending: return sheetCopy("sheet.pendingTitle")
        case .alreadyMember: return sheetCopy("sheet.alreadyTitle")
        case .error: return sheetCopy(errorTitle)
        case .unavailable: return sheetCopy("sheet.unavailableTitle")
        case .full: return sheetCopy("sheet.fullTitle")
        default: return name
        }
    }
    private var bodyKey: String {
        switch phase {
        case .loading: return "sheet.loadingBody"
        case .direct: return "sheet.directBody"
        case .approval: return "sheet.approvalBody"
        case .sending: return requiresApproval ? "sheet.sendingBody" : "sheet.joiningBody"
        case .sent: return "sheet.sentBody"
        case .pending: return "sheet.pendingBody"
        case .alreadyMember: return "sheet.alreadyBody"
        case .error: return errorBody
        case .unavailable: return "sheet.unavailableBody"
        case .full: return "sheet.fullBody"
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            GroupJoinSheetGraphic(phase: phase, name: name, image: image)
                .frame(height: 112).padding(.bottom, 4)
            Text(title).font(.title2.weight(.bold)).foregroundStyle(AdaptiveColors(colorScheme: colorScheme).primary).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if phase == .sent || phase == .pending || phase == .alreadyMember {
                Text(name).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text(sheetCopy(bodyKey)).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
}

private struct GroupJoinSheetGraphic: View {
    let phase: GroupJoinSheetPhase
    let name: String
    let image: String
    var body: some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.large).accessibilityHidden(true)
        case .sent:
            GroupRequestSentAnimation()
        case .pending:
            // ≡ SocialConnectionUserRow: Circle opaco + reversedMask; el waiting es solo el glifo (sin badge circular).
            ZStack(alignment: .bottomTrailing) {
                GroupChatAvatar(name: name, image: image, size: 104)
                    .drawingGroup(opaque: false)
                    .reversedMask(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 33, height: 33)
                            .offset(x: 1.5, y: 1.5)
                    }
                AttachmentIconView(icon: .waiting, size: 30, tintColor: .secondary)
            }
            .accessibilityHidden(true)
        case .error, .unavailable, .full:
            Image(systemName: phase == .error ? "exclamationmark.circle" : (phase == .full ? "person.3" : "link"))
                .font(.system(size: 44, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
        default:
            GroupChatAvatar(name: name, image: image, size: 104).accessibilityHidden(true)
        }
    }
}

private struct GroupJoinSheetActions: View {
    let phase: GroupJoinSheetPhase
    let busy: Bool
    let requiresApproval: Bool
    let onSubmit: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onClose: () -> Void
    let onOpenChat: () -> Void
    let onRequests: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            switch phase {
            case .loading: EmptyView()
            case .direct, .approval:
                GroupJoinSheetPrimaryButton(title: sheetCopy(phase == .approval ? "sheet.requestAction" : "joinLink"), action: onSubmit)
                if phase == .approval {
                    Text(sheetCopy("sheet.approvalFooter")).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
            case .sending:
                GroupJoinSheetPrimaryButton(title: sheetCopy(requiresApproval ? "sheet.sendingAction" : "sheet.joiningAction"), loading: true, action: {})
            case .sent:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.done"), action: onClose)
                GroupJoinSheetSecondaryButton(title: sheetCopy("sheet.viewRequests"), action: onRequests)
            case .pending:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.viewRequests"), disabled: busy, action: onRequests)
                GroupJoinSheetSecondaryButton(
                    title: sheetCopy(busy ? "sheet.cancelling" : "requestsCancel"),
                    loading: busy,
                    disabled: busy,
                    action: onCancel
                )
            case .error:
                GroupJoinSheetPrimaryButton(title: sheetCopy("requestsRetry"), action: onRetry)
                GroupJoinSheetSecondaryButton(title: sheetCopy("sheet.close"), action: onClose)
            case .unavailable, .full:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.done"), action: onClose)
            case .alreadyMember:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.openChat"), action: onOpenChat)
                GroupJoinSheetSecondaryButton(title: sheetCopy("sheet.done"), action: onClose)
            }
        }
    }
}

private struct GroupJoinSheetPrimaryButton: View {
    let title: String
    var loading = false
    var disabled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().tint(colors.surfaceBackground) }
                Text(title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colors.surfaceBackground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(colors.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(loading || disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct GroupJoinSheetSecondaryButton: View {
    let title: String
    var loading = false
    var disabled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView() }
                Text(title)
            }
            .foregroundStyle(colors.primary)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct GroupRequestSentAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animation: LottieAnimation?
    @State private var finished = false
    var body: some View {
        Group {
            if !reduceMotion, !finished, let animation {
                LottieView(animation: animation)
                    .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
                    .animationDidFinish { completed in if completed { finished = true } }
                    .configure { view in
                        view.contentMode = .scaleAspectFit
                        view.backgroundBehavior = .pauseAndRestore
                        view.isOpaque = false; view.backgroundColor = .clear
                    }
                    .scaleEffect(1.35)
            } else {
                Image(systemName: "checkmark").font(.system(size: 56, weight: .semibold)).foregroundStyle(.blue)
            }
        }
        .frame(width: 112, height: 112).accessibilityHidden(true)
        .task {
            guard !reduceMotion, animation == nil else { return }
            for directory in ["Resources/Lottie", "Lottie", nil] as [String?] {
                if let url = Bundle.main.url(forResource: "group_join_request_sent", withExtension: "json", subdirectory: directory),
                   let loaded = LottieAnimation.filepath(url.path) { animation = loaded; return }
            }
            animation = LottieAnimation.named("group_join_request_sent")
        }
    }
}
