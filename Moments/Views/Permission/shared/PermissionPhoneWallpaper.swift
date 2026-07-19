import SwiftUI

struct PermissionPhoneWallpaper: View {
    var body: some View {
        Group {
            if let ui = UIImage(named: "PermissionWallpaper") {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(.pic1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}
