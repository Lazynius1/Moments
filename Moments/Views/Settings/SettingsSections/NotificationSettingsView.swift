import SwiftUI

struct NotificationSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @State private var isSavingSchedule: Bool = false
    @State private var showSavedSchedule: Bool = false
    @State private var showScheduleError: Bool = false
    @State private var scheduleErrorMessage: String = ""

    var body: some View {
        ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.schedule.title", comment: "Notification Schedule"))
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .foregroundStyle(.gray)

                            notificationToggleRow(
                                title: NSLocalizedString("settings.notifications.schedule.enable", comment: "Set schedule"),
                                isOn: $isScheduleEnabled
                            )
                            .onChange(of: isScheduleEnabled) { _, enabled in
                                if !enabled {
                                    viewModel.clearActiveHours()
                                }
                            }

                            if isScheduleEnabled {
                                DatePicker(NSLocalizedString("settings.notifications.schedule.start", comment: "Start time"),
                                           selection: $startTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .font(.system(size: legacyPoppinsSize(14)))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .padding(.top, 2)

                                DatePicker(NSLocalizedString("settings.notifications.schedule.end", comment: "End time"),
                                           selection: $endTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .font(.system(size: legacyPoppinsSize(14)))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .padding(.top, 2)

                                Button(action: {
                                    guard !isSavingSchedule else { return }
                                    isSavingSchedule = true
                                    HapticManager.shared.lightImpact()
                                    viewModel.updateActiveHours(startTime: startTime, endTime: endTime) { error in
                                        DispatchQueue.main.async {
                                            isSavingSchedule = false
                                            if let error = error {
                                                HapticManager.shared.notification(.error)
                                                scheduleErrorMessage = error.localizedDescription
                                                showScheduleError = true
                                                return
                                            }

                                            HapticManager.shared.notification(.success)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                                showSavedSchedule = true
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    showSavedSchedule = false
                                                }
                                            }
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isSavingSchedule {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                                                .scaleEffect(0.85)
                                            Text(NSLocalizedString("settings.schedule.saving", comment: "Saving schedule"))
                                        } else {
                                            Image(systemName: "checkmark.circle")
                                            Text(NSLocalizedString("settings.schedule.save", comment: "Save schedule"))
                                        }
                                    }
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(colorScheme == .dark ? .black : .white).opacity(0.2))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(SettingsProfileColors.accentStroke(colorScheme, opacity: 0.5), lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .scaleEffect(isSavingSchedule ? 0.98 : 1.0)
                                    .animation(.easeInOut(duration: 0.15), value: isSavingSchedule)
                                }
                                .buttonStyle(SaveSchedulePressStyle())
                                .disabled(isSavingSchedule)
                                .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.types.title", comment: "Notification Types"))
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .foregroundStyle(.gray)

                            VStack(spacing: 0) {
                                ForEach(Array(NotificationType.allCases.filter { $0 != .gentleReminder }.enumerated()), id: \.element.rawValue) { index, type in
                                    notificationToggleRow(
                                        title: type.displayName,
                                        isOn: Binding(
                                            get: { viewModel.notificationPreferences[type.rawValue] ?? true },
                                            set: { viewModel.updateNotificationPreference(type: type.rawValue, isEnabled: $0) }
                                        )
                                    )

                                    if index < NotificationType.allCases.filter({ $0 != .gentleReminder }).count - 1 {
                                        Divider().padding(.leading, 4)
                                    }
                                }

                                Divider().padding(.leading, 4)

                                notificationToggleRow(
                                    title: NSLocalizedString("settings.notifications.gentleReminders.title", comment: "Gentle reminders"),
                                    isOn: Binding(
                                        get: { viewModel.notificationPreferences["gentleReminders"] ?? true },
                                        set: { viewModel.updateNotificationPreference(type: "gentleReminders", isEnabled: $0) }
                                    )
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.advanced.title", comment: "Advanced Settings"))
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .foregroundStyle(.gray)

                            VStack(spacing: 0) {
                                notificationToggleRow(
                                    title: NSLocalizedString("settings.notifications.mutualsOnly", comment: "Mutuals comments only"),
                                    isOn: Binding(
                                        get: { viewModel.notificationPreferences["commentsMutualsOnly"] ?? false },
                                        set: { viewModel.updateNotificationPreference(type: "commentsMutualsOnly", isEnabled: $0) }
                                    )
                                )

                                Divider().padding(.leading, 4)

                                notificationToggleRow(
                                    title: NSLocalizedString("settings.notifications.muteOldReactions", comment: "Mute reactions on old posts"),
                                    isOn: Binding(
                                        get: { viewModel.notificationPreferences["muteOldPostReactions"] ?? false },
                                        set: { viewModel.updateNotificationPreference(type: "muteOldPostReactions", isEnabled: $0) }
                                    )
                                )
                            }

                            Text(NSLocalizedString("settings.notifications.oldPostsExplain", comment: "Old posts explanation"))
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .padding(.top, 4)

                            Text(NSLocalizedString("settings.notifications.gentleReminders.description", comment: "Gentle reminders description"))
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                }

                if showSavedSchedule {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(NSLocalizedString("settings.schedule.saved", comment: "Schedule saved"))
                                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.45),
                                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 12, y: 6)
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle(NSLocalizedString("settings.notifications", comment: "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
                }
            }
            .alert(NSLocalizedString("settings.error.title", comment: "Error"), isPresented: $showScheduleError) {
                Button(NSLocalizedString("settings.ok", comment: "OK"), role: .cancel) { }
            } message: {
                Text(scheduleErrorMessage)
            }
            .settingsSwitchTint()
    }

    private func notificationToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .tint(SettingsProfileColors.toggleTint)
            .font(.system(size: legacyPoppinsSize(14)))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .padding(.vertical, 10)
    }
}

private struct SaveSchedulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
