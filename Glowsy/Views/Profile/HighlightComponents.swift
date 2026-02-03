import SwiftUI
import Kingfisher

// MARK: - Selectable Story Card (Premium Style Shared Component)
struct SelectableStoryCard: View {
    let story: Story
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Media
                let urlString = story.mediaItem.thumbnailUrl ?? story.mediaItem.url
                if let url = URL(string: urlString) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: (UIScreen.main.bounds.width - 4) / 3, height: (UIScreen.main.bounds.width - 4) / 3)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: (UIScreen.main.bounds.width - 4) / 3, height: (UIScreen.main.bounds.width - 4) / 3)
                }
                
                // Content Overlay (Diferenciar video)
                if story.mediaItem.type == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Spacer()
                        }
                        .padding(6)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    }
                }
                
                // Premium Selection Style
                if isSelected {
                    // Border Gradient
                    Rectangle()
                        .strokeBorder(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                    
                    // Subtle dark overlay
                    Color.black.opacity(0.15)
                    
                    // High-end indicator
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 22, height: 22)
                                    .shadow(radius: 2)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .scaleEffect(isSelected ? 0.96 : 1.0)
            .animation(.interactiveSpring(), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
