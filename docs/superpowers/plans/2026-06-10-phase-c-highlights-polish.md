# Fase C — Highlights redesign

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:brainstorming` antes de mockups finales, luego `subagent-driven-development`

**Goal:** Flujo de destacadas más premium y coherente con el resto de la app (mapas, stories). Eliminar código huérfano.

**Architecture:** Presentación tipo mapa (liquid glass, cierre seguro). Componentes shared entre crear y editar. Sin tocar Firestore schema.

**Flujo actual (correcto):**

```
ProfileHighlightsView
  ├── + → sheet → CreateHighlightView (selectStories → details)
  ├── tap → fullScreenCover → HighlightViewer
  └── edit → fullScreenCover → EditHighlightView

HighlightedStoriesView.swift ← HUÉRFANO (borrar)
```

**Depends on:** Fase A (AppErrorBanner, i18n) útil pero no bloqueante.

---

## Task 1: Limpieza legacy

**Files:**
- Delete: `Moments/Views/story/HighlightedStoriesView.swift`
- Modify: `Moments.xcodeproj/project.pbxproj`

- [ ] **Step 1:** Confirmar cero referencias:

```bash
rg 'HighlightedStoriesView' Moments/
```

- [ ] **Step 2:** Eliminar archivo y entrada en proyecto.

- [ ] **Step 3:** Commit `chore: remove orphan HighlightedStoriesView`

---

## Task 2: HighlightPresentationCoordinator

**Files:**
- Create: `Moments/Views/Profile/Highlights/HighlightPresentationCoordinator.swift`
- Modify: `ProfileHighlightsView.swift`

- [ ] **Step 1:** Centralizar presentación con cierre seguro (patrón `closeDiscoverMap`):

```swift
enum HighlightSheet: Identifiable {
    case create
    case edit(HighlightedStory)
}

@Observable
final class HighlightPresentationCoordinator {
    var sheet: HighlightSheet?
    var viewerHighlight: HighlightedStory?

    func closeAll() {
        sheet = nil
        viewerHighlight = nil
    }

    func closeSheetThenShowViewer(_ highlight: HighlightedStory) {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.dismissBeforeNextPresentation) {
            viewerHighlight = highlight
        }
    }
}
```

- [ ] **Step 2:** `ProfileHighlightsView` usa coordinator en lugar de 3 `@State` sueltos.

---

## Task 3: Rediseño CreateHighlightView

**Files:**
- Modify: `CreateHighlightView.swift`
- Modify: `HighlightComponents.swift`

**UX objetivo:**
- Header pill con título + contador `"3 seleccionadas"`
- Grid 3 columnas con checkmark overlay (como archivo stories)
- Barra inferior fija: campo título + preview portada circular
- Botón Crear deshabilitado hasta título + ≥1 story
- Fondo: material / liquid glass, no blanco plano

- [ ] **Step 1:** Fusionar pasos `selectStories` + `details` en una sola vista scrollable (eliminar `CreationStep` enum) O mantener 2 pasos con transición horizontal más clara — **decisión en brainstorming**.

- [ ] **Step 2:** Extraer `HighlightStoryGrid` shared (usado también en Edit).

- [ ] **Step 3:** Portada: primera story seleccionada por defecto; tap para elegir otra como cover.

- [ ] **Step 4:** Errores con `AppErrorBanner` + strings localizados.

- [ ] **Step 5:** Presentar como `.sheet` con `presentationDetents([.large])` + `presentationBackground(.clear)` + fondo glass (como `MapLocationSystemSheetModifier`).

---

## Task 4: Rediseño EditHighlightView

**Files:**
- Modify: `EditHighlightView.swift`

- [ ] **Step 1:** Reutilizar `HighlightStoryGrid` + header pill.

- [ ] **Step 2:** Acciones destructivas (eliminar highlight) en menú `...` no en flujo principal.

- [ ] **Step 3:** Misma presentación glass que Create.

---

## Task 5: HighlightViewer polish

**Files:**
- Modify: `HighlightViewer.swift`

- [ ] **Step 1:** Barra de progreso por story (como `StoryViewerScreen` simplificado).

- [ ] **Step 2:** Tap izquierda/derecha para navegar; swipe down para cerrar.

- [ ] **Step 3:** Cierre seguro si hay sheets anidados.

---

## Task 6: ProfileHighlightsViewModel

**Files:**
- Modify: `ProfileHighlightsView.swift` (ViewModel al final del archivo)

- [ ] **Step 1:** `FirestoreService.shared` en lugar de `FirestoreService()`.

- [ ] **Step 2:** Exponer `errorMessage` + banner en fila de highlights si falla carga.

---

## Verificación de fase

- [ ] Perfil propio → + → crear destacada → aparece en rail sin recargar manual
- [ ] Ver destacada → navegar stories → cerrar sin crash
- [ ] Editar título/portada/stories → guardar → rail actualizado
- [ ] Perfil ajeno → solo highlights visibles según privacidad
- [ ] `HighlightedStoriesView` no existe en proyecto

**Handoff:** PR `phase-c/highlights-redesign`. Pedir feedback visual al usuario antes de merge.
