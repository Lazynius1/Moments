# Fase D — Escala y polish

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:executing-plans` (tareas largas, checkpoints semanales)

**Goal:** Rendimiento feed, accesibilidad, offline visible, modularización gradual, onboarding de features.

**Exclusiones:** Partir AuthService, storyeditor, StoryViewer, EncryptionService.

**Depends on:** Fases A + B recomendadas (router facilita cambios seguros).

---

## Task 1: Feed listeners — viewport budget

**Files:**
- Modify: `Moments/Views/Feed/Core/FeedViewModel.swift`
- Modify: `Moments/Views/Feed/Core/FeedView.swift`

- [ ] **Step 1:** Documentar listeners actuales (`momentListeners`, `commentListeners`) y cuántos se abren con 50 posts.

- [ ] **Step 2:** Estrategia: solo mantener listeners para IDs en viewport visible (+ buffer 5). Usar `FeedVisibilityCoordinator` existente.

- [ ] **Step 3:** Al salir de viewport, `removeListener` para ese momentId.

- [ ] **Step 4:** Verificar en Instruments / logs que listeners no crecen linealmente al hacer scroll largo.

---

## Task 2: Accesibilidad core

**Files:**
- Modify: `CustomTabBar` / `ModernTabView`, `FeedMomentComponents.swift`, `MomentReactionButton.swift`, `DiscoverMapView.swift`, `NovaInputSection.swift`, `ProfileHighlightsView.swift`

- [ ] **Step 1:** Checklist WCAG — cada `Button` solo con `Image(systemName:)` necesita `.accessibilityLabel`.

- [ ] **Step 2:** Map pins: `Annotation` con label `"\(placeName), \(count) momentos"`.

- [ ] **Step 3:** VoiceOver walkthrough manual: login → feed → crear → perfil → highlights.

- [ ] **Step 4:** Corregir orden de foco en sheets.

---

## Task 3: Banner offline global

**Files:**
- Create: `Moments/Views/Shared/OfflineBannerModifier.swift`
- Modify: `TabBarView.swift`

- [ ] **Step 1:**

```swift
struct OfflineBannerModifier: ViewModifier {
    @ObservedObject var network = NetworkMonitor.shared
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if !network.isConnected {
                AppErrorBanner(
                    message: NSLocalizedString("offline.banner.message", comment: ""),
                    retryTitle: NSLocalizedString("common.retry", comment: "")
                ) { /* trigger pending sync */ }
            }
            content
        }
    }
}
```

- [ ] **Step 2:** Aplicar en `TabBarView` root.

- [ ] **Step 3:** Añadir strings a 8 locales.

---

## Task 4: Map default region

**Files:**
- Modify: `DiscoverMapView.swift`

- [ ] **Step 1:** Reemplazar Madrid hardcoded por `LocationUtilities.shared.currentLocation` o última región guardada en `UserDefaults`.

- [ ] **Step 2:** Fallback solo si sin permiso: región del último momento del usuario o España centro.

---

## Task 5: Design tokens

**Files:**
- Modify: `AdaptiveColors.swift` o crear `MomentsDesignTokens.swift`
- Modify: archivos con más `Color(hex:` — priorizar Feed, Profile, Highlights

- [ ] **Step 1:** Inventario top 20 hex duplicados.

- [ ] **Step 2:** Mover a tokens nombrados (`accent`, `surface`, `borderGlass`).

- [ ] **Step 3:** No big-bang — un módulo por PR.

---

## Task 6: SPM modularización (incremental)

**Files:**
- Create: `Packages/MomentsCore/Package.swift`
- Move: `Models/`, `Services/Cache/`, `AdaptiveColors`, repos Firestore

- [ ] **Step 1:** Extraer `MomentsCore` sin UI — compila y Moments app depende de él.

- [ ] **Step 2:** `MomentsFeed` con FeedViewModel + secciones.

- [ ] **Step 3:** No mover Creator/Nova hasta Core estable.

---

## Task 7: Firestore rules audit

**Files:**
- Modify: `firestore.rules`
- Create: `docs/firestore-rules-cost-audit.md`

- [ ] **Step 1:** Exportar métricas de evaluación desde Firebase Console (baseline).

- [ ] **Step 2:** Identificar reglas con >3 `get()` anidados en reads de feed/moments.

- [ ] **Step 3:** Denormalizar `audienceFlags` / `viewerCanSee` en documento momento (migration script en Functions).

- [ ] **Step 4:** Validar reglas en Firebase emulator antes de deploy a producción.

---

## Task 8: Onboarding post-registro

**Files:**
- Create: `Moments/Views/Onboarding/FeatureDiscoveryView.swift`
- Modify: flujo post `ProfileOnboardingView`

- [ ] **Step 1:** 3 páginas swipeable: Echo, Nova, Mapa Discover (ilustración + 1 línea + CTA opcional).

- [ ] **Step 2:** Mostrar una vez (`UserDefaults` `hasSeenFeatureDiscovery`).

- [ ] **Step 3:** Strings en 8 locales.

---

## Task 9: MotionPolicy en Creator y Nova

**Files:**
- Modify: `CreatorView.swift`, `NovaView.swift` / `NovaInputSection.swift`

- [ ] **Step 1:** Envolver animaciones pesadas con `if !MotionPolicy.reduceMotion`.

- [ ] **Step 2:** Verificar con Reduce Motion activado en Settings.

---

## Verificación de fase

- [ ] Instruments: listeners feed no crecen linealmente con scroll infinito
- [ ] VoiceOver usable en flujos core
- [ ] Banner offline aparece en modo avión
- [ ] `MomentsCore` compila como package local
- [ ] Documento de coste rules con baseline + post-cambio

**Handoff:** PRs pequeños por task. Checkpoint semanal con usuario.
