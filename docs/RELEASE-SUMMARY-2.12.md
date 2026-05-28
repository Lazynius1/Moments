# Moments 2.12 — Resumen de Cambios y Notas del Parche

> **Versión sugerida:** `2.12.0` (build 1)
>
> La versión actual en `project.pbxproj` sigue siendo `MARKETING_VERSION = 2.11.0`.
> Se recomienda actualizar a `2.12.0` antes del envío a App Store.

---

## Estadísticas generales

| Métrica | Valor |
|---|---|
| Commits desde 2.11 release | 67 |
| Archivos tocados | 452 |
| Líneas añadidas | ~15 591 |
| Líneas eliminadas | ~8 223 |
| Idiomas de localización actualizados | 8 (es, en, ca, de, fr, it, pt-BR, pt-PT) |
| Nuevos archivos de documentación | 4 |

---

## Áreas de cambio principales

### 1. Renombrado del proyecto: Glowsy → Moments

El proyecto completo ha sido renombrado de **Glowsy** a **Moments** (`68a501e`). Esto afecta a:

- Directorio principal del target (`Glowsy/` → `Moments/`)
- Archivos del proyecto Xcode (`.xcodeproj`, esquemas, módulos de IntelliJ/`.idea`)
- Entry point de la app (`GlowsyApp.swift` → `MomentsApp.swift`)
- Widget extension bundle
- Todos los archivos de localización

### 2. Historias y creación (Story Editor)

- **Canvas unificado** para cámara, editor y visor de historias (`79b3661`)
- **Fondos transformables** con paleta de colores automática basada en el contenido (`91db8f1`, `caccc6a`)
- **Stickers rediseñados**: nuevas variantes visuales, mejor escalado, theming y respuestas interactivas (`2f2e374`, `24d2c0d`, `7f5fc9c`, `58ad0c5`, `a4f7342`)
- **Editor de dibujo** mejorado con overlay refinado
- Soporte para **videos largos** en historias (`8da0737`)
- Nuevo componente `EditableImageView` (528 líneas) y `StoryBackgroundPresets`
- Flujos de subida más estables con recuperación de errores (`ca9d48f`, `edc5a45`)
- Nuevo sticker tool SVG asset (`MomentsStickerTool`)

### 3. Modo Incógnito (nueva feature)

Feature completamente nueva (`bee080d`) que permite navegar historias, perfiles y chats de forma privada:

- `IncognitoModeService` — servicio central (414 líneas)
- `IncognitoModeSheet` — UI de activación (347 líneas)
- `IncognitoGlobalOverlay` — overlay visual persistente (214 líneas)
- `IncognitoLiveActivity` — Live Activity con Dynamic Island (201 líneas)
- `IncognitoActivityAttributes` — modelo de Activity Attributes
- `PauseIncognitoIntent` — App Intent para pausar desde fuera de la app (43 líneas)
- Nuevo asset gráfico `IncognitoAppGlyph`

### 4. Reels y visualización

- Vista de reels renovada con experiencia más inmersiva (`b0f69ed`): ~554 líneas modificadas en `Reels.swift`
- Captions, controles y comentarios refinados
- Render de video con efecto glass optimizado (`41a16cd`)
- Evitar recompresión de videos editados (`510ff5b`)

### 5. Refactorización masiva de arquitectura

Gran campaña de extracción de componentes para modularizar el código (~40 commits):

- **Creator**: cámara, captura, filtros, crop, media picker, galería, drawing tools, overlays, text editor, caption details
- **Feed**: view model, moment components, upload progress, notification routing, presentations
- **Chat/Messaging**: bubble views, cluster media, chrome, input, options menu, media views, view model
- **Stories**: story ring coordinator, audience selector, sticker picker, drawing components, editor support

### 6. Notificaciones y menciones

- Menciones en comentarios y notificaciones mejoradas (`937817f`)
- Routing de notificaciones estabilizado (`1df41f5`)
- `NotificationsView` ampliada significativamente (+473 líneas)
- `NotificationNavigationService` refactorizado (+136 líneas)
- Nuevo `CommentMentionSearchOverlay` (227 líneas)
- Nuevo `FeedNotificationRoutingModifier`
- Documentación: `notification-contract.md` y documentación de sistema de menciones

### 7. Backend / Firebase

- `functions/index.js` ampliado significativamente (+1 226 líneas → cloud functions nuevas/mejoradas)
- `firestore.indexes.json` creado con 642 líneas de índices compuestos
- Nueva dependencia en `functions/package.json`

### 8. Servicios y datos

- `FirestoreCommentsRepository` ampliado (+417 líneas)
- `FirestoreService` refactorizado (+104 líneas)
- Repositorios de dominio extraídos del servicio monolítico Firestore (`b984721`)
- `AuthService` actualizado (+265 líneas)
- `ChatService` refactorizado (+724 líneas de cambios)
- `EncryptionService`, `MessageRequestService`, `OnlineStatusService` mejorados
- `PrivacyService` con nuevas capacidades
- `MediaModerationService` refinado

### 9. Localización

- 8 idiomas actualizados con +1 316 líneas nuevas de strings
- Nuevos strings para: incógnito, stickers, menciones, notificaciones, reels, y más
- Widget Extension localizado en los 8 idiomas

### 10. Warnings y calidad de código

- Warnings de Xcode reducidos a lo largo del proyecto (`31421aa`)
- Limpieza general de imports, tipos y convenciones

---

## Archivos clave nuevos

| Archivo | Líneas | Descripción |
|---|---|---|
| `Moments/Services/Incognito/IncognitoModeService.swift` | 414 | Servicio central de modo incógnito |
| `Moments/Views/Profile/Incognito/IncognitoModeSheet.swift` | 347 | UI de activación incógnito |
| `Moments/Views/Profile/Incognito/IncognitoGlobalOverlay.swift` | 214 | Overlay visual global |
| `GlowsyWidgetExtension/IncognitoLiveActivity.swift` | 201 | Live Activity + Dynamic Island |
| `Shared/PauseIncognitoIntent.swift` | 43 | App Intent para pausar incógnito |
| `Shared/IncognitoActivityAttributes.swift` | 20 | Modelo para Live Activities |
| `Moments/Views/Components/InteractiveStickerSharedViews.swift` | 2 010 | Vistas compartidas de stickers interactivos |
| `Moments/Views/Creator/Components/EditableImageView.swift` | 528 | Editor de imagen transformable |
| `Moments/Views/Creator/Components/StoryBackgroundPresets.swift` | 42 | Presets de fondos para historias |
| `Moments/Views/comments/CommentMentionSearchOverlay.swift` | 227 | Overlay de búsqueda de menciones |
| `docs/notifications/notification-contract.md` | 43 | Contrato de notificaciones |
| `firestore.indexes.json` | 642 | Índices compuestos de Firestore |

---

## Notas del Parche (Patch Notes) — Propuesta

### Español (App Store)

**Novedades en Moments 2.12**

🎨 **Historias reinventadas** — Crea historias con un canvas más libre: mueve, escala y rota fotos y videos con fondos automáticos basados en los colores de tu contenido.

✨ **Stickers rediseñados** — Stickers más pulidos con nuevas variantes visuales, interacciones mejoradas y respuestas más fluidas en preguntas, encuestas y quizzes.

🕵️ **Modo Incógnito** — Navega historias, perfiles y chats con más privacidad. Incluye Live Activity para que siempre sepas cuánto tiempo te queda.

🎬 **Reels renovados** — Experiencia de visualización más inmersiva, limpia y moderna con captions, controles y comentarios refinados.

🔔 **Menciones en comentarios** — Menciona a otros usuarios en comentarios y recibe notificaciones más claras.

🛠 **Fiabilidad** — Subidas más estables, mejor reproducción de video, transiciones más suaves, reducción de warnings y correcciones de estabilidad general.

### English (App Store)

**What's New in Moments 2.12**

🎨 **Reimagined Stories** — Create stories with a freer canvas: move, scale, and rotate photos and videos with automatic backgrounds based on your content's colors.

✨ **Redesigned Stickers** — More polished stickers with new visual variants, improved interactions, and smoother responses for questions, polls, and quizzes.

🕵️ **Incognito Mode** — Browse stories, profiles, and chats with more privacy. Includes a Live Activity so you always know how much time you have left.

🎬 **Refreshed Reels** — A more immersive, cleaner, and modern viewing experience with refined captions, controls, and comments.

🔔 **Comment Mentions** — Mention other users in comments and receive clearer notifications.

🛠 **Reliability** — More stable uploads, better video playback, smoother transitions, reduced warnings, and general stability fixes.

---

## Versión sugerida

| Campo | Valor actual | Valor sugerido |
|---|---|---|
| `MARKETING_VERSION` | `2.11.0` | **`2.12.0`** |
| `CURRENT_PROJECT_VERSION` | `1` | `1` |

**Razonamiento:** Los cambios incluyen features nuevas sustanciales (modo incógnito, stickers rediseñados, reels renovados), una refactorización arquitectónica profunda, renombrado del proyecto, y ampliación significativa del backend. Esto justifica un incremento de versión minor completo (2.11 → 2.12), consistente con el naming ya presente en los commits ("Start 2.12", "Finalize Moments 2.12 release polish") y el archivo `release-notes-2.12.md` existente.

No se recomienda 2.12.1 o un patch ya que no hay una versión 2.12.0 publicada previamente. Es la primera release de la serie 2.12.
