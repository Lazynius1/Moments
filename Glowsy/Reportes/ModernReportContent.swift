import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ModernReportContent: View {
    let moment: Moment?
    let story: Story?
    
    let onBack: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedCategory: ReportCategory?
    @State private var additionalDetails: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessMessage: Bool = false
    
    @Environment(\.colorScheme) var colorScheme
    
    private var contentType: String {
        return moment != nil ? "momento" : "historia"
    }
    
    private var contentId: String {
        return moment?.id ?? story?.id ?? ""
    }
    
    private var authorId: String {
        return moment?.authorId ?? story?.authorId ?? ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Header con botón de atrás
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                Text(String(format: NSLocalizedString("report.title", comment: "Report title"), contentType.capitalized))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // Botón invisible para centrar el título
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            
            if showSuccessMessage {
                successView
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // ✅ Descripción
                        Text(String(format: NSLocalizedString("report.subtitle", comment: "Report subtitle"), contentType))
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        // ✅ Categorías
                        VStack(spacing: 10) {
                            ForEach(ReportCategory.allCases, id: \.self) { category in
                                CategoryPill(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    onTap: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            selectedCategory = category
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // ✅ Detalles adicionales
                        if selectedCategory != nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(NSLocalizedString("report.additionalDetails", comment: "Additional details label"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.horizontal, 4)
                                
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $additionalDetails)
                                        .font(.custom("Poppins-Regular", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 100)
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                                                )
                                        )
                                    
                                    if additionalDetails.isEmpty {
                                        Text(NSLocalizedString("report.detailsPlaceholder", comment: "Details placeholder text"))
                                            .font(.custom("Poppins-Regular", size: 15))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 20)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // ✅ Botón de enviar
                        if selectedCategory != nil {
                            Button(action: submitReport) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(NSLocalizedString("report.sendButton", comment: "Send report button"))
                                            .font(.custom("Poppins-SemiBold", size: 16))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.red)
                                        .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                                )
                            }
                            .disabled(isSubmitting)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .frame(maxHeight: 600) // Limitar altura para el overlay
    }
    
    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("report.success.title", comment: "Report success title"))
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("report.success.message", comment: "Report success message"))
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onDismiss()
            }
        }
    }
    
    private func submitReport() {
        guard let category = selectedCategory,
              let currentUserId = Auth.auth().currentUser?.uid,
              !contentId.isEmpty else { return }
        
        isSubmitting = true
        
        let reporterId = currentUserId
        let reportedUserId = authorId
        let reportedContentType = moment != nil ? "moment" : "story"
        let reportedContentId = contentId
        let categoryRaw = category.rawValue
        let description = additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = category.priority.rawValue
        
        Task {
            await LocalPersistenceService.shared.reportContent(
                reporterId: reporterId,
                reportedUserId: reportedUserId,
                reportedContentType: reportedContentType,
                reportedContentId: reportedContentId,
                category: categoryRaw,
                description: description,
                priority: priority
            )
            
            DispatchQueue.main.async {
                self.isSubmitting = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.showSuccessMessage = true
                }
            }
        }
    }
}

struct CategoryPill: View {
    let category: ReportCategory
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        MomentRowButton(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: category.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.red : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if !category.subtitle.isEmpty {
                        Text(category.subtitle)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 20))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }
}
