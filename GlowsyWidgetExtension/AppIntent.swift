//
//  AppIntent.swift
//  GlowsyWidgetExtension
//
//  Created by Alvaro Molina Torrano on 27/11/25.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "widget.intent.configuration.title" }
    static var description: IntentDescription { IntentDescription(LocalizedStringResource("widget.intent.configuration.description")) }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
