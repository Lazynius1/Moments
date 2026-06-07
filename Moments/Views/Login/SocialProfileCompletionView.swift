import SwiftUI

struct SocialProfileCompletionView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        ProfileOnboardingView(context: .apple)
            .environmentObject(authService)
    }
}
