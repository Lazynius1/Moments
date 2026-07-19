import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraPermissionsview(
            title: NSLocalizedString("permission.camera.primer.title", comment: "Camera primer title"),
            description: NSLocalizedString("permission.camera.primer.subtitle", comment: "Camera primer subtitle"),
            primaryActionTitle: NSLocalizedString("permission.camera.primer.allow", comment: "Allow camera"),
            secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
            showsShutterUI: true
        ) {

        } secondaryAction: {

        } panorama: {
            return Image(.pic1)
                .resizable()
            
        }
    }
}
