import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        ProfileOnboardingView(context: .email)
            .environmentObject(authService)
    }
}

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView()
            .environmentObject(AuthService())
    }
}
