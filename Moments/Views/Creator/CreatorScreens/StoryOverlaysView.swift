import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import UIKit

struct StoryOverlaysView: View {
    let canvasSize: CGSize
    @Binding var text: String
    @Binding var textPosition: CGPoint
    @Binding var textStyle: StoryEditingView.TextStyle
    @Binding var textEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @Binding var isTextEditorPresented: Bool
    @Binding var stickers: [StickerItem]
    @Binding var drawingImage: UIImage?
    @Binding var isEditingSticker: Bool // ✅ NUEVO: Para ocultar la UI del padre

    let onNavigateToProfile: (String) -> Void
    let onNavigateToLocation: (String, CLLocationCoordinate2D?) -> Void

    @State private var selectedStickerId: String?
    @State private var isEditingText = false
    @State private var isDraggingItem = false
    @State private var showTrashZone = false
    @State private var isOverTrash = false
    @State private var pinchStartTextFontSize: CGFloat?
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar el texto

    // 📸 NUEVO: Estado para editar el pie de foto de la Polaroid
    @State private var editingPolaroidId: String? = nil
    @State private var polaroidCaptionBuffer: String = ""
    @State private var originalStickerTransform: (pos: CGPoint, scale: CGFloat, rot: Angle)? = nil
    @State private var keyboardHeight: CGFloat = 0

    // ✨ NUEVO: Estado para editar el diseño del Reveal
    @State private var editingRevealId: String? = nil

    var body: some View {
        ZStack {
            // Drawing overlay
            if let drawing = drawingImage {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil && !text.isEmpty ? 1.0 :
                                 isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil && text.isEmpty ? 0.8 : 1.0)
                    .allowsHitTesting(true)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !text.isEmpty { return }

                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }

                                isOverTrash = isPointOverTrash(value.location)
                            }
                            .onEnded { value in
                                if !text.isEmpty { return }

                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false

                                    if isOverTrash {
                                        drawingImage = nil
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .onTapGesture {
                        // Deseleccionar al tocar el fondo
                        selectedStickerId = nil
                    }
            }

            // Text overlay
            if !text.isEmpty && !isTextEditorPresented {
                Text(text)
                    .font(textStyle.font(size: textFontSize))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(nil)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        Group {
                            if let backgroundColor = effectiveTextBackgroundColor {
                                backgroundColor
                            }
                        }
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: effectiveTextBackgroundColor == nil ? 0 : 10, style: .continuous)
                    )
                    .padding(.horizontal, 24)
                    .scaleEffect(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .opacity(isDraggingItem && selectedStickerId == nil ? 0.8 : 1.0)
                    .modifier(TextEffectModifier(effect: textEffect, textColor: textColor))
                    .contentShape(Rectangle()) // ✅ Área táctil limitada al texto
                    .gesture(
                        DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Estabilidad absoluta en el canvas
                            .onChanged { value in
                                if dragOffset == .zero {
                                    dragOffset = CGSize(
                                        width: value.startLocation.x - textPosition.x,
                                        height: value.startLocation.y - textPosition.y
                                    )
                                }

                                let newPos = CGPoint(
                                    x: value.location.x - dragOffset.width,
                                    y: value.location.y - dragOffset.height
                                )

                                textPosition = newPos

                                if !isDraggingItem {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDraggingItem = true
                                        showTrashZone = true
                                    }
                                }

                                isOverTrash = isPointOverTrash(newPos)
                            }
                            .onEnded { value in
                                dragOffset = .zero
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = false
                                    showTrashZone = false

                                    if isOverTrash {
                                        text = ""
                                    }
                                    isOverTrash = false
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let baseFontSize = pinchStartTextFontSize ?? textFontSize
                                if pinchStartTextFontSize == nil {
                                    pinchStartTextFontSize = textFontSize
                                }
                                textFontSize = min(max(baseFontSize * value, 20), 56)
                            }
                            .onEnded { _ in
                                pinchStartTextFontSize = nil
                            }
                    )
                    .onTapGesture {
                        selectedStickerId = nil
                        isEditingText = true
                        isTextEditorPresented = true
                    }
                    .position(textPosition) // ✅ Posicionar al final
                    .animation(.easeInOut(duration: 0.2), value: isDraggingItem)
            }

            // ✅ STICKERS COMPLETAMENTE LIBRES - Sin interfaz de selección
            ForEach(stickers.indices, id: \.self) { index in
                // Ocultar stickers de tipo REVEAL del canvas (se muestran como badge arriba)
                if stickers[index].type != .reveal {
                    StickerOverlayView(
                        sticker: $stickers[index],
                        isSelected: selectedStickerId == stickers[index].id,
                        isDragging: isDraggingItem && selectedStickerId == stickers[index].id,
                        isContentEditing: editingPolaroidId == stickers[index].id,
                        onUpdate: { updatedSticker in
                            stickers[index] = updatedSticker
                        },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                stickers.remove(at: index)
                                selectedStickerId = nil
                            }
                        },
                        onDragChanged: { position in
                            if !isDraggingItem {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingItem = true
                                    showTrashZone = true
                                    selectedStickerId = stickers[index].id
                                }
                            }

                            isOverTrash = isPointOverTrash(position)
                        },
                        onDragEnded: { position in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDraggingItem = false
                                showTrashZone = false

                                if isOverTrash {
                                    stickers.remove(at: index)
                                }
                                isOverTrash = false
                            }
                        },
                        onStickerTapped: { tappedSticker in
                            handleStickerTap(tappedSticker)
                            selectedStickerId = tappedSticker.id
                        }
                    )
                    .zIndex(editingPolaroidId == stickers[index].id ? 2000 : (selectedStickerId == stickers[index].id ? 500 : 1))
                }
            }

            // ✅ REVEAL STATUS BADGE (Top)
            if stickers.contains(where: { $0.type == .reveal }) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magicmouse.fill")
                                .font(.system(size: 12))
                            Text(NSLocalizedString("storyEditor.reveal.active", comment: "Reveal effect active status"))
                                .font(.custom("Poppins-Medium", size: 11))

                            Button {
                                withAnimation(.spring()) {
                                    stickers.removeAll(where: { $0.type == .reveal })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                        .onTapGesture {
                            if let revealSticker = stickers.first(where: { $0.type == .reveal }) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    editingRevealId = revealSticker.id
                                }
                                HapticManager.shared.mediumImpact()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 100) // Debajo de los controles superiores
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }


            // Zona de papelera
            if showTrashZone {
                VStack {
                    Spacer()

                    Image(systemName: isOverTrash ? "trash.fill" : "trash")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(isOverTrash ? .red : .white)
                        .frame(width: 84, height: 84)
                        .scaleEffect(isOverTrash ? 1.12 : 1.0)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isOverTrash)
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 📸 FONDO OSCURO DE EDICIÓN (Dentro del ZStack para controlar el zIndex)
            if editingPolaroidId != nil {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .zIndex(1500) // Entre los stickers normales y el "Hero"
                    .onTapGesture {
                        savePolaroidCaption()
                    }
                    .transition(.opacity)

                // INPUT DE TEXTO (Encima de todo)
                VStack {
                    Spacer()
                    TextField(NSLocalizedString("storyEditor.polaroid.addNote", comment: "Prompt to add a note to a polaroid"), text: $polaroidCaptionBuffer)
                        .font(.custom("MarkerFelt-Wide", size: 24)) // Un pelín más pequeña
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12) // Mucho más fino
                        .padding(.horizontal, 25)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .padding(.horizontal, 40)
                        .submitLabel(.done)
                        .onSubmit {
                            savePolaroidCaption()
                        }
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 80 : 160)
                }
                .zIndex(2500)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: keyboardHeight)
                .onChange(of: polaroidCaptionBuffer) { _, newValue in
                    // ✅ ACTUALIZACIÓN EN TIEMPO REAL
                    if let editingId = editingPolaroidId,
                       let index = stickers.firstIndex(where: { $0.id == editingId }) {
                        var interaction = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
                        interaction.caption = newValue
                        stickers[index].interactionData = interaction
                    }
                }
            }

            // ✨ REVEAL EDITOR OVERLAY
            if editingRevealId != nil {
                RevealStickerEditorView(
                    stickers: $stickers,
                    editingId: $editingRevealId
                )
                .zIndex(3000)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: editingPolaroidId) { _, newValue in
            // ✅ AVISAR AL PADRE PARA OCULTAR LA UI
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingRevealId != nil
            }
        }
        .onChange(of: editingRevealId) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingPolaroidId != nil
            }
        }
        .coordinateSpace(name: "storyCanvas")
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onTapGesture {
            // Deseleccionar al tocar el fondo
            selectedStickerId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - endFrame.minY)
            keyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }

    }

    private var effectiveTextBackgroundColor: Color? {
        switch textBackgroundFill {
        case .none:
            return textEffect.backgroundColor
        case .black:
            return Color.black.opacity(0.58)
        case .white:
            return Color.white.opacity(0.90)
        }
    }

    private func handleStickerTap(_ sticker: StickerItem) {
        switch sticker.type {
        case .mention:
            if let username = sticker.interactionData?.username {
                findUserIdByUsername(username) { userId in
                    if let userId = userId {
                        DispatchQueue.main.async {
                            onNavigateToProfile(userId)
                        }
                    }
                }
            }

        case .hashtag:
            if sticker.interactionData?.hashtag != nil {
                // Handle hashtag tap
            }

        case .location:
            if let interactionData = sticker.interactionData,
               let location = interactionData.location {
                onNavigateToLocation(location, interactionData.locationCoordinate)
            }

        case .poll:
            // Handle poll tap
            break

        case .question:
            // Handle question tap
            break

        case .questionResponse:
            // Handle question response tap
            break

        case .frame:
            // 📸 EFECTO ENFOQUE: Guardar posición y centrar para editar
            if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
                let original = stickers[index]
                originalStickerTransform = (original.position, original.scale, original.rotation)

                editingPolaroidId = sticker.id
                polaroidCaptionBuffer = sticker.interactionData?.caption ?? ""

                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    // Mover al centro (un poco arriba por el teclado) y ampliar
                    stickers[index].position = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 3)
                    stickers[index].scale = 1.4
                    stickers[index].rotation = .zero
                }

                HapticManager.shared.mediumImpact()
            }

        default:
            break
        }
    }


    private func savePolaroidCaption() {
        guard let editingId = editingPolaroidId else { return }

        if let index = stickers.firstIndex(where: { $0.id == editingId }) {
            // Actualizar el caption en los datos de interacción
            var interactionData = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
            interactionData.caption = polaroidCaptionBuffer
            stickers[index].interactionData = interactionData

            // 🚀 VOLVER A LA POSICIÓN ORIGINAL CON ANIMACIÓN
            if let original = originalStickerTransform {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    stickers[index].position = original.pos
                    stickers[index].scale = original.scale
                    stickers[index].rotation = original.rot
                }
            }
        }

        withAnimation(.easeOut(duration: 0.25)) {
            editingPolaroidId = nil
            polaroidCaptionBuffer = ""
            originalStickerTransform = nil
        }

        // Ocultar teclado
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func isPointOverTrash(_ point: CGPoint) -> Bool {
        point.y > canvasSize.height - 128
    }

    private func findUserIdByUsername(_ username: String, completion: @escaping (String?) -> Void) {
        let firestoreService = FirestoreService()
        firestoreService.searchUsers(query: username, limit: 10) { result in
            switch result {
            case .success(let users):
                if let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    completion(user.id)
                } else {
                    completion(nil)
                }
            case .failure(_):
                completion(nil)
            }
        }
    }


    // ✅ FUNCIONES AUXILIARES: Mostrar toasts informativos
    private func showUserNotFoundToast(username: String) {
        // Implementar toast: "Usuario @username no encontrado"
    }

    private func showHashtagToast(hashtag: String) {
        // Implementar toast: "Ver publicaciones con #hashtag"
    }

    private func showLocationToast(location: String) {
        // Implementar toast: "Ver ubicación: location"
    }

    private func showPollToast() {
        // Implementar toast: "Toca para votar en la encuesta"
    }

    private func showQuestionToast() {
        // Implementar toast: "Toca para responder la pregunta"
    }

    private func showQuestionResponseToast() {
        // Implementar toast: "Respuesta anónima compartida"
    }
}
