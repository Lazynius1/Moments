import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import CoreLocation
import MapKit
import WeatherKit

// MARK: -  Sticker Picker with Glassmorphism

struct StickerPickerView: View {
    @Binding var selectedStickers: [StickerItem]
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedCategory: StickerCategory = .trending
    @State private var giphyResults: [GiphyGif] = []
    @State private var isLoadingGiphy = false
    @State private var showingCategories = true
    @State private var dragOffset: CGFloat = 0
    @State private var isDarkMode = true
    @State private var showingSelfieCamera = false
    
    let giphyAPIKey = "aLENUeEdnaI4z83gaLZPlOHzcLnaNGH8"
    
    // 🎯 CATEGORÍAS MEJORADAS CON GLASSMORPHISM
    enum StickerCategory: String, CaseIterable {
        case trending = "🔥"
        case emoji = "😊"
        case location = "📍"
        case mention = "@"
        case hashtag = "#"
        case poll = "📊"
        case question = "❓"
        case weather = "🌤️"
        case time = "⏰"
        case selfie = "🤳"
        
        var displayName: String {
            switch self {
            case .trending: return "GIF"
            case .emoji: return "Emoji"
            case .location: return "Lugar"
            case .mention: return "Mención"
            case .hashtag: return "Hashtag"
            case .poll: return "Votación"
            case .question: return "Preguntas"
            case .weather: return "Clima"
            case .time: return "Tiempo"
            case .selfie: return "Selfie"
            }
        }
        
        var accentColor: Color {
            switch self {
            case .trending: return .purple
            case .emoji: return .yellow
            case .location: return .red
            case .mention: return .orange
            case .hashtag: return .pink
            case .poll: return .green
            case .question: return .teal
            case .weather: return .cyan
            case .time: return .indigo
            case .selfie: return .orange
            }
        }
        
        var gradientColors: [Color] {
            switch self {
            case .trending: return [Color.purple, Color.pink]
            case .emoji: return [Color.yellow, Color.orange]
            case .location: return [Color.red, Color.pink]
            case .mention: return [Color.orange, Color.yellow]
            case .hashtag: return [Color.pink, Color.purple]
            case .poll: return [Color.green, Color.mint]
            case .question: return [Color.teal, Color.cyan]
            case .weather: return [Color.cyan, Color.blue]
            case .time: return [Color.indigo, Color.purple]
            case .selfie: return [Color.orange, Color.red]
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 🌌 FONDO GLASSMÓRFICO AVANZADO
                InstagramGlassmorphicBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 📱 HEADER ESTILO INSTAGRAM
                    InstagramStyleHeader()
                        .padding(.top, 10)
                    
                    // 📜 CONTENIDO PRINCIPAL
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // 🎯 CATEGORÍAS EN GRID ESTILO INSTAGRAM
                            InstagramCategoryGrid()
                                .padding(.top, 20)
                            
                            // 📋 CONTENIDO DINÁMICO
                            stickerContent
                                .padding(.top, selectedCategory == .trending ? 16 : 32)
                        }
                    }
                    .background(Color.clear)
                    .refreshable {
                        if selectedCategory == .trending {
                            loadTrendingStickers()
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            if selectedCategory == .trending {
                loadTrendingStickers()
            }
        }
        .sheet(isPresented: $showingSelfieCamera) {
            SelfieCameraView { image in
                createSelfieStickerFromImage(image)
            }
        }
    }
    
    // MARK: - 🎨 COMPONENTES GLASSMÓRFICOS ESTILO INSTAGRAM
    
    @ViewBuilder
    private func InstagramGlassmorphicBackground() -> some View {
        ZStack {
            // Gradiente base dinámico
            LinearGradient(
                colors: isDarkMode ? [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25),
                    Color.black
                ] : [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.9, green: 0.95, blue: 0.98),
                    Color(red: 0.85, green: 0.9, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Orbes flotantes glassmórficos
            ForEach(0..<8, id: \.self) { index in
                GlassmorphicFloatingOrb(
                    colors: selectedCategory.gradientColors,
                    size: CGFloat.random(in: 120...250),
                    x: CGFloat.random(in: -150...450),
                    y: CGFloat.random(in: -200...900),
                    duration: Double.random(in: 4...8),
                    delay: Double(index) * 0.5
                )
            }
            
            // Partículas brillantes
            ForEach(0..<15, id: \.self) { index in
                SparkleParticle(
                    x: CGFloat.random(in: 0...400),
                    y: CGFloat.random(in: 0...800),
                    delay: Double(index) * 0.3
                )
            }
        }
    }
    
    @ViewBuilder
    private func InstagramStyleHeader() -> some View {
        HStack(spacing: 16) {
            // Botón cerrar glassmórfico
            Button(action: {
                hapticFeedback(.light)
                dismiss()
            }) {
                ZStack {
                    // Fondo glassmórfico
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .pressAnimation()
            
            Spacer()
            
            // Título con efecto glassmórfico
            VStack(spacing: 4) {
                Text("Stickers")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDarkMode ? [.white, .white.opacity(0.8)] : [.black, .gray],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Indicador de categoría con glassmorphism
                Text(selectedCategory.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: selectedCategory.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: selectedCategory.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
            }
            
            Spacer()
            
            // Botón modo oscuro/claro
            Button(action: {
                hapticFeedback(.medium)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    isDarkMode.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDarkMode ? [.yellow, .orange] : [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .pressAnimation()
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func InstagramCategoryGrid() -> some View {
        VStack(spacing: 20) {
            // Barra de búsqueda glassmórfica
            InstagramSearchBar()
            
            // Grid de categorías estilo Instagram Stories
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 12) {
                
                // FILA 1: Principales
                InstagramCategoryPill(
                    icon: "🔥",
                    title: "GIF",
                    category: .trending,
                    isSelected: selectedCategory == .trending
                )
                
                InstagramCategoryPill(
                    icon: "😊",
                    title: "Emoji",
                    category: .emoji,
                    isSelected: selectedCategory == .emoji
                )
                
                InstagramCategoryPill(
                    icon: "📍",
                    title: "Lugar",
                    category: .location,
                    isSelected: selectedCategory == .location
                )
                
                // FILA 2: Interactivos
                InstagramCategoryPill(
                    icon: "🏷️",
                    title: "Mención",
                    category: .mention,
                    isSelected: selectedCategory == .mention
                )
                
                InstagramCategoryPill(
                    icon: "#",
                    title: "Hashtag",
                    category: .hashtag,
                    isSelected: selectedCategory == .hashtag
                )
                
                InstagramCategoryPill(
                    icon: "❓",
                    title: "Preguntas",
                    category: .question,
                    isSelected: selectedCategory == .question
                )
                
                // FILA 3: Extras
                InstagramCategoryPill(
                    icon: "📊",
                    title: "Votación",
                    category: .poll,
                    isSelected: selectedCategory == .poll
                )
                
                InstagramCategoryPill(
                    icon: "🌤️",
                    title: "Clima",
                    category: .weather,
                    isSelected: selectedCategory == .weather
                )
                
                InstagramCategoryPill(
                    icon: "⏰",
                    title: "Tiempo",
                    category: .time,
                    isSelected: selectedCategory == .time
                )
                
                InstagramCategoryPill(
                    icon: "🤳",
                    title: "Selfie",
                    category: .selfie,
                    isSelected: selectedCategory == .selfie
                )
            }
            .padding(.horizontal, 20)
            
            // Header de sección si es trending
            if selectedCategory == .trending {
                HStack {
                    Text("Tus stickers")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDarkMode ? [.white, .white.opacity(0.8)] : [.black, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }
    
    @ViewBuilder
    private func InstagramSearchBar() -> some View {
        HStack(spacing: 12) {
            // Icono de búsqueda con gradiente
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            TextField("Buscar stickers...", text: $searchText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isDarkMode ? .white : .black)
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .onSubmit {
                    hapticFeedback(.light)
                    if selectedCategory == .trending {
                        searchTrendingStickers()
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    hapticFeedback(.light)
                    withAnimation(.easeOut(duration: 0.2)) {
                        searchText = ""
                        if selectedCategory == .trending {
                            loadTrendingStickers()
                        }
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .pressAnimation()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func InstagramCategoryPill(
        icon: String,
        title: String,
        category: StickerCategory,
        isSelected: Bool
    ) -> some View {
        Button(action: {
            hapticFeedback(.medium)
            selectCategory(category)
        }) {
            VStack(spacing: 12) {
                // Contenedor del icono con glassmorphism avanzado
                ZStack {
                    // Fondo glassmórfico con gradiente
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: category.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: isSelected ?
                                        [Color.white.opacity(0.4), Color.white.opacity(0.2)] :
                                        [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: isSelected ? category.accentColor.opacity(0.4) : .black.opacity(0.1),
                            radius: isSelected ? 12 : 8,
                            x: 0,
                            y: isSelected ? 6 : 4
                        )
                    
                    // Icono o emoji
                    if icon.count == 1 {
                        Text(icon)
                            .font(.system(size: 26))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: isSelected ? [.white] : category.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Efecto de brillo para seleccionado
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 64, height: 64)
                    }
                }
                
                // Título con estilo
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isSelected ?
                            category.gradientColors :
                            (isDarkMode ? [.white.opacity(0.8), .white.opacity(0.6)] : [.black.opacity(0.8), .gray]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
            }
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        .pressAnimation()
    }
    
    // MARK: - 📋 CONTENIDO MEJORADO
    
    @ViewBuilder
    private var stickerContent: some View {
        switch selectedCategory {
        case .trending:
            if isLoadingGiphy {
                InstagramLoadingView()
            } else {
                InstagramTrendingGrid()
            }
            
        case .emoji:
            InstagramEmojiGrid()
            
        case .location:
            SmartLocationInputView { location, coordinate in
                createLocationSticker(location, coordinate: coordinate)
            }
            
        case .mention:
            ModernMentionInputView { username in
                createMentionSticker(username)
            }
            
        case .hashtag:
            ModernHashtagInputView { hashtag in
                createHashtagSticker(hashtag)
            }
            
        case .poll:
            ModernPollInputView { poll in
                createPollSticker(poll)
            }
            
        case .question:
            ModernQuestionInputView { question in
                createQuestionSticker(question)
            }
            
        case .weather:
            InstagramStickerCard(
                title: "🌤️ Clima actual",
                subtitle: "Muestra el tiempo de hoy",
                category: .weather
            ) {
                createWeatherSticker()
            }
            
        case .time:
            InstagramStickerCard(
                title: "⏰ Hora y fecha",
                subtitle: "Timestamp de este momento",
                category: .time
            ) {
                createTimeSticker()
            }
            
        case .selfie:
            InstagramStickerCard(
                title: "🤳 Mini selfie",
                subtitle: "Aparece en tu historia",
                category: .selfie
            ) {
                createSelfieSticker()
            }
        }
    }
    
    @ViewBuilder
    private func InstagramTrendingGrid() -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 20
        let spacing: CGFloat = 8
        let totalSpacing = spacing * 3
        let availableWidth = screenWidth - (padding * 2) - totalSpacing
        let itemWidth = availableWidth / 4
        
        let columns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 4)
        
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(giphyResults) { sticker in
                Button(action: {
                    hapticFeedback(.medium)
                    createGiphySticker(from: sticker)
                }) {
                    ZStack {
                        // Fondo glassmórfico
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        
                        AnimatedGIFView(url: URL(string: sticker.images.fixed_height.url))
                            .frame(width: itemWidth - 4, height: itemWidth - 4)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(width: itemWidth, height: itemWidth)
                }
                .pressAnimation()
            }
        }
        .padding(.horizontal, padding)
    }
    
    @ViewBuilder
    private func InstagramEmojiGrid() -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
        
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(trendingEmojis, id: \.self) { emoji in
                Button(action: {
                    hapticFeedback(.light)
                    createEmojiSticker(emoji)
                }) {
                    ZStack {
                        // Fondo glassmórfico
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    .frame(width: 54, height: 54)
                }
                .pressAnimation()
            }
        }
        .padding(.horizontal, 25)
    }
    
    @ViewBuilder
    private func InstagramLoadingView() -> some View {
        VStack(spacing: 24) {
            // Spinner glassmórfico
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 64, height: 64)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AngularGradient(
                            colors: selectedCategory.gradientColors + [selectedCategory.gradientColors.first!],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(isLoadingGiphy ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isLoadingGiphy
                    )
            }
            .background(
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .frame(width: 80, height: 80)
                    )
            )
            
            VStack(spacing: 8) {
                Text("Cargando stickers...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDarkMode ? [.white, .white.opacity(0.8)] : [.black, .gray],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Esto puede tomar unos segundos")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(isDarkMode ? .white.opacity(0.6) : .gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    @ViewBuilder
    private func InstagramStickerCard(
        title: String,
        subtitle: String,
        category: StickerCategory,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            hapticFeedback(.medium)
            action()
        }) {
            HStack(spacing: 16) {
                // Icono glassmórfico
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: category.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: category.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Efecto de brillo
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                        .frame(width: 56, height: 56)
                }
                
                // Contenido de texto
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDarkMode ? [.white, .white.opacity(0.9)] : [.black, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.leading)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(isDarkMode ? .white.opacity(0.7) : .gray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Flecha glassmórfica
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: category.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        category.accentColor.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
        }
        .pressAnimation()
        .padding(.horizontal, 25)
    }
    
    // MARK: - 🎨 COMPONENTES AUXILIARES GLASSMÓRFICOS
    
    struct GlassmorphicFloatingOrb: View {
        let colors: [Color]
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let duration: Double
        let delay: Double
        
        @State private var isAnimating = false
        @State private var rotationAngle: Double = 0
        
        var body: some View {
            ZStack {
                // Orbe principal
                Circle()
                    .fill(
                        RadialGradient(
                            colors: colors.map { $0.opacity(0.3) } + [Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size/2
                        )
                    )
                    .frame(width: size, height: size)
                    .blur(radius: 25)
                
                // Orbe interno más brillante
                Circle()
                    .fill(
                        RadialGradient(
                            colors: colors.map { $0.opacity(0.5) } + [Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size/4
                        )
                    )
                    .frame(width: size/2, height: size/2)
                    .blur(radius: 15)
            }
            .offset(
                x: isAnimating ? x + 60 : x - 60,
                y: isAnimating ? y + 40 : y - 40
            )
            .rotationEffect(.degrees(rotationAngle))
            .animation(
                .easeInOut(duration: duration)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
                withAnimation(
                    .linear(duration: duration * 2)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    rotationAngle = 360
                }
            }
        }
    }
    
    struct SparkleParticle: View {
        let x: CGFloat
        let y: CGFloat
        let delay: Double
        
        @State private var isVisible = false
        @State private var scale: CGFloat = 0
        @State private var opacity: Double = 0
        
        var body: some View {
            Image(systemName: "sparkle")
                .font(.system(size: CGFloat.random(in: 8...16), weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .yellow, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(scale)
                .opacity(opacity)
                .position(x: x, y: y)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                    ) {
                        scale = 1.0
                        opacity = 0.8
                    }
                }
        }
    }
    
    // MARK: - 🔧 FUNCIONES AUXILIARES
    
    private func selectCategory(_ category: StickerCategory) {
        hapticFeedback(.medium)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedCategory = category
        }
        
        switch category {
        case .trending:
            loadTrendingStickers()
        case .weather:
            createWeatherSticker()
        case .time:
            createTimeSticker()
        case .selfie:
            createSelfieSticker()
        default:
            break
        }
    }
    
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impact = UIImpactFeedbackGenerator(style: style)
        impact.impactOccurred()
    }
    
    private var trendingEmojis: [String] {
        ["😍", "🔥", "💯", "✨", "😂", "🥺", "💕", "🎉", "😎", "🤩", "💀", "🙄",
         "😭", "❤️", "🥳", "😘", "🤝", "👑", "💪", "🌟", "🦋", "🌈", "⚡", "💎"]
    }
    
    // MARK: - Giphy API Methods (mantener sin cambios)
    
    private func loadTrendingStickers() {
        isLoadingGiphy = true
        let urlString = "https://api.giphy.com/v1/stickers/trending?api_key=\(giphyAPIKey)&limit=24&rating=pg"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            do {
                let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
                DispatchQueue.main.async {
                    self.giphyResults = response.data
                    self.isLoadingGiphy = false
                }
            } catch {
                print("Error decoding Trending Stickers: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingGiphy = false
                }
            }
        }.resume()
    }
    
    private func searchTrendingStickers() {
        guard !searchText.isEmpty else { return }
        
        isLoadingGiphy = true
        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.giphy.com/v1/stickers/search?api_key=\(giphyAPIKey)&q=\(query)&limit=24&rating=pg"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            do {
                let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
                DispatchQueue.main.async {
                    self.giphyResults = response.data
                    self.isLoadingGiphy = false
                }
            } catch {
                print("Error searching Trending Stickers: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingGiphy = false
                }
            }
        }.resume()
    }
    
    // MARK: - Sticker Creation Methods (exactamente iguales)
    
    private func createEmojiSticker(_ emoji: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 150),
                .paragraphStyle: paragraphStyle
            ]
            
            let textRect = CGRect(x: 0, y: 25, width: 200, height: 200)
            emoji.draw(in: textRect, withAttributes: attributes)
        }
        
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .emoji,
            interactionData: nil
        )
        selectedStickers.append(sticker)
        dismiss()
    }
    
    private func createGiphySticker(from sticker: GiphyGif) {
        guard let url = URL(string: sticker.images.fixed_height.url) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            // Crear imagen estática para fallback
            let staticImage: UIImage
            if let animatedImage = UIImage.animatedImageWithData(data) {
                staticImage = animatedImage
            } else if let image = UIImage(data: data) {
                staticImage = image
            } else {
                return
            }
            
            DispatchQueue.main.async {
                let screenCenter = CGPoint(
                    x: UIScreen.main.bounds.width / 2,
                    y: UIScreen.main.bounds.height / 2
                )
                
                let randomOffset = CGPoint(
                    x: CGFloat.random(in: -40...40),
                    y: CGFloat.random(in: -40...40)
                )
                
                let finalPosition = CGPoint(
                    x: screenCenter.x + randomOffset.x,
                    y: screenCenter.y + randomOffset.y
                )
                
                let constrainedPosition = self.constrainPositionToBounds(finalPosition)
                
                // ✅ CREAR STICKER CON GIF ANIMADO usando el inicializador correcto
                let stickerItem = StickerItem(
                    image: staticImage,     // Imagen estática para fallback
                    gifURL: url,           // URL para animación
                    position: constrainedPosition,
                    type: .sticker,
                    interactionData: nil
                )
                
                self.selectedStickers.append(stickerItem)
                self.dismiss()
            }
        }.resume()
    }

    // CAMBIO 5: Función auxiliar para constrainPositionToBounds
    private func constrainPositionToBounds(_ position: CGPoint) -> CGPoint {
        let padding: CGFloat = 60
        let bounds = UIScreen.main.bounds
        
        return CGPoint(
            x: max(padding, min(bounds.width - padding, position.x)),
            y: max(padding, min(bounds.height - padding, position.y))
        )
    }

    private func createLocationSticker(_ location: String, coordinate: CLLocationCoordinate2D?) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 120)
            
            // ✅ FONDO CON GRADIENTE COMO INSTAGRAM
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            
            // Gradiente de fondo
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.85).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.85).cgColor,
                UIColor.systemPink.withAlphaComponent(0.85).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0])!
            
            context.cgContext.saveGState()
            backgroundPath.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            context.cgContext.restoreGState()
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = 1.5
            backgroundPath.stroke()
            
            // 📍 Icono de ubicación simple
            let locationIcon = "📍"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            locationIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // 📝 TEXTO DE UBICACIÓN
            let displayText = location
            
            // Texto principal
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedText = displayText.count > 25 ? String(displayText.prefix(25)) + "..." : displayText
            truncatedText.draw(in: CGRect(x: 16, y: 45, width: 248, height: 50), withAttributes: textAttributes)
            
            // Texto "Ver ubicación"
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            "Ver ubicación".draw(in: CGRect(x: 16, y: 95, width: 248, height: 20), withAttributes: subtitleAttributes)
        }
        
        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN (TAMAÑO FIJO)
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .location,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: location,
                locationCoordinate: coordinate,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }
    



    
    // MARK: - ✅ WEATHER STICKER
    private func createWeatherSticker() {
        // ✅ OBTENER CLIMA ACTUAL CON WEATHER KIT
        Task {
            do {
                let weather = try await getCurrentWeather()
                await MainActor.run {
                    createWeatherStickerWithData(weather)
                }
            } catch {
                print("❌ Error obteniendo clima: \(error)")
                // ✅ FALLBACK: Crear sticker con placeholder
                await MainActor.run {
                    createWeatherStickerWithPlaceholder()
                }
            }
        }
    }
    
    // ✅ FUNCIÓN PARA OBTENER CLIMA ACTUAL
    private func getCurrentWeather() async throws -> (temperature: Double, condition: String, symbol: String) {
        let locationManager = CLLocationManager()
        
        // ✅ VERIFICAR PERMISOS
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            throw WeatherError.noLocationPermission
        }
        
        // ✅ OBTENER UBICACIÓN ACTUAL
        guard let location = locationManager.location else {
            throw WeatherError.noLocation
        }
        
        // ✅ USAR WEATHERSERVICE EXISTENTE
        let weatherService = WeatherService.shared
        let currentWeather = try await weatherService.getWeather(for: location.coordinate)
        
        let temperature = currentWeather.temperature
        let condition = currentWeather.condition.displayName
        let symbol = getWeatherSymbol(for: condition)
        
        return (temperature: temperature, condition: condition, symbol: symbol)
    }
    
    // ✅ CONVERTIR CONDICIÓN A SÍMBOLO (MEJORADO CON HORA DEL DÍA)
    private func getWeatherSymbol(for condition: String) -> String {
        let lowercased = condition.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        
        // ✅ DETECTAR SI ES NOCHE (entre 20:00 y 6:00)
        let isNight = hour >= 20 || hour < 6
        
        if lowercased.contains("clear") || lowercased.contains("sunny") {
            return isNight ? "🌙" : "☀️"
        } else if lowercased.contains("cloud") {
            return isNight ? "☁️" : "🌤️"
        } else if lowercased.contains("rain") || lowercased.contains("drizzle") {
            return "🌧️"
        } else if lowercased.contains("snow") || lowercased.contains("sleet") {
            return "❄️"
        } else if lowercased.contains("storm") || lowercased.contains("thunder") {
            return "⛈️"
        } else if lowercased.contains("fog") || lowercased.contains("haze") {
            return "🌫️"
        } else if lowercased.contains("wind") || lowercased.contains("breeze") {
            return "💨"
        } else if lowercased.contains("hot") {
            return "🔥"
        } else if lowercased.contains("cold") {
            return "🥶"
        } else {
            return isNight ? "🌙" : "🌤️"
        }
    }
    
    // ✅ CREAR STICKER CON DATOS REALES
    private func createWeatherStickerWithData(_ weather: (temperature: Double, condition: String, symbol: String)) {
        let temperature = Int(round(weather.temperature))
        let weatherText = "\(temperature)°C"
        
        print("🌤️ [DEBUG] Creando weather sticker con datos reales:")
        print("🌤️ [DEBUG] - Temperatura: \(weatherText)")
        print("🌤️ [DEBUG] - Símbolo: \(weather.symbol)")
        print("🌤️ [DEBUG] - Condición: \(weather.condition)")
        
        // ✅ CREAR STICKER ANIMADO
        let sticker = StickerItem(
            image: createWeatherBackgroundImage(for: weather.symbol),
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .weather,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: weatherText,
                weatherSymbol: weather.symbol
            )
        )
        
        print("🌤️ [DEBUG] Weather sticker creado con ID: \(sticker.id)")
        print("🌤️ [DEBUG] Weather sticker type: \(sticker.type)")
        print("🌤️ [DEBUG] Weather sticker interactionData: \(String(describing: sticker.interactionData))")
        
        selectedStickers.append(sticker)
        print("🌤️ [DEBUG] Weather sticker agregado a selectedStickers. Total: \(selectedStickers.count)")
        dismiss()
    }
    
    // ✅ CREAR IMAGEN DE FONDO PARA ANIMACIÓN
    private func createWeatherBackgroundImage(for symbol: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 140, height: 50)
            
            // ✅ FONDO CON GRADIENTE SEGÚN CLIMA
            let colors = getWeatherGradientColors(for: symbol)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
            context.cgContext.saveGState()
            path.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            context.cgContext.restoreGState()
            
            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()
            
            // ✅ TEXTO CENTRADO (solo símbolo del clima)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            symbol.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
        }
        
        return image
    }
    
    // ✅ CREAR STICKER CON PLACEHOLDER
    private func createWeatherStickerWithPlaceholder() {
        let weatherText = "🌤️"
        
        print("🌤️ [DEBUG] Creando weather sticker con placeholder")
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 140, height: 50)
            
            // ✅ FONDO AZUL POR DEFECTO
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
            context.cgContext.saveGState()
            path.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            context.cgContext.restoreGState()
            
            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()
            
            // ✅ TEXTO CENTRADO
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            weatherText.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
        }
        
        let sticker = StickerItem(
            image: image,
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .weather,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: weatherText,
                weatherSymbol: "🌤️"
            )
        )
        
        selectedStickers.append(sticker)
        dismiss()
    }
    
    // ✅ OBTENER COLORES DE GRADIENTE SEGÚN CLIMA
    private func getWeatherGradientColors(for symbol: String) -> CFArray {
        switch symbol {
        case "☀️": // Soleado
            return [
                UIColor.systemOrange.withAlphaComponent(0.9).cgColor,
                UIColor.systemYellow.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🌧️", "⛈️": // Lluvia/Tormenta
            return [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemIndigo.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "❄️", "🌨️": // Nieve
            return [
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "☁️", "⛅": // Nublado
            return [
                UIColor.systemGray.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🔥": // Calor
            return [
                UIColor.systemRed.withAlphaComponent(0.9).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🥶": // Frío
            return [
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        default: // Por defecto
            return [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor
            ] as CFArray
        }
    }
    
    // ✅ ENUM PARA ERRORES DE CLIMA
    enum WeatherError: Error {
        case noLocationPermission
        case noLocation
        case unsupportedVersion
    }
    
    // MARK: - ✅ TIME STICKER
    private func createTimeSticker() {
        let now = Date()
        
        // ✅ FORMATO ELEGANTE: "14:30 • 7 Ago"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.locale = Locale(identifier: "es_ES")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.locale = Locale(identifier: "es_ES")
        
        let timeString = timeFormatter.string(from: now)
        let dateString = dateFormatter.string(from: now)
        let fullString = "\(timeString) • \(dateString)"
        
        // ✅ DISEÑO MÁS COMPACTO Y ELEGANTE
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 50))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 160, height: 50)
            
            // ✅ FONDO CON GRADIENTE ELEGANTE
            let colors = [
                UIColor.systemIndigo.withAlphaComponent(0.9).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.9).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
            context.cgContext.saveGState()
            path.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            context.cgContext.restoreGState()
            
            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()
            
            // ✅ TEXTO CENTRADO Y ELEGANTE
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            fullString.draw(in: CGRect(x: 10, y: 15, width: 140, height: 20), withAttributes: attributes)
        }
        
        let sticker = StickerItem(
            image: image,
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .time,
            interactionData: nil
        )
        
        selectedStickers.append(sticker)
        dismiss()
    }
    
    // MARK: - ✅ SELFIE STICKER
    private func createSelfieSticker() {
        // ✅ USAR SHEET PARA EVITAR CONFLICTOS DE PRESENTACIÓN
        showingSelfieCamera = true
    }
    
    // ✅ FUNCIÓN PARA CREAR STICKER DESDE IMAGEN
    func createSelfieStickerFromImage(_ selfieImage: UIImage) {
        // ✅ CREAR STICKER CIRCULAR CON BORDE ELEGANTE
        let size: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let stickerImage = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            
            // ✅ FONDO CIRCULAR CON GRADIENTE
            let circlePath = UIBezierPath(ovalIn: rect)
            
            // Gradiente de fondo
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.8).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.8).cgColor,
                UIColor.systemPink.withAlphaComponent(0.8).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0])!
            
            context.cgContext.saveGState()
            circlePath.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
            context.cgContext.restoreGState()
            
            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.6).setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()
            
            // ✅ FOTO DEL SELFIE (CIRCULAR)
            let imageRect = rect.insetBy(dx: 6, dy: 6)
            let imageCirclePath = UIBezierPath(ovalIn: imageRect)
            
            context.cgContext.saveGState()
            imageCirclePath.addClip()
            
            // Redimensionar y centrar la imagen
            let aspectRatio = selfieImage.size.width / selfieImage.size.height
            let drawRect: CGRect
            
            if aspectRatio > 1 {
                // Imagen más ancha que alta
                let drawHeight = imageRect.height
                let drawWidth = drawHeight * aspectRatio
                let drawX = imageRect.midX - drawWidth / 2
                drawRect = CGRect(x: drawX, y: imageRect.minY, width: drawWidth, height: drawHeight)
            } else {
                // Imagen más alta que ancha
                let drawWidth = imageRect.width
                let drawHeight = drawWidth / aspectRatio
                let drawY = imageRect.midY - drawHeight / 2
                drawRect = CGRect(x: imageRect.minX, y: drawY, width: drawWidth, height: drawHeight)
            }
            
            selfieImage.draw(in: drawRect)
            context.cgContext.restoreGState()
        }
        
        // ✅ CREAR STICKER CON LA IMAGEN GENERADA
        let sticker = StickerItem(
            image: stickerImage,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .selfie,
            interactionData: nil
        )
        
        selectedStickers.append(sticker)
        dismiss()
    }
    
    private func createMentionSticker(_ username: String) {
        // Primero buscar el usuario por username para obtener su ID y foto
        searchUserByUsername(username) { userResult in
            DispatchQueue.main.async {
                switch userResult {
                case .success(let user):
                    // Usuario encontrado - crear sticker con su foto
                    self.generateMentionStickerWithUser(user)
                case .failure(_):
                    // Usuario no encontrado - crear sticker con placeholder
                    self.generateMentionStickerWithPlaceholder(username)
                }
            }
        }
    }

    // MARK: - Buscar usuario por username
    private func searchUserByUsername(_ username: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        let firestoreService = FirestoreService()
        
        // Usar tu método existente de búsqueda
        firestoreService.searchUsers(query: username.lowercased(), limit: 1) { result in
            switch result {
            case .success(let users):
                if let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    completion(.success(user))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Generar sticker con foto real del usuario
    private func generateMentionStickerWithUser(_ user: AppUser) {
        // ✅ SOLO CREAR STICKER - la notificación se enviará al publicar
        if let profileImagePath = user.profileImagePath, !profileImagePath.isEmpty,
           let profileURL = URL(string: profileImagePath) {
            
            // Descargar la imagen de perfil
            URLSession.shared.dataTask(with: profileURL) { data, _, error in
                DispatchQueue.main.async {
                    if let data = data, let profileImage = UIImage(data: data) {
                        // Crear sticker con foto real
                        self.generateSticker(username: user.username, userId: user.id, profileImage: profileImage)
                    } else {
                        // Error al descargar - usar placeholder
                        self.generateSticker(username: user.username, userId: user.id, profileImage: nil)
                    }
                }
            }.resume()
        } else {
            // No hay foto de perfil - usar placeholder
            generateSticker(username: user.username, userId: user.id, profileImage: nil)
        }
    }

    // MARK: - Generar sticker con placeholder (cuando no se encuentra usuario)
    private func generateMentionStickerWithPlaceholder(_ username: String) {
        // ✅ No crear sticker si no se encuentra el usuario
        print("⚠️ Usuario no encontrado: @\(username) - No se creará sticker de mención")
    }

    // MARK: - Función principal para generar el sticker (ESTILO INSTAGRAM)
    private func generateSticker(username: String, userId: String, profileImage: UIImage?) {

        // ✅ ESTILO INSTAGRAM: Solo @username con fondo blanco
        let text = "@\(username)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        
        let textSize = text.size(withAttributes: textAttributes)
        let padding: CGFloat = 12
        let width = textSize.width + (padding * 2)
        let height = textSize.height + (padding * 2)
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            
            // ✅ FONDO BLANCO como Instagram
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
            UIColor.white.setFill()
            backgroundPath.fill()
            
            // ✅ BORDE SUTIL
            UIColor.black.withAlphaComponent(0.1).setStroke()
            backgroundPath.lineWidth = 0.5
            backgroundPath.stroke()
            
            // ✅ TEXTO CENTRADO
            let textRect = CGRect(
                x: padding,
                y: padding,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: textAttributes)
        }
        
        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .mention,
            interactionData: StickerItem.StickerInteractionData(
                username: username,
                userId: userId,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil
            )
                    )
            selectedStickers.append(sticker)
        dismiss()
    }
    
    private func createHashtagSticker(_ hashtag: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 120)
            
            // ✅ FONDO CON GRADIENTE COMO INSTAGRAM
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            
            // Gradiente de fondo (colores hashtag)
            let colors = [
                UIColor.systemPink.withAlphaComponent(0.85).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.85).cgColor,
                UIColor.systemYellow.withAlphaComponent(0.85).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0])!
            
            context.cgContext.saveGState()
            backgroundPath.addClip()
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            context.cgContext.restoreGState()
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = 1.5
            backgroundPath.stroke()
            
            // 🏷️ Icono de hashtag
            let hashtagIcon = "#"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            hashtagIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // 📝 TEXTO DE HASHTAG
            let displayText = hashtag
            
            // Texto principal
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedText = displayText.count > 25 ? String(displayText.prefix(25)) + "..." : displayText
            truncatedText.draw(in: CGRect(x: 16, y: 45, width: 248, height: 50), withAttributes: textAttributes)
            
            // Texto "Ver hashtag"
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            "Ver hashtag".draw(in: CGRect(x: 16, y: 95, width: 248, height: 20), withAttributes: subtitleAttributes)
        }
        
        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .hashtag,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: hashtag,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }
    
    private func createPollSticker(_ poll: [String]) {
        guard poll.count >= 3 else { return }
        
        // ✅ NUEVO: Tamaño más compacto y elegante
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 180))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 180)
            
            // ✅ Fondo con gradiente elegante (colores de la app)
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.85).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.85).cgColor,
                UIColor.systemPink.withAlphaComponent(0.85).cgColor
            ] as CFArray
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 0.5, 1.0]
            )!
            
            context.cgContext.saveGState()
            let mainPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            mainPath.addClip()
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: rect.width, y: rect.height),
                options: []
            )
            context.cgContext.restoreGState()
            
            // ✅ Borde con glow sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            mainPath.lineWidth = 1.5
            mainPath.stroke()
            
            // ✅ Icono de poll (más elegante que "ENCUESTA")
            let pollIcon = "📊"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            pollIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // ✅ Pregunta con mejor tipografía
            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let questionText = poll[0].count > 30 ? String(poll[0].prefix(30)) + "..." : poll[0]
            questionText.draw(in: CGRect(x: 16, y: 35, width: 248, height: 40), withAttributes: questionAttributes)
            
            // ✅ Opción 1 con diseño más moderno
            let option1Rect = CGRect(x: 16, y: 85, width: 248, height: 35)
            let option1Path = UIBezierPath(roundedRect: option1Rect, cornerRadius: 17.5)
            
            // Fondo semi-transparente con blur effect
            UIColor.white.withAlphaComponent(0.15).setFill()
            option1Path.fill()
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.4).setStroke()
            option1Path.lineWidth = 0.8
            option1Path.stroke()
            
            // ✅ Opción 2
            let option2Rect = CGRect(x: 16, y: 130, width: 248, height: 35)
            let option2Path = UIBezierPath(roundedRect: option2Rect, cornerRadius: 17.5)
            
            UIColor.white.withAlphaComponent(0.15).setFill()
            option2Path.fill()
            
            UIColor.white.withAlphaComponent(0.4).setStroke()
            option2Path.lineWidth = 0.8
            option2Path.stroke()
            
            // ✅ Texto de las opciones con mejor espaciado
            let optionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            
            let option1Text = poll[1].count > 22 ? String(poll[1].prefix(22)) + "..." : poll[1]
            let option2Text = poll[2].count > 22 ? String(poll[2].prefix(22)) + "..." : poll[2]
            
            option1Text.draw(in: CGRect(x: 28, y: 94, width: 224, height: 18), withAttributes: optionAttributes)
            option2Text.draw(in: CGRect(x: 28, y: 139, width: 224, height: 18), withAttributes: optionAttributes)
            
            // ✅ Indicador de "Toca para votar" sutil
            let tapText = "Toca para votar"
            let tapAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            tapText.draw(in: CGRect(x: 16, y: 155, width: 248, height: 12), withAttributes: tapAttributes)
        }
        
        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN (TAMAÑO FIJO )
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .poll,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: poll,
                questionText: nil,
                weatherSymbol: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }
    
    private func createQuestionSticker(_ question: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 300, height: 120)
            
            // Fondo degradado dinámico
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemTeal.cgColor,
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor
                ] as CFArray,
                locations: [0.0, 0.5, 1.0]
            )!
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: rect.width, y: rect.height),
                options: []
            )
            
            // Overlay glassmorphism
            UIColor.white.withAlphaComponent(0.1).setFill()
            let overlayPath = UIBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 17)
            overlayPath.fill()
            
            // Icono de pregunta
            let questionMark = "?"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            questionMark.draw(in: CGRect(x: 20, y: 20, width: 30, height: 30), withAttributes: iconAttributes)
            
            // Texto "PREGÚNTAME"
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .kern: 1.0
            ]
            "PREGÚNTAME".draw(in: CGRect(x: 60, y: 25, width: 220, height: 15), withAttributes: headerAttributes)
            
            // Pregunta personalizada
            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedQuestion = question.count > 40 ? String(question.prefix(40)) + "..." : question
            truncatedQuestion.draw(in: CGRect(x: 20, y: 55, width: 260, height: 50), withAttributes: questionAttributes)
        }
        
        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .question,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: question,
                weatherSymbol: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }
}



struct SmartLocationInputView: View {
    let onSelect: (String, CLLocationCoordinate2D?) -> Void
    
    @State private var searchText = ""
    @State private var nearbyPlaces: [LocationResult] = []
    @State private var searchResults: [LocationResult] = []
    @State private var isLoadingNearby = true
    @State private var isSearching = false
    @State private var userLocation: CLLocation?
    @FocusState private var isTextFieldFocused: Bool
    
    @StateObject private var locationManager = LocationManager()
    
    // Modelo para resultados de ubicación
    struct LocationResult: Identifiable, Hashable, Equatable {
        let id = UUID()
        let displayName: String // ✅ NOMBRE PARA MOSTRAR EN LA UI
        let fullName: String // ✅ NOMBRE COMPLETO PARA PRECISIÓN
        let address: String
        let distance: Double? // En metros
        let category: String
        let coordinate: CLLocationCoordinate2D
        
        var distanceString: String {
            guard let distance = distance else { return "" }
            if distance < 1000 {
                return "\(Int(distance))m"
            } else {
                return String(format: "%.1fkm", distance / 1000)
            }
        }
        
        var categoryIcon: String {
            switch category.lowercased() {
            case "restaurant", "food": return "fork.knife"
            case "shopping", "store": return "bag"
            case "entertainment": return "theatermasks"
            case "gas station": return "fuelpump"
            case "hospital": return "cross.case"
            case "school": return "graduationcap"
            case "park": return "tree"
            case "gym": return "dumbbell"
            case "hotel": return "bed.double"
            default: return "mappin"
            }
        }
        
        // MARK: - Conformance to Equatable
        static func == (lhs: LocationResult, rhs: LocationResult) -> Bool {
            return lhs.id == rhs.id &&
                   lhs.displayName == rhs.displayName &&
                   lhs.fullName == rhs.fullName &&
                   lhs.address == rhs.address &&
                   lhs.distance == rhs.distance &&
                   lhs.category == rhs.category &&
                   lhs.coordinate.latitude == rhs.coordinate.latitude &&
                   lhs.coordinate.longitude == rhs.coordinate.longitude
        }
        
        // MARK: - Conformance to Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(displayName)
            hasher.combine(fullName)
            hasher.combine(address)
            hasher.combine(distance)
            hasher.combine(category)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header moderno
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Añadir ubicación")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                
                // Barra de búsqueda inteligente
                HStack(spacing: 12) {
                    Image(systemName: isSearching ? "magnifyingglass" : (searchText.isEmpty ? "magnifyingglass" : "location.magnifyingglass"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(searchText.isEmpty ? .gray : .red)
                        .animation(.easeInOut(duration: 0.2), value: searchText)
                    
                    TextField("Buscar lugares cercanos...", text: $searchText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                            } else {
                                searchPlaces(query: newValue)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                searchResults = []
                                isSearching = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isTextFieldFocused ? Color.red.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Lista de ubicaciones
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Ubicaciones cercanas
                        if isLoadingNearby {
                            SectionHeader(title: "Buscando lugares cercanos...", icon: "location", color: .blue)
                            
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if nearbyPlaces.isEmpty {
                            EmptyNearbyView()
                        } else {
                            SectionHeader(title: "Lugares cercanos", icon: "location.fill", color: .red)
                            
                            ForEach(nearbyPlaces, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    } else {
                        // Resultados de búsqueda
                        if isSearching {
                            SectionHeader(title: "Buscando...", icon: "magnifyingglass", color: .blue)
                            
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if searchResults.isEmpty {
                            EmptySearchView(searchQuery: searchText)
                        } else {
                            SectionHeader(title: "\(searchResults.count) lugar\(searchResults.count == 1 ? "" : "es") encontrado\(searchResults.count == 1 ? "" : "s")", icon: "mappin.and.ellipse", color: .green)
                            
                            ForEach(searchResults, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: searchText)
                .animation(.easeInOut(duration: 0.3), value: searchResults)
                .animation(.easeInOut(duration: 0.3), value: nearbyPlaces)
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            isTextFieldFocused = true
            requestLocationAndSearch()
        }
        .onChange(of: locationManager.location) { newLocation in
            if let location = newLocation {
                userLocation = location
                searchNearbyPlaces()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                requestLocationAndSearch()
            }
        }
    }
    
    // MARK: - Componentes de UI
    
    private struct LocationRowView: View {
        let location: SmartLocationInputView.LocationResult
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    // Icono de categoría
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: location.categoryIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    // Info del lugar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(location.address)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                            
                            if !location.distanceString.isEmpty {
                                Text("• \(location.distanceString)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Flecha
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private struct SkeletonLocationRow: View {
        @State private var isAnimating = false
        
        var body: some View {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .shimmer(isAnimating)
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 140, height: 14)
                        .shimmer(isAnimating)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 100, height: 12)
                        .shimmer(isAnimating)
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .onAppear {
                isAnimating = true
            }
        }
    }
    
    private struct EmptyNearbyView: View {
        var body: some View {
            VStack(spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(spacing: 6) {
                    Text("No se pueden obtener lugares cercanos")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("Verifica que tengas la ubicación activada")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
        }
    }
    
    private struct EmptySearchView: View {
        let searchQuery: String
        
        var body: some View {
            VStack(spacing: 16) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(spacing: 6) {
                    Text("No se encontraron lugares")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("Intenta buscar \"\(searchQuery)\" de otra forma")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Funciones de búsqueda
    
    private func requestLocationAndSearch() {
        locationManager.requestLocation()
    }
    
    private func searchNearbyPlaces() {
        guard let userLocation = userLocation else { return }
        
        isLoadingNearby = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurants cafes shops"
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 2000, // 2km radius
            longitudinalMeters: 2000
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isLoadingNearby = false
                
                guard let response = response else {
                    print("Error searching nearby: \(error?.localizedDescription ?? "Unknown")")
                    return
                }
                
                self.nearbyPlaces = response.mapItems.prefix(10).compactMap { item in
                    guard let name = item.name else { return nil }
                    
                    let distance = userLocation.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))
                    
                    let fullAddress = formatAddress(item.placemark)
                    let fullName = "\(name), \(fullAddress)"
                    
                    return LocationResult(
                        displayName: name, // ✅ SOLO EL NOMBRE DEL LUGAR
                        fullName: fullName, // ✅ NOMBRE COMPLETO PARA PRECISIÓN
                        address: fullAddress,
                        distance: distance,
                        category: item.pointOfInterestCategory?.rawValue ?? "place",
                        coordinate: item.placemark.coordinate
                    )
                }.sorted { $0.distance ?? 0 < $1.distance ?? 0 }
            }
        }
    }
    
    private func searchPlaces(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        if let userLocation = userLocation {
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 10000, // 10km radius for search
                longitudinalMeters: 10000
            )
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false
                
                guard let response = response else {
                    print("Error searching places: \(error?.localizedDescription ?? "Unknown")")
                    self.searchResults = []
                    return
                }
                
                self.searchResults = response.mapItems.prefix(15).compactMap { item in
                    guard let name = item.name else { return nil }
                    
                    let distance = self.userLocation?.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))
                    
                    let fullAddress = formatAddress(item.placemark)
                    let fullName = "\(name), \(fullAddress)"
                    
                    return LocationResult(
                        displayName: name, // ✅ SOLO EL NOMBRE DEL LUGAR
                        fullName: fullName, // ✅ NOMBRE COMPLETO PARA PRECISIÓN
                        address: fullAddress,
                        distance: distance,
                        category: item.pointOfInterestCategory?.rawValue ?? "place",
                        coordinate: item.placemark.coordinate
                    )
                }.sorted { ($0.distance ?? Double.greatestFiniteMagnitude) < ($1.distance ?? Double.greatestFiniteMagnitude) }
            }
        }
    }
    
    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        // ✅ NÚMERO Y CALLE
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        
        // ✅ CÓDIGO POSTAL
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }
        
        // ✅ CIUDAD
        if let locality = placemark.locality {
            components.append(locality)
        }
        
        // ✅ PROVINCIA/ESTADO
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        // ✅ PAÍS
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

// MARK: - Modern Mention Input with Real User Search
struct ModernMentionInputView: View {
    let onSelect: (String) -> Void
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var recentUsers: [AppUser] = []
    @State private var suggestedUsers: [AppUser] = []
    @FocusState private var isTextFieldFocused: Bool
    
    private let firestoreService = FirestoreService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header moderno
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "at.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    
                    Text("Etiquetar gente")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                
                // Barra de búsqueda estilo Instagram
                HStack(spacing: 12) {
                    Image(systemName: isSearching ? "magnifyingglass" : (searchText.isEmpty ? "magnifyingglass" : "person.circle.fill"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(searchText.isEmpty ? .gray : .green)
                        .animation(.easeInOut(duration: 0.2), value: searchText)
                    
                    TextField("Buscar usuarios...", text: $searchText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                            } else {
                                searchUsers(query: newValue)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                searchResults = []
                                isSearching = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isTextFieldFocused ? Color.green.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Lista de usuarios
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Sección de recientes
                        if !recentUsers.isEmpty {
                            SectionHeader(title: "Recientes", icon: "clock.fill", color: .orange)
                            
                            ForEach(recentUsers, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                        
                        // Sección de sugerencias
                        if !suggestedUsers.isEmpty {
                            SectionHeader(title: "Sugerencias", icon: "sparkles", color: .purple)
                            
                            ForEach(suggestedUsers, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        } else {
                            // Loading de sugerencias
                            SectionHeader(title: "Sugerencias", icon: "sparkles", color: .purple)
                            
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonUserRow()
                            }
                        }
                    } else {
                        // Resultados de búsqueda
                        if isSearching {
                            SectionHeader(title: "Buscando...", icon: "magnifyingglass", color: .blue)
                            
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonUserRow()
                            }
                        } else if searchResults.isEmpty {
                            StickerEmptySearchView(searchQuery: searchText)
                        } else {
                            SectionHeader(title: "\(searchResults.count) resultado\(searchResults.count == 1 ? "" : "s")", icon: "person.2.fill", color: .green)
                            
                            ForEach(searchResults, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    saveRecentUser(user)
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: searchText)
                .animation(.easeInOut(duration: 0.3), value: searchResults)
                .padding(.horizontal, 20)
            }
        }
                        .onAppear {
            loadRecentUsers()
            loadSuggestedUsers()
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Private Methods
    private func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Debounce la búsqueda
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.searchText == query { // Solo buscar si no ha cambiado
                self.performUserSearch(query: query)
            }
        }
    }
    
    private func performUserSearch(query: String) {
        firestoreService.searchUsers(query: query.lowercased(), limit: 15) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    // Filtrar al usuario actual y ordenar por relevancia
                    self.searchResults = users
                        .filter { $0.id != Auth.auth().currentUser?.uid }
                        .sorted { user1, user2 in
                            // Priorizar usuarios Plus y después por username
                            if user1.isPlusSubscriber && !user2.isPlusSubscriber {
                                return true
                            } else if !user1.isPlusSubscriber && user2.isPlusSubscriber {
                                return false
                            }
                            return user1.username < user2.username
                        }
                case .failure(let error):
                    print("Error searching users: \(error)")
                    self.searchResults = []
                }
                self.isSearching = false
            }
        }
    }
    
    private func loadRecentUsers() {
        // Cargar usuarios recientes desde UserDefaults o Core Data
        if let data = UserDefaults.standard.data(forKey: "recentMentionedUsers"),
           let userIds = try? JSONDecoder().decode([String].self, from: data) {
            
            // Cargar detalles de usuarios
            let group = DispatchGroup()
            var users: [AppUser] = []
            
            for userId in userIds.prefix(5) {
                group.enter()
                firestoreService.fetchUserProfile(userId: userId) { result in
                    if case .success(let user) = result {
                        users.append(user)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.recentUsers = users
            }
        }
    }
    
    private func loadSuggestedUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Cargar usuarios sugeridos (conexiones mutuas, etc.)
        firestoreService.fetchMutualConnections(userId: currentUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let connections):
                    self.suggestedUsers = Array(connections.prefix(6))
                case .failure(_):
                    self.suggestedUsers = []
                }
            }
        }
    }
    
    private func saveRecentUser(_ user: AppUser) {
        var recentIds = [String]()
        
        if let data = UserDefaults.standard.data(forKey: "recentMentionedUsers"),
           let existingIds = try? JSONDecoder().decode([String].self, from: data) {
            recentIds = existingIds.filter { $0 != user.id }
        }
        
        recentIds.insert(user.id, at: 0)
        recentIds = Array(recentIds.prefix(10)) // Mantener solo 10 recientes
        
        if let data = try? JSONEncoder().encode(recentIds) {
            UserDefaults.standard.set(data, forKey: "recentMentionedUsers")
        }
    }
}

// MARK: - Supporting Views
struct StickerUserRowView: View {
    let user: AppUser
    let onTap: () -> Void
    @State private var imageLoadFailed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar con mejor handling de errores
                Group {
                    if let imagePath = user.profileImagePath, !imagePath.isEmpty, !imageLoadFailed {
                        KFImage(URL(string: imagePath))
                            .onFailure { _ in
                                imageLoadFailed = true
                            }
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Text(String(user.username.prefix(1)).uppercased())
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                
                // Info del usuario
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(user.username)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Badge de Plus subscriber si aplica
                        if user.isPlusSubscriber {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    // Mostrar si es cuenta privada
                    if user.isPrivate {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            
                            Text("Cuenta privada")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Flecha de selección
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SkeletonUserRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 50, height: 50)
                .shimmer(isAnimating)
            
            // Text skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 120, height: 14)
                    .shimmer(isAnimating)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 12)
                    .shimmer(isAnimating)
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .onAppear {
            isAnimating = true
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.bottom, 4)
    }
}

struct StickerEmptySearchView: View {
    let searchQuery: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 6) {
                Text("No se encontraron usuarios")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Intenta con \"\(searchQuery.lowercased())\" o busca otro nombre")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - Shimmer Effect Extension
extension View {
    func shimmer(_ isAnimating: Bool) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: isAnimating ? 200 : -200)
                .animation(
                    Animation.linear(duration: 1.2)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        )
        .clipped()
    }
}

// MARK: - No necesitas extensión - ya tienes las funciones en FirestoreService
// fetchMutualConnections, fetchUserProfile, searchUsers ya existen

struct ModernHashtagInputView: View {
    let onSelect: (String) -> Void
    @State private var hashtag = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 25) {
            // Header con icono
            VStack(spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.pink)
                
                Text("Añadir hashtag")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Usa hashtags para que más gente vea tu historia")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            
            // Campo de texto moderno
            VStack(spacing: 15) {
                HStack {
                    Text("#")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.pink)
                        .frame(width: 24)
                    
                    TextField("hashtag", text: $hashtag)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextFieldFocused ? Color.pink : Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                )
                
                // Botón de acción
                Button(action: {
                    onSelect(hashtag)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 18, weight: .medium))
                        
                        Text("Añadir hashtag")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(hashtag.isEmpty ? Color.gray.opacity(0.3) : Color.pink)
                    )
                }
                .disabled(hashtag.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: hashtag.isEmpty)
            }
            
            Spacer()
        }
        .padding(.horizontal, 25)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

struct ModernPollInputView: View {
    let onSelect: ([String]) -> Void
    @State private var question = ""
    @State private var option1 = ""
    @State private var option2 = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case question, option1, option2
    }
    
    var body: some View {
        VStack(spacing: 25) {
            // Header con icono
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.indigo)
                
                Text("Crear encuesta")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Haz una pregunta y deja que la gente vote")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            
            // Campos de texto modernos
            VStack(spacing: 20) {
                // Pregunta
                VStack(alignment: .leading, spacing: 8) {
                    Text("PREGUNTA")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .kerning(1)
                    
                    TextField("¿Cuál prefieres?", text: $question)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .question)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(focusedField == .question ? Color.indigo : Color.white.opacity(0.2), lineWidth: 1.5)
                                )
                        )
                }
                
                // Opción 1
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPCIÓN 1")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .kerning(1)
                    
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                        
                        TextField("Primera opción", text: $option1)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .option1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(focusedField == .option1 ? Color.blue : Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                    )
                }
                
                // Opción 2
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPCIÓN 2")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .kerning(1)
                    
                    HStack {
                        Circle()
                            .fill(Color.pink)
                            .frame(width: 12, height: 12)
                        
                        TextField("Segunda opción", text: $option2)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .option2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(focusedField == .option2 ? Color.pink : Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                    )
                }
                
                // Botón de acción
                Button(action: {
                    onSelect([question, option1, option2])
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                        
                        Text("Crear encuesta")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFormValid ? Color.indigo : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!isFormValid)
                .animation(.easeInOut(duration: 0.2), value: isFormValid)
            }
            
            Spacer()
        }
        .padding(.horizontal, 25)
        .onAppear {
            focusedField = .question
        }
    }
    
    private var isFormValid: Bool {
        !question.isEmpty && !option1.isEmpty && !option2.isEmpty
    }
}

struct ModernQuestionInputView: View {
    let onSelect: (String) -> Void
    @State private var question = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 25) {
            // Header con icono
            VStack(spacing: 12) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.teal)
                
                Text("Añadir pregunta")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Invita a tus seguidores a hacerte preguntas")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            
            // Campo de texto moderno
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.teal)
                        .frame(width: 24)
                    
                    TextField("Hazme una pregunta sobre...", text: $question)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextFieldFocused ? Color.teal : Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                )
                
                // Botón de acción
                Button(action: {
                    onSelect(question.isEmpty ? "Hazme una pregunta" : question)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                        
                        Text("Añadir pregunta")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.teal)
                    )
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 25)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Modern Grid Views

struct ModernEmojiGridView: View {
    let onSelect: (String) -> Void
    
    let emojis = ["😀", "😍", "🥳", "😎", "🤩", "😂", "🥺", "😭",
                  "😡", "🤯", "🥶", "🤗", "🙄", "😴", "🤔", "💀",
                  "❤️", "💔", "💯", "🔥", "⭐", "✨", "🎉", "🎈",
                  "👍", "👎", "👏", "🙏", "💪", "✌️", "🤟", "👌"]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15)
        ], spacing: 20) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        onSelect(emoji)
                    }
                }) {
                    Text(emoji)
                        .font(.system(size: 35))
                        .frame(width: 55, height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: emoji)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Animated GIF View
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit  // ✅ Cambio clave: aspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.clear
        
        if let url = url {
            loadAnimatedGIF(url: url, into: imageView)
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // No necesitamos actualizar
    }
    
    private func loadAnimatedGIF(url: URL, into imageView: UIImageView) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            DispatchQueue.main.async {
                if let animatedImage = UIImage.animatedImageWithData(data) {
                    imageView.image = animatedImage
                } else if let staticImage = UIImage(data: data) {
                    imageView.image = staticImage
                }
            }
        }.resume()
    }
}

// MARK: - UIImage Extension para GIFs
extension UIImage {
    static func animatedImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            // Si solo hay una imagen, retornar imagen estática
            return UIImage(data: data)
        }
        
        var images: [UIImage] = []
        var totalDuration: Double = 0
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            
            let image = UIImage(cgImage: cgImage)
            images.append(image)
            
            // ✅ OBTENER DURACIÓN DEL FRAME
            var frameDuration: Double = 0.1 // Duración por defecto
            
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                
                if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double {
                    frameDuration = delayTime
                } else if let delayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                    frameDuration = delayTime
                }
                
                // ✅ MÍNIMO 0.02 segundos para evitar animaciones demasiado rápidas
                frameDuration = max(frameDuration, 0.02)
            }
            
            totalDuration += frameDuration
        }
        
        // ✅ CREAR IMAGEN ANIMADA
        guard !images.isEmpty else { return nil }
        
        return UIImage.animatedImage(with: images, duration: totalDuration)
    }
}

struct ModernGiphyGridView: View {
    let gifs: [GiphyGif]
    let onSelect: (GiphyGif) -> Void
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(gifs) { gif in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        onSelect(gif)
                    }
                }) {
                    // Usar AnimatedGIFView para mostrar GIFs animados
                    if let url = URL(string: gif.images.fixed_height.url) {
                        AnimatedGIFView(url: url)
                            .frame(height: 120)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    } else {
                        // Placeholder si no hay URL válida
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: gif.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Giphy Models (sin cambios)

struct GiphyResponse: Codable {
    let data: [GiphyGif]
}

struct GiphyGif: Codable, Identifiable {
    let id: String
    let images: GiphyImages
}

struct GiphyImages: Codable {
    let fixed_height: GiphyImage
}

struct GiphyImage: Codable {
    let url: String
    let width: String
    let height: String
}

// MARK: - Extensions y Efectos Visuales (AGREGAR AL FINAL)

extension View {
    func glow(color: Color, radius: CGFloat) -> some View {
        self
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
    }
    
    func pressAnimation() -> some View {
        self.scaleEffect(1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: UUID())
    }
}

// MARK: - MeshGradient Fallback para iOS < 18
struct MeshGradient: View {
    let width: Int
    let height: Int
    let points: [[Float]]
    let colors: [Color]
    
    var body: some View {
        LinearGradient(
            colors: [colors.first ?? .black, colors.last ?? .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func pressAnimatioon() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    // Animation handled by button press
                }
            }
    }
}

// MARK: - Notificación de Menciones
extension StickerPickerView {
    // ✅ Función para enviar notificaciones de menciones al publicar historia
    static func sendMentionNotificationsForStory(storyId: String, stickers: [StickerItem]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ Filtrar solo stickers de menciones
        let mentionStickers = stickers.filter { $0.type == .mention }
        
        for sticker in mentionStickers {
            if let interactionData = sticker.interactionData,
               let userId = interactionData.userId,
               let username = interactionData.username {
                
                // ✅ Enviar notificación con storyId real
                NotificationService.shared.sendMentionNotification(
                    to: userId,
                    from: currentUserId,
                    contentId: storyId, // ✅ Usar storyId real
                    contentType: "story",
                    content: "Te mencionó en una historia"
                )
                
                print("📧 Notificación de mención enviada a @\(username) para historia \(storyId)")
            }
        }
    }
    
    // ✅ Función auxiliar para extraer userId de sticker de mención
    private func extractUserIdFromMentionSticker(_ sticker: StickerItem) -> String? {
        if let interactionData = sticker.interactionData {
            return interactionData.userId
        }
        return nil
    }
}

// MARK: - ✅ CLAVE ASOCIADA PARA DELEGATE
// MARK: - ✅ VISTA DE CÁMARA PARA SELFIE
struct SelfieCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    let onImageCaptured: (UIImage) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                
                Text("🤳 Selfie")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Toca para abrir la cámara frontal")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
                
                Button(action: {
                    showingImagePicker = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera, cameraDevice: .front) { image in
                onImageCaptured(image)
                dismiss()
            }
        }
    }
}

// MARK: - ✅ IMAGE PICKER WRAPPER
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let cameraDevice: UIImagePickerController.CameraDevice?
    let onImagePicked: (UIImage) -> Void
    
    init(sourceType: UIImagePickerController.SourceType, cameraDevice: UIImagePickerController.CameraDevice? = nil, onImagePicked: @escaping (UIImage) -> Void) {
        self.sourceType = sourceType
        self.cameraDevice = cameraDevice
        self.onImagePicked = onImagePicked
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        if let cameraDevice = cameraDevice {
            picker.cameraDevice = cameraDevice
        }
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
