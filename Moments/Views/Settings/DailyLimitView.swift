import SwiftUI

struct DailyLimitView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var timeSpentManager = TimeSpentManager.shared
    
    @State private var isLimitEnabled: Bool = false
    @State private var selectedHours: Int = 1
    @State private var selectedMinutes: Int = 0
    
    // Arrays for pickers
    private let hoursOffset = Array(0...23)
    private let minutesOffset = Array(stride(from: 0, to: 60, by: 5))
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
                
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("userActivity.timeSpent.dailyLimit.descTitle", value: "Establece tu ritmo", comment: "Daily limit desc title"))
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                        Text(NSLocalizedString("userActivity.timeSpent.dailyLimit.descBody", value: "Moments te enviará una notificación cuando rebase el tiempo que hayas decidido pasar en la aplicación cada día.", comment: "Daily limit desc body"))
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundColor(.gray)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Toggle Card
                    VStack(spacing: 0) {
                        Toggle(isOn: $isLimitEnabled.animation(MotionPolicy.Spring.toggle)) {
                            Text(NSLocalizedString("userActivity.timeSpent.dailyLimit.toggle", value: "Aviso de límite diario", comment: "Daily limit toggle"))
                                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .tint(SettingsProfileColors.toggleTint)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal, 16)
                    
                    // Time Picker (Only shown if enabled)
                    if isLimitEnabled {
                        VStack(spacing: 0) {
                            Text(NSLocalizedString("userActivity.timeSpent.dailyLimit.pickerTitle", value: "Duración del límite", comment: "Daily limit picker title"))
                                .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                            
                            HStack {
                                Picker("Hours", selection: $selectedHours) {
                                    ForEach(hoursOffset, id: \.self) { hour in
                                        Text("\(hour) h").tag(hour)
                                            .font(.system(size: legacyPoppinsSize(18)))
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                
                                Picker("Minutes", selection: $selectedMinutes) {
                                    ForEach(minutesOffset, id: \.self) { minute in
                                        Text("\(minute) min").tag(minute)
                                            .font(.system(size: legacyPoppinsSize(18)))
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                            }
                            .frame(height: 150)
                            .padding(.bottom, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer(minLength: 40)
                    
                    // Save Button
                    Button(action: saveSettings) {
                        Text(NSLocalizedString("settings.schedule.save", comment: "Save"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundColor(SettingsProfileColors.accentContrastingText(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(SettingsProfileColors.accent(colorScheme))
                            )
                            .shadow(color: SettingsProfileColors.accent(colorScheme).opacity(0.2), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .settingsSwitchTint()
        .navigationTitle(NSLocalizedString("userActivity.timeSpent.dailyLimit.title", value: "Límite diario", comment: "Daily limit title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private func loadCurrentSettings() {
        if let limit = timeSpentManager.dailyLimitSeconds {
            isLimitEnabled = true
            selectedHours = Int(limit) / 3600
            selectedMinutes = (Int(limit) % 3600) / 60
        } else {
            isLimitEnabled = false
            selectedHours = 1
            selectedMinutes = 0
        }
    }
    
    private func saveSettings() {
        if isLimitEnabled {
            // Prevent 0 hours and 0 minutes
            if selectedHours == 0 && selectedMinutes == 0 {
                selectedMinutes = 5 // Minimum 5 mins
            }
            
            let totalSeconds = TimeInterval((selectedHours * 3600) + (selectedMinutes * 60))
            timeSpentManager.setDailyLimit(totalSeconds)
            
            // Request Notification Permissions if needed
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                // Handle permission explicitly if needed, but we already scheduled inside TimeSpentManager
            }
        } else {
            timeSpentManager.setDailyLimit(nil)
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismiss()
    }
}
