import SwiftUI

/// Shared native chrome; each entry retains its own content and navigation state.
struct MapImmersiveChrome: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    @Binding var searchText: String
    var contentFilter: MapDiscoverContentFilter? = nil
    var onFilter: ((MapDiscoverContentFilter) -> Void)? = nil
    let onClose: () -> Void
    let onSearch: () -> Void
    let onRecenter: () -> Void
    let onOpenContent: () -> Void
    var showsSearchArea = false
    var onSearchArea: (() -> Void)? = nil
    var showsDock = true
    var panelHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    private var controlColor: Color { colorScheme == .dark ? .white : .black }
    private var selectedControlColor: Color { colorScheme == .dark ? .black : .white }

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) {
                chromeContent
            }
        } else {
            chromeContent
        }
    }

    private var chromeContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Label(NSLocalizedString("common.close", comment: ""), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .momentsChromeGlass(in: Circle(), style: .tinted)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.secondary)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text(NSLocalizedString("maps.search.placeholder", comment: ""))
                            .foregroundStyle(colors.secondary)
                    )
                        .font(.subheadline)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit {
                            searchFocused = false
                            onSearch()
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Label(NSLocalizedString("common.close", comment: ""), systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .momentsChromeGlass(in: Capsule(), style: .tinted)
            }
            Spacer(minLength: 16)
            HStack {
                Spacer()
                Button {
                    searchFocused = false
                    onRecenter()
                } label: {
                    Label(NSLocalizedString("maps.chrome.recenter", comment: ""), systemImage: "location.fill")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controlColor)
                .momentsChromeGlass(in: Circle(), style: .tinted)
            }
            if let contentFilter, let onFilter {
                HStack(spacing: 8) {
                    ForEach(MapDiscoverContentFilter.allCases) { filter in
                        Button {
                            searchFocused = false
                            onFilter(filter)
                        } label: {
                            Text(NSLocalizedString(filter.titleKey, comment: ""))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .foregroundStyle(filter == contentFilter ? selectedControlColor : controlColor)
                                .background {
                                    if filter == contentFilter {
                                        Capsule().fill(controlColor)
                                    }
                                }
                                .momentsChromeGlass(
                                    in: Capsule(),
                                    isEnabled: filter != contentFilter,
                                    style: .tinted
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == contentFilter ? [.isSelected] : [])
                    }
                }
            }
            if showsSearchArea, let onSearchArea {
                Button {
                    searchFocused = false
                    onSearchArea()
                } label: {
                    Label(NSLocalizedString("maps.search.thisArea", comment: ""), systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .momentsChromeGlass(in: Capsule(), style: .tinted)
            }
            if showsDock {
            Button {
                searchFocused = false
                onOpenContent()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(controlColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).lineLimit(2)
                        Text(subtitle).font(.footnote).foregroundStyle(colors.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.up").font(.subheadline.weight(.semibold))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 26), style: .tinted)
            }
            .buttonStyle(.plain)
            }
        }
        .tint(controlColor)
        .foregroundStyle(controlColor)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, showsDock ? 12 : min(panelHeight, 350) + 12)
        .opacity(showsDock ? 1 : max(0, min(1, 1 - (panelHeight - 350) / 50)))
        .allowsHitTesting(showsDock || panelHeight < 400)
        .accessibilityHidden(!showsDock && panelHeight >= 400)
    }
}
