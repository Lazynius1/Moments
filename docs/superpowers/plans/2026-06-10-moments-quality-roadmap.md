# Moments — Plan maestro de calidad (2026)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans` para implementar fase a fase. Cada sub-plan tiene checkboxes (`- [ ]`) para tracking.

**Goal:** Elevar estabilidad, UX y mantenibilidad de Moments sin reescribir módulos críticos (Creator, Auth, Encryption).

**Architecture:** Roadmap en 4 fases independientes. Cada fase entrega software usable y verificable en simulador. Se excluye explícitamente partir god files monolíticos (AuthService, storyeditor, StoryViewer, EncryptionService).

**Tech Stack:** SwiftUI, Firebase (Auth/Firestore/Functions), SwiftData offline, Kingfisher.

**Corrección de auditoría — Highlights:**
- El flujo real es `ProfileHighlightsView` → botón `+` → `CreateHighlightView` (sheet 2 pasos) → `HighlightViewer` / `EditHighlightView`.
- `HighlightedStoriesView.swift` es **código huérfano** (solo Preview, TODOs sin usar). No es la entrada del perfil.
- Mejora pedida: **rediseño del sheet/flujo**, no implementar highlights desde cero.

---

## Exclusiones (acordado)

| # | Item excluido | Motivo |
|---|---------------|--------|
| 13 | Partir god files (AuthService, storyeditor, StoryViewer, EncryptionService) | Alto riesgo de regresión en flujos críticos |

Todo lo demás del plan original **sí entra**.

---

## Mapa de sub-planes

| Fase | Documento | Duración estimada | Entregable principal |
|------|-----------|-------------------|----------------------|
| **A** | [2026-06-10-phase-a-foundation.md](./2026-06-10-phase-a-foundation.md) | 2–4 semanas | Errores unificados, skeleton feed, Firestore.shared |
| **B** | [2026-06-10-phase-b-navigation-detail.md](./2026-06-10-phase-b-navigation-detail.md) | 6–10 semanas | AppRouter, detalle de momento unificado, FeedView modular |
| **C** | [2026-06-10-phase-c-highlights-polish.md](./2026-06-10-phase-c-highlights-polish.md) | 2–3 semanas | Rediseño highlights + limpieza legacy |
| **C2** | [2026-06-10-phase-c2-instagram-highlights-flow.md](./2026-06-10-phase-c2-instagram-highlights-flow.md) | 4–5 días | Wizard 2 pasos estilo Instagram (paralelo a B) |
| **D** | [2026-06-10-phase-d-scale-polish.md](./2026-06-10-phase-d-scale-polish.md) | 8–12 semanas | Listeners feed, a11y, offline banner, SPM, rules, onboarding |

**Orden recomendado:** A → C → **C2** (paralelo con B) → B → D

Highlights (C) puede empezar pronto porque es acotado y visible en producto. **C2** refina el flujo hacia Instagram tras C, sin bloquear el router (B).

---

## Fase A — Foundation (detalle en sub-plan)

- [ ] `AppErrorBanner` / toast reutilizable
- [ ] Migrar strings hardcoded críticos a `Localizable.strings`
- [ ] `FeedViewModel.errorMessage` visible en UI
- [ ] Skeleton de posts en feed (no solo story ring)
- [ ] Auditar `FirestoreService.shared` en vistas top
- [ ] Completar o eliminar handlers vacíos en `MomentsApp.swift`

**Archivos clave:** `FeedView.swift`, `FeedViewModel.swift`, `ExploreViewModel.swift`, `MomentsApp.swift`, `Moments.xcodeproj`

---

## Fase B — Navegación y detalle (detalle en sub-plan)

- [ ] `AppRouter` con rutas enum tipadas
- [ ] Migrar `NotificationCenter` → router (30+ call sites, incremental)
- [ ] Unificar `MomentDetailView` + `ModernMomentDetailView` + `LocationMomentDetailView`
- [ ] Cerrar TODOs de sync de array en `LocationMomentDetailView.swift:415,445`
- [ ] Modularizar `FeedView` en secciones (<400 LOC/archivo)

**Archivos clave:** `TabBarView.swift`, `NotificationNavigationService.swift`, `FeedPresentationModifier.swift`, `MomentDetailView.swift`, `ModernMomentDetailView.swift`, `LocationMomentDetailView.swift`

---

## Fase C — Highlights redesign (detalle en sub-plan)

**Estado actual**

```
ProfileShellComponents / UserProfilePublicProfileView
  └── ProfileHighlightsView
        ├── + → .sheet → CreateHighlightView (2 steps: selectStories → details)
        ├── tap → .fullScreenCover → HighlightViewer
        └── context menu → EditHighlightView

HighlightedStoriesView.swift  ← HUÉRFANO (eliminar o redirigir)
```

**Objetivos de rediseño**

- [ ] Sustituir `NavigationView` + sheet plano por presentación premium (liquid glass, como mapas)
- [ ] Flujo crear: grid de stories más claro, selección múltiple con contador, preview de portada en vivo
- [ ] Unificar `CreateHighlightView` y `EditHighlightView` donde compartan UI (story grid + title + cover)
- [ ] `HighlightViewer` alineado con `StoryViewerScreen` (gestos, progreso, cierre seguro)
- [ ] Eliminar `HighlightedStoriesView.swift` y `HighlightedStoriesViewModel` (dead code)
- [ ] `ProfileHighlightsViewModel` → `FirestoreService.shared`
- [ ] Strings y errores localizados en ViewModels de highlights

**Archivos clave:**
- `Views/Profile/Highlights/ProfileHighlightsView.swift`
- `Views/Profile/Highlights/CreateHighlightView.swift`
- `Views/Profile/Highlights/EditHighlightView.swift`
- `Views/Profile/Highlights/HighlightViewer.swift`
- `Views/Profile/Highlights/HighlightComponents.swift`
- `Views/story/HighlightedStoriesView.swift` (borrar)

---

## Fase D — Escala y polish (detalle en sub-plan)

- [ ] Limitar listeners per-moment en `FeedViewModel` (viewport / paginación)
- [ ] Pase accesibilidad: tab bar, reacciones, map pins, Nova input, highlights
- [ ] Banner offline global con `NetworkMonitor`
- [ ] Map: región default desde `LocationUtilities` (no Madrid hardcoded en Discover)
- [ ] Modularización SPM: `MomentsCore`, `MomentsFeed`, `MomentsCreator`, `MomentsNova` (incremental)
- [ ] Auditar coste `firestore.rules` + denormalizar flags de audiencia (con métricas)
- [ ] Design tokens: extender `AdaptiveColors` / `ProfileColors` como fuente única
- [ ] Onboarding post-registro: 3 cards (Echo, Nova, Mapa Discover)
- [ ] `MotionPolicy` en Creator y Nova chat

**Archivos clave:** `FeedViewModel.swift`, `DiscoverMapView.swift`, `firestore.rules`, `AdaptiveColors`, `ProfileOnboardingView.swift`

---

## Métricas de éxito

| Métrica | Hoy | Objetivo 3 meses |
|---------|-----|------------------|
| `FeedView.swift` LOC | ~1.483 | < 600 |
| Strings ES hardcoded en ViewModels (core) | ~30+ | 0 |
| Vistas detalle de momento | 3 | 1 (+ modos) |
| `NotificationCenter` navegación | 30+ posts | < 5 (legacy) |
| `accessibilityLabel` en flujos core | ~20 archivos | 100% botones icon-only |

---

## Ejecución con Superpowers

1. **Brainstorming** — solo si un sub-plan necesita decisiones de diseño (ej. highlights UX)
2. **writing-plans** — un sub-plan por fase (este doc + 4 hijos)
3. **using-git-worktrees** — rama aislada por fase (`phase-a/foundation`, etc.)
4. **subagent-driven-development** — un subagent por task, review entre tasks
5. **verification-before-completion** — build + prueba manual en simulador antes de marcar fase done
6. **requesting-code-review** — al cerrar cada fase
7. **finishing-a-development-branch** — merge/PR al completar fase

---

## Próximo paso

Empezar por **[Fase A — Foundation](./2026-06-10-phase-a-foundation.md)** o **[Fase C — Highlights](./2026-06-10-phase-c-highlights-polish.md)** si prefieres impacto visual rápido en perfil.
