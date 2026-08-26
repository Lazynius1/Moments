import SwiftUI
import UIKit

enum ChatListUpdateKind: Equatable {
    case initial
    case prependHistory
    case appendMessages
    case reconfigureRows
    case replaceAll
    case jump
}

enum ChatTimelineUpdateReason: Equatable {
    case history
    case incoming
    case outgoing
    case search
    case highlight
    case unread
    case layout
}

enum ChatListScrollCommand: Equatable {
    case none
    case bottom(animated: Bool)
    case firstUnread(messageId: String, animated: Bool)
    case highlight(messageId: String, animated: Bool)
}

struct ChatViewportAnchor: Equatable {
    let rowId: String
    let offsetFromContentTop: CGFloat
}

struct ChatListUpdateTransaction {
    let kind: ChatListUpdateKind
    let rows: [ChatRenderRow]
    let changedRowIds: [String]
    let anchorRowId: String?
    let scrollCommand: ChatListScrollCommand?
    let reason: ChatTimelineUpdateReason

    init(
        kind: ChatListUpdateKind,
        rows: [ChatRenderRow],
        changedRowIds: [String] = [],
        anchorRowId: String? = nil,
        scrollCommand: ChatListScrollCommand? = nil,
        reason: ChatTimelineUpdateReason
    ) {
        self.kind = kind
        self.rows = rows
        self.changedRowIds = changedRowIds
        self.anchorRowId = anchorRowId
        self.scrollCommand = scrollCommand
        self.reason = reason
    }
}

enum ChatListInitialScrollPolicy: Equatable {
    case automaticBottom
    case row(id: String, position: UICollectionView.ScrollPosition)
    case deferred
}

/// Intenciones de scroll serializadas.
enum ChatListScrollIntent: Equatable {
    case scrollToBottom(animated: Bool)
    case scrollToRow(id: String, position: UICollectionView.ScrollPosition, animated: Bool)
}

final class ChatMessageListController: ObservableObject {
    fileprivate weak var viewController: ChatMessageListViewController?
    let timestampRevealState = ChatTimestampRevealState()

    var initialScrollPolicy: ChatListInitialScrollPolicy = .automaticBottom
    /// Alturas medidas por fila: persiste entre recreaciones del view controller (pushes, sheets).
    let rowHeightCache = ChatRowHeightCache()

    func enqueue(_ intent: ChatListScrollIntent) {
        viewController?.enqueue(intent)
    }

    func scrollToBottom(animated: Bool) {
        enqueue(.scrollToBottom(animated: animated))
    }

    func forceScrollToBottom(animated: Bool) {
        viewController?.forceScrollToBottom(animated: animated, allowDuringNavigation: false)
    }

    func forceScrollToBottomIgnoringNavigation(animated: Bool) {
        viewController?.forceScrollToBottom(animated: animated, allowDuringNavigation: true)
    }

    func scrollToRow(id: String, at position: UICollectionView.ScrollPosition, animated: Bool) {
        enqueue(.scrollToRow(id: id, position: position, animated: animated))
    }

    func navigateToRow(id: String, at position: UICollectionView.ScrollPosition, animated: Bool) {
        viewController?.navigateToRow(id: id, at: position, animated: animated)
    }

    func perform(_ command: ChatListScrollCommand) {
        viewController?.perform(command)
    }

    func clearNavigationTarget() {
        viewController?.scrollNavigationTargetRowId = nil
    }

    func reconfigureVisible(exceptRowId: String? = nil) {
        viewController?.reconfigureVisible(exceptRowId: exceptRowId)
    }

    func reconfigure(messageIds: [String]) {
        viewController?.reconfigure(messageIds: messageIds)
    }

    var isAtBottom: Bool {
        viewController?.currentIsAtBottom ?? true
    }

    var contentExceedsViewport: Bool {
        viewController?.contentExceedsViewport ?? false
    }

    var contentOffsetY: CGFloat {
        viewController?.contentOffsetY ?? 0
    }

    var topVisibleRowId: String? {
        viewController?.topVisibleRowId
    }

    var bottomVisibleRowId: String? {
        viewController?.bottomVisibleRowId
    }

    var firstVisibleRowIndex: Int? {
        viewController?.firstVisibleRowIndex
    }

    var distanceFromBottom: CGFloat {
        viewController?.distanceFromBottom ?? 0
    }

    var isStrictlyAtBottom: Bool {
        viewController?.isStrictlyAtBottom ?? true
    }

    func resetVanishPullState(animated: Bool) {
        viewController?.resetVanishPullState(animated: animated)
    }

    /// Frame de una fila en coordenadas de ventana, vía UIKit directo. `GeometryReader(in: .global)`
    /// no resuelve de forma fiable dentro de una celda `UIHostingConfiguration` (cada celda hostea
    /// su propio árbol SwiftUI) — por eso el menú contextual del long-press se quedaba sin abrir.
    func frameInWindow(forRowId rowId: String) -> CGRect? {
        viewController?.frameInWindow(forRowId: rowId)
    }

    func resolvedRowId(forMessageId messageId: String) -> String? {
        viewController?.resolvedRowId(forMessageId: messageId)
    }

    func containsRow(id: String) -> Bool {
        viewController?.containsRow(id: id) ?? false
    }

    /// Mientras está definido, `apply(rows:)` no fuerza scroll al fondo aunque el usuario estuviera abajo.
    var scrollNavigationTargetRowId: String? {
        get { viewController?.scrollNavigationTargetRowId }
        set { viewController?.scrollNavigationTargetRowId = newValue }
    }
}

struct ChatMessageListView: UIViewControllerRepresentable {
    let transaction: ChatListUpdateTransaction
    let controller: ChatMessageListController
    @Binding var isAtBottom: Bool
    var onReachedTop: () -> Void
    var composerBottomInset: CGFloat = 0
    var isVanishGestureEnabled: Bool = true
    var isVanishModeActive: Bool = false
    var onVanishPullReleased: (VanishPullResult) -> Void = { _ in }
    var onVanishDraggingChanged: (Bool) -> Void = { _ in }
    var onContentExtentChanged: (Bool) -> Void = { _ in }
    var onPrependFinished: () -> Void = {}
    var onPrefetchRows: ([ChatRenderRow]) -> Void = { _ in }
    var rowContent: (ChatRenderRow) -> AnyView

    func makeUIViewController(context: Context) -> ChatMessageListViewController {
        let viewController = ChatMessageListViewController()
        viewController.loadViewIfNeeded()
        configure(viewController)
        viewController.apply(transaction: transaction, animated: false)
        return viewController
    }

    func updateUIViewController(_ viewController: ChatMessageListViewController, context: Context) {
        configure(viewController)
        viewController.apply(transaction: transaction, animated: true)
    }

    private func configure(_ viewController: ChatMessageListViewController) {
        viewController.rowContent = rowContent
        viewController.onReachedTop = onReachedTop
        viewController.composerBottomInset = composerBottomInset
        viewController.isVanishGestureEnabled = isVanishGestureEnabled
        viewController.isVanishModeActive = isVanishModeActive
        viewController.externalIsAtBottom = isAtBottom
        viewController.onVanishPullReleased = onVanishPullReleased
        viewController.onVanishDraggingChanged = onVanishDraggingChanged
        viewController.onContentExtentChanged = onContentExtentChanged
        viewController.onPrependFinished = onPrependFinished
        viewController.onPrefetchRows = onPrefetchRows
        viewController.onIsAtBottomChanged = { value in
            DispatchQueue.main.async {
                if isAtBottom != value { isAtBottom = value }
            }
        }
        viewController.initialScrollPolicy = controller.initialScrollPolicy
        viewController.rowHeightCache = controller.rowHeightCache
        controller.viewController = viewController
    }
}

/// Compositional layout con supresión opcional del `contentOffsetAdjustment` que UIKit aplica
/// al procesar tamaños preferidos de celdas self-sizing. Ese ajuste re-ancla el scroll a las
/// filas que estaban visibles (el fondo) de forma silenciosa —sin `scrollViewDidScroll`— y
/// deshace cualquier salto programático a un mensaje lejano con celdas aún sin medir.
final class ChatNavigationAwareCompositionalLayout: UICollectionViewCompositionalLayout {
    var suppressesPreferredOffsetAdjustment = false
    /// Notifica cada altura real medida por self-sizing para alimentar la caché de alturas.
    var onPreferredHeightMeasured: ((IndexPath, CGFloat) -> Void)?

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes
        )
        onPreferredHeightMeasured?(preferredAttributes.indexPath, preferredAttributes.frame.height)
        if suppressesPreferredOffsetAdjustment {
            context.contentOffsetAdjustment = .zero
        }
        return context
    }
}

/// Métricas compartidas entre el section provider y los cálculos de posición por caché.
private enum ChatListLayoutMetrics {
    static let estimatedRowHeight: CGFloat = 60
    static let interGroupSpacing: CGFloat = 2
    static let sectionTopInset: CGFloat = 10
    static let sectionBottomInset: CGFloat = 4
}

/// Caché de alturas reales por fila: con alturas estimadas, cada
/// celda nunca medida hace bailar el contentSize y los scrolls programáticos aterrizan lejos.
/// Con las alturas reales cacheadas, los saltos aciertan a la primera. Vive en el controller
/// (sobrevive a recreaciones del view controller) y se invalida si cambia el ancho.
final class ChatRowHeightCache {
    private var measuredHeights: [String: CGFloat] = [:]
    private var estimatedHeights: [String: CGFloat] = [:]
    private var referenceWidth: CGFloat = 0

    @discardableResult
    func syncWidth(_ width: CGFloat) -> Bool {
        guard width > 0, abs(width - referenceWidth) > 0.5 else { return false }
        referenceWidth = width
        measuredHeights.removeAll()
        estimatedHeights.removeAll()
        return true
    }

    func height(for rowId: String) -> CGFloat? {
        measuredHeights[rowId] ?? estimatedHeights[rowId]
    }

    func store(_ height: CGFloat, for rowId: String) {
        guard height > 0 else { return }
        measuredHeights[rowId] = height
    }

    func invalidate(_ rowIds: [String]) {
        for rowId in rowIds {
            measuredHeights.removeValue(forKey: rowId)
        }
    }

    func seedEstimates(for rows: [ChatRenderRow], containerWidth: CGFloat) {
        guard containerWidth > 0 else { return }
        var updated: [String: CGFloat] = [:]
        updated.reserveCapacity(rows.count)
        for row in rows {
            updated[row.id] = ChatRowHeightEstimator.estimatedHeight(for: row, containerWidth: containerWidth)
        }
        estimatedHeights = updated
    }
}

final class ChatMessageListViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
    var rowContent: ((ChatRenderRow) -> AnyView)?
    var onReachedTop: (() -> Void)?
    var onIsAtBottomChanged: ((Bool) -> Void)?
    var onVanishPullReleased: ((VanishPullResult) -> Void)?
    var onVanishDraggingChanged: ((Bool) -> Void)?
    var onContentExtentChanged: ((Bool) -> Void)?
    var onPrependFinished: (() -> Void)?
    var onPrefetchRows: (([ChatRenderRow]) -> Void)?
    var initialScrollPolicy: ChatListInitialScrollPolicy = .automaticBottom
    var composerBottomInset: CGFloat = 0 {
        didSet {
            guard composerBottomInset != oldValue else { return }
            vanishPullOverlay?.composerBottomInset = composerBottomInset
            if currentVanishLift > 0 {
                vanishPullOverlay?.setRevealLayout(
                    composerBottomInset: composerBottomInset,
                    conversationLift: currentVanishLift
                )
            }
            applyComposerBottomContentInset(preservingBottomPin: true)
        }
    }
    var isVanishGestureEnabled = true {
        didSet {
            if !isVanishGestureEnabled {
                resetVanishPullState(animated: false)
            }
        }
    }
    var isVanishModeActive = false
    var externalIsAtBottom = true
    var scrollNavigationTargetRowId: String? {
        didSet {
            updatePreferredOffsetAdjustmentSuppression()
        }
    }

    private(set) var currentIsAtBottom = true
    private(set) var isStrictlyAtBottom = true
    private var lastReportedContentExceedsViewport: Bool?

    private var navigationAwareLayout: ChatNavigationAwareCompositionalLayout?
    var rowHeightCache: ChatRowHeightCache?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var rowsById: [String: ChatRenderRow] = [:]
    private var orderedItemIds: [String] = []
    private var hasLoadedInitial = false
    private var pendingScrollToId: String?
    private var pendingScrollPosition: UICollectionView.ScrollPosition = .centeredVertically
    private var pendingScrollAnimated = false
    private var reconfigureScheduled = false
    private var messageIdToRowId: [String: String] = [:]
    private var pendingReconfigureRowIds: Set<String> = []
    private var reconfigureAllVisiblePending = false
    private var reconfigureExcludedRowId: String?
    private var needsDeferredInitialScroll = false
    private var lastAppliedRows: [ChatRenderRow] = []
    private var isRestoringPrependAnchor = false
    private var suppressHistoryLoadUntilNextUserScroll = false
    private var historyLoadWorkItem: DispatchWorkItem?
    private var historyLoadArmed = true
    private var scrollIntentQueue: [ChatListScrollIntent] = []
    private var isProcessingScrollIntent = false
    private var awaitsScrollAnimationEnd = false

    private let strictAtBottomThreshold: CGFloat = 8
    private let loadOlderItemThreshold = 10
    private let historyPrefetchItemThreshold = 40
    private let historyLoadDebounceNs: UInt64 = 50_000_000
    /// Dedos mínimos antes de armar vanish por pan (evita activación accidental al hacer scroll).
    private let vanishEngageThreshold: CGFloat = 44
    private let vanishToggleCooldown: TimeInterval = 2.0
    private var lastVanishToggleAt: Date?

    private var vanishPullOverlay: ChatVanishPullOverlayView!
    private var vanishPanGesture: UIPanGestureRecognizer!
    private var keyboardDismissTapGesture: UITapGestureRecognizer!
    private var isVanishPanActive = false
    private var isVanishOverscrollActive = false
    private var vanishPanPull: CGFloat = 0
    private var vanishDidCrossThreshold = false
    private var vanishLastHapticStep = -1
    private var isClampingBottomScroll = false
    private var isEnforcingNavTarget = false
    private var currentVanishLift: CGFloat = 0

    var contentExceedsViewport: Bool {
        guard collectionView != nil else { return false }
        return collectionView.contentSize.height > collectionView.bounds.height + 1
    }

    var contentOffsetY: CGFloat {
        collectionView?.contentOffset.y ?? 0
    }

    var distanceFromBottom: CGFloat {
        guard let collectionView else { return 0 }
        let maxY = collectionView.contentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
        return max(0, maxY - collectionView.contentOffset.y)
    }

    var topVisibleRowId: String? {
        rowId(atVisibleIndex: firstVisibleRowIndex)
    }

    var bottomVisibleRowId: String? {
        rowId(atVisibleIndex: lastVisibleRowIndex)
    }

    func frameInWindow(forRowId rowId: String) -> CGRect? {
        guard let collectionView,
              let index = orderedItemIds.firstIndex(of: rowId),
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: index))
        else { return nil }
        return collectionView.convert(attributes.frame, to: nil)
    }

    var firstVisibleRowIndex: Int? {
        guard let collectionView else { return nil }
        let indices = collectionView.indexPathsForVisibleItems.map(\.section)
        return indices.min()
    }

    private var lastVisibleRowIndex: Int? {
        guard let collectionView else { return nil }
        let indices = collectionView.indexPathsForVisibleItems.map(\.section)
        return indices.max()
    }

    private func rowId(atVisibleIndex index: Int?) -> String? {
        guard let index, let dataSource, index >= 0, index < orderedItemIds.count else { return nil }
        return dataSource.itemIdentifier(for: IndexPath(item: 0, section: index))
    }

    private func changedRowIds(
        oldRowsById: [String: ChatRenderRow],
        newRowsById: [String: ChatRenderRow],
        orderedIds: [String]
    ) -> [String] {
        orderedIds.filter { id in
            guard let oldRow = oldRowsById[id], let newRow = newRowsById[id] else { return false }
            return oldRow.visualSignature != newRow.visualSignature
        }
    }

    private func isLastRowVisible() -> Bool {
        guard let lastIndex = orderedItemIds.indices.last,
              let lastVisibleRowIndex else { return false }
        return lastVisibleRowIndex >= lastIndex
    }

    private func recomputeBottomPinnedState() {
        guard let collectionView else { return }
        let maxY = collectionView.contentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
        let offsetNearBottom = collectionView.contentOffset.y >= maxY - strictAtBottomThreshold
        let lastRowVisible = orderedItemIds.isEmpty || isLastRowVisible()
        var strict = offsetNearBottom && lastRowVisible

        // Solo un gesto real del usuario puede "despegar" del fondo. Si el cambio es programático
        // (p.ej. el inset inferior se reajusta cuando el composer termina de medirse, después de
        // ya haber forzado el scroll al fondo) y estábamos pegados abajo, la lista sigue al fondo
        // en vez de marcar "no estás abajo" — así no aparece la flecha sin que nadie haya scrolleado.
        // Excepción: una navegación a mensaje (nav target) también debe poder despegar, si no este
        // clamp revierte en silencio cualquier salto a un destacado/búsqueda.
        let isUserDriven = collectionView.isDragging || collectionView.isTracking || collectionView.isDecelerating
        if !strict, isStrictlyAtBottom, !isUserDriven, scrollNavigationTargetRowId == nil, !orderedItemIds.isEmpty {
            let lastIndex = orderedItemIds.count - 1
            isClampingBottomScroll = true
            collectionView.scrollToItem(at: IndexPath(item: 0, section: lastIndex), at: .bottom, animated: false)
            isClampingBottomScroll = false
            strict = true
        }

        if strict != isStrictlyAtBottom {
            isStrictlyAtBottom = strict
        }
        currentIsAtBottom = strict
        // Comparar contra el valor externo real permite resincronizar SwiftUI sin publicar
        // un bloque al main queue en cada frame de scroll.
        if externalIsAtBottom != strict {
            externalIsAtBottom = strict
            onIsAtBottomChanged?(strict)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateCanvasBackgroundColor()
        configureCollectionView()
        configureDataSource()
        configureVanishGesture()
        configureKeyboardDismissGesture()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateCanvasBackgroundColor()
        }
        guard isVanishPanActive, currentVanishLift > 0 else { return }
        let progress = ChatVanishSwipeMetrics.progress(lift: currentVanishLift)
        vanishPullOverlay.update(
            lift: currentVanishLift,
            progress: progress,
            isActive: isVanishModeActive,
            isDragging: true,
            colorScheme: traitCollection.userInterfaceStyle
        )
    }

    private func updateCanvasBackgroundColor() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        view.backgroundColor = UIColor(hex: isDark ? "0B1215" : "FAF9F6")
    }

    private func configureVanishGesture() {
        vanishPullOverlay = ChatVanishPullOverlayView()
        vanishPullOverlay.hide()
        vanishPullOverlay.install(in: view)
        vanishPullOverlay.composerBottomInset = composerBottomInset

        vanishPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleVanishPan(_:)))
        vanishPanGesture.delegate = self
        // Sin esto, cualquier micro-temblor del dedo al mantener pulsado un mensaje (long-press)
        // arma este pan gesture y cancela el toque que SwiftUI rastreaba para el menú contextual,
        // matando el long-press antes de completarse. Ambos gestos deben poder coexistir.
        vanishPanGesture.cancelsTouchesInView = false
        // `UICollectionView` ya entrega el overscroll inferior mediante su pan nativo.
        // Un segundo pan simultáneo duplicaba la misma interacción y ensuciaba el scroll.
        // Se conserva el handler como fallback documental, pero no se instala otro recognizer.
    }

    // keyboardDismissMode = .interactive solo funciona arrastrando contenido con
    // overflow; en conversaciones cortas no hay nada que arrastrar y el teclado
    // quedaba atrapado hasta salir del chat. Un tap simple en la lista lo cierra.
    private func configureKeyboardDismissGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleListTapToDismissKeyboard))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tap)
        keyboardDismissTapGesture = tap
    }

    @objc private func handleListTapToDismissKeyboard() {
        view.window?.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if rowHeightCache?.syncWidth(collectionView.bounds.width) == true {
            rowHeightCache?.seedEstimates(for: lastAppliedRows, containerWidth: collectionView.bounds.width)
        }
        if #available(iOS 26.0, *) {
            collectionView.bottomEdgeEffect.isHidden = true
            collectionView.topEdgeEffect.style = .soft
        }
        applyComposerBottomContentInset(preservingBottomPin: false)
        reportContentExtentIfChanged()
        enforceNavigationTargetIfNeeded(context: "layout")
        guard needsDeferredInitialScroll,
              collectionView.bounds.height > 0,
              !orderedItemIds.isEmpty else { return }
        needsDeferredInitialScroll = false
        applyInitialScrollPolicy(animated: false)
    }

    /// El compositional layout con alturas estimadas restaura el offset en silencio
    /// (contentOffsetAdjustment al medir celdas) anclándose a las filas del fondo, deshaciendo
    /// cualquier salto a un mensaje lejano. Mientras haya nav target, se re-impone el destino en
    /// cada pasada de layout/scroll no iniciada por el usuario; el drag del usuario lo libera.
    private func enforceNavigationTargetIfNeeded(context: String) {
        guard let navId = scrollNavigationTargetRowId, !isEnforcingNavTarget else { return }
        guard !collectionView.isDragging, !collectionView.isTracking, !collectionView.isDecelerating else { return }
        let resolved = resolvedRowId(forMessageId: navId)
        guard let index = orderedItemIds.firstIndex(of: resolved) else { return }
        let indexPath = IndexPath(item: 0, section: index)
        guard let attrs = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else { return }
        let targetY = clampedOffsetY(toReveal: attrs.frame, at: .centeredVertically)
        guard abs(collectionView.contentOffset.y - targetY) > 40 else { return }
        isEnforcingNavTarget = true
        collectionView.contentOffset.y = targetY
        isEnforcingNavTarget = false
    }

    private func configureCollectionView() {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = ChatListLayoutMetrics.interGroupSpacing

        let layout = ChatNavigationAwareCompositionalLayout(sectionProvider: { [weak self] sectionIndex, _ in
            let bestGuessHeight: CGFloat
            if let self, sectionIndex < self.orderedItemIds.count {
                bestGuessHeight = self.rowHeightCache?.height(for: self.orderedItemIds[sectionIndex])
                    ?? ChatListLayoutMetrics.estimatedRowHeight
            } else {
                bestGuessHeight = ChatListLayoutMetrics.estimatedRowHeight
            }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(bestGuessHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)

            let isFirst = sectionIndex == 0
            let isLast = self.map { sectionIndex == $0.orderedItemIds.count - 1 } ?? false
            section.contentInsets = NSDirectionalEdgeInsets(
                top: isFirst ? ChatListLayoutMetrics.sectionTopInset : 0,
                leading: 0,
                bottom: isLast ? ChatListLayoutMetrics.sectionBottomInset : 0,
                trailing: 0
            )
            return section
        }, configuration: configuration)
        navigationAwareLayout = layout
        layout.suppressesPreferredOffsetAdjustment = scrollNavigationTargetRowId != nil || isRestoringPrependAnchor
        layout.onPreferredHeightMeasured = { [weak self] indexPath, height in
            guard let self, indexPath.section < self.orderedItemIds.count else { return }
            self.rowHeightCache?.store(height, for: self.orderedItemIds[indexPath.section])
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.isDirectionalLockEnabled = true
        collectionView.alwaysBounceVertical = true
        collectionView.bounces = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.style = .soft
            collectionView.bottomEdgeEffect.isHidden = true
        }
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, itemId in
            guard let self, let row = self.rowsById[itemId], let rowContent = self.rowContent else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                rowContent(row)
                    .frame(maxWidth: .infinity)
            }
            .margins(.all, 0)
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = .clear
            cell.backgroundConfiguration = background
        }

        dataSource = UICollectionViewDiffableDataSource<String, String>(collectionView: collectionView) { collectionView, indexPath, itemId in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemId)
        }
    }

    func apply(transaction: ChatListUpdateTransaction, animated: Bool) {
        loadViewIfNeeded()
        guard dataSource != nil else { return }

        let rows = transaction.rows
        let oldRowsById = rowsById
        let oldIds = orderedItemIds
        let newRowsById = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIds = rows.map(\.id)
        let isInitial = !hasLoadedInitial
        let wasAtBottom = currentIsAtBottom
        // Capturar el viewport en el instante en que llega la página, no cuando se pidió.
        // El usuario puede haber avanzado muchos puntos durante la consulta.
        let livePrependAnchor = transaction.kind == .prependHistory
            ? captureTopVisibleAnchor()
            : nil
        let detectedChangedRowIds = changedRowIds(
            oldRowsById: oldRowsById,
            newRowsById: newRowsById,
            orderedIds: newIds
        )
        let explicitChangedRowIds = transaction.changedRowIds.filter { newRowsById[$0] != nil }
        let changedRowIds = Array(Set(detectedChangedRowIds).union(explicitChangedRowIds))

        rowsById = newRowsById
        rebuildMessageIdToRowIdIndex(rows)

        guard newIds != oldIds || !hasLoadedInitial || !changedRowIds.isEmpty else { return }
        orderedItemIds = newIds
        rowHeightCache?.invalidate(changedRowIds)
        rowHeightCache?.seedEstimates(for: rows, containerWidth: collectionView.bounds.width)
        lastAppliedRows = rows

        let normalizedKind = normalizedTransactionKind(
            requestedKind: transaction.kind,
            anchorRowId: transaction.anchorRowId,
            oldIds: oldIds,
            newIds: newIds,
            changedRowIds: changedRowIds
        )
        let prependAnchor = normalizedKind == .prependHistory
            ? (livePrependAnchor ?? captureTopVisibleAnchor())
            : nil
        if normalizedKind == .prependHistory {
            isRestoringPrependAnchor = true
            suppressHistoryLoadUntilNextUserScroll = true
        } else {
            isRestoringPrependAnchor = false
        }
        updatePreferredOffsetAdjustmentSuppression()

        if normalizedKind == .reconfigureRows, newIds == oldIds, !changedRowIds.isEmpty {
            let stationaryAnchor = (!wasAtBottom && scrollNavigationTargetRowId == nil)
                ? captureTopVisibleAnchor()
                : nil
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(changedRowIds)
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                self.updateBottomAnchorInset()
                if wasAtBottom, self.scrollNavigationTargetRowId == nil {
                    self.forceScrollToBottom(animated: false)
                } else if let stationaryAnchor {
                    self.restoreViewportAnchor(stationaryAnchor)
                } else {
                    self.recomputeBottomPinnedState()
                }
                self.applyScrollCommandIfNeeded(transaction.scrollCommand)
                self.resolvePendingScrollIfPossible()
            }
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(newIds)
        for id in newIds {
            snapshot.appendItems([id], toSection: id)
        }
        let reconfigurableRowIds = changedRowIds.filter { newRowsById[$0] != nil }
        if !reconfigurableRowIds.isEmpty {
            snapshot.reconfigureItems(reconfigurableRowIds)
        }

        if normalizedKind == .prependHistory {
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                self.updateBottomAnchorInset()
                if let prependAnchor {
                    self.restoreViewportAnchor(prependAnchor)
                }
                self.isRestoringPrependAnchor = false
                self.updatePreferredOffsetAdjustmentSuppression()
                self.recomputeBottomPinnedState()
                self.onPrependFinished?()
            }
            self.applyScrollCommandIfNeeded(transaction.scrollCommand)
            self.resolvePendingScrollIfPossible()
            return
        }

        let stationaryAnchor = (
            normalizedKind != .initial
                && normalizedKind != .jump
                && !wasAtBottom
                && scrollNavigationTargetRowId == nil
        ) ? captureTopVisibleAnchor() : nil

        let shouldAnimateDiff = animated && normalizedKind != .initial && normalizedKind != .prependHistory
        dataSource.apply(snapshot, animatingDifferences: shouldAnimateDiff) { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            self.updateBottomAnchorInset()
            if normalizedKind == .initial {
                self.hasLoadedInitial = true
                self.applyInitialScrollPolicy(animated: false)
            } else if wasAtBottom, self.scrollNavigationTargetRowId == nil {
                if normalizedKind == .appendMessages {
                    self.forceScrollToBottom(animated: animated)
                } else {
                    self.recomputeBottomPinnedState()
                }
            } else if let stationaryAnchor {
                self.restoreViewportAnchor(stationaryAnchor)
            } else {
                self.recomputeBottomPinnedState()
            }
            self.applyScrollCommandIfNeeded(transaction.scrollCommand)
            self.resolvePendingScrollIfPossible()
        }
    }

    private func applyInitialScrollPolicy(animated: Bool) {
        switch initialScrollPolicy {
        case .automaticBottom:
            needsDeferredInitialScroll = true
            if collectionView.bounds.height > 0, !orderedItemIds.isEmpty {
                needsDeferredInitialScroll = false
                forceScrollToBottom(animated: animated)
            }
        case .deferred:
            needsDeferredInitialScroll = false
        case .row(let id, let position):
            needsDeferredInitialScroll = false
            scrollToRow(id: id, at: position, animated: animated)
        }
    }

    func scrollToBottom(animated: Bool) {
        if scrollNavigationTargetRowId != nil {
            return
        }
        guard !orderedItemIds.isEmpty else { return }
        recomputeBottomPinnedState()
        guard !isStrictlyAtBottom else { return }
        let lastIndex = orderedItemIds.count - 1
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: lastIndex),
            at: .bottom,
            animated: animated
        )
    }

    func forceScrollToBottom(animated: Bool, allowDuringNavigation: Bool = false) {
        if !allowDuringNavigation, scrollNavigationTargetRowId != nil {
            return
        }
        resetVanishPullState(animated: false)
        guard !orderedItemIds.isEmpty else { return }

        // Celdas auto-dimensionadas (UIHostingConfiguration): la primera vez que una celda entra
        // en pantalla puede medirse con un ancho/alto provisional antes de que el layout conozca
        // el bounds real, dejando contentSize desactualizado tras un solo scrollToItem. Se repite
        // scroll → invalidateLayout → layout hasta que el contentSize deje de moverse.
        let lastIndex = orderedItemIds.count - 1
        var previousHeight: CGFloat = -1
        for _ in 0..<6 {
            collectionView.layoutIfNeeded()
            let height = collectionView.collectionViewLayout.collectionViewContentSize.height
            let stabilized = abs(height - previousHeight) < 0.5
            previousHeight = height

            collectionView.scrollToItem(
                at: IndexPath(item: 0, section: lastIndex),
                at: .bottom,
                animated: false
            )

            if stabilized { break }
            collectionView.collectionViewLayout.invalidateLayout()
        }

        if animated {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: lastIndex), at: .bottom, animated: true)
        }

        // Tras el scrollToItem no animado, indexPathsForVisibleItems puede seguir reflejando las
        // celdas visibles ANTES del scroll hasta el siguiente layout pass. Sin este layoutIfNeeded,
        // isLastRowVisible() consulta datos obsoletos y recomputeBottomPinnedState falla incluso
        // con el offset ya correcto — la flecha se queda pegada aunque se esté en el fondo.
        collectionView.layoutIfNeeded()
        recomputeBottomPinnedState()
    }

    private func isLikelyHistoryPrepend(oldIds: [String], newIds: [String]) -> Bool {
        guard let anchorId = oldIds.first else { return false }
        guard let newIndex = newIds.firstIndex(of: anchorId) else { return false }
        return newIndex > 0
    }

    private func normalizedTransactionKind(
        requestedKind: ChatListUpdateKind,
        anchorRowId: String?,
        oldIds: [String],
        newIds: [String],
        changedRowIds: [String]
    ) -> ChatListUpdateKind {
        if !hasLoadedInitial || oldIds.isEmpty {
            return .initial
        }

        // El ViewModel sólo emite este tipo para páginas históricas ya validadas.
        // Confiar en la intención evita degradar a replaceAll si la primera cabecera
        // o un álbum cambia de composición justo en el borde de página.
        if requestedKind == .prependHistory, newIds.count >= oldIds.count {
            return .prependHistory
        }

        if requestedKind == .prependHistory,
           let anchorRowId,
           let oldAnchorIndex = oldIds.firstIndex(of: anchorRowId),
           let newAnchorIndex = newIds.firstIndex(of: anchorRowId),
           newAnchorIndex > oldAnchorIndex {
            return .prependHistory
        }

        if newIds == oldIds {
            return changedRowIds.isEmpty ? requestedKind : .reconfigureRows
        }
        if newIds.count > oldIds.count {
            if Array(newIds.suffix(oldIds.count)) == oldIds || isLikelyHistoryPrepend(oldIds: oldIds, newIds: newIds) {
                return .prependHistory
            }
            if Array(newIds.prefix(oldIds.count)) == oldIds {
                return .appendMessages
            }
        }
        return requestedKind == .jump ? .jump : .replaceAll
    }

    private func captureTopVisibleAnchor() -> ChatViewportAnchor? {
        let visibleIndices = collectionView.indexPathsForVisibleItems
            .map(\.section)
            .sorted { lhs, rhs in
                let leftY = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: 0, section: lhs)
                )?.frame.minY ?? .greatestFiniteMagnitude
                let rightY = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: 0, section: rhs)
                )?.frame.minY ?? .greatestFiniteMagnitude
                return leftY < rightY
            }
        let messageIndex = visibleIndices.first { index in
            guard index >= 0, index < orderedItemIds.count,
                  let row = rowsById[orderedItemIds[index]] else { return false }
            if case .message = row { return true }
            return false
        }
        guard let index = messageIndex ?? visibleIndices.first,
              index >= 0,
              index < orderedItemIds.count,
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: index))
        else { return nil }
        let offsetFromContentTop = attributes.frame.minY - collectionView.contentOffset.y
        return ChatViewportAnchor(
            rowId: orderedItemIds[index],
            offsetFromContentTop: offsetFromContentTop
        )
    }

    private func restoreViewportAnchor(_ anchor: ChatViewportAnchor) {
        guard let index = orderedItemIds.firstIndex(of: anchor.rowId),
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: index))
        else {
            recomputeBottomPinnedState()
            return
        }
        let currentOffsetFromContentTop = attributes.frame.minY - collectionView.contentOffset.y
        let viewportDeltaY = currentOffsetFromContentTop - anchor.offsetFromContentTop
        guard abs(viewportDeltaY) > 0.5 else { return }
        let targetY = clampedContentOffsetY(collectionView.contentOffset.y + viewportDeltaY)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetY),
            animated: false
        )
    }

    private func clampedContentOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let minY = -collectionView.adjustedContentInset.top
        let maxY = max(minY, maxContentOffsetY(in: collectionView))
        return min(max(offsetY, minY), maxY)
    }

    private func updatePreferredOffsetAdjustmentSuppression() {
        let isInteracting = collectionView?.isDragging == true
            || collectionView?.isTracking == true
            || collectionView?.isDecelerating == true
        navigationAwareLayout?.suppressesPreferredOffsetAdjustment =
            scrollNavigationTargetRowId != nil || isRestoringPrependAnchor || isInteracting
    }

    private func applyScrollCommandIfNeeded(_ command: ChatListScrollCommand?) {
        guard let command else { return }
        perform(command)
    }

    func perform(_ command: ChatListScrollCommand) {
        switch command {
        case .none:
            return
        case .bottom(let animated):
            forceScrollToBottom(animated: animated, allowDuringNavigation: true)
        case .firstUnread(let messageId, let animated):
            scrollNavigationTargetRowId = nil
            _ = scrollToRow(id: messageId, at: .top, animated: animated)
        case .highlight(let messageId, let animated):
            navigateToRow(id: messageId, at: .centeredVertically, animated: animated)
        }
    }

    func enqueue(_ intent: ChatListScrollIntent) {
        if case .scrollToBottom = intent,
           case .scrollToBottom? = scrollIntentQueue.last {
            return
        }
        scrollIntentQueue.append(intent)
        processScrollIntentQueue()
    }

    private func processScrollIntentQueue() {
        guard !isProcessingScrollIntent, !scrollIntentQueue.isEmpty else { return }
        isProcessingScrollIntent = true
        let intent = scrollIntentQueue.removeFirst()

        switch intent {
        case .scrollToBottom(let animated):
            scrollToBottom(animated: animated)
            finishScrollIntentProcessing(wasAnimated: animated)
        case .scrollToRow(let id, let position, let animated):
            let didScroll = scrollToRow(id: id, at: position, animated: animated)
            finishScrollIntentProcessing(wasAnimated: didScroll && animated)
        }
    }

    private func finishScrollIntentProcessing(wasAnimated: Bool) {
        if wasAnimated {
            awaitsScrollAnimationEnd = true
        } else {
            isProcessingScrollIntent = false
            processScrollIntentQueue()
        }
    }

    private func completeScrollIntentAfterAnimation() {
        guard awaitsScrollAnimationEnd else { return }
        awaitsScrollAnimationEnd = false
        isProcessingScrollIntent = false
        processScrollIntentQueue()
    }

    @discardableResult
    func scrollToRow(id: String, at position: UICollectionView.ScrollPosition, animated: Bool) -> Bool {
        let resolvedId = resolvedRowId(forMessageId: id)
        guard let index = orderedItemIds.firstIndex(of: resolvedId) else {
            pendingScrollToId = id
            pendingScrollPosition = position
            pendingScrollAnimated = animated
            return false
        }
        pendingScrollToId = nil
        forceScrollToRow(at: index, position: position, animated: animated)
        return true
    }

    func navigateToRow(id: String, at position: UICollectionView.ScrollPosition, animated: Bool) {
        scrollNavigationTargetRowId = id
        _ = scrollToRow(id: id, at: position, animated: animated)
    }

    /// Estabiliza el scroll a una fila ARBITRARIA (no solo el fondo) cuando de por medio hay
    /// celdas auto-dimensionadas nunca medidas: un único `scrollToItem` calcula la posición usando
    /// alturas ESTIMADAS para todo lo no medido, y en una conversación larga puede aterrizar lejos
    /// del objetivo real (o directamente no moverse de forma perceptible). Se repite
    /// scroll → invalidateLayout → layout hasta que el contentSize deje de moverse, igual que
    /// `forceScrollToBottom` ya hace para el índice final.
    private func forceScrollToRow(at index: Int, position: UICollectionView.ScrollPosition, animated: Bool) {
        let indexPath = IndexPath(item: 0, section: index)

        // Primer disparo con la caché de alturas medidas: posicionar el offset cerca del destino
        // real ANTES de forzar layout hace que se midan directamente las celdas de la zona
        // objetivo, en vez de converger a base de iteraciones desde una posición equivocada.
        if let cache = rowHeightCache {
            let estimatedFrame = estimatedFrameForItem(at: index, cache: cache)
            let firstShot = clampedOffsetY(toReveal: estimatedFrame, at: position)
            if abs(collectionView.contentOffset.y - firstShot) > 2 {
                collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: firstShot), animated: false)
            }
        }

        // Converger sobre el OFFSET OBJETIVO, no sobre la altura del contenido: al medirse las
        // celdas estimadas, el layout self-sizing compensa el offset para mantener estable el
        // contenido que estaba visible (las filas del fondo) y deshace el scrollToItem. Se
        // recalcula el destino desde los atributos ya medidos y se fija hasta que aguante.
        for _ in 0..<12 {
            collectionView.layoutIfNeeded()
            guard let attrs = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                // Ítems fuera del rect preparado pueden no tener atributos aún: scrollToItem
                // fuerza al layout a prepararlos y la siguiente iteración converge con frames reales.
                collectionView.scrollToItem(at: indexPath, at: position, animated: false)
                continue
            }
            let targetY = clampedOffsetY(toReveal: attrs.frame, at: position)
            if abs(collectionView.contentOffset.y - targetY) <= 2 { break }
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetY), animated: false)
        }
        collectionView.layoutIfNeeded()
        clearNavigationTargetIfSettled()
    }

    private func estimatedFrameForItem(at index: Int, cache: ChatRowHeightCache) -> CGRect {
        var y = ChatListLayoutMetrics.sectionTopInset
        for item in 0..<index {
            let height = cache.height(for: orderedItemIds[item]) ?? ChatListLayoutMetrics.estimatedRowHeight
            y += height + ChatListLayoutMetrics.interGroupSpacing
        }
        let height = cache.height(for: orderedItemIds[index]) ?? ChatListLayoutMetrics.estimatedRowHeight
        return CGRect(x: 0, y: y, width: collectionView.bounds.width, height: height)
    }

    private func clampedOffsetY(toReveal frame: CGRect, at position: UICollectionView.ScrollPosition) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let viewport = collectionView.bounds.height
        let raw: CGFloat
        if position.contains(.top) {
            raw = frame.minY - inset.top
        } else if position.contains(.bottom) {
            raw = frame.maxY - viewport + inset.bottom
        } else {
            raw = frame.midY - viewport / 2
        }
        let minY = -inset.top
        let maxY = max(minY, collectionView.collectionViewLayout.collectionViewContentSize.height - viewport + inset.bottom)
        return min(max(raw, minY), maxY)
    }

    func resolvedRowId(forMessageId messageId: String) -> String {
        messageIdToRowId[messageId] ?? messageId
    }

    func containsRow(id: String) -> Bool {
        orderedItemIds.contains(resolvedRowId(forMessageId: id))
    }

    private func resolvePendingScrollIfPossible() {
        if let navMessageId = scrollNavigationTargetRowId {
            let resolved = resolvedRowId(forMessageId: navMessageId)
            if let index = orderedItemIds.firstIndex(of: resolved) {
                pendingScrollToId = nil
                forceScrollToRow(at: index, position: .centeredVertically, animated: false)
                return
            }
        }
        guard let messageId = pendingScrollToId else { return }
        let resolved = resolvedRowId(forMessageId: messageId)
        guard let index = orderedItemIds.firstIndex(of: resolved) else { return }
        pendingScrollToId = nil
        forceScrollToRow(at: index, position: pendingScrollPosition, animated: pendingScrollAnimated)
    }

    private func clearNavigationTargetIfSettled() {
        guard let navId = scrollNavigationTargetRowId else { return }
        let resolved = resolvedRowId(forMessageId: navId)
        guard let index = orderedItemIds.firstIndex(of: resolved) else { return }
        let indexPath = IndexPath(item: 0, section: index)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.scrollNavigationTargetRowId == navId else { return }
            self.scrollNavigationTargetRowId = nil
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let onPrefetchRows, let dataSource else { return }
        if let firstPrefetchedIndex = indexPaths.map(\.section).min(),
           firstPrefetchedIndex <= historyPrefetchItemThreshold {
            scheduleHistoryLoadIfNeeded(triggerIndex: firstPrefetchedIndex)
        }
        let rows = indexPaths
            .compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { rowsById[$0] }
        guard !rows.isEmpty else { return }
        onPrefetchRows(rows)
    }

    private func rebuildMessageIdToRowIdIndex(_ rows: [ChatRenderRow]) {
        var index: [String: String] = [:]
        for row in rows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message):
                index[message.id] = row.id
            case .mediaCluster(let messages):
                for message in messages { index[message.id] = row.id }
            }
        }
        messageIdToRowId = index
    }

    func reconfigureVisible(exceptRowId: String? = nil) {
        reconfigureAllVisiblePending = true
        reconfigureExcludedRowId = exceptRowId
        scheduleReconfigureFlush()
    }

    func reconfigure(messageIds: [String]) {
        let rowIds = messageIds.compactMap { messageIdToRowId[$0] }
        guard !rowIds.isEmpty else { return }
        pendingReconfigureRowIds.formUnion(rowIds)
        scheduleReconfigureFlush()
    }

    private func scheduleReconfigureFlush() {
        guard !reconfigureScheduled else { return }
        reconfigureScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconfigureScheduled = false
            self.flushReconfigure()
        }
    }

    private func flushReconfigure() {
        guard let dataSource else { return }
        let visibleIds = Set(collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0) })
        guard !visibleIds.isEmpty else {
            reconfigureAllVisiblePending = false
            reconfigureExcludedRowId = nil
            pendingReconfigureRowIds.removeAll()
            return
        }

        let targetIds: [String]
        if reconfigureAllVisiblePending {
            if let excluded = reconfigureExcludedRowId {
                targetIds = visibleIds.filter { $0 != excluded }
            } else {
                targetIds = Array(visibleIds)
            }
        } else {
            targetIds = Array(pendingReconfigureRowIds.intersection(visibleIds))
        }
        reconfigureAllVisiblePending = false
        reconfigureExcludedRowId = nil
        pendingReconfigureRowIds.removeAll()
        guard !targetIds.isEmpty else { return }

        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(targetIds)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            self.updateBottomAnchorInset()
            self.recomputeBottomPinnedState()
        }
    }

    private func scheduleHistoryLoadIfNeeded(triggerIndex: Int? = nil) {
        guard historyLoadArmed,
              !suppressHistoryLoadUntilNextUserScroll,
              let firstIndex = triggerIndex ?? firstVisibleRowIndex,
              firstIndex <= loadOlderItemThreshold else { return }

        historyLoadArmed = false
        historyLoadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onReachedTop?()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.historyLoadArmed = true
            }
        }
        historyLoadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(historyLoadDebounceNs) / 1_000_000_000, execute: work)
    }

    private func maxContentOffsetY(in scrollView: UIScrollView) -> CGFloat {
        scrollView.contentSize.height
            - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
    }

    /// Anclaje inferior: si el contenido no llena el viewport, se empuja con inset superior.
    private func updateBottomAnchorInset() {
        guard let collectionView else { return }
        let safeTop = collectionView.safeAreaInsets.top
        let composerBottom = max(0, composerBottomInset)
        let available = collectionView.bounds.height - safeTop - composerBottom
        guard available > 0 else { return }
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let extraTop = max(0, available - contentHeight)
        guard abs(collectionView.contentInset.top - extraTop) > 0.5 else { return }
        let shouldPreservePrependViewport = isRestoringPrependAnchor
        let wasPinned = (isStrictlyAtBottom || currentIsAtBottom)
            && scrollNavigationTargetRowId == nil
            && !shouldPreservePrependViewport
        collectionView.contentInset.top = extraTop
        if wasPinned {
            forceScrollToBottom(animated: false)
        }
    }

    private func applyComposerBottomContentInset(preservingBottomPin: Bool) {
        guard isViewLoaded, collectionView != nil else { return }
        let desiredAdjustedBottom = max(0, composerBottomInset)
        let bottom = max(0, desiredAdjustedBottom - collectionView.safeAreaInsets.bottom)
        let bottomChanged = abs(collectionView.contentInset.bottom - bottom) > 0.5
        guard bottomChanged else {
            updateBottomAnchorInset()
            return
        }
        let wasPinned = preservingBottomPin
            && (isStrictlyAtBottom || currentIsAtBottom)
            && scrollNavigationTargetRowId == nil
            && !isRestoringPrependAnchor
        collectionView.contentInset.bottom = bottom
        collectionView.verticalScrollIndicatorInsets.bottom = bottom
        updateBottomAnchorInset()
        if wasPinned {
            forceScrollToBottom(animated: false)
        }
    }

    private func reportContentExtentIfChanged() {
        let exceedsViewport = contentExceedsViewport
        guard lastReportedContentExceedsViewport != exceedsViewport else { return }
        lastReportedContentExceedsViewport = exceedsViewport
        onContentExtentChanged?(exceedsViewport)
    }

    private func bottomOverscroll(in scrollView: UIScrollView) -> CGFloat {
        max(0, scrollView.contentOffset.y - maxContentOffsetY(in: scrollView))
    }

    private func applyVanishFromOverscroll(_ rawOverscroll: CGFloat, isDragging: Bool) {
        // Los scrolls iniciales, restauraciones de ancla y reajustes de alturas pueden
        // producir un overscroll inferior transitorio. Vanish solo debe reaccionar a
        // un gesto real del dedo, nunca a movimiento programático de UICollectionView.
        guard isDragging else {
            if !isVanishOverscrollActive && !isVanishPanActive {
                currentVanishLift = 0
                vanishPullOverlay.hide()
            }
            return
        }

        guard isVanishGestureEnabled, isStrictlyAtBottom else {
            if rawOverscroll <= 0 {
                clearVanishOverscrollPresentation()
            }
            return
        }

        guard rawOverscroll > 0 else {
            if isVanishOverscrollActive || isVanishPanActive {
                clearVanishOverscrollPresentation()
            }
            return
        }

        if isDragging, !isVanishOverscrollActive, !isVanishPanActive {
            isVanishOverscrollActive = true
            onVanishDraggingChanged?(true)
        }

        let lift = ChatVanishSwipeMetrics.conversationLift(fingerUpward: rawOverscroll)
        currentVanishLift = lift

        if ChatVanishSwipeMetrics.shouldRevealVanishUI(lift: lift) {
            let progress = ChatVanishSwipeMetrics.progress(lift: lift)
            updateVanishHaptics(lift: lift, progress: progress)
            vanishPullOverlay.setRevealLayout(
                composerBottomInset: composerBottomInset,
                conversationLift: lift
            )
            vanishPullOverlay.update(
                lift: lift,
                progress: progress,
                isActive: isVanishModeActive,
                isDragging: true,
                colorScheme: traitCollection.userInterfaceStyle
            )
        } else {
            vanishPullOverlay.hide()
        }
    }

    private func clearVanishOverscrollPresentation() {
        guard isVanishOverscrollActive || isVanishPanActive || currentVanishLift > 0 else { return }
        isVanishOverscrollActive = false
        isVanishPanActive = false
        onVanishDraggingChanged?(false)
        vanishPanPull = 0
        currentVanishLift = 0
        vanishDidCrossThreshold = false
        vanishLastHapticStep = -1
        vanishPullOverlay.hide()
    }

    private func finishVanishOverscrollRelease(completed: Bool) {
        let progress = ChatVanishSwipeMetrics.progress(lift: currentVanishLift)
        let effectivePull = ChatVanishSwipeMetrics.effectiveLiftForCompletion(currentVanishLift)

        guard isVanishOverscrollActive || isVanishPanActive || currentVanishLift > 0 else { return }

        isVanishOverscrollActive = false
        isVanishPanActive = false
        onVanishDraggingChanged?(false)
        vanishPanPull = 0
        vanishDidCrossThreshold = false
        vanishLastHapticStep = -1
        vanishPullOverlay.hide()
        currentVanishLift = 0

        onVanishPullReleased?(VanishPullResult(
            completed: completed,
            progress: progress,
            effectivePull: effectivePull
        ))
    }

    private func canEngageVanishPan() -> Bool {
        isVanishGestureEnabled && isStrictlyAtBottom && (orderedItemIds.isEmpty || isLastRowVisible())
    }

    @objc private func handleVanishPan(_ gesture: UIPanGestureRecognizer) {
        guard isVanishGestureEnabled else {
            if gesture.state == .ended || gesture.state == .cancelled {
                finishVanishPan(gesture: gesture, completed: false)
            }
            return
        }

        let translationY = gesture.translation(in: collectionView).y
        let upward = max(0, -translationY)

        switch gesture.state {
        case .began, .changed:
            guard canEngageVanishPan() else { return }
            guard upward >= vanishEngageThreshold || isVanishPanActive else { return }

            if !isVanishPanActive {
                isVanishPanActive = true
                onVanishDraggingChanged?(true)
            }

            vanishPanPull = upward

            let maxY = maxContentOffsetY(in: collectionView)
            let rubberBanded = ChatVanishSwipeMetrics.rubberBandPull(from: translationY)
            isClampingBottomScroll = true
            collectionView.contentOffset.y = maxY + rubberBanded
            isClampingBottomScroll = false
            applyVanishFromOverscroll(rubberBanded, isDragging: true)

        case .ended, .cancelled:
            let completedByThreshold = vanishDidCrossThreshold
                && ChatVanishSwipeMetrics.effectiveLiftForCompletion(currentVanishLift) > 0
            // Flick estilo IG: un tirón rápido y decidido completa aunque el dedo no llegue
            // a la distancia del umbral.
            let completedByFlick = gesture.velocity(in: collectionView).y < -1400
                && ChatVanishSwipeMetrics.progress(lift: currentVanishLift) >= 0.5
            let withinCooldown = lastVanishToggleAt.map { Date().timeIntervalSince($0) < vanishToggleCooldown } ?? false
            let completed = (completedByThreshold || completedByFlick) && !withinCooldown
            if completed {
                lastVanishToggleAt = Date()
            }
            finishVanishPan(gesture: gesture, completed: completed)

        default:
            break
        }
    }

    private func updateVanishHaptics(lift: CGFloat, progress: CGFloat) {
        let effectivePull = ChatVanishSwipeMetrics.effectiveLiftForCompletion(lift)
        guard effectivePull > 0 else {
            vanishDidCrossThreshold = false
            return
        }

        let crossed = progress >= ChatVanishSwipeMetrics.completionThreshold
        if crossed, !vanishDidCrossThreshold {
            vanishDidCrossThreshold = true
            HapticManager.shared.vanishPullThresholdReached()
        } else if !crossed, vanishDidCrossThreshold {
            vanishDidCrossThreshold = false
        }

        let hapticStep = Int(effectivePull / ChatVanishSwipeMetrics.hapticStepPoints)
        if hapticStep != vanishLastHapticStep {
            vanishLastHapticStep = hapticStep
            HapticManager.shared.vanishPullStep()
        }
    }

    private func finishVanishPan(gesture: UIPanGestureRecognizer, completed: Bool) {
        gesture.setTranslation(.zero, in: collectionView)
        guard isVanishPanActive || currentVanishLift > 0 else { return }
        finishVanishOverscrollRelease(completed: completed)
    }

    func resetVanishPullState(animated: Bool) {
        guard isVanishPanActive || isVanishOverscrollActive || currentVanishLift > 0 else { return }
        clearVanishOverscrollPresentation()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // El tap para cerrar teclado cede ante cualquier otro gesto de la celda (long-press
    // del menú contextual, doble-tap de reacción rápida, swipe de reply): sin esto,
    // competir por el mismo toque a nivel de collectionView podía matar el long-press
    // de SwiftUI antes de completarse. Defensa en profundidad además del fix real
    // (rowId sin prefijo en renderMessageItem, que era la causa de que no saliera el menú).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === keyboardDismissTapGesture && otherGestureRecognizer !== keyboardDismissTapGesture
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === vanishPanGesture else { return true }
        guard canEngageVanishPan() else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        if isVanishPanActive { return true }

        let velocity = pan.velocity(in: collectionView)
        let translationY = pan.translation(in: collectionView).y
        let upwardTranslation = max(0, -translationY)
        let isDeliberateUpwardPull = velocity.y < -400 || upwardTranslation >= vanishEngageThreshold
        return isDeliberateUpwardPull
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        navigationAwareLayout?.suppressesPreferredOffsetAdjustment = true
        suppressHistoryLoadUntilNextUserScroll = false
        // El usuario toma el control: soltar el nav target para no pelear contra su gesto.
        if scrollNavigationTargetRowId != nil {
            scrollNavigationTargetRowId = nil
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isClampingBottomScroll else { return }

        enforceNavigationTargetIfNeeded(context: "didScroll")

        let overscroll = bottomOverscroll(in: scrollView)
        if isVanishGestureEnabled, isStrictlyAtBottom, !isVanishPanActive {
            applyVanishFromOverscroll(overscroll, isDragging: scrollView.isDragging || scrollView.isTracking)
        }

        recomputeBottomPinnedState()
        scheduleHistoryLoadIfNeeded()

        if !isStrictlyAtBottom, isVanishPanActive || isVanishOverscrollActive {
            clearVanishOverscrollPresentation()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updatePreferredOffsetAdjustmentSuppression()
        }
        guard !isVanishPanActive else { return }
        guard isVanishOverscrollActive || currentVanishLift > 0 else { return }

        let completed = vanishDidCrossThreshold
            && ChatVanishSwipeMetrics.effectiveLiftForCompletion(currentVanishLift) > 0
        finishVanishOverscrollRelease(completed: completed)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updatePreferredOffsetAdjustmentSuppression()
        clearNavigationTargetIfSettled()
        completeScrollIntentAfterAnimation()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        clearNavigationTargetIfSettled()
        completeScrollIntentAfterAnimation()
    }
}

private extension ChatRenderRow {
    var visualSignature: Int {
        var hasher = Hasher()
        switch self {
        case .conversationIntro(let context):
            hasher.combine(5)
            hasher.combine(context)
        case .requestDisclaimer(let context):
            hasher.combine(6)
            hasher.combine(context?.id)
            hasher.combine(context?.status.rawValue)
        case .pendingRequestMessage(let message):
            hasher.combine(7)
            hasher.combine(message.id)
            hasher.combine(message.text)
            hasher.combine(message.isOutgoing)
            hasher.combine(message.contextKind)
            hasher.combine(message.storyId)
            hasher.combine(message.storyOwnerId)
            hasher.combine(message.sharedContentId)
            hasher.combine(message.sharedContentOwnerId)
        case .incomingRequestActions(let isLoading):
            hasher.combine(8)
            hasher.combine(isLoading)
        case .outgoingRequestControls(let messageCount, let limitReached):
            hasher.combine(9)
            hasher.combine(messageCount)
            hasher.combine(limitReached)
        case .header(let date):
            hasher.combine(0)
            hasher.combine(date.timeIntervalSinceReferenceDate)
        case .message(let item):
            hasher.combine(1)
            hasher.combine(item.visualSignature)
        case .buzz(let event):
            hasher.combine(2)
            hasher.combine(event.id)
            hasher.combine(event.senderId)
            hasher.combine(event.createdAt.timeIntervalSinceReferenceDate)
        case .typing:
            hasher.combine(3)
        case .historyStart:
            hasher.combine(4)
        }
        return hasher.finalize()
    }
}

private extension MessageItem {
    var visualSignature: Int {
        var hasher = Hasher()
        switch self {
        case .single(let message):
            hasher.combine(0)
            hasher.combine(message.visualRenderSignature)
        case .mediaCluster(let messages):
            hasher.combine(1)
            hasher.combine(messages.count)
            messages.forEach { hasher.combine($0.visualRenderSignature) }
        }
        return hasher.finalize()
    }
}

private extension EnhancedMessage {
    var visualRenderSignature: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(senderId)
        hasher.combine(type.rawValue)
        hasher.combine(content)
        hasher.combine(duration)
        hasher.combine(fileName)
        hasher.combine(fileSize)
        hasher.combine(mediaWidth)
        hasher.combine(mediaHeight)
        hasher.combine(latitude)
        hasher.combine(longitude)
        hasher.combine(locationName)
        hasher.combine(locationAddress)
        hasher.combine(isLiveLocation)
        hasher.combine(liveLocationExpiresAt?.timeIntervalSinceReferenceDate)
        hasher.combine(liveLocationDuration)
        hasher.combine(liveLocationStoppedAt?.timeIntervalSinceReferenceDate)
        hasher.combine(liveLocationSessionId)
        hasher.combine(locationUpdatedAt?.timeIntervalSinceReferenceDate)
        hasher.combine(timestamp.timeIntervalSinceReferenceDate)
        hasher.combine(status.rawValue)
        hasher.combine(isRead)
        hasher.combine(isDeleted)
        hasher.combine(deletedAt?.timeIntervalSinceReferenceDate)
        hasher.combine(editedAt?.timeIntervalSinceReferenceDate)
        hasher.combine(replyTo)
        hasher.combine(expirationDate?.timeIntervalSinceReferenceDate)
        hasher.combine(isViewed)
        hasher.combine(mediaBatchId)
        hasher.combine(isForwarded)
        hasher.combine(isVanishModeMessage)
        hasher.combine(vanishExpiresAt?.timeIntervalSinceReferenceDate)
        hasher.combine(stableDictionarySignature(reactions))
        hasher.combine(stableDictionarySignature(storyReplyData))
        hasher.combine(stableDictionarySignature(sharedMomentData))
        hasher.combine(stableDictionarySignature(sharedStoryData))
        hasher.combine(stableDictionarySignature(sharedProfileData))
        hasher.combine(stableArraySignature(viewedBy))
        hasher.combine(stableArraySignature(readBy))
        hasher.combine(stableDateDictionarySignature(readAtBy))
        hasher.combine(stableArraySignature(starredBy))
        hasher.combine(stableArraySignature(vanishedFor))
        return hasher.finalize()
    }

    private func stableArraySignature(_ values: [String]?) -> Int {
        var hasher = Hasher()
        (values ?? []).sorted().forEach { hasher.combine($0) }
        return hasher.finalize()
    }

    private func stableDateDictionarySignature(_ values: [String: Date]?) -> Int {
        var hasher = Hasher()
        (values ?? [:]).sorted(by: { $0.key < $1.key }).forEach { key, value in
            hasher.combine(key)
            hasher.combine(value.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func stableDictionarySignature(_ values: [String: String]?) -> Int {
        var hasher = Hasher()
        (values ?? [:]).sorted(by: { $0.key < $1.key }).forEach { key, value in
            hasher.combine(key)
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    private func stableDictionarySignature(_ values: [String: [String]]?) -> Int {
        var hasher = Hasher()
        (values ?? [:]).sorted(by: { $0.key < $1.key }).forEach { key, value in
            hasher.combine(key)
            value.sorted().forEach { hasher.combine($0) }
        }
        return hasher.finalize()
    }
}
