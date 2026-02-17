import WidgetKit
import SwiftUI

@main
struct GlowsyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        GlowsyWidgetExtension()
        
        if #available(iOS 18.0, *) {
            GlowsyWidgetExtensionControl()
        }
        
        if #available(iOS 16.1, *) {
            GlowsyWidgetExtensionLiveActivity()
            MomentUploadLiveActivity()
        }
    }
}
