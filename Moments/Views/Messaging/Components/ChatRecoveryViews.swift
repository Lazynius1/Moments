import SwiftUI

struct ChatRecoveryGateView<Content: View>: View {
    let onCancel: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @ObservedObject private var accessCoordinator = ChatAccessCoordinator.shared
    @State private var refreshToken = UUID()

    private var resolvedAccessState: ChatAccessState? {
        accessCoordinator.accessState
    }

    var body: some View {
        Group {
            switch resolvedAccessState {
            case .available:
                content()
            case .needsPinSetup:
                CreateChatPINView(
                    onSuccess: reloadState,
                    onCancel: onCancel
                )
            case .needsRestore:
                RestoreChatPINView(
                    onSuccess: reloadState,
                    onCancel: onCancel
                )
            case .unavailable(let message):
                ChatRecoveryStatusView(
                    title: NSLocalizedString("chatRecovery.unavailable.title", comment: "Chat unavailable"),
                    message: message,
                    primaryTitle: NSLocalizedString("chatRecovery.action.retry", comment: "Retry"),
                    primaryAction: reloadState,
                    secondaryTitle: onCancel == nil ? nil : NSLocalizedString("chatRecovery.action.close", comment: "Close"),
                    secondaryAction: onCancel
                )
            case .none:
                ProgressView(NSLocalizedString("chatRecovery.loading", comment: "Preparing chat security"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ChatRecoveryBackdrop())
            }
        }
        .task(id: refreshToken) {
            _ = await accessCoordinator.ensureAccess()
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }

    private func reloadState() {
        Task {
            await accessCoordinator.refreshAccess()
        }
    }
}

private struct ChatRecoveryPalette {
    let colorScheme: ColorScheme

    var title: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.88)
    }

    var body: Color {
        colorScheme == .dark ? Color.white.opacity(0.74) : Color.black.opacity(0.62)
    }

    var secondary: Color {
        colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.46)
    }

    var mutedAction: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.64)
    }

    var error: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.53, blue: 0.53) : Color(red: 0.73, green: 0.17, blue: 0.17)
    }

    var digitText: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.86)
    }

    var digitFillFilled: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    var digitFillEmpty: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    var digitBorderFocused: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.42)
    }

    var digitBorderFilled: Color {
        colorScheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.22)
    }

    var digitBorderEmpty: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }
}

struct ChatRecoverySettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showChangePIN = false
    @State private var isRemovingLocalKey = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(NSLocalizedString("chatRecovery.settings.description", comment: "Chat recovery description"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }

                Section {
                    Button(NSLocalizedString("chatRecovery.settings.changePin", comment: "Change recovery PIN")) {
                        showChangePIN = true
                    }

                    Button(isRemovingLocalKey ? NSLocalizedString("chatRecovery.settings.removingLocalKey", comment: "Removing local key") : NSLocalizedString("chatRecovery.settings.forceRestore", comment: "Force restore on this device")) {
                        forceRestoreOnThisDevice()
                    }
                    .disabled(isRemovingLocalKey)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("chatRecovery.settings.title", comment: "Chat recovery"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button(NSLocalizedString("chatRecovery.action.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showChangePIN) {
                CreateChatPINView(
                    isChangeFlow: true,
                    onSuccess: {
                        statusMessage = NSLocalizedString("chatRecovery.settings.updated", comment: "Recovery PIN updated")
                        showChangePIN = false
                    },
                    onCancel: {
                        showChangePIN = false
                    }
                )
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private func forceRestoreOnThisDevice() {
        isRemovingLocalKey = true

        Task {
            defer { isRemovingLocalKey = false }

            do {
                try await EncryptionService.shared.removeLocalChatIdentity()
                statusMessage = NSLocalizedString("chatRecovery.settings.localKeyRemoved", comment: "Local chat key removed")
                await ChatAccessCoordinator.shared.refreshAccess()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

private struct CreateChatPINView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let pinLength = 6
    let isChangeFlow: Bool
    let onSuccess: () -> Void
    let onCancel: (() -> Void)?

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var activeField: ChatRecoveryPINField.Kind = .primary

    init(
        isChangeFlow: Bool = false,
        onSuccess: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.isChangeFlow = isChangeFlow
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)

        ChatRecoveryFormContainer(
            title: isChangeFlow ? NSLocalizedString("chatRecovery.create.changeTitle", comment: "Change chat recovery PIN") : NSLocalizedString("chatRecovery.create.title", comment: "Set up your chat recovery PIN"),
            subtitle: NSLocalizedString("chatRecovery.create.subtitle", comment: "Create recovery PIN subtitle")
        ) {
            ChatRecoveryPINField(
                title: NSLocalizedString("chatRecovery.field.createPin", comment: "Create PIN"),
                subtitle: NSLocalizedString("chatRecovery.field.sixDigits", comment: "6 digits"),
                text: $pin,
                length: pinLength,
                kind: .primary,
                activeField: $activeField
            )

            ChatRecoveryPINField(
                title: NSLocalizedString("chatRecovery.field.confirmPin", comment: "Confirm PIN"),
                subtitle: NSLocalizedString("chatRecovery.field.repeatSixDigits", comment: "Repeat the same 6 digits"),
                text: $confirmPIN,
                length: pinLength,
                kind: .confirmation,
                activeField: $activeField
            )
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(isSubmitting ? NSLocalizedString("chatRecovery.action.saving", comment: "Saving") : (isChangeFlow ? NSLocalizedString("chatRecovery.action.updatePin", comment: "Update PIN") : NSLocalizedString("chatRecovery.action.savePin", comment: "Save PIN"))) {
                submit()
            }
            .buttonStyle(ChatRecoveryPrimaryButtonStyle())
            .disabled(isSubmitting)

            if let onCancel {
                Button(NSLocalizedString("chatRecovery.action.notNow", comment: "Not now")) {
                    onCancel()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(palette.mutedAction)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            activeField = .primary
        }
        .onChange(of: pin) { _, newValue in
            if newValue.count == pinLength && activeField == .primary {
                activeField = .confirmation
            }
        }
    }

    private func submit() {
        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirmPIN = confirmPIN.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidPIN(trimmedPIN, length: pinLength) else {
            errorMessage = NSLocalizedString("chatRecovery.error.invalidLength", comment: "Use exactly 6 digits")
            return
        }

        guard trimmedPIN == trimmedConfirmPIN else {
            errorMessage = NSLocalizedString("chatRecovery.error.mismatch", comment: "The PINs do not match")
            return
        }

        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                try await EncryptionService.shared.createRecoveryBundle(pin: trimmedPIN)
                pin = ""
                confirmPIN = ""
                onSuccess()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RestoreChatPINView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let pinLength = 6
    let onSuccess: () -> Void
    let onCancel: (() -> Void)?

    @State private var pin = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var activeField: ChatRecoveryPINField.Kind = .primary
    @State private var attemptState = ChatRecoveryAttemptState()
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)

        ChatRecoveryFormContainer(
            title: NSLocalizedString("chatRecovery.restore.title", comment: "Restore your chats"),
            subtitle: NSLocalizedString("chatRecovery.restore.subtitle", comment: "Restore subtitle")
        ) {
            ChatRecoveryPINField(
                title: NSLocalizedString("chatRecovery.field.recoveryPin", comment: "Recovery PIN"),
                subtitle: NSLocalizedString("chatRecovery.field.sixDigits", comment: "6 digits"),
                text: $pin,
                length: pinLength,
                kind: .primary,
                activeField: $activeField
            )

            if let visibleMessage {
                Text(visibleMessage)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .monospacedDigit()
            }
        } footer: {
            Button(primaryActionTitle) {
                restore()
            }
            .buttonStyle(ChatRecoveryPrimaryButtonStyle())
            .disabled(isSubmitting || attemptState.isLocked)

            if let onCancel {
                Button(NSLocalizedString("chatRecovery.action.close", comment: "Close")) {
                    onCancel()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(palette.mutedAction)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            activeField = .primary
            currentTime = Date()
            refreshAttemptState()
        }
        .onReceive(timer) { _ in
            currentTime = Date()

            guard attemptState.isLocked else { return }

            if countdownRemaining == nil {
                refreshAttemptState()
            }
        }
    }

    private func restore() {
        refreshAttemptState()

        guard !attemptState.isLocked else {
            return
        }

        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPIN(trimmedPIN, length: pinLength) else {
            errorMessage = NSLocalizedString("chatRecovery.error.enterRecoveryPin", comment: "Enter your 6-digit recovery PIN")
            return
        }

        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                try await EncryptionService.shared.restoreChatIdentity(pin: trimmedPIN)
                pin = ""
                refreshAttemptState()
                onSuccess()
            } catch {
                refreshAttemptState()
                errorMessage = error.localizedDescription
            }
        }
    }

    private var visibleMessage: String? {
        if let countdownRemaining {
            return String(
                format: NSLocalizedString("chatRecovery.error.lockedTimer", comment: "Recovery locked timer"),
                formattedLockoutDuration(countdownRemaining)
            )
        }

        return errorMessage
    }

    private var primaryActionTitle: String {
        if isSubmitting {
            return NSLocalizedString("chatRecovery.action.restoring", comment: "Restoring")
        }

        if let countdownRemaining {
            return String(
                format: NSLocalizedString("chatRecovery.action.tryAgainIn", comment: "Try again in %@"),
                formattedLockoutDuration(countdownRemaining)
            )
        }

        return NSLocalizedString("chatRecovery.action.restoreChats", comment: "Restore chats")
    }

    private func refreshAttemptState() {
        attemptState = EncryptionService.shared.chatRecoveryAttemptState()
    }

    private var countdownRemaining: TimeInterval? {
        guard let lockedUntil = attemptState.lockedUntil else { return nil }
        let remaining = lockedUntil.timeIntervalSince(currentTime)
        return remaining > 0 ? remaining : nil
    }

    private func formattedLockoutDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(1, Int(interval.rounded(.up)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ChatRecoveryFormContainer<FormContent: View, FooterContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    @ViewBuilder let formContent: () -> FormContent
    @ViewBuilder let footerContent: () -> FooterContent

    init(
        title: String,
        subtitle: String,
        @ViewBuilder formContent: @escaping () -> FormContent,
        @ViewBuilder footer: @escaping () -> FooterContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.formContent = formContent
        self.footerContent = footer
    }

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)
        let cardBaseFill = colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.82)
        let cardMaterialOpacity = colorScheme == .dark ? 0.95 : 0.72
        let cardStroke = colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.72)
        let cardShadow = colorScheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.14)
        let grabberColor = colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.14)
        let lockGradient = colorScheme == .dark
            ? [Color.white.opacity(0.96), Color.white.opacity(0.68)]
            : [Color.black.opacity(0.82), Color.black.opacity(0.52)]

        ZStack(alignment: .bottom) {
            ChatRecoveryBackdrop()

            VStack(spacing: 0) {
                Capsule()
                    .fill(grabberColor)
                    .frame(width: 42, height: 5)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .center, spacing: 12) {
                        HStack {
                            Spacer()

                            Image(systemName: "lock.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: lockGradient,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            Spacer()
                        }

                        Text(title)
                            .font(.custom("Poppins-SemiBold", size: 28))
                            .foregroundColor(palette.title)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(subtitle)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        formContent()
                    }

                    footerContent()
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(cardBaseFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(cardMaterialOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(cardStroke, lineWidth: 1)
                    )
                    .shadow(color: cardShadow, radius: 24, x: 0, y: 16)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

private struct ChatRecoveryStatusView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)

        ZStack(alignment: .bottom) {
            ChatRecoveryBackdrop()

            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: 42, height: 5)
                    .padding(.top, 12)

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 24))
                    .foregroundColor(palette.title)

                Text(message)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(palette.body)
                    .multilineTextAlignment(.center)

                Button(primaryTitle) {
                    primaryAction()
                }
                .buttonStyle(ChatRecoveryPrimaryButtonStyle())

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle) {
                        secondaryAction()
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(palette.mutedAction)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

private struct ChatRecoveryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Poppins-SemiBold", size: 15))
            .foregroundColor(.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? 0.78 : 0.92),
                                Color.white.opacity(configuration.isPressed ? 0.58 : 0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

private struct ChatRecoveryPINField: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Kind: Hashable {
        case primary
        case confirmation
    }

    let title: String
    let subtitle: String
    @Binding var text: String
    let length: Int
    let kind: Kind
    @Binding var activeField: Kind

    @FocusState private var isFocused: Bool

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(palette.title)

                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(palette.secondary)
            }

            ZStack {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .foregroundColor(.clear)
                    .accentColor(.clear)
                    .focused($isFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: text) { _, newValue in
                        let filtered = filteredPIN(newValue, length: length)
                        if filtered != newValue {
                            text = filtered
                        }
                    }

                HStack(spacing: 10) {
                    ForEach(0..<length, id: \.self) { index in
                        ChatRecoveryDigitCell(
                            state: digitState(at: index),
                            isFocused: activeField == kind && isFocused && text.count == index,
                            palette: palette
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                activeField = kind
                isFocused = true
            }
        }
        .onAppear {
            if activeField == kind {
                isFocused = true
            }
        }
        .onChange(of: activeField) { _, newValue in
            isFocused = newValue == kind
        }
    }

    private func digitState(at index: Int) -> ChatRecoveryDigitCell.State {
        if index < text.count {
            return .filled
        }
        return .empty
    }
}

private struct ChatRecoveryDigitCell: View {
    enum State {
        case empty
        case filled
    }

    let state: State
    let isFocused: Bool
    let palette: ChatRecoveryPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(state == .filled ? palette.digitFillFilled : palette.digitFillEmpty)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
                )
                .frame(width: 48, height: 60)

            Text(state == .filled ? "*" : "")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(palette.digitText)
                .offset(y: 3)
        }
    }

    private var borderColor: Color {
        if isFocused {
            return palette.digitBorderFocused
        }

        switch state {
        case .empty:
            return palette.digitBorderEmpty
        case .filled:
            return palette.digitBorderFilled
        }
    }
}

private struct ChatRecoveryBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}

private func filteredPIN(_ text: String, length: Int) -> String {
    String(text.filter(\.isNumber).prefix(length))
}

private func isValidPIN(_ pin: String, length: Int) -> Bool {
    pin.count == length && pin.allSatisfy(\.isNumber)
}
