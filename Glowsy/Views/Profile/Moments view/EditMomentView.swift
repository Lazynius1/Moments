import SwiftUI

struct EditMomentView: View {
    let moment: Moment
    @Binding var editedContent: String
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSaving = false
    
    var body: some View {
        ZStack {
            // MARK: - 1. Immersive Background
            GeometryReader { proxy in
                if let imagePath = moment.imagePath, let url = URL(string: imagePath) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .blur(radius: 40)
                            .overlay(Color.black.opacity(0.6)) // Slightly darker for better contrast
                    } placeholder: {
                        darkGradientBackground
                    }
                } else {
                    darkGradientBackground
                }
            }
            .ignoresSafeArea()
            
            // MARK: - 2. Main Content
            VStack(spacing: 0) {
                // Header Flotante
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    
                    Spacer()
                    
                    Text(NSLocalizedString("editMoment.title", comment: "Title"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    Spacer()
                    
                    Button(action: { saveChanges() }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(editedContent != moment.content ? Color(hex: "00A896") : Color.gray.opacity(0.5))
                            )
                            .shadow(radius: 5)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .disabled(editedContent == moment.content || isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 30) { // Espacio entre imagen y texto
                        
                        // 1. Imagen Flotante (Multi-image Stack)
                        MomentMediaStackPreview(moment: moment)
                            .frame(height: 350) // Dedicated height for the stack
                            .padding(.horizontal, 20)
                        
                        // Pie de página explicativo
                        Text(NSLocalizedString("editMoment.description", comment: "Description"))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .shadow(radius: 2)
                        
                        // 2. Editor de Texto (En contenedor Glassmorphic AÚN MÁS sutil)
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                if editedContent.isEmpty {
                                    Text(NSLocalizedString("editMoment.placeholder", comment: "Placeholder"))
                                        .font(.custom("Poppins-Regular", size: 18))
                                        .foregroundColor(.white.opacity(0.5))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                                
                                TextEditor(text: $editedContent)
                                    .font(.custom("Poppins-Regular", size: 18))
                                    .foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(minHeight: 120)
                            }
                        }
                        .padding(20)
                        .background(Color.black.opacity(0.2)) // ✅ Más sutil que ultraThinMaterial
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // ✅ Borde apenas visible
                        )
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2) // ✅ Sombra muy suavizada
                        .padding(.horizontal, 16)
                        

                    }
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
            
            // Loading Overlay Immersivo
            if isSaving {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text(NSLocalizedString("editMoment.saving", comment: "Saving"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var darkGradientBackground: some View {
        LinearGradient(
            colors: [Color(hex: "0F2027"), Color(hex: "203A43"), Color(hex: "2C5364")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func saveChanges() {
        guard editedContent != moment.content else { return }
        
        withAnimation {
            isSaving = true
        }
        
        // Simular operacion de red para feedback visual
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onSave(editedContent)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    isSaving = false
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Helper Views

struct MomentMediaStackPreview: View {
    let moment: Moment
    
    // Computed property to get items to display (id, url)
    private var mediaItemsToDisplay: [(String, String)] {
        if let items = moment.mediaItems, !items.isEmpty {
            return items.prefix(3).map { ($0.id, $0.url) }
        } else if let path = moment.imagePath {
            // Fallback for legacy usage or single image moments
            return [(UUID().uuidString, path)]
        }
        return []
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show items in reverse order so the first one is on top
                ForEach(Array(mediaItemsToDisplay.enumerated().reversed()), id: \.element.0) { index, item in
                    let (_, urlString) = item
                    
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit) // Ensure full content visibility
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            case .empty, .failure:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        ProgressView()
                                            .tint(.white)
                                    )
                                    .cornerRadius(16)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        // Stack visual effects
                        .frame(width: geometry.size.width * 0.85) // Slightly smaller width for stack effect
                        .rotationEffect(.degrees(Double(index) * 3)) // Rotate background cards
                        .offset(x: CGFloat(index) * 10, y: CGFloat(index) * 5) // Offset background cards
                        .zIndex(Double(-index)) // Ensure correct stacking order
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
