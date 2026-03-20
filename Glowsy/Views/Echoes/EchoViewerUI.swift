import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth
import MapKit
import CoreLocation

struct EchoViewerUI: View {
    let echoId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: EchoViewModel
    
    // ✅ Gesture State
    @State private var dragOffset: CGFloat = 0
    @State private var showLockoutAlert = false // ✅ NUEVO
    @State private var selectedLocationPresentation: EchoLocationPresentation?
    
    private struct EchoLocationPresentation: Identifiable {
        let id: String
        let locationName: String
        let coordinate: CLLocationCoordinate2D
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
                        if viewModel.isEchoActive {
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
                            }
                        } else {
                            // Si no hay al menos 2 personas, mostramos el estado de espera
                            waitingStateView
                        }
                    }
                    .overlay(rippleEffect)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if viewModel.isEchoActive {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                guard viewModel.isEchoActive else { return }
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
                    if viewModel.isEchoActive {
                        lateralVerticalIndicator()
                    }
                }
                
                // ✅ NUEVO: Custom Glass Alert
                if showLockoutAlert {
                    glassAlertView
                }
            }
        }
        .onAppear { viewModel.loadEcho() }
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
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: viewModel.isLoading)
                }
                
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
        VStack(spacing: 10) {
            if !viewModel.groupedPerspectives.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<viewModel.groupedPerspectives.count, id: \.self) { index in
                        Capsule()
                            .fill(index < viewModel.currentPerspectiveIndex ? Color.white : Color.white.opacity(0.28))
                            .frame(height: 2.8)
                            .overlay(alignment: .leading) {
                                if index == viewModel.currentPerspectiveIndex {
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .animation(.easeInOut(duration: 0.18), value: viewModel.currentPerspectiveIndex)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    if viewModel.currentPerspectiveIndex < viewModel.groupedPerspectives.count {
                        let p = viewModel.groupedPerspectives[viewModel.currentPerspectiveIndex]
                        AsyncProfileImageView(userId: p.authorId)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.username)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(relativeTimeText(from: viewModel.currentMoment?.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }
                }
                .padding(.leading, 2)
                
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
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
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
                                .fill(index == viewModel.currentVerticalIndex ? Color.orange : Color.white.opacity(0.4))
                                .frame(width: 4, height: index == viewModel.currentVerticalIndex ? 24 : 12)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.trailing, 16)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.currentVerticalIndex)
                }
            }
        }
    }
    
    private func locationContextBox(echo: Echo) -> some View {
        Button {
            openInAppMap(for: echo)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.orange.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 14, weight: .bold)).foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(echo.locationName ?? NSLocalizedString("echo.viewer.location.fallback", comment: ""))
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(String(format: NSLocalizedString("echo.viewer.location.header", comment: ""), echo.createdAt.formatted(date: .omitted, time: .shortened)) + " • " + NSLocalizedString("echo.viewer.location.viewMaps", comment: ""))
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
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
        VStack(spacing: 12) {
            Text(NSLocalizedString("echo.viewer.perspective.change", comment: ""))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<viewModel.groupedPerspectives.count, id: \.self) { index in
                        let p = viewModel.groupedPerspectives[index]
                        Button {
                            guard index != viewModel.currentPerspectiveIndex else { return }
                            HapticManager.shared.selection()
                            viewModel.switchPerspective(to: index)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .trailing) {
                                    AsyncProfileImageView(userId: p.authorId)
                                        .frame(width: 52, height: 52)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(viewModel.currentPerspectiveIndex == index ? Color.white : Color.white.opacity(0.22), lineWidth: viewModel.currentPerspectiveIndex == index ? 2.2 : 1))
                                        .shadow(color: viewModel.currentPerspectiveIndex == index ? .white.opacity(0.35) : .clear, radius: 8)
                                        .scaleEffect(viewModel.currentPerspectiveIndex == index ? 1.04 : 1.0)
                                        .animation(.easeOut(duration: 0.18), value: viewModel.currentPerspectiveIndex)
                                    
                                    // Comentado para usar el lateral indicador, o dejarlo como "pista" visual sutil
                                    /*
                                    if p.moments.count > 1 {
                                        VStack(spacing: 2) {
                                            ForEach(0..<p.moments.count, id: \.self) { vIndex in
                                                Capsule()
                                                    .fill(index == viewModel.currentPerspectiveIndex && vIndex == viewModel.currentVerticalIndex ? Color.orange : Color.white)
                                                    .frame(width: 3, height: 6)
                                            }
                                        }
                                        .padding(.trailing, -6)
                                    }
                                    */
                                }
                                
                                Text(p.username)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(viewModel.currentPerspectiveIndex == index ? .white : .white.opacity(0.66))
                                    .lineLimit(1)
                                    .frame(maxWidth: 72)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
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
    
    // ✅ NUEVO: Diseño minimalista con ultraThinMaterial
    private var glassAlertView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showLockoutAlert = false }
                }
            
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(NSLocalizedString("echo.leave.locked", comment: ""))
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                
                Button(action: {
                    withAnimation { showLockoutAlert = false }
                }) {
                    Text(NSLocalizedString("echo.viewer.ok", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func openInAppMap(for echo: Echo) {
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
}

// MARK: - Safe Collection Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
