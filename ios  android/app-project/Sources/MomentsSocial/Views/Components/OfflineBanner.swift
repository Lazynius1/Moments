import SwiftUI

struct OfflineBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    let onRetry: () -> Void
    
    var body: some View {
        if !networkMonitor.isConnected {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("network.offline.title")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                            Text("network.offline.retry")
                                .font(.custom("Poppins-Medium", size: 12))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#5b2c6f").opacity(0.9), Color(hex: "#007bff").opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkMonitor.isConnected)
        }
    }
}

struct SlowConnectionBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    
    var body: some View {
        if networkMonitor.isSlowConnection {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "tortoise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("network.slow.title")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: networkMonitor.connectionType.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#007bff").opacity(0.9), Color(hex: "#40dfcf").opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkMonitor.isSlowConnection)
        }
    }
}

#Preview {
    VStack {
        OfflineBanner(networkMonitor: NetworkMonitor.shared) {
        }
        
        SlowConnectionBanner(networkMonitor: NetworkMonitor.shared)
        
        Spacer()
    }
    .padding()
}
