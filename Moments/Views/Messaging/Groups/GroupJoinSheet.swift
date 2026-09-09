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
            ScrollView {
                VStack(spacing: 24) {
                    GroupJoinSheetHeader(phase: store.phase, name: store.name, image: store.image,
                        requiresApproval: store.requiresApproval, errorTitle: store.errorTitle, errorBody: store.errorBody)
                    GroupJoinSheetActions(phase: store.phase, busy: store.busy, requiresApproval: store.requiresApproval,
                        onSubmit: { Task { await store.submit() } },
                        onRetry: { Task { await store.retry() } },
                        onCancel: { Task { await store.cancel() } },
                        onClose: { dismiss() },
                        onRequests: { dismiss(); onViewRequests() })
                }.padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32).background(.primary.opacity(0.06), in: Circle())
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(sheetCopy("sheet.close"))
                    .padding(.top, 10).padding(.trailing, 14)
            }
            .task(id: link.id) { await store.load(link) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onChange(of: store.joined) { _, joined in
            if joined { dismiss(); onJoined() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshPending() } }
        }
        .onDisappear { store.stop() }
        .modifier(GroupJoinSheetBackground())
    }
}

private struct GroupJoinSheetBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content }
        else { content.presentationBackground(AdaptiveColors(colorScheme: colorScheme).surfaceBackground) }
    }
}

private struct GroupJoinSheetHeader: View {
    let phase: GroupJoinSheetPhase
    let name: String
    let image: String
    let requiresApproval: Bool
    let errorTitle: String
    let errorBody: String
    private var title: String {
        switch phase {
        case .loading: return sheetCopy("sheet.loadingTitle")
        case .sent: return sheetCopy("sheet.sentTitle")
        case .pending: return sheetCopy("sheet.pendingTitle")
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
        case .error: return errorBody
        case .unavailable: return "sheet.unavailableBody"
        case .full: return "sheet.fullBody"
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            GroupJoinSheetGraphic(phase: phase, name: name, image: image)
                .frame(height: 112).padding(.bottom, 4)
            Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if phase == .sent || phase == .pending {
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
            GroupChatAvatar(name: name, image: image, size: 104)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "clock").font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary).padding(5)
                        .background(Color(uiColor: .systemBackground), in: Circle())
                }.accessibilityHidden(true)
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
                Button(sheetCopy("sheet.viewRequests"), action: onRequests).frame(minHeight: 44)
            case .pending:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.viewRequests"), action: onRequests).disabled(busy)
                Button(action: onCancel) {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(sheetCopy(busy ? "sheet.cancelling" : "requestsCancel"))
                    }.frame(minHeight: 44)
                }.disabled(busy)
            case .error:
                GroupJoinSheetPrimaryButton(title: sheetCopy("requestsRetry"), action: onRetry)
                Button(sheetCopy("sheet.close"), action: onClose).frame(minHeight: 44)
            case .unavailable, .full:
                GroupJoinSheetPrimaryButton(title: sheetCopy("sheet.done"), action: onClose)
            }
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }
}

private struct GroupJoinSheetPrimaryButton: View {
    let title: String
    var loading = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().tint(colorScheme == .dark ? .black : .white) }
                Text(title).font(.body.weight(.semibold)).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 16)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .background(Color.primary.opacity(loading ? 0.35 : 1), in: Capsule())
        }.buttonStyle(.plain).disabled(loading)
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
