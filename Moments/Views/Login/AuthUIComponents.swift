import SwiftUI
import PhotosUI

// MARK: - Enhanced Profile Photo Picker
struct EnhancedProfilePhotoPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: UIImage?
    @Binding var showingPhotoPicker: Bool
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: { showingPhotoPicker = true }) {
                EnhancedProfilePhotoContent(profileImage: profileImage)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isPressed), value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        profileImage = image
                    }
                }
            }
            
            Text("register.profilePhoto.optional")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.62))
        }
    }
}

// MARK: - Enhanced Profile Photo Content
struct EnhancedProfilePhotoContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let profileImage: UIImage?
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        ZStack {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: AuthFormMetrics.profilePhotoSize, height: AuthFormMetrics.profilePhotoSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.42), .blue.opacity(0.24)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .white.opacity(glowIntensity * 0.55), radius: 7, x: 0, y: 0)
                    .shadow(color: .blue.opacity(0.15), radius: 14, x: 0, y: 0)
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AuthColors.subtle(colorScheme, opacity: 0.12), AuthColors.subtle(colorScheme, opacity: 0.04)],
                            center: .center,
                            startRadius: 8,
                            endRadius: AuthFormMetrics.profilePhotoSize / 2
                        )
                    )
                    .frame(width: AuthFormMetrics.profilePhotoSize, height: AuthFormMetrics.profilePhotoSize)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AuthColors.secondary(colorScheme, opacity: 0.78), .blue.opacity(0.46)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("register.profilePhoto.add")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.64))
                        }
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.24), .blue.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                            )
                    )
                    .shadow(color: .white.opacity(0.08), radius: 10, x: 0, y: 0)
            }
            
            if profileImage != nil {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .blue.opacity(0.7)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 16
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                    )
                    .offset(x: AuthFormMetrics.profilePhotoSize * 0.32, y: AuthFormMetrics.profilePhotoSize * 0.32)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.42
            }
        }
    }
}

// MARK: - Enhanced Interests Selector
enum RegisterInterestsPolicy {
    static let minimum = 3
    static let maximum = 5
}

struct EnhancedInterestsSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var availableInterests: [String]
    @Binding var selectedInterests: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AuthColors.secondary(colorScheme, opacity: 0.92), .blue.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("register.interests.title")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.94))
                }
                
                Spacer()
                
                Text(String(format: NSLocalizedString("register.interests.count", comment: "Interests count"), selectedInterests.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedInterests.count >= RegisterInterestsPolicy.minimum
                            ? AuthColors.primary(colorScheme)
                            : .orange.opacity(0.92)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Color.clear
                            .liquidGlass(in: Capsule())
                    }
            }

            Text("register.interests.description")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.62))
                .fixedSize(horizontal: false, vertical: true)

            if selectedInterests.count < RegisterInterestsPolicy.minimum {
                Text("register.interests.minimumHint")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(availableInterests, id: \.self) { interest in
                    EnhancedInterestChip(
                        interest: interest,
                        isSelected: selectedInterests.contains(interest),
                        onTap: {
                            if selectedInterests.contains(interest) {
                                selectedInterests.removeAll { $0 == interest }
                            } else if selectedInterests.count < RegisterInterestsPolicy.maximum {
                                selectedInterests.append(interest)
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Enhanced Interest Chip
struct EnhancedInterestChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let interest: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            Text("\(InterestCatalog.emoji(for: interest)) \(InterestOption.localize(interest))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? AuthColors.primary(colorScheme) : AuthColors.secondary(colorScheme, opacity: 0.72))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background {
                    Color.clear
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .overlay {
                    Capsule()
                        .stroke(AuthColors.subtle(colorScheme, opacity: isSelected ? 0.34 : 0.08), lineWidth: isSelected ? 1.4 : 0.8)
                        .allowsHitTesting(false)
                }
                .scaleEffect(isSelected ? 1.03 : (isPressed ? 0.97 : 1.0))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isSelected), value: isSelected)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .accessibilityLabel(Text(InterestOption.localize(interest)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            isPressed = pressing
        })
    }
}

// MARK: - Enhanced Custom Toggle Style
struct EnhancedCustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(
                        configuration.isOn ?
                        LinearGradient(
                            colors: [.green.opacity(0.8), .green.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 50, height: 28)
                    .shadow(
                        color: configuration.isOn ? .green.opacity(0.3) : .clear,
                        radius: configuration.isOn ? 8 : 0,
                        x: 0,
                        y: 0
                    )
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.8)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 12
                        )
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .offset(x: configuration.isOn ? 11 : -11)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: configuration.isOn), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

// MARK: - Enhanced Flow Layout
struct EnhancedFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                     y: result.positions[index].y + bounds.minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

// MARK: - Placeholder Extension
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
