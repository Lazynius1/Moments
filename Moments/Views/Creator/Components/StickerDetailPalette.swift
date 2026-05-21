import SwiftUI

struct StickerDetailPalette {
    let colorScheme: ColorScheme

    var primaryText: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.92)
    }

    var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color.black.opacity(0.50)
    }

    var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.40) : Color.black.opacity(0.34)
    }

    var searchIcon: Color {
        colorScheme == .dark ? .white.opacity(0.54) : Color.black.opacity(0.36)
    }

    var searchIconActive: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.66)
    }

    var clearIcon: Color {
        colorScheme == .dark ? .white.opacity(0.56) : Color.black.opacity(0.34)
    }

    var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var fieldStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    var buttonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var divider: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var skeletonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}
