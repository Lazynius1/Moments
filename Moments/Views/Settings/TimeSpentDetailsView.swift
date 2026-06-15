import SwiftUI

struct TimeSpentDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("userActivity.timeSpent.details.title", value: "Time on Moments", comment: "Time spent details title"))
                            .font(.custom("Poppins-Bold", size: 28))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(NSLocalizedString("userActivity.timeSpent.details.subtitle", value: "See how much time you spend on Moments each day. We use this data to help you manage your time.", comment: "Time spent details subtitle"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Reusing the beautiful Liquid Glass card we just made
                    TimeSpentCardView()
                        .padding(.horizontal, 16)
                        
                    // MARK: - Navigation Links for Limits and Rest
                    VStack(spacing: 0) {
                        NavigationLink(destination: DailyLimitView()) {
                            TimeSpentSettingsRow(
                                title: NSLocalizedString("userActivity.timeSpent.dailyLimit.title", value: "Límite diario", comment: "Daily limit title"),
                                subtitle: NSLocalizedString("userActivity.timeSpent.dailyLimit.subtitle", value: "Añade un límite para el tiempo que pasas cada día.", comment: "Daily limit subtitle")
                            )
                        }
                        
                        NavigationLink(destination: RestModeView()) {
                            TimeSpentSettingsRow(
                                title: NSLocalizedString("userActivity.timeSpent.restMode.title", value: "Modo descanso", comment: "Rest mode title"),
                                subtitle: NSLocalizedString("userActivity.timeSpent.restMode.subtitle", value: "Elige las horas del día a las que quieres silenciar las notificaciones push.", comment: "Rest mode subtitle")
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(NSLocalizedString("userActivity.timeSpent.navTitle", value: "Time Spent", comment: "Nav title for Time spent"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
    }
}

// MARK: - Reusable Row Component
struct TimeSpentSettingsRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray.opacity(0.8))
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
