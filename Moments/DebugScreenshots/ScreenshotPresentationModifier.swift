#if DEBUG
import SwiftUI

/// Abre la pantalla pedida en modo captura encima de la app real.
/// Fuera del modo captura no hace nada ni crea servicios.
struct ScreenshotPresentationModifier: ViewModifier {
    @State private var cover: ScreenshotMode.Screen?
    @State private var sheet: ScreenshotMode.Screen?
    @State private var didPresent = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $cover) { screen in
                withEnvironment(coverContent(for: screen))
            }
            .sheet(item: $sheet) { screen in
                withEnvironment(sheetContent(for: screen))
            }
            .onAppear(perform: presentIfNeeded)
    }

    private func presentIfNeeded() {
        guard let screen = ScreenshotMode.screen, !didPresent else { return }
        didPresent = true

        // Margen para que la app termine su primer layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch screen {
            case .feed, .aiLabel:
                break
            case .chat:
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToConversation"),
                    object: ScreenshotFixtures.chatConversationId
                )
            case .chatInbox:
                NotificationCenter.default.post(name: NSNotification.Name("ShowMessages"), object: nil)
            case .storyViewer, .hiddenLayers, .echo, .map, .nova:
                cover = screen
            case .privacy, .appIcons:
                sheet = screen
            }
        }
    }

    @ViewBuilder
    private func coverContent(for screen: ScreenshotMode.Screen) -> some View {
        switch screen {
        case .storyViewer:
            ScreenshotStoryHost(stories: ScreenshotFixtures.stories, index: ScreenshotMode.storyIndex)
        case .hiddenLayers:
            MomentDetailView(moment: ScreenshotFixtures.hiddenLayersMoment)
        case .echo:
            EchoViewerUI(echoId: ScreenshotFixtures.echo.id ?? "ss_echo", initialEcho: ScreenshotFixtures.echo)
        case .map:
            NavigationStack {
                DiscoverMapView(isPresented: .constant(true))
            }
        case .nova:
            NavigationStack {
                NovaView()
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sheetContent(for screen: ScreenshotMode.Screen) -> some View {
        switch screen {
        case .privacy:
            // Misma presentación que en CaptionAndDetailsView, a altura completa.
            AudienceSelectionView(
                selectedAudience: .constant(.bestFriends),
                selectedListId: .constant(nil),
                selectedListName: .constant(nil),
                customSelectedUsers: .constant([])
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        case .appIcons:
            ScreenshotAppIconPickerHost()
        default:
            EmptyView()
        }
    }

    private func withEnvironment<V: View>(_ view: V) -> some View {
        let environment = ScreenshotEnvironment.shared
        return view
            .environmentObject(FirestoreService.shared)
            .environmentObject(environment.authService)
            .environmentObject(environment.tabBarMinimize)
            .environmentObject(environment.messagingViewModel)
            .environment(environment.feedViewModel)
    }
}

/// Objetos de entorno que la app inyecta dentro de TabBarView; las
/// presentaciones del modo captura cuelgan fuera y los necesitan aparte.
@MainActor
private final class ScreenshotEnvironment {
    static let shared = ScreenshotEnvironment()
    let authService = AuthService()
    let tabBarMinimize = TabBarMinimizeController()
    let messagingViewModel = MessagingViewModel()
    let feedViewModel = FeedViewModel()
}

/// Visor de historias fijo (basado en ArchiveDayStoriesViewer): abre una
/// historia concreta con el progreso a mitad y nunca se cierra.
struct ScreenshotStoryHost: View {
    @Environment(\.momentsViewportSize) private var momentsViewportSize

    let stories: [Story]
    let index: Int

    @StateObject private var storyViewModel = StoryViewModel()
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false

    var body: some View {
        ZStack {
            if let story = currentStory {
                StoryViewerScreen(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: clampedIndex,
                    screenSize: momentsViewportSize,
                    storyViewModel: storyViewModel,
                    showingReportSheet: $showingReportSheet,
                    showingBlockConfirmation: $showingBlockConfirmation,
                    onReportStory: {},
                    onBlockUser: {},
                    onNext: {},
                    onPrevious: {},
                    onClose: {},
                    onProfileTap: {},
                    initialElapsed: story.duration * 0.4
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .all)
        .ignoresSafeArea(.container, edges: .all)
        .statusBar(hidden: false)
        .onAppear {
            GlobalVideoManager.shared.pauseAllVideos()
            if let authorId = stories.first?.authorId {
                storyViewModel.stories[authorId] = stories
            }
        }
    }

    private var clampedIndex: Int {
        min(max(index, 0), max(stories.count - 1, 0))
    }

    private var currentStory: Story? {
        stories.indices.contains(clampedIndex) ? stories[clampedIndex] : nil
    }
}
#endif
