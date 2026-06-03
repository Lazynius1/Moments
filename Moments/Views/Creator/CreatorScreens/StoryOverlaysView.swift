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
    @Binding var visualEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @Binding var textStroke: StoryEditingView.TextStroke
    @Binding var textMotion: StoryEditingView.TextMotion
    @Binding var forcesAllCaps: Bool
    @Binding var isTextEditorPresented: Bool
    @Binding var stickers: [StickerItem]
    @Binding var drawingImage: UIImage?
    @Binding var isEditingSticker: Bool // ✅ NUEVO: Para ocultar la UI del padre
    @Binding var editingRevealId: String?

    let onNavigateToProfile: (String) -> Void
    let onNavigateToLocation: (String, CLLocationCoordinate2D?) -> Void

    @Binding var selectedStickerId: String?
    @Binding var activeEditingStickerId: String? // ✅ NUEVO: Edición inline en Canvas
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
    @State private var focusedInlineStickerTransform: (id: String, pos: CGPoint, scale: CGFloat, rot: Angle)? = nil
    @State private var keyboardHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // 📸 FONDO OSCURO DE EDICIÓN INLINE DE STICKERS
            if activeEditingStickerId != nil {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.65))
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .zIndex(2500)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeEditingStickerId = nil
                        }
                    }
            }

            // Drawing overlay
            if let drawing = drawingImage {
                Image(uiImage: drawing)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(1.0)
                    .opacity(1.0)
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
                let textConfig = StoryTextRenderConfiguration(
                    text: text,
                    style: textStyle,
                    visualEffect: visualEffect,
                    textColor: textColor,
                    textAlignment: textAlignment,
                    textBackgroundFill: textBackgroundFill,
                    fontSize: textFontSize,
                    textStroke: textStroke,
                    forcesAllCaps: forcesAllCaps
                )
                let maxTextWidth = max(canvasSize.width - 48, 120)
                let overlaySize = StoryTextAttributesBuilder.overlayContentSize(
                    for: textConfig,
                    maxWidth: maxTextWidth
                )

                StoryTextOverlayContainerRepresentable(
                    configuration: textConfig,
                    motion: textMotion,
                    maxWidth: maxTextWidth,
                    replayToken: 0
                )
                    .frame(width: overlaySize.width, height: overlaySize.height)
                    .contentShape(Rectangle())
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

                                textPosition = clampedTextPosition(newPos)

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
                                textFontSize = min(max(baseFontSize * value, 16), 72)
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
                    .position(textPosition)
                    .zIndex(20)
                    .animation(.easeInOut(duration: 0.2), value: isDraggingItem)
            }

            // ✅ STICKERS COMPLETAMENTE LIBRES - Sin interfaz de selección
            ForEach(stickers.indices, id: \.self) { index in
                // Ocultar stickers de tipo REVEAL del canvas (se muestran como badge arriba)
                if stickers[index].type != .reveal {
                    StickerOverlayView(
                        sticker: $stickers[index],
                        canvasSize: canvasSize,
                        isSelected: selectedStickerId == stickers[index].id,
                        isDragging: isDraggingItem && selectedStickerId == stickers[index].id,
                        isContentEditing: editingPolaroidId == stickers[index].id,
                        activeEditingStickerId: $activeEditingStickerId,
                        onUpdate: { updatedSticker in
                            stickers[index] = updatedSticker
                        },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                stickers.remove(at: index)
                                selectedStickerId = nil
                                activeEditingStickerId = nil
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
                                    selectedStickerId = nil
                                    activeEditingStickerId = nil
                                }
                                isOverTrash = false
                            }
                        },
                        onStickerTapped: { tappedSticker in
                            if isInlineEditableSticker(tappedSticker) {
                                focusInlineEditableSticker(tappedSticker.id)
                                return
                            }

                            let wasSelected = selectedStickerId == tappedSticker.id
                            selectedStickerId = tappedSticker.id

                            if tapCyclesStickerStyle(tappedSticker.type) {
                                if wasSelected {
                                    cycleStickerStyle(for: tappedSticker.id)
                                }
                                return
                            }

                            handleStickerTap(tappedSticker)
                        }
                    )
                    .zIndex(activeEditingStickerId == stickers[index].id ? 3000 : (editingPolaroidId == stickers[index].id ? 2000 : (selectedStickerId == stickers[index].id ? 500 : 1)))
                }
            }

            // ✅ REVEAL STATUS BADGE (Top)
            if stickers.contains(where: { $0.type == .reveal }) && editingRevealId == nil {
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
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(isOverTrash ? .red : .white)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                        .scaleEffect(isOverTrash ? 1.28 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isOverTrash)
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 📸 FONDO OSCURO DE EDICIÓN (Dentro del ZStack para controlar el zIndex)
            if editingPolaroidId != nil {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .ignoresSafeArea(.keyboard)
                    .zIndex(1500) // Entre los stickers normales y el "Hero"
                    .gesture(polaroidFrameSwipeGesture())
                    .onTapGesture {
                        savePolaroidCaption()
                    }
                    .transition(.opacity)

                VStack(spacing: 12) {
                    Spacer()

                    TextField(NSLocalizedString("storyEditor.polaroid.addNote", comment: "Prompt to add a note to a polaroid"), text: $polaroidCaptionBuffer)
                        .font(.custom("MarkerFelt-Wide", size: 24))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 25)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .submitLabel(.done)
                        .onSubmit {
                            savePolaroidCaption()
                        }
                        .frame(maxWidth: 320)
                }
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .bottom)
                .offset(y: keyboardHeight > 0 ? -(keyboardHeight - 116) : -24)
                .ignoresSafeArea(.keyboard)
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
        .onChange(of: activeEditingStickerId) { oldValue, newValue in
            if oldValue != newValue, let oldValue, oldValue != editingPolaroidId {
                restoreInlineEditableStickerIfNeeded(for: oldValue)
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingPolaroidId != nil || editingRevealId != nil
            }
        }
        .onChange(of: editingRevealId) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingSticker = newValue != nil || editingPolaroidId != nil || activeEditingStickerId != nil
            }
        }
        .onChange(of: isOverTrash) { oldValue, newValue in
            if newValue {
                HapticManager.shared.mediumImpact()
            }
        }
        .coordinateSpace(name: "storyCanvas")
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onChange(of: textFontSize) { _, _ in
            if !text.isEmpty {
                textPosition = clampedTextPosition(textPosition)
            }
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
        .onAppear {
            seedTextPositionIfNeeded()
        }
        .onChange(of: isTextEditorPresented) { _, isPresented in
            if !isPresented {
                seedTextPositionIfNeeded()
            }
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty {
                seedTextPositionIfNeeded()
            }
        }

    }

    private func seedTextPositionIfNeeded() {
        guard !text.isEmpty else { return }
        if StoryTextCanvasPlacement.needsSeed(position: textPosition, canvasSize: canvasSize) {
            textPosition = StoryTextCanvasPlacement.defaultPosition(in: canvasSize)
        }
        textPosition = clampedTextPosition(textPosition)
    }

    private func clampedTextPosition(_ proposedPosition: CGPoint) -> CGPoint {
        let textBounds = estimatedTextBounds()
        let halfWidth = min(textBounds.width / 2, canvasSize.width / 2)
        let halfHeight = min(textBounds.height / 2, canvasSize.height / 2)

        return CGPoint(
            x: min(max(proposedPosition.x, halfWidth), canvasSize.width - halfWidth),
            y: min(max(proposedPosition.y, halfHeight), canvasSize.height - halfHeight)
        )
    }

    private func estimatedTextBounds() -> CGSize {
        guard !text.isEmpty else { return CGSize(width: 44, height: 44) }

        let config = StoryTextRenderConfiguration(
            text: text,
            style: textStyle,
            visualEffect: visualEffect,
            textColor: textColor,
            textAlignment: textAlignment,
            textBackgroundFill: textBackgroundFill,
            fontSize: textFontSize,
            textStroke: textStroke,
            forcesAllCaps: forcesAllCaps
        )
        let maxTextWidth = max(canvasSize.width - 76, 120)
        let measured = StoryTextAttributesBuilder.measuredSize(for: config, maxWidth: maxTextWidth)

        return CGSize(
            width: min(canvasSize.width, measured.width + 28 + 48),
            height: min(canvasSize.height, measured.height + 20)
        )
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
        let trashCenter = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height - 44 // 20px padding + 24px (mitad de un tamaño de 48pt)
        )
        let dx = point.x - trashCenter.x
        let dy = point.y - trashCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance < 60 // Radio de detección discreto y preciso (60pt)
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

    private func focusInlineEditableSticker(_ stickerId: String) {
        guard let index = stickers.firstIndex(where: { $0.id == stickerId }) else { return }

        if focusedInlineStickerTransform?.id != stickerId {
            restoreCurrentInlineEditableStickerIfNeeded(except: stickerId)

            let original = stickers[index]
            focusedInlineStickerTransform = (original.id, original.position, original.scale, original.rotation)

            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                stickers[index].position = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 3)
                stickers[index].scale = focusedInlineScale(for: original.type, originalScale: original.scale)
                stickers[index].rotation = .zero
            }
        }

        activeEditingStickerId = stickerId
        selectedStickerId = stickerId
        HapticManager.shared.mediumImpact()
    }

    private func restoreCurrentInlineEditableStickerIfNeeded(except stickerId: String? = nil) {
        guard let focused = focusedInlineStickerTransform else { return }
        guard focused.id != stickerId else { return }
        restoreInlineEditableStickerIfNeeded(for: focused.id)
    }

    private func restoreInlineEditableStickerIfNeeded(for stickerId: String) {
        guard let focused = focusedInlineStickerTransform, focused.id == stickerId else { return }
        guard let index = stickers.firstIndex(where: { $0.id == stickerId }) else {
            focusedInlineStickerTransform = nil
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            stickers[index].position = focused.pos
            stickers[index].scale = focused.scale
            stickers[index].rotation = focused.rot
        }

        focusedInlineStickerTransform = nil
    }

    private func focusedInlineScale(for type: StickerItem.StickerType, originalScale: CGFloat) -> CGFloat {
        let minimumFocusScale: CGFloat

        switch type {
        case .poll, .quiz:
            minimumFocusScale = 1.12
        case .question, .countdown, .emojiSlider, .hashtag:
            minimumFocusScale = 1.18
        default:
            minimumFocusScale = 1.14
        }

        return max(originalScale, minimumFocusScale)
    }

    private func polaroidFrameSwipeGesture() -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) >= 36 else { return }
                cyclePolaroidFrameStyle(direction: horizontal < 0 ? 1 : -1)
            }
    }

    private func cyclePolaroidFrameStyle(direction: Int) {
        guard let editingPolaroidId,
              let index = stickers.firstIndex(where: { $0.id == editingPolaroidId })
        else { return }

        let allStyles = StoryPolaroidFrameStyle.allCases
        let currentStyle = StoryPolaroidFrameStyle(rawValueOrDefault: stickers[index].interactionData?.frameStyle)
        guard let currentIndex = allStyles.firstIndex(of: currentStyle) else { return }

        let nextIndex = (currentIndex + direction + allStyles.count) % allStyles.count
        var interactionData = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
        interactionData.frameStyle = allStyles[nextIndex].rawValue
        stickers[index].interactionData = interactionData
        HapticManager.shared.lightImpact()
    }

    private func isInlineEditableSticker(_ sticker: StickerItem) -> Bool {
        switch sticker.type {
        case .poll, .question, .quiz, .countdown, .emojiSlider:
            return true
        case .hashtag:
            // Solo editable inline al crearse (cuando está vacío)
            if let hashtag = sticker.interactionData?.hashtag {
                return hashtag.isEmpty
            }
            return true
        default:
            return false
        }
    }

    private func tapCyclesStickerStyle(_ type: StickerItem.StickerType) -> Bool {
        switch type {
        case .location, .mention, .link, .hashtag, .time, .questionResponse:
            return true
        default:
            return false
        }
    }

    private func cycleStickerStyle(for stickerId: String) {
        guard let index = stickers.firstIndex(where: { $0.id == stickerId }) else { return }

        let sticker = stickers[index]
        var interactionData = stickers[index].interactionData ?? StickerItem.StickerInteractionData()
        let variantCount = styleVariantCount(for: sticker.type)
        interactionData.styleVariant = ((interactionData.styleVariant ?? 0) + 1) % variantCount

        if sticker.type == .questionResponse,
           let questionText = interactionData.questionText {
            let updatedImage = makeQuestionResponseStickerImage(
                questionText: questionText,
                styleVariant: interactionData.styleVariant ?? 0,
                colorScheme: colorScheme
            )

            stickers[index] = StickerItem(
                id: sticker.id,
                image: updatedImage,
                position: sticker.position,
                scale: sticker.scale,
                rotation: sticker.rotation,
                gifURL: sticker.gifURL,
                videoURL: sticker.videoURL,
                isAnimated: sticker.isAnimated,
                type: sticker.type,
                interactionData: interactionData
            )
        } else {
            stickers[index].interactionData = interactionData
        }

        HapticManager.shared.lightImpact()
    }

    private func styleVariantCount(for type: StickerItem.StickerType) -> Int {
        switch type {
        case .questionResponse:
            return 6
        default:
            return 4
        }
    }
}
