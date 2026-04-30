import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let sections: [PrivacyPolicySection] = [
        .init(titleKey: "privacyPolicy.section.summary.title", bodyKey: "privacyPolicy.section.summary.body"),
        .init(titleKey: "privacyPolicy.section.data.title", bodyKey: "privacyPolicy.section.data.body"),
        .init(titleKey: "privacyPolicy.section.use.title", bodyKey: "privacyPolicy.section.use.body"),
        .init(titleKey: "privacyPolicy.section.nova.title", bodyKey: "privacyPolicy.section.nova.body"),
        .init(titleKey: "privacyPolicy.section.visibility.title", bodyKey: "privacyPolicy.section.visibility.body"),
        .init(titleKey: "privacyPolicy.section.messages.title", bodyKey: "privacyPolicy.section.messages.body"),
        .init(titleKey: "privacyPolicy.section.permissions.title", bodyKey: "privacyPolicy.section.permissions.body"),
        .init(titleKey: "privacyPolicy.section.ads.title", bodyKey: "privacyPolicy.section.ads.body"),
        .init(titleKey: "privacyPolicy.section.moderation.title", bodyKey: "privacyPolicy.section.moderation.body"),
        .init(titleKey: "privacyPolicy.section.providers.title", bodyKey: "privacyPolicy.section.providers.body"),
        .init(titleKey: "privacyPolicy.section.retention.title", bodyKey: "privacyPolicy.section.retention.body"),
        .init(titleKey: "privacyPolicy.section.rights.title", bodyKey: "privacyPolicy.section.rights.body"),
        .init(titleKey: "privacyPolicy.section.minors.title", bodyKey: "privacyPolicy.section.minors.body"),
        .init(titleKey: "privacyPolicy.section.contact.title", bodyKey: "privacyPolicy.section.contact.body")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    ForEach(sections) { section in
                        policySection(section)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
            }
            .scrollContentBackground(.hidden)
            .background((colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea())
            .navigationBarTitle(NSLocalizedString("privacyPolicy.title", comment: "Privacy policy title"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 34)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                    }
                    .accessibilityLabel(Text("login.close"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("privacyPolicy.title", comment: "Privacy policy title"))
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(AuthColors.primary(colorScheme))

            Text(NSLocalizedString("privacyPolicy.lastUpdated", comment: "Privacy policy last updated date"))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.64))
        }
    }

    private func policySection(_ section: PrivacyPolicySection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(NSLocalizedString(section.titleKey, comment: "Privacy policy section title"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(AuthColors.primary(colorScheme))

            Text(NSLocalizedString(section.bodyKey, comment: "Privacy policy section body"))
                .font(.custom("Poppins-Regular", size: 15))
                .lineSpacing(4)
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.78))
                .textSelection(.enabled)
        }
    }
}

private struct PrivacyPolicySection: Identifiable {
    let id = UUID()
    let titleKey: String
    let bodyKey: String
}

struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyPolicyView()
    }
}
