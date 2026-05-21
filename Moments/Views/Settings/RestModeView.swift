import SwiftUI

struct RestModeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    
    @State private var isRestModeEnabled: Bool = false
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
                
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("userActivity.timeSpent.restMode.descTitle", value: "Momento de pausa", comment: "Rest mode desc title"))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                        Text(NSLocalizedString("userActivity.timeSpent.restMode.descBody", value: "Silencia las notificaciones push de Moments durante las horas que elijas para evitar distracciones.", comment: "Rest mode desc body"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else {
                        // Toggle Card
                        VStack(spacing: 0) {
                            Toggle(isOn: $isRestModeEnabled.animation(.spring(response: 0.3, dampingFraction: 0.7))) {
                                Text(NSLocalizedString("settings.notifications.schedule.enable", comment: "Enable rest mode"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            .tint(Color(hex: "8B5CF6")) // Violet
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 16)
                        
                        // Time Pickers
                        if isRestModeEnabled {
                            VStack(spacing: 0) {
                                DatePicker(
                                    NSLocalizedString("settings.notifications.schedule.start", comment: "Start time"),
                                    selection: $startTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .font(.custom("Poppins-Medium", size: 15))
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.horizontal, 16)
                                
                                DatePicker(
                                    NSLocalizedString("settings.notifications.schedule.end", comment: "End time"),
                                    selection: $endTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .font(.custom("Poppins-Medium", size: 15))
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
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
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 4)
                                }
                                Text(NSLocalizedString("settings.schedule.save", comment: "Save"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "8B5CF6"), Color(hex: "6D28D9")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .shadow(color: Color(hex: "8B5CF6").opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("userActivity.timeSpent.restMode.title", value: "Modo descanso", comment: "Rest mode title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private func loadCurrentSettings() {
        viewModel.fetchUserSettings { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let user):
                    if let startStr = user.activeHoursStart, let endStr = user.activeHoursEnd,
                       let startDt = self.viewModel.dateFormatter.date(from: startStr),
                       let endDt = self.viewModel.dateFormatter.date(from: endStr) {
                        self.isRestModeEnabled = true
                        self.startTime = startDt
                        self.endTime = endDt
                    } else {
                        self.isRestModeEnabled = false
                    }
                case .failure:
                    // Default values if fail
                    self.isRestModeEnabled = false
                }
            }
        }
    }
    
    private func saveSettings() {
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        
        if isRestModeEnabled {
            viewModel.updateActiveHours(startTime: startTime, endTime: endTime) { error in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if error != nil {
                        generator.notificationOccurred(.error)
                    } else {
                        generator.notificationOccurred(.success)
                        self.dismiss()
                    }
                }
            }
        } else {
            viewModel.clearActiveHours()
            
            // Simulating network delay since clearActiveHours doesn't have a completion block in SettingsViewModel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isSaving = false
                generator.notificationOccurred(.success)
                self.dismiss()
            }
        }
    }
}
