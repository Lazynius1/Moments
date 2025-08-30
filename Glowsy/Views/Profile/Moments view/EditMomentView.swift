import SwiftUI

struct EditMomentView: View {
    let moment: Moment
    @Binding var editedContent: String
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(NSLocalizedString("editMoment.cancel", comment: "Cancel button in edit moment view")) {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    
                    Spacer()
                    
                    Text(NSLocalizedString("editMoment.title", comment: "Title for edit moment view"))
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    Button(NSLocalizedString("editMoment.save", comment: "Save button in edit moment view")) {
                        saveChanges()
                    }
                    .foregroundColor(editedContent != moment.content ? Color(hex: "00A896") : .gray)
                    .disabled(editedContent == moment.content || isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Contenido principal
                VStack(spacing: 20) {
                    // Preview de la imagen si existe
                    if let imagePath = moment.imagePath,
                       let url = URL(string: imagePath) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .frame(height: 200)
                                .overlay(
                                    ProgressView()
                                        .tint(Color(hex: "00A896"))
                                )
                        }
                    }
                    
                    // Editor de texto
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("editMoment.description", comment: "Description label in edit moment view"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                        
                        TextEditor(text: $editedContent)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .background(Color.clear)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2),
                                                Color(hex: "00A896").opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .frame(minHeight: 120)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay(
            // Loading overlay
            Group {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.2)
                                .tint(Color(hex: "00A896"))
                            
                            Text(NSLocalizedString("editMoment.saving", comment: "Saving changes text in edit moment view"))
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                }
            }
        )
    }
    
    private func saveChanges() {
        guard editedContent != moment.content else { return }
        
        isSaving = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onSave(editedContent)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isSaving = false
                dismiss()
            }
        }
    }
}
