import SwiftUI
import UIKit

// MARK: - Media Editing View
struct MediaEditingView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) var colorScheme

    @State private var currentMediaIndex = 0
    @State private var showingCropView = false
    @State private var showingFilterToolbar = false // Nueva flag para el modo edición filtros
    @State private var appliedFilters: [String: FilterSettings] = [:]

    // Filtro temporal para el modo edición (antes de aplicar)
    @State private var tempFilterType: FilterService.FilterType = .normal
    @State private var tempFilterIntensity: Double = 1.0
    @State private var previewImage: UIImage? = nil
    @State private var filterTask: Task<Void, Never>? = nil

    // ✅ NUEVO: Aspect ratio recomendado (detectado automáticamente de la imagen original)
    private var recommendedAspectRatio: CreatorMedia.AspectRatio {
        guard currentMediaIndex < selectedMediaItems.count else { return .square }
        // Usar el aspect ratio recomendado guardado, o el actual si no hay recomendado
        return selectedMediaItems[currentMediaIndex].recommendedAspectRatio ?? selectedMediaItems[currentMediaIndex].aspectRatio
    }

    var body: some View {

            VStack(spacing: 0) {
                // Header (Branded)
                HStack {
                    if showingFilterToolbar {
                        Button(action: {
                            cancelFilter()
                        }) {
                            Text(NSLocalizedString("common.cancel", comment: ""))
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: {
                            applyFilter()
                        }) {
                            Text(NSLocalizedString("common.done", comment: ""))
                                .foregroundColor(.pink)
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.pink.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    } else {
                        Button(action: {
                            currentFlow = .mediaSelection
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(10)
                                .liquidGlass(in: Circle(), interactive: true)
                        }

                        Spacer()

                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 5)

                        Spacer()

                        GlowSharePill(title: "creator.next", icon: "arrow.right", isLoading: false) {
                            currentFlow = .captionAndDetails
                        }
                    }
                }
                .padding()
                .background(
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                )

                Spacer()

                // Media preview (con aspecto mejorado)
                ZStack {
                    TabView(selection: $currentMediaIndex) {
                        ForEach(selectedMediaItems.indices, id: \.self) { index in
                            ZStack {
                                if index == currentMediaIndex, let preview = previewImage, showingFilterToolbar {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(uiImage: selectedMediaItems[index].image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                            }
                            .cornerRadius(12)
                            .padding(.horizontal, 10)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)

                    // Recommended Dimensions badge
                    VStack {
                        if recommendedAspectRatio != .square || (currentMediaIndex < selectedMediaItems.count && selectedMediaItems[currentMediaIndex].aspectRatio != recommendedAspectRatio) {
                            Text("creator.recommendedDimensions")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                .padding(.top, 12)
                        }
                        Spacer()
                    }
                }

                Spacer()

                // Bottom Area: Thumbnails, Format and Tools
                VStack(spacing: 0) {
                    if showingFilterToolbar {
                        // Filter Mode View
                        VStack(spacing: 20) {
                            // Intensity Slider
                            if tempFilterType != .normal {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("creator.intensity")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(Int(tempFilterIntensity * 100))%")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.pink)
                                    }

                                    Slider(value: $tempFilterIntensity, in: 0...1)
                                        .tint(.pink)
                                        .onChange(of: tempFilterIntensity) { _ in
                                            updatePreviewTask()
                                        }
                                }
                                .padding(.horizontal, 25)
                            }

                            // Filter Carousel
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(FilterService.FilterType.allCases, id: \.self) { filter in
                                        FilterOption(
                                            image: selectedMediaItems[currentMediaIndex].image,
                                            filter: filter,
                                            isSelected: tempFilterType == filter
                                        ) {
                                            HapticManager.shared.lightImpact()
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                tempFilterType = filter
                                                if filter == .normal {
                                                    tempFilterIntensity = 1.0
                                                }
                                            }
                                            updatePreviewTask()
                                        }
                                    }
                                }
                                .padding(.horizontal, 25)
                            }
                            .frame(height: 140)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.vertical, 20)
                    } else {
                        // Regular Edit Mode View
                        VStack(spacing: 0) {
                            // Media thumbnails
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selectedMediaItems.indices, id: \.self) { index in
                                        Button(action: {
                                            withAnimation(.spring()) {
                                                currentMediaIndex = index
                                            }
                                        }) {
                                            ZStack {
                                                Image(uiImage: selectedMediaItems[index].image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 55, height: 55)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    .opacity(currentMediaIndex == index ? 1.0 : 0.6)
                                                    .scaleEffect(currentMediaIndex == index ? 1.05 : 0.95)

                                                if currentMediaIndex == index {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(
                                                            LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                            lineWidth: 2
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 60)
                            .padding(.bottom, 15)

                            // Controls Row
                            HStack(spacing: 0) {
                                // Aspect ratio selector
                                HStack(spacing: 20) {
                                    ForEach([CreatorMedia.AspectRatio.square, .portrait, .landscape], id: \.self) { ratio in
                                        Button(action: {
                                            if currentMediaIndex < selectedMediaItems.count {
                                                HapticManager.shared.lightImpact()
                                                selectedMediaItems[currentMediaIndex].aspectRatio = ratio
                                                showingCropView = true
                                            }
                                        }) {
                                            VStack(spacing: 4) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(
                                                        selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? Color.pink :
                                                        (ratio == recommendedAspectRatio ? Color.green.opacity(0.6) : Color.white.opacity(0.3)),
                                                        lineWidth: selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? 2 : 1
                                                    )
                                                    .frame(
                                                        width: ratio == .landscape ? 35 : (ratio == .square ? 25 : 20),
                                                        height: 25
                                                    )

                                                Text(ratio.displayName)
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundColor(selectedMediaItems[currentMediaIndex].aspectRatio == ratio ? .pink : .white.opacity(0.6))
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 20)

                                Spacer()

                                // Editing tools (Glassmorphic)
                                HStack(spacing: 12) {
                                    ToolIconButton(icon: "crop.rotate") { showingCropView = true }
                                    ToolIconButton(icon: "camera.filters") {
                                        enterFilterMode()
                                    }
                                }
                                .padding(.trailing, 20)
                            }
                            .padding(.bottom, 30)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                )
            }
        .navigationBarHidden(true)
        .background(
            ZStack {
                Color.black.ignoresSafeArea()
                if currentMediaIndex < selectedMediaItems.count {
                    Image(uiImage: selectedMediaItems[currentMediaIndex].image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.4))
                        .ignoresSafeArea()
                }
            }
        )
        .sheet(isPresented: $showingCropView) {
            if currentMediaIndex < selectedMediaItems.count {
                // ✅ MEJORADO: Usar el aspect ratio recomendado si el usuario no ha seleccionado uno manualmente
                let currentAspectRatio = selectedMediaItems[currentMediaIndex].aspectRatio
                let aspectRatioToUse = currentAspectRatio == .square && recommendedAspectRatio != .square
                    ? recommendedAspectRatio
                    : currentAspectRatio

                CropViewWrapper(
                    image: selectedMediaItems[currentMediaIndex].image,
                    aspectRatio: aspectRatioToUse,
                    allowFreeCrop: true // ✅ NUEVO: Permitir crop libre (no bloquear ratio)
                ) { croppedImage, newAspectRatio in
                    selectedMediaItems[currentMediaIndex].image = croppedImage
                    selectedMediaItems[currentMediaIndex].aspectRatio = newAspectRatio
                    selectedMediaItems[currentMediaIndex].hasEdits = true
                    // ✅ Reset filter task and applied filters if needed when image changes
                    updatePreviewTask()
                }
            }
        }
    }

    // MARK: - Filter Logic Integration

    private func enterFilterMode() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let currentItem = selectedMediaItems[currentMediaIndex]

        // Cargar ajustes actuales si existen
        if let settings = appliedFilters[currentItem.id],
           let type = FilterService.FilterType(rawValue: settings.name) {
            tempFilterType = type
            tempFilterIntensity = settings.intensity
        } else {
            tempFilterType = .normal
            tempFilterIntensity = 1.0
        }

        withAnimation(.spring()) {
            showingFilterToolbar = true
        }
        updatePreviewTask()
    }

    private func cancelFilter() {
        filterTask?.cancel()
        withAnimation(.spring()) {
            showingFilterToolbar = false
            previewImage = nil
        }
    }

    private func applyFilter() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let currentItemId = selectedMediaItems[currentMediaIndex].id

        // Guardar ajustes
        let settings = FilterSettings(name: tempFilterType.rawValue, intensity: tempFilterIntensity)
        appliedFilters[currentItemId] = settings

        // Aplicar permanentemente a la imagen de la lista si no es normal
        if let preview = previewImage {
            selectedMediaItems[currentMediaIndex].image = preview
            selectedMediaItems[currentMediaIndex].hasEdits = true
        }

        withAnimation(.spring()) {
            showingFilterToolbar = false
            previewImage = nil
        }
    }

    private func updatePreviewTask() {
        guard currentMediaIndex < selectedMediaItems.count else { return }
        let baseImage = selectedMediaItems[currentMediaIndex].image

        filterTask?.cancel()

        if tempFilterType == .normal {
            previewImage = nil
            return
        }

        let tempFilterType = self.tempFilterType
        let tempFilterIntensity = self.tempFilterIntensity

        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 45_000_000)

            if Task.isCancelled { return }

            let filtered = FilterService.shared.applyFilter(tempFilterType, to: baseImage, intensity: tempFilterIntensity)

            if !Task.isCancelled {
                await MainActor.run {
                    self.previewImage = filtered
                }
            }
        }
    }
}
