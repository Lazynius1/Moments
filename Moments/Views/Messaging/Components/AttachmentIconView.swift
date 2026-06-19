import SwiftUI
import UIKit

enum AttachmentIcon: String {
    case camera = "AttachmentCameraIcon"
    case photos = "AttachmentPhotosIcon"
    case gif = "AttachmentGifIcon"
    case location = "AttachmentLocationIcon"
    case liveLocation = "AttachmentLiveLocationIcon"
    case voice = "AttachmentVoiceIcon"
    case ephemeral = "AttachmentEphemeralIcon"
    case bookmark = "AttachmentBookmarkIcon"
    case tagged = "AttachmentTaggedIcon"
    case comments = "AttachmentCommentsIcon"
    case share = "AttachmentShareIcon"
    case hiddenLayer = "AttachmentHiddenLayerIcon"
}

/// Tamaños calibrados para iconos PNG custom vs SF Symbols equivalentes.
/// Ajusta aquí si al probar se ven grandes/pequeños respecto al sistema.
enum AttachmentIconMetrics {
    /// Menú + adjuntos (chat/Nova). SF Symbol ref: 18pt
    static let attachmentMenu: CGFloat = 22

    /// Fila sheet de ubicación. SF Symbol ref: 20pt semibold
    static let locationSheetRow: CGFloat = 23

    /// Barra inferior burbuja de ubicación. SF Symbol ref: 14pt
    static let locationBubbleInfo: CGFloat = 18

    /// Tarjeta inferior detalle fullscreen. SF Symbol ref: 18pt semibold
    static let locationDetailCard: CGFloat = 23

    /// WhatsNew feature row. SF Symbol ref: 17pt semibold
    static let whatsNew: CGFloat = 22

    /// Píldora catálogo stickers. SF Symbol ref: 16pt bold
    static let stickerCatalogPill: CGFloat = 20

    /// Cabecera de sección en picker de ubicación sticker. SF Symbol ref: 14pt
    static let stickerSectionHeader: CGFloat = 15

    /// Sticker de ubicación en canvas de story. SF Symbol ref: 16pt bold
    static let storyLocationSticker: CGFloat = 20

    /// Chip/botón cámara en creator. SF Symbol ref: 14pt
    static let creatorCameraChip: CGFloat = 15

    /// Acción reply en story viewer. SF Symbol ref: 22pt
    static let storyReplyAction: CGFloat = 25

    /// Prompt permiso mediano (Nova). SF Symbol ref: 32pt
    static let permissionPromptMedium: CGFloat = 36

    /// Prompt permiso grande (creator). SF Symbol ref: 60pt
    static let permissionPromptLarge: CGFloat = 54

    /// Fila de solicitud de mensaje. SF Symbol ref: 14pt
    static let messageRequestRow: CGFloat = 15

    /// Botón inline “usar ubicación actual”. SF Symbol ref: 14pt
    static let locationPickerInline: CGFloat = 15

    /// Botón polaroid en sticker sheet. SF Symbol ref: 18pt
    static let stickerPolaroidButton: CGFloat = 19

    /// Proporción del glifo dentro del accent pill (CoreGraphics).
    static let stickerAccentPillFill: CGFloat = 0.50

    /// Proporción del glifo en placeholder de selfie (CoreGraphics).
    static let selfiePlaceholderFill: CGFloat = 0.40

    // MARK: - Social icons (tamaño óptico calibrado vs SF adyacente; ver AudienceIconMetrics / EchoesIconMetrics)

    /// Rail lateral. PNG comments/share ~91–96% → 24–26pt en círculo 44
    static let rail: CGFloat = 24
    static let railBookmark: CGFloat = 26

    /// Píldora tabs perfil. SF `square.grid.2x2` 12pt; PNG ~96% canvas → 16pt frame
    static let profilePillTab: CGFloat = 16
    static let profilePillTabBookmark: CGFloat = 16

    /// Estado vacío perfil (círculo 54). SF 22pt → PNG ~28pt
    static let profileEmptyState: CGFloat = 28

    /// Barra acciones momento. SF `message` 18pt → PNG ~22pt
    static let momentActionBar: CGFloat = 22

    /// Fila ajustes (slot 28). SF 19pt; PNG bookmark ~91% alto → 21pt
    static let settingsRow: CGFloat = 21

    /// Chip tagged compacto. SF ~18pt → PNG ~22pt
    static let overlayTaggedCompact: CGFloat = 22

    /// Botón glass tagged feed/detail. PNG ~96% → 24pt
    static let overlayTaggedGlass: CGFloat = 24

    /// Header comentarios inline. SF 18pt → PNG ~22pt
    static let inlineCommentsHeader: CGFloat = 22

    /// Chips acción comment/save. SF 18pt → PNG ~22pt
    static let actionChip: CGFloat = 22

    /// Reels sidebar. SF 24pt → PNG ~30pt
    static let reelsSidebar: CGFloat = 30

    /// Creator caption toggles/filas. SF 20pt → PNG ~24pt
    static let creatorMetaRow: CGFloat = 24

    /// Share sheet fila. SF 20pt → PNG ~24pt
    static let shareSheetRow: CGFloat = 24

    /// Botones share inline. SF 16pt → PNG ~19pt
    static let shareInline: CGFloat = 19

    /// Nova historial share mini. SF 12pt → PNG ~14pt
    static let novaShareInline: CGFloat = 14

    /// Cámara efímero. SF 12pt → PNG ~14pt
    static let cameraEphemeral: CGFloat = 14

    /// Badge preview efímero. SF ~12pt → PNG ~14pt
    static let cameraEphemeralBadge: CGFloat = 14

    /// Badge guardado miniatura grid. SF ~10pt → PNG ~12pt
    static let gridSavedBadge: CGFloat = 12

    /// Chip contador tags. SF ~12pt → PNG ~14pt
    static let tagCountChip: CGFloat = 14

    /// Banner in-app. SF 16pt → PNG ~20pt
    static let inAppBanner: CGFloat = 20

    /// Actividad categoría (slot 36). PNG tagged ~96% → 26pt (eco Echoes 28)
    static let activityCategoryRow: CGFloat = 26

    /// Actividad empty state. SF 30pt light → PNG ~38pt
    static let activityEmptyState: CGFloat = 38

    /// Estado vacío comentarios (círculo 54–60). SF ~24pt → PNG ~30pt
    static let commentsEmptyState: CGFloat = 30

    /// Estado vacío hero. SF ~48pt → PNG ~56pt
    static let emptyStateHero: CGFloat = 56

    /// Chat input mic. SF 20pt → PNG ~24pt
    static let chatVoiceInput: CGFloat = 24

    /// Story reply efímero. SF 22pt → PNG ~26pt
    static let storyEphemeral: CGFloat = 26

    /// View-once burbuja grande. SF 26pt → PNG ~30pt
    static let viewOnceBubble: CGFloat = 30

    /// View-once badge pequeño. SF 18pt → PNG ~21pt
    static let viewOnceBadge: CGFloat = 21

    /// Burbuja chat efímero placeholder. SF 40pt → PNG ~46pt
    static let chatEphemeralPlaceholder: CGFloat = 46

    /// Badge reacción miniatura actividad. SF 14pt → PNG ~16pt
    static let activityReactionBadge: CGFloat = 16

    /// Editor sticker voz. SF 24pt → PNG ~28pt
    static let voiceEditor: CGFloat = 28

    /// Grabación voz activa. SF 28pt → PNG ~32pt
    static let voiceRecording: CGFloat = 32

    /// Prompt voz sticker vacío. SF 30pt → PNG ~34pt
    static let voiceStickerPrompt: CGFloat = 34
}

struct AttachmentIconView: View {
    let icon: AttachmentIcon
    let size: CGFloat
    var tintColor: Color = .primary

    init(icon: AttachmentIcon, size: CGFloat, tintColor: Color = .primary) {
        self.icon = icon
        self.size = size
        self.tintColor = tintColor
    }

    init(icon: AttachmentIcon, preset: AttachmentIconPreset, tintColor: Color = .primary) {
        self.icon = icon
        self.size = preset.resolvedSize(for: icon)
        self.tintColor = tintColor
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(tintColor)
            .accessibilityHidden(true)
    }
}

enum AttachmentIconPreset {
    case attachmentMenu
    case locationSheetRow
    case locationBubbleInfo
    case locationDetailCard
    case stickerCatalogPill
    case stickerSectionHeader
    case storyLocationSticker
    case creatorCameraChip
    case storyReplyAction
    case permissionPromptMedium
    case permissionPromptLarge
    case messageRequestRow
    case locationPickerInline
    case stickerPolaroidButton
    case rail
    case profilePillTab
    case profileEmptyState
    case momentActionBar
    case settingsRow
    case overlayTaggedCompact
    case overlayTaggedGlass
    case inlineCommentsHeader
    case actionChip
    case reelsSidebar
    case creatorMetaRow
    case shareSheetRow
    case shareInline
    case novaShareInline
    case cameraEphemeral
    case cameraEphemeralBadge
    case gridSavedBadge
    case tagCountChip
    case inAppBanner
    case activityCategoryRow
    case activityEmptyState
    case commentsEmptyState
    case emptyStateHero
    case chatVoiceInput
    case storyEphemeral
    case viewOnceBubble
    case viewOnceBadge
    case chatEphemeralPlaceholder
    case activityReactionBadge
    case voiceEditor
    case voiceRecording
    case voiceStickerPrompt
    case whatsNew

    var size: CGFloat {
        switch self {
        case .attachmentMenu: AttachmentIconMetrics.attachmentMenu
        case .locationSheetRow: AttachmentIconMetrics.locationSheetRow
        case .locationBubbleInfo: AttachmentIconMetrics.locationBubbleInfo
        case .locationDetailCard: AttachmentIconMetrics.locationDetailCard
        case .stickerCatalogPill: AttachmentIconMetrics.stickerCatalogPill
        case .stickerSectionHeader: AttachmentIconMetrics.stickerSectionHeader
        case .storyLocationSticker: AttachmentIconMetrics.storyLocationSticker
        case .creatorCameraChip: AttachmentIconMetrics.creatorCameraChip
        case .storyReplyAction: AttachmentIconMetrics.storyReplyAction
        case .permissionPromptMedium: AttachmentIconMetrics.permissionPromptMedium
        case .permissionPromptLarge: AttachmentIconMetrics.permissionPromptLarge
        case .messageRequestRow: AttachmentIconMetrics.messageRequestRow
        case .locationPickerInline: AttachmentIconMetrics.locationPickerInline
        case .stickerPolaroidButton: AttachmentIconMetrics.stickerPolaroidButton
        case .rail: AttachmentIconMetrics.rail
        case .profilePillTab: AttachmentIconMetrics.profilePillTab
        case .profileEmptyState: AttachmentIconMetrics.profileEmptyState
        case .momentActionBar: AttachmentIconMetrics.momentActionBar
        case .settingsRow: AttachmentIconMetrics.settingsRow
        case .overlayTaggedCompact: AttachmentIconMetrics.overlayTaggedCompact
        case .overlayTaggedGlass: AttachmentIconMetrics.overlayTaggedGlass
        case .inlineCommentsHeader: AttachmentIconMetrics.inlineCommentsHeader
        case .actionChip: AttachmentIconMetrics.actionChip
        case .reelsSidebar: AttachmentIconMetrics.reelsSidebar
        case .creatorMetaRow: AttachmentIconMetrics.creatorMetaRow
        case .shareSheetRow: AttachmentIconMetrics.shareSheetRow
        case .shareInline: AttachmentIconMetrics.shareInline
        case .novaShareInline: AttachmentIconMetrics.novaShareInline
        case .cameraEphemeral: AttachmentIconMetrics.cameraEphemeral
        case .cameraEphemeralBadge: AttachmentIconMetrics.cameraEphemeralBadge
        case .gridSavedBadge: AttachmentIconMetrics.gridSavedBadge
        case .tagCountChip: AttachmentIconMetrics.tagCountChip
        case .inAppBanner: AttachmentIconMetrics.inAppBanner
        case .activityCategoryRow: AttachmentIconMetrics.activityCategoryRow
        case .activityEmptyState: AttachmentIconMetrics.activityEmptyState
        case .commentsEmptyState: AttachmentIconMetrics.commentsEmptyState
        case .emptyStateHero: AttachmentIconMetrics.emptyStateHero
        case .chatVoiceInput: AttachmentIconMetrics.chatVoiceInput
        case .storyEphemeral: AttachmentIconMetrics.storyEphemeral
        case .viewOnceBubble: AttachmentIconMetrics.viewOnceBubble
        case .viewOnceBadge: AttachmentIconMetrics.viewOnceBadge
        case .chatEphemeralPlaceholder: AttachmentIconMetrics.chatEphemeralPlaceholder
        case .activityReactionBadge: AttachmentIconMetrics.activityReactionBadge
        case .voiceEditor: AttachmentIconMetrics.voiceEditor
        case .voiceRecording: AttachmentIconMetrics.voiceRecording
        case .voiceStickerPrompt: AttachmentIconMetrics.voiceStickerPrompt
        case .whatsNew: AttachmentIconMetrics.whatsNew
        }
    }

    /// Tamaño óptico según forma del glifo (bookmark/mic más estrechos que comments/share).
    func resolvedSize(for icon: AttachmentIcon) -> CGFloat {
        switch self {
        case .rail:
            return icon == .bookmark ? AttachmentIconMetrics.railBookmark : AttachmentIconMetrics.rail
        case .profilePillTab:
            return icon == .bookmark ? AttachmentIconMetrics.profilePillTabBookmark : AttachmentIconMetrics.profilePillTab
        case .actionChip, .momentActionBar:
            return icon == .bookmark ? AttachmentIconMetrics.actionChip + 2 : AttachmentIconMetrics.actionChip
        default:
            let base = size
            switch icon {
            case .bookmark, .voice, .tagged:
                return base * 1.04
            default:
                return base
            }
        }
    }
}

extension AttachmentIcon {
    func uiImage(size: CGFloat, tint: UIColor) -> UIImage? {
        guard let image = UIImage(named: rawValue)?.withRenderingMode(.alwaysTemplate) else {
            return nil
        }

        let target = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            tint.setFill()
            image.draw(in: CGRect(origin: .zero, size: target))
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.fill(CGRect(origin: .zero, size: target))
        }
    }
}
