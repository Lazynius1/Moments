import WidgetKit
import SwiftUI

@main
struct GlowsyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        GlowsyWidgetExtension()
        GlowsyWidgetExtensionControl()
        GlowsyWidgetExtensionLiveActivity()
    }
}
