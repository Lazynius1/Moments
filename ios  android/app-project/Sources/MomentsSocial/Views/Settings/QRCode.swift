import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel = QRCodeViewModel()
    @State var showShareSheet = false
    @State var qrImage: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(NSLocalizedString("qrCode.title", comment: "QR code title"))
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(NSLocalizedString("qrCode.subtitle", comment: "QR code subtitle"))
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                    }
                    
                    // QR Code Card
                    VStack(spacing: 20) {
                        // Profile Info
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: viewModel.user?.profileImagePath ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 25))
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(viewModel.user?.username ?? "")")
                                    .font(.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                if let bio = viewModel.user?.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        
                        // QR Code
                        if let qrImage = qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: .gray.opacity(0.3), radius: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 200)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                )
                        }
                        
                        Text("moments.app/\(viewModel.user?.username ?? "")")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            showShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .medium))
                                Text(NSLocalizedString("qrCode.share", comment: "Share QR code"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "00A896"))
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            if let qrImage = qrImage {
                                UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
                                // Show success feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 16, weight: .medium))
                                Text(NSLocalizedString("qrCode.saveToPhotos", comment: "Save to photos"))
                                    .font(.custom("Poppins-Medium", size: 16))
                            }
                            .foregroundColor(Color(hex: "00A896"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "00A896"), lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "00A896"))
                        }
                    }
                }
            }
            .onAppear {
                viewModel.loadUserData()
                generateQRCode()
            }
            .onChange(of: viewModel.user) { _ in
                generateQRCode()
            }
            .sheet(isPresented: $showShareSheet) {
                if let qrImage = qrImage {
                    QRShareSheet(activityItems: [qrImage])
                }
            }
        }
    }
    
    private func generateQRCode() {
        guard let username = viewModel.user?.username else { return }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        let data = Data("moments://profile/\(username)".utf8)
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
                case .failure(let error):
                    break
                }
            }
        }
    }
}
