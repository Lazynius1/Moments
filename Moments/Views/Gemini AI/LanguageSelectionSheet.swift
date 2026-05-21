import SwiftUI

struct LanguageSelectionSheet: View {
    let onSelect: (NovaLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: NovaLanguage = NovaLanguageService.getPreferredLanguage() ?? .es
    
    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("nova.select_language_title", comment: "Select language title"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .padding(.top, 12)
            
            ForEach(NovaLanguage.allCases, id: \.self) { lang in
                Button(action: {
                    selected = lang
                    onSelect(lang)
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.displayName)
                                .foregroundColor(.primary)
                                .font(.custom("Poppins-Medium", size: 16))
                            Text(lang.shortDescription)
                                .foregroundColor(.secondary)
                                .font(.custom("Poppins-Regular", size: 12))
                        }
                        Spacer()
                        if selected == lang {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            
            Button(action: { dismiss() }) {
                Text(NSLocalizedString("nova.select_language_cancel", comment: "Cancel"))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
}


