import WidgetKit
import SwiftUI

// MARK: - Localization Helper

/// Helper para cargar localizaciones desde el bundle del widget extension
private func localizedString(_ key: String, comment: String) -> String {
    // Los archivos de localización están ahora en el widget extension bundle
    return NSLocalizedString(key, bundle: Bundle.main, comment: comment)
}

// MARK: - Timeline Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            profileVisitsToday: 0,
            unreadMessages: 0,
            unreadNotifications: 0,
            recentEvents: []
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        loadEntryFromSharedDefaults()
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = loadEntryFromSharedDefaults()
        return Timeline(entries: [entry], policy: .atEnd)
    }
    
    // MARK: - Shared storage
    
    private func loadEntryFromSharedDefaults() -> SimpleEntry {
        // ✅ Debe coincidir con el App Group configurado en Xcode (Targets Moments + Widget)
        let defaults = UserDefaults(suiteName: "group.com.glowsyapp")
        
        let visitsToday = defaults?.integer(forKey: "widget_profile_visits_today") ?? 0
        let unreadMessages = defaults?.integer(forKey: "widget_unread_messages") ?? 0
        let unreadNotifications = defaults?.integer(forKey: "widget_unread_notifications") ?? 0
        let newStoriesCount = defaults?.integer(forKey: "widget_new_stories_count") ?? 0
        let pendingMessageRequests = defaults?.integer(forKey: "widget_pending_message_requests") ?? 0
        
        var events: [WidgetEvent] = []
        if visitsToday > 0 {
            events.append(.visits(count: visitsToday))
        }
        if unreadMessages > 0 {
            events.append(.messages(count: unreadMessages))
        }
        if unreadNotifications > 0 {
            events.append(.notifications(count: unreadNotifications))
        }
        if newStoriesCount > 0 {
            events.append(.newStories(count: newStoriesCount))
        }
        if pendingMessageRequests > 0 {
            events.append(.messageRequests(count: pendingMessageRequests))
        }
        
        return SimpleEntry(
            date: Date(),
            profileVisitsToday: visitsToday,
            unreadMessages: unreadMessages,
            unreadNotifications: unreadNotifications,
            recentEvents: events
        )
    }
}

// MARK: - Entry

struct WidgetEvent: Identifiable {
    let id = UUID()
    let text: String
    let deepLink: URL
    
    static func visits(count: Int) -> WidgetEvent {
        let text = count == 1 
            ? localizedString("widget.visits.singular", comment: "1 person visited profile")
            : String(format: localizedString("widget.visits.plural", comment: "X people visited profile"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://profile/visits")!
        )
    }
    
    static func messages(count: Int) -> WidgetEvent {
        let text = count == 1
            ? localizedString("widget.messages.singular", comment: "1 unread message")
            : String(format: localizedString("widget.messages.plural", comment: "X unread messages"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://messages")!
        )
    }
    
    static func notifications(count: Int) -> WidgetEvent {
        let text = count == 1
            ? localizedString("widget.notifications.singular", comment: "1 new notification")
            : String(format: localizedString("widget.notifications.plural", comment: "X new notifications"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://notifications")!
        )
    }
    
    static func newStories(count: Int) -> WidgetEvent {
        let text = count == 1
            ? localizedString("widget.stories.singular", comment: "1 new story")
            : String(format: localizedString("widget.stories.plural", comment: "X new stories"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://stories")!
        )
    }
    
    static func messageRequests(count: Int) -> WidgetEvent {
        let text = count == 1
            ? localizedString("widget.messageRequests.singular", comment: "1 pending message request")
            : String(format: localizedString("widget.messageRequests.plural", comment: "X pending message requests"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://messages")!
        )
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let profileVisitsToday: Int
    let unreadMessages: Int
    let unreadNotifications: Int
    let recentEvents: [WidgetEvent]
}

// MARK: - Main Widget View

struct MomentsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry
    
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple, Color.pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallCreatorView
        case .systemMedium:
            mediumPanelView
        default:
            smallCreatorView
        }
    }
    
    // MARK: - Small: acción principal Creator
    
    private var smallCreatorView: some View {
        let url = URL(string: "moments://story/create")!
        
        return Link(destination: url) {
            VStack(spacing: 10) {
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(gradient, lineWidth: 4)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(gradient)
                }
                
                VStack(spacing: 4) {
                    Text(localizedString("widget.createStory.title", comment: "Upload story"))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(localizedString("widget.createStory.subtitle", comment: "Tap to create in Moments"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(0.8)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                ContainerRelativeShape()
                    .stroke(gradient.opacity(0.6), lineWidth: 2)
            )
        }
    }
    
    // MARK: - Medium: panel con visitas, mensajes y notificaciones
    
    private var mediumPanelView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Métricas rápidas
            HStack(spacing: 10) {
                metricChip(
                    icon: "person.crop.circle",
                    label: localizedString("widget.metrics.visits", comment: "Visits"),
                    value: entry.profileVisitsToday
                )
                
                metricChip(
                    icon: "bubble.left.and.bubble.right.fill",
                    label: localizedString("widget.metrics.messages", comment: "Messages"),
                    value: entry.unreadMessages
                )
                
                metricChip(
                    icon: "bell.fill",
                    label: localizedString("widget.metrics.notifications", comment: "Notifications"),
                    value: entry.unreadNotifications
                )
                
                Spacer(minLength: 0)
            }
            
            Divider()
                .overlay(gradient.opacity(0.3))
            
            // Últimos eventos (3 máx) - cada uno es tappable
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.recentEvents.prefix(3)) { event in
                    Link(destination: event.deepLink) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(gradient)
                                .frame(width: 6, height: 6)
                            
                            Text(event.text)
                                .font(.footnote) // Un poco más grande que caption2
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(
            ContainerRelativeShape()
                .stroke(gradient.opacity(0.6), lineWidth: 2)
        )
    }
    
    // MARK: - Subvistas
    
    private func metricChip(icon: String, label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            
            Text(label)
                .font(.system(size: 10, weight: .regular))
            
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
        .foregroundStyle(LinearGradient(
            colors: [Color.primary, Color.primary.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }
    
}

// MARK: - Widget

struct GlowsyWidgetExtension: Widget {
    let kind: String = "GlowsyWidgetExtension"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: Provider()
        ) { entry in
            MomentsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Moments")
        .description("Accede rápido a tus historias, visitas y mensajes.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    GlowsyWidgetExtension()
} timeline: {
    SimpleEntry(
        date: .now,
        profileVisitsToday: 5,
        unreadMessages: 2,
        unreadNotifications: 7,
        recentEvents: [
            .visits(count: 5),
            .messages(count: 2),
            .notifications(count: 7),
            .newStories(count: 3),
            .messageRequests(count: 1)
        ]
    )
}
