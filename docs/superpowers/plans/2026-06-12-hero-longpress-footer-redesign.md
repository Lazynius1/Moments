# Hero long-press — info abajo + aspect ratio adaptativo

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rediseñar el peek del long-press en el grid de perfil: media arriba (altura según aspect ratio, máx 4:3), info compacta abajo (identidad Moments, no copia de Instagram), y animación de cierre sin jank del `liquidGlass`.

**Architecture:** Separar el card en `VStack(media + footer)` con altura total calculada en `ProfileGridHeroLayout`. El footer usa material opaco (sin `liquidGlass`); solo el menú contextual mantiene glass. El footer se desvanece antes que el media durante el dismiss mediante una curva de opacidad atada a `peekProgress`.

**Tech Stack:** SwiftUI, iOS 26 `glassEffect` (solo menú), `ProfileGridHeroTransitionCoordinator`, UIKit long-press overlay existente.

**Archivos principales:**
- `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift` — layout, frames, opacidad chrome
- `Moments/Views/Profile/Core/Sections/ProfileGridMomentMenu.swift` — `ProfileGridHeroCard` UI
- `Moments/Extensions/View+LiquidGlass.swift` — sin cambios obligatorios

---

## Diseño visual (referencia)

```
┌─────────────────────────┐
│                         │
│   MEDIA (ratio real)    │  esquinas superiores redondeadas
│   máx vertical 4:3      │
│                         │
├─────────────────────────┤
│ avatar · user · lugar   │  footer fijo ~56pt, opaco
│              [audience]   │  esquinas inferiores redondeadas
└─────────────────────────┘
           ↓ 14pt
      [ menú glass ]
```

**Diferenciador vs Instagram:** info abajo, no arriba.

---

## Task 1: Nuevas constantes y fórmula de altura

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift`

- [ ] **Step 1:** Añadir constantes en `ProfileGridHeroLayout`:

```swift
static let peekFooterHeight: CGFloat = 56
/// Mínimo width/height → retrato más alto permitido (3:4 → altura = width × 4/3)
static let peekMinWidthOverHeight: CGFloat = 3.0 / 4.0
/// Máximo width/height → landscape más bajo (16:9)
static let peekMaxWidthOverHeight: CGFloat = 16.0 / 9.0
```

- [ ] **Step 2:** Reemplazar `mediaHeight`:

```swift
static func mediaHeight(width: CGFloat, aspectRatio: String?) -> CGFloat {
    let ratio = parsedAspectRatio(aspectRatio) // width / height
    let clamped = min(max(ratio, peekMinWidthOverHeight), peekMaxWidthOverHeight)
    return width / clamped
}

static func peekCardHeight(width: CGFloat, aspectRatio: String?) -> CGFloat {
    mediaHeight(width: width, aspectRatio: aspectRatio) + peekFooterHeight
}
```

- [ ] **Step 3:** Verificar casos manualmente (anotar en PR):

| Aspect ratio | width 320 | mediaHeight esperado |
|---|---|---|
| 16:9 (1.78) | 320 | ~180 |
| 1:1 (1.0) | 320 | 320 |
| 3:4 (0.75) | 320 | ~427 |
| 9:16 (0.5625) | 320 | ~427 (cap 4:3) |

---

## Task 2: Actualizar `peekCardFrame` y posicionamiento del menú

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift` (`peekCardFrame`, `heroPresentation`)

- [ ] **Step 1:** En `peekCardFrame`, usar altura total del card:

```swift
let width = cardWidth(for: containerSize.width)
let height = peekCardHeight(width: width, aspectRatio: moment.aspectRatio)
```

- [ ] **Step 2:** Confirmar que `menuStack` en `ProfileGridHeroDetailLayer` sigue usando `heroFrame.maxY` — no requiere cambio si el frame del hero ya incluye el footer.

- [ ] **Step 3:** En `heroPresentation` caso `.menuPeek`, el `peekFrame` de `peekCardFrame` ya refleja altura completa; verificar que `ProfileGridFlyingHeroShell` no recorta el footer.

---

## Task 3: Opacidad del chrome desacoplada en dismiss

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift`

- [ ] **Step 1:** Añadir computed property en `ProfileGridHeroTransitionCoordinator`:

```swift
/// Footer/info: se desvanece antes que el media al cerrar (evita glass/jank).
var heroChromeRevealOpacity: CGFloat {
    switch phase {
    case .menuPeek:
        return min(1, peekProgress / 0.38)
    case .expanding:
        return detailContentOpacity < 0.08 ? 1 : 0
    default:
        return 1
    }
}
```

- [ ] **Step 2:** Extender environment (junto a `ProfileHeroShowsChromeKey`):

```swift
private struct ProfileHeroChromeOpacityKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var profileHeroChromeOpacity: CGFloat {
        get { self[ProfileHeroChromeOpacityKey.self] }
        set { self[ProfileHeroChromeOpacityKey.self] = newValue }
    }
}
```

- [ ] **Step 3:** En `ProfileGridHeroDetailLayer`, además de `profileHeroShowsChrome`:

```swift
.environment(\.profileHeroChromeOpacity, coordinator.heroChromeRevealOpacity)
```

---

## Task 4: Refactor `ProfileGridHeroCard` — media arriba, footer abajo

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridMomentMenu.swift`

- [ ] **Step 1:** Renombrar/reemplazar constantes de sizing:

```swift
private let profileGridHeroFooterHeight: CGFloat = ProfileGridHeroLayout.peekFooterHeight
private let profileGridHeroFooterAvatarSize: CGFloat = 36
private let profileGridHeroFooterHorizontalPadding: CGFloat = 12
```

Eliminar: `profileGridHeroTopBleed`, `profileGridHeroCapsuleHeight`, `profileGridHeroCapsuleContentYOffset`, `heroTopGlassExtension`, `heroCapsuleShape` (top-only).

- [ ] **Step 2:** Reemplazar `body` por estructura VStack:

```swift
var body: some View {
    VStack(spacing: 0) {
        heroMediaSection
        if showsChrome {
            heroFooterBar
                .opacity(profileHeroChromeOpacity)
        }
    }
    .frame(width: width, height: mediaHeight + (showsChrome ? profileGridHeroFooterHeight : 0))
    .clipShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
    .onTapGesture(perform: onOpenMoment)
    .overlay(alignment: .topTrailing) { videoDurationBadge }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 16, x: 0, y: 8)
}
```

- [ ] **Step 3:** `heroMediaSection` — media limpio, sin gradiente superior ni bleed:

```swift
private var heroMediaSection: some View {
    heroMedia
        .frame(width: width, height: mediaHeight)
        .clipped()
}
```

Opcional: gradiente sutil solo en el borde inferior del media (8–12% altura) para transición visual hacia el footer.

- [ ] **Step 4:** `heroFooterBar` — opaco, sin `liquidGlass`:

```swift
@Environment(\.profileHeroChromeOpacity) private var profileHeroChromeOpacity

private var heroFooterBar: some View {
    HStack(alignment: .center, spacing: 10) {
        AsyncProfileImageView(userId: moment.authorId)
            .frame(width: profileGridHeroFooterAvatarSize, height: profileGridHeroFooterAvatarSize)
            .clipShape(Circle())

        VStack(alignment: .leading, spacing: 2) {
            Text(moment.username)
                .font(.custom("Poppins-SemiBold", size: 13))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
            if let locationText {
                Text(locationText)
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
        }

        Spacer(minLength: 0)

        ActivityGridAudienceIcon(audience: resolvedAudience)
            .accessibilityLabel(resolvedAudience.title)
    }
    .padding(.horizontal, profileGridHeroFooterHorizontalPadding)
    .frame(height: profileGridHeroFooterHeight)
    .frame(maxWidth: .infinity)
    .background(footerBackground)
}

private var footerBackground: some View {
    Group {
        if colorScheme == .dark {
            Color(hex: "1C1C1E")
        } else {
            Color(hex: "FAF9F6")
        }
    }
}
```

- [ ] **Step 5:** Reposicionar badge de vídeo — overlay en `heroMediaSection`, padding `.top 10` / `.trailing 10` (ya no depende de altura de cápsula superior).

---

## Task 5: Ajustar altura del flying hero en presentación

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridMomentMenu.swift`
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift`

- [ ] **Step 1:** `ProfileGridHeroCard` debe exponer altura total coherente con layout:

```swift
var totalCardHeight: CGFloat {
    mediaHeight + (showsChrome ? ProfileGridHeroLayout.peekFooterHeight : 0)
}
```

- [ ] **Step 2:** En `ProfileGridFlyingHeroShell` / `heroPresentation`, el `presentation.frame.height` para `.menuPeek` debe coincidir con `peekCardHeight` (Task 2). Probar long-press en foto 16:9 y 3:4: el menú debe quedar pegado bajo el card sin solaparse.

---

## Task 6: Pulido de animación dismiss

**Files:**
- Modify: `Moments/Views/Profile/Core/Sections/ProfileGridHeroTransition.swift` (`dismissMenu`, `openMenu`)

- [ ] **Step 1:** Mantener `dismissSpring` en `peekProgress`, `scrimOpacity`, `menuOpacity` — el footer ya fadea antes vía `heroChromeRevealOpacity`.

- [ ] **Step 2:** Si el footer aún parpadea con glass residual, buscar y eliminar cualquier `.liquidGlass` restante en `ProfileGridHeroCard` (solo debe quedar en `actionsMenu` / `pinConfirmPanel`).

- [ ] **Step 3:** Probar en **iOS 26** dispositivo real:
  - Long-press → peek
  - Tap scrim → dismiss (footer desaparece antes que media)
  - Tap card → abre detalle zoom
  - Swipe back desde detalle → grid OK (regresión zoom iOS 26)

---

## Task 7: QA manual — matriz de pruebas

**Files:** ninguno (verificación)

- [ ] **Perfil propio** — grid 3 columnas, momento foto portrait, landscape, vídeo, texto-only
- [ ] **Perfil público** — mismo long-press si aplica `ProfileGridHeroDetailLayer`
- [ ] **Pin confirm** — panel no tapa footer; posición menú correcta
- [ ] **Dark / Light** — footer opaco legible en ambos
- [ ] **Reel 9:16** — altura capada a 4:3 (no infinita)
- [ ] **Landscape 16:9** — card baja, usa poco vertical
- [ ] **Regresión** — menú contextual acciones (pin, edit, delete) funcionan

---

## Fuera de alcance (YAGNI)

- No cambiar ancho máximo del card (350) en esta iteración
- No añadir `fullScreenCover` como workaround zoom iOS 26
- No mover el menú contextual a otra posición (sigue debajo del card)
- No tocar `ModernMomentDetailView` carousel

---

## Orden de commits sugerido

1. `refactor(profile): adaptive peek media height with 4:3 cap`
2. `feat(profile): hero peek footer bar below media`
3. `fix(profile): decouple chrome fade on hero dismiss`

---

## Spec self-review

| Requisito | Task |
|---|---|
| Info abajo (no Instagram) | Task 4 |
| Aspect ratio adaptativo | Task 1 |
| Máx 4:3 vertical | Task 1 (`peekMinWidthOverHeight`) |
| Sin liquidGlass en info peek | Task 4 |
| Dismiss más limpio | Task 3, 6 |
| Menú glass intacto | Task 6 (verificar no regresión) |
| Menú posicionado bajo card | Task 2, 5 |

Sin placeholders TBD.
