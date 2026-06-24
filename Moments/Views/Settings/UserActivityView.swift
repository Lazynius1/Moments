import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import Kingfisher
import AVFoundation

struct UserActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var summaryVM = ActivitySummaryViewModel()

    var body: some View {
        ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("userActivity.simple.headline", comment: "Activity headline"))
                                .font(.custom("Poppins-Bold", size: 30))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.leading)

                            Text(NSLocalizedString("userActivity.simple.subtitle", comment: "Activity subtitle"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 32) {
                            // SECCIÓN: INTERACCIONES
                            activitySection(
                                title: NSLocalizedString("userActivity.section.interactions", comment: "Interactions section"),
                                categories: [.reactions, .comments, .tags, .stickerReplies]
                            )

                            // SECCIÓN: CONTENIDO ELIMINADO Y ARCHIVADO
                            activitySection(
                                title: NSLocalizedString("userActivity.module.content.title", comment: "Content section"),
                                categories: [.archived, .storiesArchive, .recentlyDeleted]
                            )

                            // SECCIÓN: CONTENIDO COMPARTIDO
                            activitySection(
                                title: NSLocalizedString("userActivity.section.sharedContent", comment: "Shared content section"),
                                categories: [.moments, .reels, .echoes]
                            )

                            // SECCIÓN: HISTORIAL
                            activitySection(
                                title: NSLocalizedString("userActivity.section.history", comment: "History section"),
                                categories: [.followers, .visits]
                            )

                            // SECCIÓN: CÓMO USAS MOMENTS
                            activitySection(
                                title: NSLocalizedString("userActivity.section.usage", value: "HOW YOU USE MOMENTS", comment: "Usage section"),
                                categories: [.timeSpent, .searches, .accountHistory]
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(NSLocalizedString("userActivity.title", comment: "User activity title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
                }
            }
            .onAppear {
                summaryVM.load()
                summaryVM.autoRefresh()
            }
        .momentZoomNavigationSurface(colorScheme: colorScheme)
    }

    private func activitySection(title: String, categories: [ActivityInteractionCategory]) -> some View {
            VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(.gray.opacity(0.8))
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    NavigationLink {
                        activityDestination(for: category)
                    } label: {
                        ActivityInteractionCategoryRow(
                            category: category,
                            summary: summaryVM.summaries[category]
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    if index < categories.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
        }
    }

    // Removed custom timeSpentSection() method -> now using activitySection()

    @ViewBuilder
    private func activityDestination(for category: ActivityInteractionCategory) -> some View {
        switch category {
        case .archived:
            ArchivedActivityView()
        case .recentlyDeleted:
            RecentlyDeletedActivityView()
        case .storiesArchive:
            ArchivedActivityView(initialKind: .stories)
        case .timeSpent:
            TimeSpentDetailsView()
        case .searches:
            SearchHistoryActivityView()
        case .accountHistory:
            AccountHistoryActivityView()
        default:
            ActivityInteractionDetailView(category: category)
        }
    }
}

struct RecentlyDeletedActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedKind: RecentlyDeletedContentKind = .moments

    private var momentsTitle: String {
        NSLocalizedString("profile.moments.title", comment: "Moments")
    }

    private var storiesTitle: String {
        NSLocalizedString("notifications.tab.stories", comment: "Stories")
    }

    private var currentTitle: String {
        selectedKind == .moments ? momentsTitle : storiesTitle
    }

    var body: some View {
        ActivityInteractionDetailView(category: .recentlyDeleted, recentlyDeletedKind: selectedKind)
            .id(selectedKind)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            selectedKind = .moments
                        } label: {
                            Label(momentsTitle, systemImage: selectedKind == .moments ? "checkmark" : "photo.on.rectangle")
                        }

                        Button {
                            selectedKind = .stories
                        } label: {
                            Label(storiesTitle, systemImage: selectedKind == .stories ? "checkmark" : "circle.dashed")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(currentTitle)
                                .font(.custom("Poppins-SemiBold", size: 17))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
    }
}

struct ArchivedActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedKind: ArchivedContentKind

    init(initialKind: ArchivedContentKind = .moments) {
        _selectedKind = State(initialValue: initialKind)
    }

    private var momentsTitle: String {
        NSLocalizedString("userActivity.simple.item.archived.headerTitle", comment: "Archived moments header title")
    }

    private var storiesTitle: String {
        NSLocalizedString("archivedStories.headerTitle", comment: "Archive Stories header title")
    }

    private var currentTitle: String {
        selectedKind == .moments ? momentsTitle : storiesTitle
    }

    var body: some View {
        Group {
            switch selectedKind {
            case .moments:
                ActivityInteractionDetailView(category: .archived, suppressInlineNavigationTitle: true)
            case .stories:
                ArchiveView(embedInNavigation: false, showsCustomDismiss: false)
            }
        }
        .id(selectedKind)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    Button {
                        selectedKind = .moments
                    } label: {
                        Label(momentsTitle, systemImage: selectedKind == .moments ? "checkmark" : "photo.on.rectangle")
                    }

                    Button {
                        selectedKind = .stories
                    } label: {
                        Label(storiesTitle, systemImage: selectedKind == .stories ? "checkmark" : "circle.dashed")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(currentTitle)
                            .font(.custom("Poppins-SemiBold", size: 17))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
}

// MARK: - Compatibility Type
enum ActivityTimeRange: String, CaseIterable {
    case week = "week"
    case month = "month"
    case year = "year"

    var title: String {
        switch self {
        case .week:
            return NSLocalizedString("userActivity.range.week", comment: "7 days range")
        case .month:
            return NSLocalizedString("userActivity.range.month", comment: "30 days range")
        case .year:
            return NSLocalizedString("userActivity.range.year", comment: "1 year range")
        }
    }
}
