import SwiftUI

/// Estado derivado del overlay flotante.
struct ChatFloatingNavigationState: Equatable {
    var showsSearchControls: Bool = false
    var showsScrollToBottom: Bool = false

    var isVisible: Bool {
        showsSearchControls || showsScrollToBottom
    }

    static func resolve(
        hasCompletedInitialScroll: Bool,
        isSearchVisible: Bool,
        isSearchingHistory: Bool,
        hasSearchQuery: Bool,
        isPinnedToBottom: Bool
    ) -> ChatFloatingNavigationState {
        guard hasCompletedInitialScroll else { return ChatFloatingNavigationState() }

        let showsSearch = isSearchVisible && (isSearchingHistory || hasSearchQuery)
        let showsScroll = !isPinnedToBottom && !isSearchVisible

        return ChatFloatingNavigationState(
            showsSearchControls: showsSearch,
            showsScrollToBottom: showsScroll
        )
    }
}

/// Un solo bloque flotante abajo-derecha.
struct ChatFloatingNavigationOverlay: View {
    let state: ChatFloatingNavigationState
    let counterText: String
    let isSearching: Bool
    let canSearchGoUp: Bool
    let canSearchGoDown: Bool
    let pendingIncomingCount: Int
    let accentColor: Color
    let badgeTextColor: Color
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let onSearchPrevious: () -> Void
    let onSearchNext: () -> Void
    let onScrollToBottom: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if state.showsSearchControls {
                searchControls
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }

            if state.showsScrollToBottom {
                ChatScrollDownButton(
                    pendingCount: pendingIncomingCount,
                    accentColor: accentColor,
                    badgeTextColor: badgeTextColor,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion,
                    action: onScrollToBottom
                )
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72),
            value: state
        )
    }

    private var searchControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            floatingNavButton(systemName: "chevron.up", isEnabled: canSearchGoUp, action: onSearchPrevious)
            floatingNavButton(systemName: "chevron.down", isEnabled: canSearchGoDown, action: onSearchNext)
        }
        .scaleEffect(searchControlsAppeared ? 1 : 0.2)
        .opacity(searchControlsAppeared ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                searchControlsAppeared = true
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                searchControlsAppeared = true
            }
        }
        .onDisappear {
            searchControlsAppeared = false
        }
    }

    @State private var searchControlsAppeared = false

    private func floatingNavButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isEnabled ? accentColor : accentColor.opacity(0.35))
                .frame(width: 40, height: 40)
                .momentsChromeGlass(in: Circle(), interactive: true)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
