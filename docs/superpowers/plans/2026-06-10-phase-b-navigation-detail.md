# Fase B — Navegación y detalle unificado

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`

**Goal:** Navegación tipada y un solo detalle de momento. Feed modular y mantenible.

**Architecture:** `AppRouter` como `@Observable` en environment. Migración incremental: nuevas rutas usan router; legacy NotificationCenter se depreca con wrappers.

**Depends on:** Fase A (errores + skeleton) recomendada.

---

## Task 1: AppRouter scaffold

**Files:**
- Create: `Moments/Coordinators/AppRouter.swift`
- Modify: `Moments/Coordinators/TabBarView.swift`
- Modify: `Moments/MomentsApp.swift`

- [ ] **Step 1:** Definir rutas:

```swift
@Observable
final class AppRouter {
    enum Destination: Equatable {
        case profile(userId: String)
        case moment(id: String, context: MomentDetailContext)
        case conversation(id: String)
        case storyChain(userId: String, storyId: String?)
        case echo(echoId: String)
        case discoverMap
    }

    var pending: Destination?
    var selectedTab: AppTab = .home

    func navigate(to destination: Destination) {
        pending = destination
        routeToTab(for: destination)
    }
}
```

- [ ] **Step 2:** Inyectar `.environment(appRouter)` en root tras auth.

- [ ] **Step 3:** `TabBarView` consume `pending` en `onChange` y presenta sheet/fullScreenCover.

- [ ] **Step 4:** Probar manualmente en simulador: deep link / notificación abre perfil correcto.

---

## Task 2: Migrar NotificationCenter (incremental)

**Files:**
- Modify: 30+ archivos con `NotificationCenter.default.post(name: NSNotification.Name("NavigateToProfile")` etc.
- Create: `Moments/Coordinators/LegacyNavigationBridge.swift`

- [ ] **Step 1:** Inventario:

```bash
rg 'NotificationCenter\.default\.post' Moments/Moments --glob '*.swift' -c | sort -t: -k2 -nr
```

- [ ] **Step 2:** `LegacyNavigationBridge` escucha notificaciones viejas y llama `appRouter.navigate`.

- [ ] **Step 3:** Migrar emisores de alta frecuencia primero: `FeedView`, `NotificationNavigationService`, widget/deep link handlers.

- [ ] **Step 4:** Por cada archivo migrado, reemplazar post por `appRouter.navigate`. Dejar bridge hasta fase completa.

---

## Task 3: Unified MomentDetail

**Files:**
- Create: `Moments/Views/Shared/MomentDetail/MomentDetailContainerView.swift`
- Create: `Moments/Views/Shared/MomentDetail/MomentDetailViewModel.swift`
- Create: `Moments/Views/Shared/MomentDetail/MomentDetailContext.swift`
- Modify: `MomentDetailView.swift`, `ModernMomentDetailView.swift`, `LocationMomentDetailView.swift` → thin wrappers

- [ ] **Step 1:** `MomentDetailContext` enum:

```swift
enum MomentDetailContext {
    case feed(moments: [Moment], index: Int)
    case profile(userId: String)
    case map(moments: [Moment], index: Int, locationName: String, availability: [String: Bool])
    case explore(moments: [Moment], index: Int)
}
```

- [ ] **Step 2:** Extraer lógica compartida: comentarios, reacciones, share, report — del archivo más completo (`MomentDetailView.swift`).

- [ ] **Step 3:** `LocationMomentDetailView` pasa a wrapper que inyecta context `.map` + binding availability.

- [ ] **Step 4:** Cerrar TODOs líneas 415/445 — actualizar array tras delete/hide:

```swift
onMomentRemoved: { moment in
    moments.removeAll { $0.id == moment.id }
}
```

- [ ] **Step 5:** Probar manualmente detalle desde feed, perfil, mapa y explore — mismo comportamiento.

---

## Task 4: Modularizar FeedView

**Files:**
- Create: `Moments/Views/Feed/Core/Sections/FeedHeaderSection.swift`
- Create: `Moments/Views/Feed/Core/Sections/FeedListSection.swift`
- Create: `Moments/Views/Feed/Core/Sections/FeedOverlaysSection.swift`
- Modify: `FeedView.swift` — solo composición + bindings

- [ ] **Step 1:** Mover `storyRing`, notificaciones badge, selector Following/For You → `FeedHeaderSection`.

- [ ] **Step 2:** Mover `LazyVStack` de momentos + reels trigger → `FeedListSection`.

- [ ] **Step 3:** Mover upload overlay, echo invitation, map entry → `FeedOverlaysSection`.

- [ ] **Step 4:** Objetivo: `FeedView.swift` < 400 LOC. Build sin cambio de comportamiento.

---

## Verificación de fase

- [ ] Deep link de notificación abre perfil/momento vía router
- [ ] Detalle desde feed, perfil, mapa y explore usa mismo container
- [ ] `FeedView.swift` LOC < 500
- [ ] Build OK + smoke test manual de navegación cross-tab

**Handoff:** PR `phase-b/navigation-detail`. No tocar AuthService ni storyeditor.
