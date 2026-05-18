import SwiftUI

struct MomentDetailFromNotificationView: View {
    let momentId: String
    let userId: String  // ✅ Ahora required
    @Binding var isPresented: Bool
    @State private var moment: Moment?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingMomentView()
            } else if let errorMessage = errorMessage {
                ErrorMomentView(message: errorMessage) {
                    isPresented = false
                }
            } else if let moment = moment {
                MomentDetailView(moment: moment)
            } else {
                ErrorMomentView(message: "Momento no encontrado") {
                    isPresented = false
                }
            }
        }
        .onAppear {
            loadMoment()
        }
    }

    private func loadMoment() {
        // ✅ USAR TU MÉTODO EXISTENTE
        FirestoreService().fetchMoment(momentId: momentId, userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loadedMoment):
                    moment = loadedMoment
                case .failure(let error):
                    errorMessage = "No se pudo cargar el momento"
                }
            }
        }
    }
}

struct LoadingMomentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
                    .scaleEffect(1.5)

                Text("feed.loadingMoment")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
            }
        }
    }
}

struct ErrorMomentView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)

                Text(message)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Button("Cerrar") {
                    onClose()
                }
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.red)
                .clipShape(Capsule())
            }
            .padding(40)
        }
    }
}
