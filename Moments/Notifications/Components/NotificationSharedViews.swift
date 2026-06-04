import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Combine

struct NotificationDateHeaderView: View {
    let dateString: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            Text(localizedDateString(dateString))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.6))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }

    private func localizedDateString(_ dateString: String) -> String {
        switch dateString {
        case "New": return NSLocalizedString("notifications.section.new", comment: "New")
        case "This Week": return NSLocalizedString("notifications.section.this_week", comment: "This Week")
        case "This Month": return NSLocalizedString("notifications.section.this_month", comment: "This Month")
        case "Earlier": return NSLocalizedString("notifications.section.earlier", comment: "Earlier")
        default: return dateString
        }
    }
}

struct NotificationSkeletonRow: View {
    let colorScheme: ColorScheme // ✅ AGREGADO
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.05),
                            lineWidth: 0.5
                        ) // ✅ ADAPTATIVO
                )
            
            HStack(spacing: 15) {
                Circle()
                    .fill(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                        Color.gray.opacity(0.2)
                    ) // ✅ ADAPTATIVO
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            colorScheme == .dark ?
                            Color.gray.opacity(0.3) :
                            Color.gray.opacity(0.2)
                        ) // ✅ ADAPTATIVO
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            colorScheme == .dark ?
                            Color.gray.opacity(0.3) :
                            Color.gray.opacity(0.2)
                        ) // ✅ ADAPTATIVO
                        .frame(width: 100, height: 12)
                }
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                        Color.gray.opacity(0.2)
                    ) // ✅ ADAPTATIVO
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

struct NotificationDeletionUndoToast: View {
    let deletedCount: Int
    let colorScheme: ColorScheme
    let onUndo: () -> Void

    private var message: String {
        deletedCount > 1
            ? NSLocalizedString("notifications.deleted.toast.plural", comment: "Notifications deleted toast")
            : NSLocalizedString("notifications.deleted.toast", comment: "Notification deleted toast")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onUndo) {
                Text(NSLocalizedString("notifications.deleted.undo", comment: "Undo notification deletion"))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// ✅ BUTTON STYLES GLASSMORPHIC ADAPTATIVO
struct GlassmorphicButtonStyle: ButtonStyle {
    let color: Color
    let colorScheme: ColorScheme // ✅ AGREGADO
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Poppins-SemiBold", size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.3) :
                        Color.black.opacity(0.2),
                        lineWidth: 1
                    ) // ✅ ADAPTATIVO
            )
            .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
