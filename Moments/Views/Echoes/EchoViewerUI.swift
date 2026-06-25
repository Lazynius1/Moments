import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth
import MapKit
import CoreLocation
import UIKit

struct EchoViewerUI: View {
    let echoId: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: EchoViewModel
    
    // ✅ Gesture State
    @State private var dragOffset: CGFloat = 0
    @State private var showLockoutAlert = false // ✅ NUEVO
    @State private var showIncompleteDecision = false
    @State private var selectedLocationPresentation: EchoLocationPresentation?
    @State private var overlayTextTone = OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
    @State private var overlayTextToneCache: [String: OverlayTextTone] = [:]
    
    private struct EchoLocationPresentation: Identifiable {
        let id: String
        let locationName: String
        let coordinate: CLLocationCoordinate2D
    }

    private struct OverlayTextTone: Equatable {
        let topUsesDarkForeground: Bool
        let bottomUsesDarkForeground: Bool
    }
    
    init(echoId: String, initialEcho: Echo? = nil) {
        self.echoId = echoId
        self._viewModel = StateObject(wrappedValue: EchoViewModel(echoId: echoId, initialEcho: initialEcho))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "0B1215").ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else if let echo = viewModel.echo {
                    // Main Content: Media Player with 2D Navigation
                    ZStack {
                        if let currentMoment = viewModel.currentMoment {
                            let isAvailable = viewModel.momentAvailability[currentMoment.momentId] ?? true
                            
                            perspectiveView(for: currentMoment)
                                .blur(radius: isAvailable ? 0 : 20)
                                .overlay {
                                    if !isAvailable { unavailableOverlay }
                                }
                                .clipped()
                                .id(currentMoment.momentId)
                                .transition(.asymmetric(
                                    insertion: .move(edge: dragOffset > 0 ? .top : .bottom).combined(with: .opacity),
                                    removal: .move(edge: dragOffset > 0 ? .bottom : .top).combined(with: .opacity)
                                ))
                        } else if viewModel.isHistoricalIncomplete {
                            Color(hex: "0B1215").ignoresSafeArea()
                        } else {
                            waitingStateView
                        }
                    }
                    .overlay(rippleEffect)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if viewModel.canBrowseMedia {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                guard viewModel.canBrowseMedia else { return }
                                let threshold: CGFloat = 50
                                if value.translation.height < -threshold {
                                    HapticManager.shared.selection()
                                    viewModel.switchVerticalIndex(to: viewModel.currentVerticalIndex + 1)
                                } else if value.translation.height > threshold {
                                    HapticManager.shared.selection()
                                    viewModel.switchVerticalIndex(to: viewModel.currentVerticalIndex - 1)
                                }
                                dragOffset = 0
                            }
                    )
                    
                    // Overlay UI
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(geometry.safeAreaInsets.top, 47) + 8)

                        headerUI()

                        locationContextBox(echo: echo)

                        Spacer()

                        perspectiveSwitcher(echo: echo)
                    }
                    .padding(.bottom, 0)
                    .ignoresSafeArea(.container, edges: .top)
                    
                    // ✅ Lateral Vertical Indicator
                    if viewModel.canBrowseMedia {
                        lateralVerticalIndicator()
                    }
                }
                
                // ✅ NUEVO: Custom Glass Alert
                if showLockoutAlert {
                    glassAlertView
                }

                if showIncompleteDecision {
                    incompleteDecisionOverlay
                }
            }
        }
        .onAppear {
            showIncompleteDecision = viewModel.isHistoricalIncomplete
            viewModel.loadEcho()
        }
        .onChange(of: viewModel.isHistoricalIncomplete) { _, isIncomplete in
            if isIncomplete {
                showIncompleteDecision = true
            } else {
                showIncompleteDecision = false
            }
        }
        .onChange(of: currentToneAssetKey) { _, _ in
            refreshOverlayTextTone()
        }
        .fullScreenCover(item: $selectedLocationPresentation) { presentation in
            LocationMapView(
                locationName: presentation.locationName,
                coordinate: presentation.coordinate,
                echoHistoryUserId: Auth.auth().currentUser?.uid,
                echoHistoryOnly: true,
                isPresented: Binding(
                    get: { selectedLocationPresentation != nil },
                    set: { if !$0 { selectedLocationPresentation = nil } }
                )
            )
        }
    }
    
    private var unavailableOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 16) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.8))
                Text(NSLocalizedString("echo.viewer.unavailable", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var waitingStateView: some View {
        ZStack {
            Color(hex: "0B1215").ignoresSafeArea()
            
            VStack(spacing: 24) {
                EchoesIconView(
                    size: EchoesIconMetrics.viewerLoading,
                    gradient: EchoesIconView.echoesBrandGradient
                )
                .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: viewModel.isLoading)
                
                VStack(spacing: 8) {
                    Text(NSLocalizedString("echo.viewer.waiting.title", comment: ""))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(NSLocalizedString("echo.viewer.waiting.subtitle", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Un pequeño indicador de quién falta o quién ya está
                HStack(spacing: -10) {
                    ForEach(viewModel.echo?.participants ?? []) { p in
                        AsyncProfileImageView(userId: p.userId)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(p.status == .accepted ? Color.orange : Color.white.opacity(0.2), lineWidth: 2))
                            .opacity(p.status == .accepted ? 1.0 : 0.4)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var incompleteDecisionOverlay: some View {
        let primaryTextColor = colorScheme == .dark ? Color.white : Color.black
        let secondaryTextColor = primaryTextColor.opacity(0.72)
        let dividerColor = primaryTextColor.opacity(0.12)

        return ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(NSLocalizedString("echo.viewer.incomplete.title", comment: ""))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("echo.viewer.incomplete.body", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.5)

                Button {
                    if let uid = Auth.auth().currentUser?.uid {
                        leaveEchoAction(userId: uid)
                    }
                } label: {
                    Text(NSLocalizedString("echo.viewer.incomplete.delete", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.5)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showIncompleteDecision = false
                    }
                } label: {
                    Text(NSLocalizedString("echo.viewer.incomplete.keep", comment: ""))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .frame(maxWidth: 320)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
            .zIndex(5000)
        }
    }

    // MARK: - Components
    
    private func perspectiveView(for moment: EchoMomentRef) -> some View {
        GeometryReader { proxy in
            let isHorizontal = isHorizontal(aspectRatio: moment.aspectRatio)
            ZStack {
                if isHorizontal {
                    KFImage(URL(string: moment.thumbnailUrl ?? moment.mediaUrl))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 20)
                        .opacity(0.6)
                }
                
                KFImage(URL(string: moment.thumbnailUrl ?? moment.mediaUrl))
                    .resizable()
                    .aspectRatio(contentMode: isHorizontal ? .fit : .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                
                if moment.mediaType == "video", let url = URL(string: moment.mediaUrl) {
                    GlassmorphicStoryVideoPlayer(
                        url: url,
                        isPlaying: $viewModel.isVideoPlaying,
                        isReadyToPlay: .constant(true),
                        isMutedExternally: false,
                        isHorizontalVideo: isHorizontal,
                        videoGravity: isHorizontal ? .resizeAspect : .resizeAspectFill,
                        shouldLoop: true,
                        onProgressUpdate: { _ in },
                        onVideoComplete: { }
                    )
                    .aspectRatio(contentMode: isHorizontal ? .fit : .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            }
        }
    }
    
    private func isHorizontal(aspectRatio: String?) -> Bool {
        guard let aspectRatio = aspectRatio else { return false }
        let components = aspectRatio.split(separator: ":")
        if components.count == 2, let w = Int(components[0]), let h = Int(components[1]) {
            return w > h
        }
        return false
    }
    
    private var rippleEffect: some View {
        Circle()
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            .scaleEffect(viewModel.ripplePhase)
            .opacity(1 - viewModel.ripplePhase)
            .animation(.easeOut(duration: 0.8), value: viewModel.ripplePhase)
    }
    
    private func headerUI() -> some View {
        VStack(spacing: 8) {
            if !viewModel.groupedPerspectives.isEmpty {
                HStack(spacing: 3) {
                    ForEach(0..<viewModel.groupedPerspectives.count, id: \.self) { index in
                        Capsule()
                            .fill(index < viewModel.currentPerspectiveIndex ? topPrimaryTextColor.opacity(0.46) : topPrimaryTextColor.opacity(0.18))
                            .frame(height: 2.2)
                            .overlay(alignment: .leading) {
                                if index == viewModel.currentPerspectiveIndex {
                                    Capsule()
                                        .fill(topPrimaryTextColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.18), value: viewModel.currentPerspectiveIndex)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    if viewModel.currentPerspectiveIndex < viewModel.groupedPerspectives.count {
                        let p = viewModel.groupedPerspectives[viewModel.currentPerspectiveIndex]
                        AsyncProfileImageView(userId: p.authorId)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(topPrimaryTextColor.opacity(0.28), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.username)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(topPrimaryTextColor)
                                .lineLimit(1)
                            Text(relativeTimeText(from: viewModel.currentMoment?.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(topSecondaryTextColor)
                        }
                    }
                }
                
                Spacer()
                
                Menu {
                    if let uid = Auth.auth().currentUser?.uid {
                        Button(role: .destructive) { leaveEchoAction(userId: uid) } label: {
                            Label(NSLocalizedString("echo.viewer.leave", comment: ""), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(topPrimaryTextColor)
                        .frame(width: 36, height: 36)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(topPrimaryTextColor)
                        .frame(width: 36, height: 36)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // ✅ NEW: Lateral Vertical Indicator for sub-moments
    private func lateralVerticalIndicator() -> some View {
        HStack {
            Spacer()
            
            if viewModel.currentPerspectiveIndex < viewModel.groupedPerspectives.count {
                let moments = viewModel.groupedPerspectives[viewModel.currentPerspectiveIndex].moments
                if moments.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(0..<moments.count, id: \.self) { index in
                            Capsule()
                                .fill(index == viewModel.currentVerticalIndex ? Color.white.opacity(0.92) : Color.white.opacity(0.28))
                                .frame(width: index == viewModel.currentVerticalIndex ? 4 : 3, height: index == viewModel.currentVerticalIndex ? 20 : 10)
                        }
                    }
                    .padding(.trailing, 16)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.currentVerticalIndex)
                }
            }
        }
    }
    
    private func locationContextBox(echo: Echo) -> some View {
        Button {
            openInAppMap(for: echo)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(topPrimaryTextColor.opacity(0.88))

                VStack(alignment: .leading, spacing: 1) {
                    Text(echo.locationName ?? NSLocalizedString("echo.viewer.location.fallback", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(topPrimaryTextColor)
                        .lineLimit(1)
                    Text(echo.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(topSecondaryTextColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(topPrimaryTextColor.opacity(0.34))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .momentsChromeGlass(in: Capsule(), interactive: true)
        }
        .disabled(!viewModel.canOpenLocationMap)
        .opacity(viewModel.canOpenLocationMap ? 1.0 : 0.55)
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 16).padding(.top, 10)
    }
    
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
    
    private func perspectiveSwitcher(echo: Echo) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<viewModel.groupedPerspectives.count, id: \.self) { index in
                        let p = viewModel.groupedPerspectives[index]
                        Button {
                            guard index != viewModel.currentPerspectiveIndex else { return }
                            HapticManager.shared.selection()
                            viewModel.switchPerspective(to: index)
                        } label: {
                            VStack(spacing: 6) {
                                AsyncProfileImageView(userId: p.authorId)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                viewModel.currentPerspectiveIndex == index ? Color.white.opacity(0.95) : Color.white.opacity(0.22),
                                                lineWidth: viewModel.currentPerspectiveIndex == index ? 2 : 1
                                            )
                                    )
                                    .shadow(
                                        color: viewModel.currentPerspectiveIndex == index ? Color.white.opacity(0.18) : .clear,
                                        radius: 8
                                    )
                                    .scaleEffect(viewModel.currentPerspectiveIndex == index ? 1.03 : 1.0)
                                    .animation(.easeOut(duration: 0.18), value: viewModel.currentPerspectiveIndex)
                                
                                Text(p.username)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        viewModel.currentPerspectiveIndex == index
                                            ? bottomPrimaryTextColor
                                            : bottomSecondaryTextColor
                                    )
                                    .lineLimit(1)
                                    .frame(maxWidth: 70)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private func relativeTimeText(from date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func leaveEchoAction(userId: String) {
        // Usamos el echoId del viewModel directamente para mayor seguridad
        guard let echoId = viewModel.echo?.id else {
            print("❌ Error: Echo ID is nil in Viewer")
            dismiss() // Fallback: cerrar si no hay ID
            return
        }
        
        EchoService.shared.leaveEcho(echoId: echoId, userId: userId) { error in
            if let error = error {
                print("❌ Error abandoning Echo: \(error.localizedDescription)")
                
                // Si es un error de lockout (403), mostramos alerta personalizada
                if (error as NSError).code == 403 {
                    DispatchQueue.main.async {
                        withAnimation(.spring()) {
                            showLockoutAlert = true
                        }
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }
    
    private var glassAlertView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showLockoutAlert = false }
                }
            
            VStack(spacing: 18) {
                Text(NSLocalizedString("echo.leave.locked", comment: ""))
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                
                Button(action: {
                    withAnimation { showLockoutAlert = false }
                }) {
                    Text(NSLocalizedString("echo.viewer.ok", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.22))
                        )
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .overlay {
                        Color.clear
                            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func openInAppMap(for echo: Echo) {
        guard viewModel.canOpenLocationMap else { return }
        HapticManager.shared.lightImpact()
        let resolvedLocationName = (echo.locationName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        selectedLocationPresentation = EchoLocationPresentation(
            id: echo.id ?? UUID().uuidString,
            locationName: resolvedLocationName.isEmpty
                ? NSLocalizedString("echo.viewer.location.fallback", comment: "")
                : resolvedLocationName,
            coordinate: CLLocationCoordinate2D(
            latitude: echo.location.latitude,
            longitude: echo.location.longitude
        )
        )
    }

    private var currentToneAssetKey: String? {
        guard let moment = viewModel.currentMoment else { return nil }
        if let thumbnailUrl = moment.thumbnailUrl, !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }
        if moment.mediaType == "image" {
            return moment.mediaUrl
        }
        return nil
    }

    private var topPrimaryTextColor: Color {
        overlayTextTone.topUsesDarkForeground ? .black : .white
    }

    private var topSecondaryTextColor: Color {
        overlayTextTone.topUsesDarkForeground ? .black.opacity(0.66) : .white.opacity(0.72)
    }

    private var bottomPrimaryTextColor: Color {
        overlayTextTone.bottomUsesDarkForeground ? .black : .white
    }

    private var bottomSecondaryTextColor: Color {
        overlayTextTone.bottomUsesDarkForeground ? .black.opacity(0.66) : .white.opacity(0.66)
    }

    private func refreshOverlayTextTone() {
        guard let key = currentToneAssetKey else {
            overlayTextTone = OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
            return
        }

        if let cachedTone = overlayTextToneCache[key] {
            overlayTextTone = cachedTone
            return
        }

        guard let url = URL(string: key) else {
            overlayTextTone = OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
            return
        }

        KingfisherManager.shared.retrieveImage(with: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    let tone = Self.computeOverlayTextTone(from: value.image)
                    overlayTextToneCache[key] = tone
                    if currentToneAssetKey == key {
                        overlayTextTone = tone
                    }
                case .failure:
                    let fallbackTone = OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
                    overlayTextToneCache[key] = fallbackTone
                    if currentToneAssetKey == key {
                        overlayTextTone = fallbackTone
                    }
                }
            }
        }
    }

    private static func computeOverlayTextTone(from image: UIImage) -> OverlayTextTone {
        guard let cgImage = image.cgImage else {
            return OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
        }

        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return OverlayTextTone(topUsesDarkForeground: false, bottomUsesDarkForeground: false)
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func averageLuminance(rows: Range<Int>) -> CGFloat {
            var luminanceSum: CGFloat = 0
            var sampleCount: CGFloat = 0

            for y in rows {
                for x in 0..<width {
                    let index = (y * width + x) * bytesPerPixel
                    let red = CGFloat(rawData[index]) / 255
                    let green = CGFloat(rawData[index + 1]) / 255
                    let blue = CGFloat(rawData[index + 2]) / 255
                    luminanceSum += (0.299 * red) + (0.587 * green) + (0.114 * blue)
                    sampleCount += 1
                }
            }

            guard sampleCount > 0 else { return 0 }
            return luminanceSum / sampleCount
        }

        let topLuminance = averageLuminance(rows: 0..<8)
        let bottomLuminance = averageLuminance(rows: 16..<24)

        return OverlayTextTone(
            topUsesDarkForeground: topLuminance > 0.62,
            bottomUsesDarkForeground: bottomLuminance > 0.62
        )
    }
}

// MARK: - Safe Collection Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
