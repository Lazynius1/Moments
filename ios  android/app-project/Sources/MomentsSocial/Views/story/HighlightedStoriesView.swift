import SwiftUI

struct HighlightedStoriesView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel = HighlightedStoriesViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text(NSLocalizedString("highlightedStories.loading", comment: "Loading highlighted stories"))
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                    }
                } else if viewModel.highlightedStories.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "star.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("highlightedStories.empty", comment: "No highlighted stories"))
                                .font(.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Text(NSLocalizedString("highlightedStories.emptyDescription", comment: "Mark your favorite stories as highlighted to save them here"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(NSLocalizedString("highlightedStories.create", comment: "Create highlighted")) {
                            // TODO: Implementar creación de destacada
                        }
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "00A896"))
                        .cornerRadius(25)
                    }
                    .padding()
                } else {
                    // Highlighted stories content
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.highlightedStories, id: \.id) { highlight in
                                HighlightedStoryCard(highlight: highlight)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("highlightedStories.title", comment: "Highlighted stories"))
            .navigationBarTitleDisplayMode(.large)
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("highlightedStories.new", comment: "New highlighted")) {
                        // TODO: Implementar creación de nueva destacada
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(Color(hex: "00A896"))
                }
            }
            .onAppear {
                viewModel.loadHighlightedStories()
            }
        }
    }
}

// MARK: - Highlighted Story Card
struct HighlightedStoryCard: View {
    @Environment(\.colorScheme) var colorScheme
    let highlight: HighlightedStory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Cover image
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "star.fill")
                            .foregroundColor(Color(hex: "00A896"))
                            .font(.system(size: 24))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlight.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(String(format: NSLocalizedString("highlightedStories.storyCount", comment: "Story count"), highlight.storiesCount, highlight.storiesCount == 1 ? "" : "s"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    Text("Creada \(formatDate(highlight.createdAt))")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(colorScheme == .dark ? .black : .white).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Highlighted Story Model
struct HighlightedStory: Identifiable {
    let id: String
    let title: String
    let coverImageUrl: String?
    let storiesCount: Int
    let createdAt: Date
    let stories: [Story]
}

// MARK: - Highlighted Stories ViewModel
class HighlightedStoriesViewModel: ObservableObject {
    @Published var highlightedStories: [HighlightedStory] = []
    @Published var isLoading = false
    
    private let firestoreService = FirestoreService()
    
    func loadHighlightedStories() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        // TODO: Implementar carga de historias destacadas desde Firestore
        // Por ahora, simulamos datos vacíos
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
            self.highlightedStories = []
        }
    }
}

// MARK: - Preview
struct HighlightedStoriesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HighlightedStoriesView()
        }
        .preferredColorScheme(.light)
        
        NavigationView {
            HighlightedStoriesView()
        }
        .preferredColorScheme(.dark)
    }
}
