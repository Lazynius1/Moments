# Fase C2 — Flujo Instagram para Highlights

> **Paralelo a:** [Fase C](./2026-06-10-phase-c-highlights-polish.md) (ya implementada). C2 **refina el UX** hacia el patrón de Instagram sin cambiar el schema de Firestore.
>
> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:brainstorming` para validar mockups del paso 2 (portada + nombre) antes de codificar.

**Goal:** Que crear/editar una destacada se sienta como Instagram: wizard de 2 pasos, selección primero, nombre/portada después, presentación casi fullscreen.

**Architecture:** Reutilizar `HighlightPresentationCoordinator`, `HighlightStoryGrid`, `FirestoreService.shared`. Nuevo `HighlightCreationStep` enum y vistas por paso. Fuente de stories = **archivo** (expiradas), no todas las stories del usuario.

**Depends on:** Fase C (coordinator, componentes, viewer). No bloquea Fase B.

---

## Cómo funciona Instagram (referencia UX)

### Entrada desde perfil (método principal)

```
Perfil
  └── Fila Highlights → círculo "+" etiquetado "Nuevo"
        └── Modal casi fullscreen
              ├── PASO 1 — Seleccionar stories
              │     ├── Nav: [X/Cancelar]  "Nueva destacada"  [Siguiente →]
              │     ├── Grid 3 columnas del Archivo de stories (más recientes primero)
              │     ├── Tap en esquina → check azul/blanco
              │     └── "Siguiente" deshabilitado si 0 seleccionadas
              │
              └── PASO 2 — Nombre y portada
                    ├── Nav: [← Atrás]  (sin título grande)  [Añadir / Listo]
                    ├── Círculo grande centrado = portada (1ª story por defecto)
                    ├── Texto "Editar portada" bajo el círculo
                    │     └── Sheet: miniaturas de stories seleccionadas + galería (subir icono)
                    ├── Campo nombre (≈15 caracteres visibles en perfil; límite ~100 en backend)
                    └── CTA "Añadir" → vuelve al perfil, highlight en el rail
```

### Otros caminos en Instagram (opcional en Moments, fase posterior)

| Camino | Acción |
|--------|--------|
| Story activa (24h) | Botón "Destacar" (corazón+) → elegir highlight existente o "Nueva" → nombre → Añadir |
| Editar existente | Mantener pulsado highlight → "Editar destacada" → mismo grid + nombre/portada |
| Desde Archivo | Menú → Archivo → Stories → seleccionar → "Destacar" |

### Principios de diseño Instagram

1. **Una decisión por pantalla** — no mezclar grid + título + portada + CTA en la misma vista.
2. **Selección = pantalla completa** — el grid es el protagonista; sin barra inferior fija.
3. **Metadata = pantalla dedicada** — portada grande centrada, nombre secundario.
4. **Navegación explícita** — Cancelar / Siguiente / Atrás / Añadir (no un solo botón "Crear" abajo).
5. **Fuente = archivo** — solo stories expiradas (equivalente a `expirationDate < now`).
6. **Presentación** — modal tipo navigation stack, fondo sólido (blanco/negro sistema), no sheet glass pequeño.

---

## Moments hoy vs Instagram

| Aspecto | Moments (Fase C) | Instagram |
|---------|------------------|-----------|
| Pasos | 1 pantalla combinada | 2 pasos secuenciales |
| Presentación | Sheet glass `.large` | Modal / navigation casi fullscreen |
| Fuente stories | `fetchStoriesPaginated` (todas) | Archivo (expiradas) |
| Selección | Grid + barra inferior fija | Solo grid + nav "Siguiente" |
| Nombre/portada | Barra inferior con TextField + mini portada | Pantalla 2: círculo grande + "Editar portada" |
| CTA crear | Botón en bottom bar | "Añadir" en nav bar paso 2 |
| Editar | Misma UI que crear (1 pantalla) | Mismo wizard; pre-selección de stories actuales |
| Atajo desde story activa | No | Sí (corazón+) |

---

## Flujo objetivo en Moments

```
ProfileHighlightsView
  ├── + → fullScreenCover (o sheet .large sin glass) → HighlightCreateFlowView
  │       ├── step: .selectStories → HighlightSelectStoriesStep
  │       └── step: .nameAndCover  → HighlightNameCoverStep
  ├── tap highlight → HighlightViewer (sin cambios)
  └── context edit → HighlightEditFlowView (mismo wizard, datos precargados)
```

**Decisión de presentación (brainstorming):**
- **Opción A (recomendada):** `fullScreenCover` para create/edit — más fiel a Instagram.
- **Opción B:** Sheet `.large` con fondo sólido (sin `highlightGlassSheet`) — menos invasivo, más rápido de implementar.

---

## Task 1: Fuente de datos — Archivo de stories

**Files:**
- Modify: `FirestoreStoriesRepository.swift` / `FirestoreService.swift`
- Modify: `CreateHighlightViewModel` → renombrar/mover a `HighlightCreateFlowViewModel`

- [ ] **Step 1:** Añadir `fetchArchivedStoriesPaginated(userId:limit:lastDocument:)` con query:

```swift
.whereField("expirationDate", isLessThan: Date())
.order(by: "timestamp", descending: true)
```

(mismo patrón que `ArchiveViewModel` en `archived stories.swift`)

- [ ] **Step 2:** Reutilizar en create **y** edit (edit carga archivo + marca las ya incluidas en el highlight).

- [ ] **Step 3:** Empty state: "No tienes stories en el archivo" + enlace opcional a publicar story (copy `archivedStories.empty.*`).

---

## Task 2: Wizard — `HighlightCreateFlowView`

**Files:**
- Create: `HighlightCreateFlowView.swift`
- Create: `HighlightSelectStoriesStep.swift`
- Create: `HighlightNameCoverStep.swift`
- Modify: `HighlightPresentationCoordinator.swift`
- Modify: `ProfileHighlightsView.swift` — presentar flow en lugar de `CreateHighlightView` directo

```swift
enum HighlightCreateStep {
    case selectStories
    case nameAndCover
}

@Observable
final class HighlightCreateFlowViewModel {
    var step: HighlightCreateStep = .selectStories
    var selectedStories: [Story] = []
    var title = ""
    var coverStory: Story?
    // ... load archived, save
}
```

- [ ] **Step 1:** Paso 1 — `NavigationStack` con toolbar:
  - Leading: `common.cancel` → dismiss flow
  - Trailing: `common.next` → avanza si `selectedStories.count > 0`

- [ ] **Step 2:** Reutilizar `HighlightStoryGrid` a pantalla completa (sin `HighlightEditorBottomBar`).

- [ ] **Step 3:** Paso 2 — layout Instagram:
  - Círculo ~96pt centrado con portada
  - Botón texto `highlightedStories.editCover` debajo
  - `TextField` nombre con límite visual (truncar preview en rail si >15 chars — solo UI)
  - Trailing nav: `highlightedStories.add` / `common.done`
  - Leading: `common.back` → vuelve a paso 1 conservando selección

- [ ] **Step 4:** `HighlightCoverPickerSheet` — añadir fila horizontal de thumbnails (estilo IG) además del grid actual; galería custom cover = **opcional v2** (requiere upload).

- [ ] **Step 5:** Eliminar o deprecar `CreateHighlightView.swift` (wrapper que delega al flow).

---

## Task 3: Editar — `HighlightEditFlowView`

**Files:**
- Create: `HighlightEditFlowView.swift` (o mismo `HighlightCreateFlowView` con modo `.edit(highlight)`)
- Modify: `EditHighlightView.swift` → deprecar

- [ ] **Step 1:** Al abrir edit: precargar `title`, `coverStory`, `selectedStories` desde `highlight.storyIds`.

- [ ] **Step 2:** Mismo wizard; paso 1 muestra checkmarks en stories ya incluidas.

- [ ] **Step 3:** Paso 2 CTA = `common.save`; menú `...` con `common.delete` (mantener de Fase C).

- [ ] **Step 4:** Tras guardar/borrar → dismiss + `loadHighlights` en rail.

---

## Task 4: Presentación y perfil

**Files:**
- Modify: `ProfileHighlightsView.swift`
- Modify: `HighlightPresentationCoordinator.swift`

- [ ] **Step 1:** Cambiar sheet create/edit a `fullScreenCover` (o sheet sólido sin glass — decisión brainstorming).

- [ ] **Step 2:** Botón "+" del rail: etiqueta `highlightedStories.new` bajo el círculo (ya existe); opcional renombrar a "Nuevo" estilo IG.

- [ ] **Step 3:** Mantener `closeAll()` / delays si se encadena viewer tras edit.

---

## Task 5: i18n

**Files:** 8× `Localizable.strings`

Nuevas claves:

| Key | EN | ES |
|-----|----|----|
| `highlightedStories.next` | Next | Siguiente |
| `highlightedStories.add` | Add | Añadir |
| `highlightedStories.nameAndCover` | Name your highlight | Nombra tu destacada |
| `highlightedStories.selectFromArchive` | Select stories | Seleccionar historias |
| `highlightedStories.archiveEmpty` | No archived stories yet | Aún no tienes historias en el archivo |
| `highlightedStories.titleMaxHint` | Shorter names look better on your profile | Los nombres cortos se ven mejor en el perfil |

- [ ] Añadir en en, es, ca, de, fr, it, pt-BR, pt-PT.

---

## Task 6 (opcional / v2): Atajo desde story activa

**Files:**
- Modify: `StoriesView` / chrome de story viewer

- [ ] Botón "Destacar" en story propia → sheet mini: lista highlights existentes + "Nueva" → abre flow paso 2 directo con esa story preseleccionada.

- [ ] No bloqueante para C2 v1.

---

## Wireframes ASCII (referencia rápida)

### Paso 1 — Selección

```
┌─────────────────────────────────┐
│  ✕          Nueva        Siguiente │
├─────────────────────────────────┤
│  ┌──┐ ┌──┐ ┌──┐               │
│  │✓ │ │  │ │✓ │   grid 3 col  │
│  └──┘ └──┘ └──┘               │
│  ┌──┐ ┌──┐ ┌──┐               │
│  │  │ │✓ │ │  │               │
│  └──┘ └──┘ └──┘               │
│         ... scroll            │
└─────────────────────────────────┘
```

### Paso 2 — Nombre y portada

```
┌─────────────────────────────────┐
│  ← Atrás              Añadir ✓  │
├─────────────────────────────────┤
│                                 │
│           ┌────────┐            │
│           │  cover │  96pt       │
│           └────────┘            │
│         Editar portada          │
│                                 │
│   ┌─────────────────────────┐   │
│   │ Verano 2024             │   │
│   └─────────────────────────┘   │
│   Los nombres cortos se ven...  │
│                                 │
└─────────────────────────────────┘
```

---

## Verificación de fase

- [ ] Perfil → + → paso 1 solo grid → Siguiente deshabilitado con 0 selección
- [ ] Paso 2 → portada por defecto = primera story seleccionada
- [ ] Editar portada → elegir otra story del set
- [ ] Añadir → highlight en rail sin recargar manual
- [ ] Editar highlight existente → wizard con preselección
- [ ] Solo stories **archivadas** (expiradas) en el picker
- [ ] Cancelar en paso 1 o 2 cierra sin guardar
- [ ] Atrás en paso 2 conserva selección del paso 1

**Handoff:** PR `phase-c2/instagram-highlights-flow`. Pedir feedback visual comparando lado a lado con Instagram en dispositivo.

---

## Estimación

| Task | Esfuerzo |
|------|----------|
| 1 Archivo paginado | 0.5 día |
| 2 Wizard create | 1.5–2 días |
| 3 Wizard edit | 1 día |
| 4 Presentación perfil | 0.5 día |
| 5 i18n | 0.5 día |
| 6 Atajo story (v2) | 1–2 días |

**Total v1:** ~4–5 días. Compatible en paralelo con Fase B.
