import SwiftUI

struct FloatingGlassFeedToggle: View {
    @Binding var selectedFeedType: FeedType
    @Namespace private var animationNamespace
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(FeedType.allCases, id: \.self) { feedType in
                            FeedTypeButton(
                                type: feedType,
                                selectedType: selectedFeedType,
                                namespace: animationNamespace
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeedType = feedType
                                }
                                
                                // Haptic feedback
                                let impactMed = UIImpactFeedbackGenerator(style: .light)
                                impactMed.impactOccurred()
                                
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(FeedType.allCases, id: \.self) { feedType in
                        FeedTypeButton(
                            type: feedType,
                            selectedType: selectedFeedType,
                            namespace: animationNamespace
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFeedType = feedType
                            }
                            
                            // Haptic feedback
                            let impactMed = UIImpactFeedbackGenerator(style: .light)
                            impactMed.impactOccurred()
                            
                        }
                    }
                }
            }
        }
        .padding(4) // ✅ RESTORED to 4 (Original size)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .glassEffect(.regular, in: Capsule()) // 💧 'waterDrop' not available, using .regular
            } else {
                ZStack {
                    // Enhanced glass morphism effect (Water Drop) - Fallback
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    // Enhanced border gradient to stimulate light reflection
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
        }
    }
}

private struct FeedTypeButton: View {
    let type: FeedType
    let selectedType: FeedType
    let namespace: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var isSelected: Bool {
        selectedType == type
    }
    
    var body: some View {
        Button(action: action) {
            Text(type.title)
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.8)))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "00A896").opacity(0.8), // Teal
                                        Color.purple.opacity(0.8)          // Purple
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .matchedGeometryEffect(id: "background", in: namespace)
                            .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Preview to verify the design
struct FloatingGlassFeedToggle_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FloatingGlassFeedToggle(selectedFeedType: .constant(.forYou))
        }
    }
}
