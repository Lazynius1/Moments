import SwiftUI
import UIKit

struct StoryBackgroundPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let hexColors: [String]
    let usesAutoPalette: Bool

    init(id: String, name: String, hexColors: [String], usesAutoPalette: Bool = false) {
        self.id = id
        self.name = name
        self.hexColors = hexColors
        self.usesAutoPalette = usesAutoPalette
    }

    var uiColors: [UIColor] {
        if usesAutoPalette { return [] }
        return hexColors.map { UIColor(Color(hex: $0)) }
    }

    static let auto = StoryBackgroundPreset(
        id: "auto",
        name: "Auto",
        hexColors: [],
        usesAutoPalette: true
    )

    static let presets: [StoryBackgroundPreset] = [
        .auto,
        StoryBackgroundPreset(id: "sunset", name: "Sunset", hexColors: ["FF7A59", "FFB347", "FFD56F"]),
        StoryBackgroundPreset(id: "berry", name: "Berry", hexColors: ["5B2A86", "A4508B", "F764A1"]),
        StoryBackgroundPreset(id: "lagoon", name: "Lagoon", hexColors: ["005AA7", "43C6AC", "E4FDF9"]),
        StoryBackgroundPreset(id: "lime", name: "Lime", hexColors: ["1E9600", "93F9B9", "F9F871"]),
        StoryBackgroundPreset(id: "ember", name: "Ember", hexColors: ["2B061E", "875053", "D1A080"]),
        StoryBackgroundPreset(id: "midnight", name: "Midnight", hexColors: ["0F2027", "203A43", "2C5364"]),
        StoryBackgroundPreset(id: "candy", name: "Candy", hexColors: ["FF5F6D", "FFC371", "FFE29F"]),
        StoryBackgroundPreset(id: "aurora", name: "Aurora", hexColors: ["00C9A7", "845EC2", "FF6F91"]),
        StoryBackgroundPreset(id: "ocean", name: "Ocean", hexColors: ["114B5F", "028090", "E4FDE1"]),
        StoryBackgroundPreset(id: "pride", name: "Pride", hexColors: ["E40303", "FF8C00", "FFED00", "008026", "24408E", "732982"])
    ]
}
