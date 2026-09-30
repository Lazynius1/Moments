import SwiftUI

/// Persistent native map sheet, following the supplied Maps reference.
struct MapImmersivePanel<Content: View>: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    @Binding var detent: PresentationDetent
    var onBack: (() -> Void)? = nil
    var storyCover: MapStoryPreview? = nil
    var locationMoment: Moment? = nil
    var onStoriesTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    private var controlColor: Color { colorScheme == .dark ? .white : .black }
    private var isCollapsed: Bool { detent == MapLocationSystemSheetModifier.collapsedDetent }

    var body: some View {
        VStack(spacing: 0) {
            if !isCollapsed, let onBack {
                Button(action: onBack) {
                    Label(NSLocalizedString("maps.zoneSheet.places", comment: ""), systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(controlColor.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(controlColor.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(controlColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            HStack(spacing: 12) {
                if storyCover != nil, let onStoriesTap {
                    Button(action: onStoriesTap) { locationCover }
                        .buttonStyle(.plain)
                        .accessibilityLabel(subtitle)
                } else {
                    locationCover.accessibilityHidden(true)
                }
            Button {
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                    if isCollapsed {
                        detent = MapLocationSystemSheetModifier.middleDetent
                    } else if detent == MapLocationSystemSheetModifier.middleDetent {
                        detent = .large
                    } else {
                        detent = MapLocationSystemSheetModifier.collapsedDetent
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).lineLimit(1)
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isLoading {
                        ProgressView()
                    }
                }
                .frame(height: 80)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            if !isCollapsed {
                content()
            }
        }
        .tint(controlColor)
        .foregroundStyle(controlColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    @ViewBuilder
    private var locationCover: some View {
        Group {
            if let storyCover {
                MapStoryPin(story: storyCover, colorScheme: colorScheme)
            } else if let locationMoment {
                MapMomentPin(moment: locationMoment, colorScheme: colorScheme, count: 1)
            } else {
                Circle().fill(controlColor.opacity(0.12))
                    .overlay(Image("AttachmentMapIcon").resizable().scaledToFit().frame(width: 23, height: 23).foregroundStyle(controlColor))
            }
        }
        .frame(width: 54, height: 54)
    }

}
