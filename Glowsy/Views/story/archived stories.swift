import SwiftUI
import FirebaseAuth
import Kingfisher
import FirebaseFirestore

struct ArchiveView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ArchiveViewModel()
    @State private var selectedStory: Story?
    @State private var showStoryViewer = false
    @State private var showStoryStats = false
    @State private var viewMode: ArchiveViewMode = .vertical
    
    enum ArchiveViewMode: String, CaseIterable {
        case vertical = "Vertical"
        case grid = "Cuadrícula"
        
        var icon: String {
            switch self {
            case .vertical: return "rectangle.grid.1x2"
            case .grid: return "square.grid.3x3"
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    
                    Text("archivedStories.loading")
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray)
                }
            } else if viewModel.groupedStories.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    VStack(spacing: 8) {
                        Text("archivedStories.empty.title")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("archivedStories.empty.description")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            } else {
                // Archive content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.groupedStories.keys.sorted().reversed(), id: \.self) { dateKey in
                            if let stories = viewModel.groupedStories[dateKey], !stories.isEmpty {
                                if viewMode == .vertical {
                                    ArchiveDateSectionVertical(
                                        dateKey: dateKey,
                                        stories: stories,
                                        onStoryTap: { story in
                                            selectedStory = story
                                            showStoryViewer = true
                                        },
                                        onStatsTap: { story in
                                            selectedStory = story
                                            showStoryStats = true
                                        }
                                    )
                                } else {
                                    ArchiveDateSectionGrid(
                                        dateKey: dateKey,
                                        stories: stories,
                                        onStoryTap: { story in
                                            selectedStory = story
                                            showStoryViewer = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Archivo")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(ArchiveViewMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewMode = mode
                            }
                        }) {
                            HStack {
                                Text(mode.rawValue)
                                    .font(.custom("Poppins-Medium", size: 14))
                                
                                if viewMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "00A896"))
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: viewMode.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .onAppear {
            viewModel.loadArchivedStories()
        }
        .fullScreenCover(isPresented: $showStoryViewer) {
            if let story = selectedStory {
                SingleStoryViewer(story: story)
            }
        }
        .sheet(isPresented: $showStoryStats) {
            if let story = selectedStory {
                StoryStatsView(story: story)
            }
        }
    }
}

// MARK: - Archive Date Section VERTICAL
struct ArchiveDateSectionVertical: View {
    @Environment(\.colorScheme) var colorScheme
    let dateKey: String
    let stories: [Story]
    let onStoryTap: (Story) -> Void
    let onStatsTap: (Story) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date header
            HStack {
                Text(formatDateKey(dateKey))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Stories in vertical format
            LazyVStack(spacing: 12) {
                ForEach(stories) { story in
                    ArchiveStoryVerticalCard(
                        story: story,
                        onTap: { onStoryTap(story) },
                        onStatsTap: { onStatsTap(story) }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            // Separator
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 12)
        }
    }
    
    private func formatDateKey(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateKey) {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "es")
            
            if Calendar.current.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            } else if Calendar.current.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
                displayFormatter.dateFormat = "d 'de' MMMM"
                return displayFormatter.string(from: date)
            } else {
                displayFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateKey
    }
}

// MARK: - Archive Date Section GRID
struct ArchiveDateSectionGrid: View {
    @Environment(\.colorScheme) var colorScheme
    let dateKey: String
    let stories: [Story]
    let onStoryTap: (Story) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(formatDateKey(dateKey))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Stories grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(stories) { story in
                    ArchiveStorySquareCard(story: story) {
                        onStoryTap(story)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }
    
    private func formatDateKey(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateKey) {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "es")
            
            if Calendar.current.isDateInToday(date) {
                return "Hoy"
            } else if Calendar.current.isDateInYesterday(date) {
                return "Ayer"
            } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
                displayFormatter.dateFormat = "d 'de' MMMM"
                return displayFormatter.string(from: date)
            } else {
                displayFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateKey
    }
}

// MARK: - Archive Story VERTICAL Card
struct ArchiveStoryVerticalCard: View {
    @Environment(\.colorScheme) var colorScheme
    let story: Story
    let onTap: () -> Void
    let onStatsTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Story thumbnail
                ZStack {
                    if let url = URL(string: story.mediaItem.url) {
                        KFImage(url)
                            .placeholder {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 70, height: 124)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray.opacity(0.5))
                                            .font(.system(size: 20))
                                    )
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 70, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 124)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                            )
                    }
                    
                    // Video indicator
                    if story.mediaItem.type == .video {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.6))
                                            .frame(width: 28, height: 28)
                                    )
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                    
                    // Duration indicator
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(story.duration))
                                .font(.custom("Poppins-Bold", size: 10))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                        }
                    }
                    .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "00A896").opacity(0.6),
                                    Color(hex: "02C39A").opacity(0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                
                // Story info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Profile image
                        if let profileImagePath = story.profileImagePath,
                           let url = URL(string: profileImagePath) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        Text(story.username)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatTime(story.timestamp))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                        
                        Text(formatRelativeDate(story.timestamp))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    // Story type and stats
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "00A896"))
                            
                            Text(story.mediaItem.type == .video ? "Video" : "Foto")
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        // Stats button
                        Button(action: onStatsTap) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue.opacity(0.8))
                                
                                Text("archivedStories.viewActivity")
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(.blue.opacity(0.8))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
                
                Spacer()
                
                // Archive indicator
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .black : .white).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        return "\(seconds)s"
    }
}

// MARK: - Archive Story SQUARE Card
struct ArchiveStorySquareCard: View {
    let story: Story
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack {
                    // Media thumbnail
                    if let url = URL(string: story.mediaItem.url) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    // Video indicator
                    if story.mediaItem.type == .video {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.5))
                                            .frame(width: 24, height: 24)
                                    )
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                    
                    // Time overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatTime(story.timestamp))
                                .font(.custom("Poppins-Bold", size: 9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                        }
                    }
                    .padding(4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Single Story Viewer
struct SingleStoryViewer: View {
    let story: Story
    @Environment(\.dismiss) var dismiss
    @State private var isLoading: Bool = true
    @State private var showContent: Bool = false
    @State private var loadingProgress: Double = 0.0
    @State private var loadingText: String = "Preparando historia..."
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Story content
            if let url = URL(string: story.mediaItem.url) {
                if story.mediaItem.type == .video {
                    GlassmorphicStoryVideoPlayer(
                        url: url, 
                        isPlaying: .constant(true),
                        isHorizontalVideo: GlassmorphicStoryViewer.isHorizontalAspectRatio(story.aspectRatio),
                        onProgressUpdate: { _ in
                            // ✅ NO NECESITAMOS PROGRESO EN ARCHIVED STORIES
                        },
                        onVideoComplete: {
                            // ✅ NO NECESITAMOS COMPLETACIÓN EN ARCHIVED STORIES
                        }
                    )
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.4), value: showContent)
                    .onAppear {
                        startLoadingSequence(isVideo: true)
                    }
                } else {
                    KFImage(url)
                        .placeholder {
                            ZStack {
                                Color.black
                                
                                if let thumbnailUrl = URL(string: story.mediaItem.url) {
                                    KFImage(thumbnailUrl)
                                        .resizable()
                                        .scaledToFill()
                                        .blur(radius: 20)
                                        .opacity(0.3)
                                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                                }
                            }
                        }
                        .onSuccess { _ in
                            withAnimation(.easeInOut(duration: 0.4)) {
                                isLoading = false
                                showContent = true
                            }
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .onAppear {
                            startLoadingSequence(isVideo: false)
                        }
                }
            }
            
            // Loading overlay
            if isLoading {
                ZStack {
                    Color.black.opacity(0.9)
                    
                    VStack(spacing: 24) {
                        // Thumbnail preview
                        if let url = URL(string: story.mediaItem.url) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 213)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .blur(radius: 2)
                                .opacity(0.6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color(hex: "00A896"), Color(hex: "02C39A")]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                        }
                        
                        VStack(spacing: 16) {
                            // Progress ring
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                                    .frame(width: 60, height: 60)
                                
                                Circle()
                                    .trim(from: 0, to: loadingProgress)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color(hex: "00A896"), Color(hex: "02C39A")]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                    )
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.3), value: loadingProgress)
                                
                                Text("\(Int(loadingProgress * 100))%")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(spacing: 8) {
                                Text(loadingText)
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.white)
                                    .animation(.easeInOut(duration: 0.3), value: loadingText)
                                
                                Text("Historia del \(formatShortDate(story.timestamp))")
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        
                        // Cancel button
                        Button(action: { dismiss() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .medium))
                                Text("archivedStories.cancel")
                                    .font(.custom("Poppins-Medium", size: 14))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .transition(.opacity)
            }
            
            // UI Overlay
            if !isLoading {
                VStack(spacing: 0) {
                    // Top section
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 30)
                        
                        // Progress bar
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.white.opacity(0.8))
                                .frame(height: 2.5)
                                .cornerRadius(1.25)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        
                        // Header
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 38, height: 38)
                                        .storyGlassmorphic()
                                    
                                    if let profileImagePath = story.profileImagePath {
                                        KFImage(URL(string: profileImagePath))
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 34, height: 34)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 28))
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(story.username)
                                        .foregroundColor(.white)
                                        .font(.custom("Poppins-SemiBold", size: 14))
                                        .lineLimit(1)
                                    
                                    Text(formatArchiveDate(story.timestamp))
                                        .foregroundColor(.white.opacity(0.7))
                                        .font(.custom("Poppins-Regular", size: 11))
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 40, height: 40)
                                    .storyGlassmorphic()
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    // Archive info
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 16))
                            
                            Text("archivedStories.archivedStory")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.custom("Poppins-Medium", size: 14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                    }
                    .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
    }
    
    private func startLoadingSequence(isVideo: Bool) {
        loadingProgress = 0.1
        loadingText = "Preparando historia..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingProgress = 0.4
                loadingText = "Descargando contenido..."
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingProgress = 0.7
                loadingText = isVideo ? "Procesando video..." : "Optimizando imagen..."
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingProgress = 0.9
                loadingText = "Casi listo..."
            }
        }
        
        let finalDelay = isVideo ? 2.0 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingProgress = 1.0
                loadingText = "¡Listo!"
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isLoading = false
                    showContent = true
                }
            }
        }
    }
    
    private func formatArchiveDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Story Stats View
struct StoryStatsView: View {
    let story: Story
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = StoryStatsViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text("archivedStories.loadingStats")
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Story preview
                            VStack(spacing: 16) {
                                if let url = URL(string: story.mediaItem.url) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 213)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                
                                VStack(spacing: 4) {
                                    Text(String(format: NSLocalizedString("archivedStories.storyFrom", comment: "Story from date"), formatStoryDate(story.timestamp)))
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(String(format: NSLocalizedString("archivedStories.publishedAt", comment: "Published at time"), formatStoryTime(story.timestamp)))
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.top, 20)
                            
                            // Stats cards
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                                StatsCard(
                                    icon: "eye.fill",
                                    title: "Visualizaciones",
                                    value: "\(viewModel.viewCount)",
                                    color: .blue
                                )
                                
                                StatsCard(
                                    icon: "heart.fill",
                                    title: "Reacciones",
                                    value: "\(viewModel.reactionCount)",
                                    color: .red
                                )
                                
                                StatsCard(
                                    icon: "paperplane.fill",
                                    title: "Compartidas",
                                    value: "\(viewModel.shareCount)",
                                    color: Color(hex: "00A896")
                                )
                                
                                StatsCard(
                                    icon: "person.2.fill",
                                    title: "Alcance",
                                    value: "\(viewModel.reachCount)",
                                    color: .purple
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // Viewers list
                            if !viewModel.viewers.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Text("archivedStories.whoViewed")
                                            .font(.custom("Poppins-SemiBold", size: 18))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                        
                                        Spacer()
                                        
                                        Text(String(format: NSLocalizedString("archivedStories.peopleCount", comment: "People count"), viewModel.viewers.count))
                                            .font(.custom("Poppins-Regular", size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    LazyVStack(spacing: 12) {
                                        ForEach(viewModel.viewers.prefix(10), id: \.id) { viewer in
                                            ViewerRow(viewer: viewer)
                                        }
                                        
                                        if viewModel.viewers.count > 10 {
                                            Button(String(format: NSLocalizedString("archivedStories.viewAll", comment: "View all"), viewModel.viewers.count)) {
                                                // TODO: Show all viewers
                                            }
                                            .font(.custom("Poppins-Medium", size: 14))
                                            .foregroundColor(Color(hex: "00A896"))
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                            }
                            
                            // Reactions list
                            if !viewModel.reactions.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Text("archivedStories.reactions")
                                            .font(.custom("Poppins-SemiBold", size: 18))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                        
                                        Spacer()
                                        
                                        Text("\(viewModel.reactions.count)")
                                            .font(.custom("Poppins-Regular", size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 20)
                                    
                                    LazyVStack(spacing: 12) {
                                        ForEach(viewModel.reactions.prefix(5), id: \.id) { reaction in
                                            ReactionRow(reaction: reaction)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Estadísticas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("archivedStories.close", comment: "Close")) {
                        dismiss()
                    }
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(Color(hex: "00A896"))
                }
            }
        }
        .onAppear {
            viewModel.loadStats(for: story)
        }
    }
    
    private func formatStoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter.string(from: date)
    }
    
    private func formatStoryTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Stats Card
struct StatsCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(title)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(colorScheme == .dark ? .black : .white).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Viewer Row
struct ViewerRow: View {
    let viewer: StoryViewer
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImagePath = viewer.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewer.username ?? "Usuario")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Vio hace \(timeAgo(from: viewer.timestamp))")
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Reaction Row
struct ReactionRow: View {
    let reaction: StoryReaction
    @Environment(\.colorScheme) var colorScheme
    @State private var username: String = "Usuario"
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Reaccionó hace \(timeAgo(from: reaction.timestamp))")
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(reaction.reaction)
                .font(.system(size: 28))
        }
        .padding(.horizontal, 20)
        .onAppear {
            fetchUsername()
        }
    }
    
    private func fetchUsername() {
        FirestoreService().fetchUserProfile(userId: reaction.userId) { result in
            switch result {
            case .success(let user):
                self.username = user.username
            case .failure(_):
                self.username = "Usuario"
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Archive ViewModel
class ArchiveViewModel: ObservableObject {
    @Published var groupedStories: [String: [Story]] = [:]
    @Published var isLoading = false
    
    private let firestoreService = FirestoreService()
    
    func loadArchivedStories() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isLessThan: Date())
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        print("Error loading archived stories: \(error.localizedDescription)")
                        return
                    }
                    
                    let stories = snapshot?.documents.compactMap { doc -> Story? in
                        var data = doc.data()
                        data["id"] = doc.documentID
                        return try? Firestore.Decoder().decode(Story.self, from: data)
                    } ?? []
                    
                    self?.groupStoriesByDate(stories)
                    self?.prefetchRecentImages(stories: stories)
                }
            }
    }
    
    private func groupStoriesByDate(_ stories: [Story]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let grouped = Dictionary(grouping: stories) { story in
            formatter.string(from: story.timestamp)
        }
        
        self.groupedStories = grouped
    }
    
    private func prefetchRecentImages(stories: [Story]) {
        let imageStories = stories.filter { $0.mediaItem.type == .image }
        let recentImageUrls = Array(imageStories.prefix(10)).compactMap { URL(string: $0.mediaItem.url) }
        
        if !recentImageUrls.isEmpty {
            let prefetcher = ImagePrefetcher(urls: recentImageUrls) { skippedResources, failedResources, completedResources in
                print("📸 Precarga de archivo completada: \(completedResources.count) imágenes")
            }
            prefetcher.start()
        }
    }
}

// MARK: - Story Stats ViewModel
class StoryStatsViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var viewCount = 0
    @Published var reactionCount = 0
    @Published var shareCount = 0
    @Published var reachCount = 0
    @Published var viewers: [StoryViewer] = []
    @Published var reactions: [StoryReaction] = []
    
    private let firestoreService = FirestoreService()
    
    func loadStats(for story: Story) {
        guard let storyId = story.id else { return }
        
        isLoading = true
        
        let group = DispatchGroup()
        
        // Load viewers
        group.enter()
        firestoreService.db.collection("users").document(story.authorId).collection("stories").document(storyId)
            .collection("viewers")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("Error fetching viewers: \(error.localizedDescription)")
                    return
                }
                
                let viewers = snapshot?.documents.compactMap { doc -> StoryViewer? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    let username = data["username"] as? String
                    let profileImagePath = data["profileImagePath"] as? String
                    return StoryViewer(
                        id: doc.documentID,
                        userId: userId,
                        username: username,
                        profileImagePath: profileImagePath,
                        timestamp: timestamp
                    )
                } ?? []
                
                DispatchQueue.main.async {
                    self?.viewers = viewers
                    self?.viewCount = viewers.count
                    self?.reachCount = Set(viewers.map { $0.userId }).count
                }
            }
        
        // Load reactions
        group.enter()
        firestoreService.db.collection("users").document(story.authorId).collection("stories").document(storyId)
            .collection("reactions")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("Error fetching reactions: \(error.localizedDescription)")
                    return
                }
                
                let reactions = snapshot?.documents.compactMap { doc -> StoryReaction? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let reaction = data["reaction"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    return StoryReaction(id: doc.documentID, userId: userId, reaction: reaction, timestamp: timestamp)
                } ?? []
                
                DispatchQueue.main.async {
                    self?.reactions = reactions
                    self?.reactionCount = reactions.count
                }
            }
        
        group.notify(queue: .main) {
            self.isLoading = false
            self.shareCount = Int.random(in: 0...max(1, self.viewCount / 10))
        }
    }
}

// MARK: - Preview
struct ArchiveView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ArchiveView()
        }
        .preferredColorScheme(.light)
        
        NavigationView {
            ArchiveView()
        }
        .preferredColorScheme(.dark)
    }
}
