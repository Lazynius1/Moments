import SwiftUI
import FirebaseAuth

struct PersonalInfoView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String

    private enum ViewState {
        case main
        case username
    }

    // Username change state
    @State private var viewState: ViewState = .main
    @State private var lastUsernameChange: Date? = nil
    private let firestoreService = FirestoreService()

    // Cooldown helpers
    private var canChangeUsername: Bool {
        guard let last = lastUsernameChange else { return true }
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return last <= sixMonthsAgo
    }

    private var nextAvailableDate: String? {
        guard let last = lastUsernameChange, !canChangeUsername else { return nil }
        let next = Calendar.current.date(byAdding: .month, value: 6, to: last) ?? Date()
        return MomentsFormat.smartDate(from: next, context: .longDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ZStack {
                    switch viewState {
                    case .main:
                        personalInfoMainContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                    case .username:
                        UsernameChangeContent(
                            currentUsername: $username,
                            lastUsernameChange: $lastUsernameChange,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    viewState = .main
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewState)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewState == .username {
                    ToolbarItem(placement: .navigationBarLeading) {
                        SettingsToolbarBackButton(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                viewState = .main
                            }
                        })
                    }
                }
            }
        }
        .onAppear {
            // Load lastUsernameChange from Firestore
            if let uid = Auth.auth().currentUser?.uid {
                firestoreService.fetchUser(userId: uid) { result in
                    if case .success(let user) = result {
                        lastUsernameChange = user.lastUsernameChange
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch viewState {
        case .main:
            return NSLocalizedString("settings.sections.personalInfo", comment: "Personal Information")
        case .username:
            return NSLocalizedString("username.change.title", comment: "Change username title")
        }
    }

    private var personalInfoMainContent: some View {
        VStack(spacing: 0) {
            Button(action: {
                guard canChangeUsername else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    viewState = .username
                }
            }) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("settings.profile.username", comment: "Username label"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        if let nextDate = nextAvailableDate {
                            Text(String(format: NSLocalizedString("username.availableOn", comment: "Available on %@"), nextDate))
                                .font(.system(size: legacyPoppinsSize(12)))
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 12)

                    Text("@\(username.isEmpty ? "—" : username)")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.gray)
                        .lineLimit(1)

                    if canChangeUsername {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.gray.opacity(0.3))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)
            .padding(.bottom, 10)

            Divider()
                .opacity(0.2)
                .padding(.leading, 2)
                .padding(.vertical, 4)

            HStack(spacing: 14) {
                Text(NSLocalizedString("settings.profile.email", comment: "Email label"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer(minLength: 12)

                Text(email.isEmpty ? NSLocalizedString("settings.notConfigured", comment: "Not configured") : email)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Username Change Sheet
struct UsernameChangeContent: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var currentUsername: String
    @Binding var lastUsernameChange: Date?
    let onBack: (() -> Void)?

    @State private var newUsername: String = ""
    @State private var isChecking: Bool = false
    @State private var isAvailable: Bool? = nil
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var checkTask: Task<Void, Never>? = nil

    private let firestoreService = FirestoreService()

    private var isValidFormat: Bool {
        let clean = newUsername.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return clean.count >= 3 && clean.count <= 30 && clean.unicodeScalars.allSatisfy({ allowed.contains($0) })
    }

    private var isDifferent: Bool {
        newUsername.lowercased() != currentUsername.lowercased()
    }

    private var canSave: Bool {
        isValidFormat && isDifferent && isAvailable == true && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("username.change.title", comment: "Change username title"))
                        .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("username.change.subtitle", comment: "Can be changed every 6 months"))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("@")
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField(currentUsername, text: $newUsername)
                            .font(.system(size: legacyPoppinsSize(17)))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: newUsername) { _, _ in
                                triggerAvailabilityCheck()
                            }

                        Spacer()

                        if isChecking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if newUsername.count >= 3 && isDifferent {
                            if let available = isAvailable {
                                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(available ? .green : .red)
                                    .font(.system(size: 20))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(borderColor, lineWidth: 1.5)
                            )
                    )

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(.red)
                    } else if newUsername.count >= 3 && isDifferent, let available = isAvailable {
                        Text(available
                             ? NSLocalizedString("username.available", comment: "Username available")
                             : NSLocalizedString("username.taken", comment: "Username taken"))
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(available ? .green : .red)
                    } else {
                        Text(NSLocalizedString("username.rules", comment: "3-30 chars, letters, numbers and _"))
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 4)
                        }
                        Text(NSLocalizedString("username.change.save", comment: "Save username"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canSave ? Color.primary : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(canSave ? (colorScheme == .dark ? .black : .white) : .gray)
                }
                .disabled(!canSave)
                .animation(.easeInOut(duration: 0.2), value: canSave)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var borderColor: Color {
        if let available = isAvailable, newUsername.count >= 3 && isDifferent {
            return available ? Color.green.opacity(0.6) : Color.red.opacity(0.6)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4)
    }

    private func triggerAvailabilityCheck() {
        isAvailable = nil
        errorMessage = nil
        checkTask?.cancel()
        let username = newUsername.lowercased()
        guard username.count >= 3 && isDifferent else { return }
        isChecking = true
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            guard !Task.isCancelled else { return }
            let snap = try? await firestoreService.db
                .collection("usernames")
                .document(username)
                .getDocument()
            await MainActor.run {
                isChecking = false
                isAvailable = !(snap?.exists ?? false)
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let oldUsernameLower = currentUsername.lowercased()
        isSaving = true
        errorMessage = nil
        firestoreService.changeUsername(userId: uid, oldUsername: currentUsername, newUsername: newUsername) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    let newUsernameLower = newUsername.lowercased()
                    currentUsername = newUsernameLower
                    lastUsernameChange = Date()
                    if let email = Auth.auth().currentUser?.email {
                        UserDefaults.standard.set(email, forKey: "cachedEmail_\(newUsernameLower)")
                    }
                    UserDefaults.standard.removeObject(forKey: "cachedEmail_\(oldUsernameLower)")
                    UserDefaults.standard.set(newUsernameLower, forKey: "current_username")
                    onBack?()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
