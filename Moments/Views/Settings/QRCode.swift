import SwiftUI
import CoreImage.CIFilterBuiltins
import FirebaseAuth

struct QRCodeView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = QRCodeViewModel()
    @StateObject private var photosSaveGate = PermissionPrimerGate(.photosSave)
    @State private var showShareSheet = false
    @State private var qrImage: UIImage?
    var targetUser: AppUser? = nil
    var onClose: (() -> Void)? = nil
    
// MARK: - Modern Sheet View
    var body: some View {
        VStack(spacing: 0) {
            // Header con título
            ZStack {
                Text(NSLocalizedString("qrCode.title", comment: "QR code title"))
                    .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                if onClose != nil {
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ProfileColors.textPrimary)
                                .frame(width: 38, height: 38)
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            
            // Tarjeta QR Limpia
            VStack(spacing: 20) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                } else {
                    ProgressView()
                        .frame(width: 200, height: 200)
                }
                
                Text("@\(targetUser?.username ?? viewModel.user?.username ?? "")")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(ProfileColors.accent)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(hex: "1A1A1A") : .white)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(.bottom, 30)
            
            // Botones de acción
            if targetUser == nil {
                HStack(spacing: 16) {
                    Button(action: {
                        showShareSheet = true
                    }) {
                        HStack(spacing: 8) {
                            AttachmentIconView(icon: .share, preset: .shareInline, tintColor: .white)
                            Text(NSLocalizedString("qrCode.share", comment: "Share"))
                        }
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ProfileColors.accent)
                        .clipShape(Capsule())
                    }

                    Button(action: {
                        guard let qrImage = qrImage else { return }
                        photosSaveGate.requestAccess {
                            UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 20))
                            .foregroundStyle(ProfileColors.textPrimary)
                            .frame(width: 50, height: 50)
                            .background(ProfileColors.materialBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(ProfileColors.borderColor, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            } else {
                Spacer()
                    .frame(height: 20)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            viewModel.loadUserData()
            generateQRCode()
        }
        .onChange(of: viewModel.user) { _, _ in
            generateQRCode()
        }
        .sheet(isPresented: $showShareSheet) {
            if let qrImage = qrImage {
                QRShareSheet(activityItems: [qrImage, URL(string: "https://glowsy.app/\(targetUser?.username ?? viewModel.user?.username ?? "")")!])
            }
        }
        .permissionPrimerGate(photosSaveGate)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
    
    private func generateQRCode() {
        guard let username = targetUser?.username ?? viewModel.user?.username else { return }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        // ✅ URL FINAL: glowsy://profile/username
        // Esto abrirá la app y navegará al perfil del usuario
        let deepLink = "glowsy://profile/\(username)"
        let data = Data(deepLink.utf8)
        
        filter.setValue(data, forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                qrImage = UIImage(cgImage: cgImage)
            }
        }
    }
}

struct QRShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

class QRCodeViewModel: ObservableObject {
    @Published var user: AppUser?
    private let firestoreService = FirestoreService()
    
    func loadUserData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    self?.user = user
                case .failure:
                    break
                }
            }
        }
    }
}
