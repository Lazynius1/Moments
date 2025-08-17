import SwiftUI
import FirebaseFirestore

// MARK: - ✅ VISTA PARA VER RESPUESTAS (AUTOR)
struct QuestionResponsesView: View {
    let questionText: String
    let storyId: String
    let userId: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var responses: [QuestionResponse] = []
    @State private var isLoading = true
    @State private var showingShareSheet = false
    @State private var selectedResponse: QuestionResponse?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header con la pregunta
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(questionText)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    HStack(spacing: 8) {
                        Text("\(responses.count)")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.blue)
                        
                        Text(responses.count == 1 ? NSLocalizedString("questionResponses.response", comment: "Response singular") : NSLocalizedString("questionResponses.responses", comment: "Responses plural"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 20)
                .background(Color(.systemBackground))
                
                // Lista de respuestas
                if isLoading {
                    Spacer()
                    ProgressView(NSLocalizedString("questionResponses.loading", comment: "Loading responses"))
                        .font(.custom("Poppins-Regular", size: 14))
                    Spacer()
                } else if responses.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("questionResponses.noAnswers", comment: "No answers yet"))
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("questionResponses.shareStory", comment: "Share story to receive answers"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(responses.enumerated()), id: \.element.id) { index, response in
                                VStack(spacing: 0) {
                                    QuestionResponseRow(
                                        response: response,
                                        onShare: {
                                            selectedResponse = response
                                            showingShareSheet = true
                                        }
                                    )
                                    
                                    // ✅ SEPARADOR ENTRE RESPUESTAS (excepto la última)
                                    if index < responses.count - 1 {
                                        Divider()
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("questionResponses.title", comment: "Responses title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("questionResponses.close", comment: "Close button")) {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let response = selectedResponse {
                ShareResponseView(
                    questionText: questionText,
                    response: response,
                    onDismiss: {
                        showingShareSheet = false
                        selectedResponse = nil
                    }
                )
            }
        }
        .onAppear {
            loadResponses()
        }
    }
    
    private func loadResponses() {
        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("questionResponses")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let documents = snapshot?.documents {
                        self.responses = documents.compactMap { document in
                            do {
                                let data = document.data()
                                let response = QuestionResponse(
                                    userId: data["userId"] as? String ?? "",
                                    response: data["response"] as? String ?? ""
                                )
                                return response
                            } catch {
                                print("❌ Error parsing response: \(error)")
                                return nil
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - ✅ FILA DE RESPUESTA
struct QuestionResponseRow: View {
    let response: QuestionResponse
    let onShare: () -> Void
    
    @State private var responderUsername: String = ""
    @State private var showingResponderProfile = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ✅ HEADER CON FOTO Y NOMBRE DE QUIEN RESPONDIÓ
            HStack(spacing: 12) {
                AsyncProfileImageView(userId: response.userId)
                    .frame(width: 32, height: 32)
                    .onTapGesture {
                        showingResponderProfile = true
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(responderUsername.isEmpty ? "Cargando..." : responderUsername)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.primary)
                    
                    Text(timeAgo(from: response.timestamp))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
            }
            
            // ✅ RESPUESTA
            Text(response.response)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 12)
        .onAppear {
            loadResponderUsername()
        }
        .sheet(isPresented: $showingResponderProfile) {
            UserProfileView(userId: response.userId)
        }
    }
    
    private func loadResponderUsername() {
        FirestoreService().db.collection("users").document(response.userId).getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let username = data["username"] as? String {
                    self.responderUsername = username
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ VISTA PARA COMPARTIR RESPUESTA
struct ShareResponseView: View {
    let questionText: String
    let response: QuestionResponse
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var showingCreatorView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Preview de la historia compartida
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(questionText)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Respuesta anónima:")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.secondary)
                    
                    Text(response.response)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Botón para crear nueva historia
                Button(action: createResponseStory) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Text(NSLocalizedString("questionResponses.createStory", comment: "Create story with this answer"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoading)
                .padding(.horizontal, 20)
            }
            .padding(.top, 20)
            .navigationTitle(NSLocalizedString("questionResponses.shareResponse", comment: "Share response title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("questionResponses.cancel", comment: "Cancel button")) {
                        dismiss()
                        onDismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCreatorView) {
            CreatorViewWithResponseData(
                questionText: questionText,
                response: response,
                onDismiss: {
                    showingCreatorView = false
                    dismiss()
                    onDismiss()
                }
            )
        }
    }
    
    private func createResponseStory() {
        isLoading = true
        
        // Simular carga y abrir CreatorView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
            showingCreatorView = true
        }
    }
}

// MARK: - ✅ CREATOR VIEW CON RESPUESTA
struct CreatorViewWithResponse: View {
    let questionText: String
    let response: QuestionResponse
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreatorView = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Preview de la respuesta que se va a compartir
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(NSLocalizedString("questionResponses.sharingResponseTo", comment: "Sharing response to"))
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.secondary)
                
                Text(questionText)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Text(NSLocalizedString("questionResponses.anonymousResponse", comment: "Anonymous response"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                
                Text(response.response)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Botón para abrir CreatorView
            Button(action: {
                showingCreatorView = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    
                    Text(NSLocalizedString("questionResponses.createStory", comment: "Create story with this answer"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple, Color.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
                    .navigationTitle(NSLocalizedString("questionResponses.shareResponse", comment: "Share response title"))
        .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("questionResponses.cancel", comment: "Cancel button")) {
                        dismiss()
                        onDismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        .fullScreenCover(isPresented: $showingCreatorView) {
            CreatorViewWithResponseData(
                questionText: questionText,
                response: response,
                onDismiss: {
                    showingCreatorView = false
                    dismiss()
                    onDismiss()
                }
            )
        }
    }
}

// MARK: - ✅ CREATOR VIEW CON STICKER DE RESPUESTA
struct CreatorViewWithResponseData: View {
    let questionText: String
    let response: QuestionResponse
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingStory: Bool = true
    @State private var showCreatorView: Bool = true
    
    var body: some View {
        CreatorView(
            isCreatingStory: $isCreatingStory,
            showCreatorView: $showCreatorView,
            initialSticker: createResponseStickerImage() // ✅ PASAR STICKER DIRECTAMENTE
        )
        .onChange(of: showCreatorView) { _, newValue in
            // ✅ CERRAR CUANDO SE COMPLETE LA SUBIDA
            if !newValue {
                onDismiss()
            }
        }
    }
    
    private func createResponseStickerImage() -> StickerItem {
        // Crear una imagen del sticker de respuesta
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 60))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
            
            // Fondo con gradiente
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor,
                    UIColor.systemPink.cgColor
                ] as CFArray,
                locations: [0.0, 0.5, 1.0]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 200, y: 60),
                options: []
            )
            
            // Borde blanco con esquinas más redondeadas
            let borderPath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            borderPath.lineWidth = 2
            UIColor.white.withAlphaComponent(0.3).setStroke()
            borderPath.stroke()
            
            // Icono de pregunta
            let iconRect = CGRect(x: 12, y: 10, width: 18, height: 18)
            let iconPath = UIBezierPath(ovalIn: iconRect)
            UIColor.white.setFill()
            iconPath.fill()
            
            // Texto "Respuesta anónima"
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Poppins-SemiBold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let titleString = NSLocalizedString("questionResponses.anonymousResponseTitle", comment: "Anonymous response title")
            let titleSize = titleString.size(withAttributes: titleAttributes)
            titleString.draw(
                at: CGPoint(x: 35, y: 12),
                withAttributes: titleAttributes
            )
            
            // Texto de la respuesta
            let responseAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Poppins-Regular", size: 12) ?? UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.white
            ]
            
            let responseString = response.response
            let responseRect = CGRect(x: 12, y: 32, width: 176, height: 24)
            
            // Asegurar que el texto se ajuste
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .center
            
            var finalAttributes = responseAttributes
            finalAttributes[.paragraphStyle] = paragraphStyle
            
            responseString.draw(
                with: responseRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: finalAttributes,
                context: nil
            )
        }
        
        // Crear el StickerItem
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .questionResponse, // Usar el nuevo tipo específico para respuestas
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: "Respuesta: \(response.response)",
                weatherSymbol: nil
            )
        )
        
        return sticker
    }
}

 
