import WidgetKit
import SwiftUI

@main
struct GlowsyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        GlowsyWidgetExtension()
        GlowsyWidgetExtensionControl()
        if #available(iOS 16.1, *) {
            GlowsyWidgetExtensionLiveActivity()
            MomentUploadLiveActivity()
        }
    }
}
