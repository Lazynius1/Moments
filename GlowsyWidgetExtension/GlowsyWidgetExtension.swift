import WidgetKit
import SwiftUI
import UIKit

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
            unreadEchoes: 0,
            unreadTags: 0,
            profileImageData: nil,
            recentEvents: []
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        await loadEntryFromSharedDefaults()
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = await loadEntryFromSharedDefaults()
        return Timeline(entries: [entry], policy: .atEnd)
    }
    
    // MARK: - Shared storage
    
    private func loadEntryFromSharedDefaults() async -> SimpleEntry {
        // ✅ Debe coincidir con el App Group configurado en Xcode (Targets Moments + Widget)
        let defaults = UserDefaults(suiteName: "group.com.glowsyapp")
        
        let visitsToday = defaults?.integer(forKey: "widget_profile_visits_today") ?? 0
        let unreadMessages = defaults?.integer(forKey: "widget_unread_messages") ?? 0
        let unreadNotifications = defaults?.integer(forKey: "widget_unread_notifications") ?? 0
        let newStoriesCount = defaults?.integer(forKey: "widget_new_stories_count") ?? 0
        let pendingMessageRequests = defaults?.integer(forKey: "widget_pending_message_requests") ?? 0
        let unreadEchoes = defaults?.integer(forKey: "widget_unread_echoes") ?? 0
        let unreadTags = defaults?.integer(forKey: "widget_unread_tags") ?? 0
        
        var events: [WidgetEvent] = []
        if unreadEchoes > 0 {
            events.append(.echoes(count: unreadEchoes))
        }
        if unreadTags > 0 {
            events.append(.tags(count: unreadTags))
        }
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
        
        // Perfil para el "Clock"
        let profileImagePath = defaults?.string(forKey: "widget_user_profile_image")
        let imageData = await fetchImageData(from: profileImagePath)
        
        return SimpleEntry(
            date: Date(),
            profileVisitsToday: visitsToday,
            unreadMessages: unreadMessages,
            unreadNotifications: unreadNotifications,
            unreadEchoes: unreadEchoes,
            unreadTags: unreadTags,
            profileImageData: imageData,
            recentEvents: events
        )
    }

    // Helper para descargar la imagen de perfil para el widget
    private func fetchImageData(from urlString: String?) async -> Data? {
        guard let urlString = urlString, let url = URL(string: urlString) else { return nil }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5 // Limitar a 5 segundos para no colgar el widget
        let session = URLSession(configuration: config)
        
        do {
            let (data, _) = try await session.data(from: url)
            return data
        } catch {
            return nil
        }
    }
}

// MARK: - Entry

struct WidgetEvent: Identifiable {
    let id = UUID()
    let text: String
    let deepLink: URL
    
    static func echoes(count: Int) -> WidgetEvent {
        let text = count == 1 
            ? localizedString("widget.echoes.singular", comment: "1 friend nearby")
            : String(format: localizedString("widget.echoes.plural", comment: "X friends nearby"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://echoes")!
        )
    }
    
    static func tags(count: Int) -> WidgetEvent {
        let text = count == 1 
            ? localizedString("widget.tags.singular", comment: "1 new tag")
            : String(format: localizedString("widget.tags.plural", comment: "X new tags"), count)
        return WidgetEvent(
            text: text,
            deepLink: URL(string: "moments://notifications")!
        )
    }
    
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
    let unreadEchoes: Int
    let unreadTags: Int
    let profileImageData: Data? // ✅ Foto descargada para el estado "Empty"
    let recentEvents: [WidgetEvent]
    var shouldPulse: Bool { unreadEchoes > 0 } // ✅ Refinement: Pulse if Echoes
}

// MARK: - Main Widget View

struct MomentsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry
    
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [MomentsBrand.teal, MomentsBrand.blue],
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
        VStack(spacing: 8) {
            Spacer()
            
            ZStack {
                // ✅ Refinement: Pulsing Aura
                if entry.shouldPulse {
                    Circle()
                        .fill(gradient)
                        .frame(width: 56, height: 56)
                        .blur(radius: 8)
                        .opacity(0.4)
                        .phaseAnimator([0.8, 1.2]) { content, phase in
                            content.scaleEffect(phase)
                        } animation: { _ in
                            .easeInOut(duration: 2).repeatForever(autoreverses: true)
                        }
                }
                
                Circle()
                    .stroke(gradient, lineWidth: 4)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.ultraThinMaterial))
                
                // ✅ Refinement: Interactive Link (Standard for reliable deep linking)
                Link(destination: URL(string: "moments://story/create")!) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(gradient)
                }
                
                // Notificación flotante de Echoes/Tags si existen (Subtle)
                if entry.unreadEchoes > 0 || entry.unreadTags > 0 {
                    Circle()
                        .fill(entry.unreadEchoes > 0 ? MomentsBrand.blue : MomentsBrand.teal)
                        .frame(width: 10, height: 10)
                        .offset(x: 18, y: -18)
                        .shadow(radius: 1)
                        .widgetAccentable()
                }
            }
            .padding(.top, 4)
            
            VStack(spacing: 2) {
                Text(localizedString("widget.createStory.title", comment: "Upload story"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if entry.unreadEchoes > 0 {
                    Text(localizedString("widget.echoes.singular", comment: "Echo nearby"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MomentsBrand.blue)
                } else {
                    Text(localizedString("widget.createStory.subtitle", comment: "Tap to create"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
            }
            
            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    // MARK: - Medium: panel con diseño asimétrico Premium
    
    // Estructura para manejar el orden dinámico de las métricas
    struct MetricInfo: Comparable {
        let id: String
        let icon: String
        let label: String
        let value: Int
        
        static func < (lhs: MetricInfo, rhs: MetricInfo) -> Bool {
            return lhs.value < rhs.value
        }
    }

    private var mediumPanelView: some View {
        let allMetrics = [
            MetricInfo(id: "messages", icon: "bubble.left.fill", label: "Chats", value: entry.unreadMessages),
            MetricInfo(id: "echoes", icon: "wave.3.right", label: "Echoes", value: entry.unreadEchoes),
            MetricInfo(id: "tags", icon: "tag.fill", label: "Tags", value: entry.unreadTags),
            MetricInfo(id: "notifications", icon: "bell.fill", label: "Notifs", value: entry.unreadNotifications)
        ].sorted(by: >)
        
        // El Héroe es la métrica con más notificaciones (mínimo 1)
        let heroMetric = allMetrics.first { $0.value > 0 }
        
        // Las secundarias son todas las demás métricas para que el grid siempre esté lleno (4 cajas en total)
        let secondaryMetrics = allMetrics.filter { $0.id != (heroMetric?.id ?? "eye_placeholder") }

        return HStack(alignment: .top, spacing: 16) {
            // --- LADO IZQUIERDO: HERO ---
            VStack(alignment: .leading, spacing: 12) {
                if let hero = heroMetric {
                    metricChip(icon: hero.icon, label: hero.label, value: hero.value, isLarge: true)
                        .frame(width: 105)
                } else {
                    // ESTADO: Profile Square Card (Ocupa todo el espacio hasta el botón)
                    ZStack {
                        if let data = entry.profileImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 105, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 105, height: 108)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.secondary.opacity(0.3))
                                )
                        }
                        
                        // Overlay de cristal sutil en la parte inferior si queremos poner algo (opcional)
                    }
                    .padding(.top, 2)
                    .frame(width: 105, height: 118)
                }
                
                if heroMetric != nil {
                    Spacer()
                }
                
                // Botón de Captura (Ancho fijo)
                Link(destination: URL(string: "moments://story/create")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text(localizedString("widget.createStory.title", comment: "Upload"))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 105)
                    .padding(.vertical, 10)
                    .background(gradient)
                    .cornerRadius(12)
                    .shadow(color: MomentsBrand.blue.opacity(0.3), radius: 5, x: 0, y: 3)
                }
            }
            
            // --- LADO DERECHO: GRID ESCALABLE ---
            VStack(alignment: .leading, spacing: 12) {
                Text("Moments")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(gradient)
                    .opacity(0.7)

                // Lista de métricas secundarias en una sola línea
                HStack(spacing: 6) {
                    ForEach(secondaryMetrics, id: \.id) { metric in
                        metricChip(icon: metric.icon, label: metric.label, value: metric.value)
                    }
                }
                
                Divider().opacity(0.1)
                
                // Eventos Recientes
                VStack(alignment: .leading, spacing: 8) {
                    if entry.recentEvents.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(gradient)
                            Text(localizedString("widget.allCaughtUp", comment: "All caught up"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(entry.recentEvents.prefix(2)) { event in
                            Link(destination: event.deepLink) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(gradient)
                                        .frame(width: 4, height: 4)
                                    Text(event.text)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.primary.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    // MARK: - Subvistas
    
    private func metricChip(icon: String, label: String, value: Int, isLarge: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isLarge ? 4 : 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                    .foregroundStyle(gradient)
                
                Text("\(value)")
                    .font(.system(size: isLarge ? 16 : 12, weight: .black, design: .rounded))
            }
            
            Text(label)
                .font(.system(size: isLarge ? 10 : 8, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, isLarge ? 12 : 8)
        .padding(.vertical, isLarge ? 10 : 6)
        .frame(maxWidth: isLarge ? .infinity : nil, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(isLarge ? 14 : 10)
        .widgetAccentable()
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
        profileVisitsToday: 12,
        unreadMessages: 3,
        unreadNotifications: 5,
        unreadEchoes: 1,
        unreadTags: 0,
        profileImageData: nil,
        recentEvents: [
            .echoes(count: 1),
            .visits(count: 12)
        ]
    )
}


// MARK: - App Intents (Example, currently using native Link for deep links)

import AppIntents
