import SwiftUI

struct IncognitoModeSheet: View {
    @ObservedObject var service: IncognitoModeService
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("incognito_has_seen_inline_onboarding") private var hasSeenOnboarding = false

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "3BA4FF"), Color(hex: "6E8BFF"), Color(hex: "90E0EF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var onboardingBackgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var onboardingBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    private var primaryActionKey: String {
        if service.isSyncing {
            return "incognito.cta.syncing"
        }
        if !networkMonitor.isConnected {
            return "incognito.cta.offline"
        }
        if service.isExhausted {
            return "incognito.cta.exhausted"
        }
        return service.isActive ? "incognito.cta.pause" : (service.remainingSeconds == service.dailyBudgetSeconds ? "incognito.cta.activate" : "incognito.cta.resume")
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    header
                    hero
                    actions
                    details
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)

            if !hasSeenOnboarding {
                onboardingOverlay
                    .padding(.horizontal, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .presentationDetents([.fraction(0.64), .large])
        .presentationDragIndicator(.visible)
        .task {
            if !service.isLoaded {
                service.loadState()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: hasSeenOnboarding)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("incognito.title")
                .font(.custom("Poppins-SemiBold", size: 28))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)

            Text("incognito.subtitle")
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.14), lineWidth: 10)
                    .frame(width: 156, height: 156)

                Circle()
                    .trim(from: 0, to: max(service.progress, 0.0001))
                    .stroke(accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 156, height: 156)

                VStack(spacing: 6) {
                    Image(systemName: service.isActive ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconColor)

                    Text(service.formattedTime)
                        .font(.custom("Poppins-SemiBold", size: 30))
                        .monospacedDigit()
                        .foregroundStyle(titleColor)

                    Text(LocalizedStringKey(statusKey))
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorKey {
                Text(LocalizedStringKey(errorKey))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.isActive {
                Text("incognito.liveHint.active")
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if service.remainingSeconds < service.dailyBudgetSeconds {
                Text("incognito.liveHint.paused")
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 10) {
                    if service.isSyncing {
                        ProgressView()
                            .tint(titleColor)
                    } else {
                        Image(systemName: primarySymbol)
                            .font(.system(size: 14, weight: .semibold))
                    }

                    Text(LocalizedStringKey(primaryActionKey))
                        .font(.custom("Poppins-SemiBold", size: 15))
                }
                .foregroundStyle(titleColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: primaryActionEnabled))
            }
            .buttonStyle(.plain)
            .disabled(!primaryActionEnabled)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailRow(
                icon: "circle.dashed.inset.filled",
                titleKey: "incognito.feature.stories.title",
                bodyKey: "incognito.feature.stories.body"
            )

            detailRow(
                icon: "person.crop.circle.badge.checkmark",
                titleKey: "incognito.feature.visits.title",
                bodyKey: "incognito.feature.visits.body"
            )

            detailRow(
                icon: "message.badge.waveform",
                titleKey: "incognito.feature.readReceipts.title",
                bodyKey: "incognito.feature.readReceipts.body"
            )
        }
        .padding(.top, 4)
    }

    private var onboardingOverlay: some View {
        VStack {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColor)

                    Text("incognito.onboarding.title")
                        .font(.custom("Poppins-SemiBold", size: 24))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.center)

                    Text("incognito.onboarding.body")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 11) {
                    onboardingBullet("incognito.onboarding.bullet.one")
                    onboardingBullet("incognito.onboarding.bullet.two")
                    onboardingBullet("incognito.onboarding.bullet.three")
                }

                Button {
                    hasSeenOnboarding = true
                    HapticManager.shared.selection()
                } label: {
                    Text("incognito.onboarding.dismiss")
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundStyle(titleColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(onboardingBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(onboardingBorderColor, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.24) : .black.opacity(0.10),
                radius: 24,
                x: 0,
                y: 10
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func onboardingBullet(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(iconColor.opacity(colorScheme == .dark ? 0.92 : 0.86))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(LocalizedStringKey(key))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailRow(icon: String, titleKey: String, bodyKey: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(titleKey))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundStyle(titleColor)

                Text(LocalizedStringKey(bodyKey))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func handlePrimaryAction() {
        guard primaryActionEnabled else { return }

        if service.isActive {
            service.pause()
        } else if service.remainingSeconds == service.dailyBudgetSeconds {
            service.activate()
        } else {
            service.resume()
        }
    }

    private var primaryActionEnabled: Bool {
        !service.isSyncing && networkMonitor.isConnected && !service.isExhausted
    }

    private var primarySymbol: String {
        if !networkMonitor.isConnected {
            return "wifi.slash"
        }
        if service.isExhausted {
            return "eye"
        }
        return service.isActive ? "eye.slash.fill" : "eye"
    }

    private var statusKey: String {
        if service.isSyncing {
            return "incognito.status.syncing"
        }
        if service.isExhausted {
            return "incognito.status.exhausted"
        }
        return service.isActive ? "incognito.status.active" : "incognito.status.paused"
    }

    private var errorKey: String? {
        switch service.lastErrorState {
        case .offline:
            return "incognito.error.offline"
        case .exhausted:
            return "incognito.error.exhausted"
        case .unavailable:
            return "incognito.error.unavailable"
        case .unauthorized:
            return "incognito.error.unauthorized"
        case .unknown:
            return "incognito.error.unavailable"
        case nil:
            return nil
        }
    }
}
