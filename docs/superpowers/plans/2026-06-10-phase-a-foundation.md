# Fase A — Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` o `superpowers:executing-plans`

**Goal:** Errores visibles y localizados, feed que no parece roto al cargar, menos duplicación en Firestore.

**Architecture:** Componentes shared pequeños + cambios acotados en Feed/Explore. Sin refactors grandes.

**Tech Stack:** SwiftUI, Localizable.strings (8 locales)

**Depends on:** Nada. Primera fase.

---

## Task 1: AppErrorBanner reutilizable

**Files:**
- Create: `Moments/Views/Shared/AppErrorBanner.swift`
- Modify: `Moments/Views/Explore/ExploreView.swift`
- Modify: `Moments/Views/Feed/Core/FeedView.swift`

- [ ] **Step 1:** Crear componente:

```swift
struct AppErrorBanner: View {
    let message: String
    var retryTitle: String = NSLocalizedString("maps.error.retry", comment: "")
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.custom("Poppins-Medium", size: 12))
                .lineLimit(2)
            Spacer(minLength: 0)
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(.custom("Poppins-SemiBold", size: 11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }
}
```

- [ ] **Step 2:** Usar en `ExploreView` donde ya hay banners ad hoc.

- [ ] **Step 3:** En `FeedView`, overlay superior cuando `viewModel.errorMessage != nil`:

```swift
if let error = viewModel.errorMessage {
    AppErrorBanner(message: error) {
        viewModel.refreshFeed()
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
}
```

- [ ] **Step 4:** Commit `feat: shared AppErrorBanner for feed and explore`

---

## Task 2: i18n de errores hardcoded

**Files:**
- Modify: `Moments/Views/Explore/ExploreViewModel.swift` (o ruta real del VM)
- Modify: `Moments/Views/Feed/Sharing/share.swift`
- Modify: `Moments/Views/SidebarMenuView.swift` (si existe)
- Modify: `Moments/en.lproj/Localizable.strings` + `es.lproj` + 6 restantes

- [ ] **Step 1:** Grep strings españoles en ViewModels:

```bash
rg '"[A-ZÁÉÍÓÚÑ][^"]*"' Moments/Moments --glob '*ViewModel*.swift' | rg -v NSLocalizedString
```

- [ ] **Step 2:** Por cada string encontrada, añadir clave `errors.*` en los 8 `Localizable.strings`.

- [ ] **Step 3:** Reemplazar con `NSLocalizedString("errors.authRequired", comment: "")` etc.

- [ ] **Step 4:** Commit `i18n: localize ViewModel error strings`

---

## Task 3: Skeleton de posts en feed

**Files:**
- Create: `Moments/Views/Feed/Core/Sections/FeedPostSkeletonView.swift`
- Modify: `Moments/Views/Feed/Core/FeedView.swift`

- [ ] **Step 1:** Crear skeleton que imite altura de `FeedMomentCard` (avatar + rectángulo media + 2 líneas texto) con `.shimmering()` ya usado en perfil.

- [ ] **Step 2:** En lista de feed, cuando `viewModel.isLoading && viewModel.moments.isEmpty`, mostrar 3–5 skeletons en lugar de lista vacía.

- [ ] **Step 3:** Verificar en simulador: pull-to-refresh y cold start muestran skeleton.

- [ ] **Step 4:** Commit `feat: feed post skeleton while loading`

---

## Task 4: FirestoreService.shared audit

**Files:**
- Modify: vistas que instancian `FirestoreService()` — prioridad: `FeedView`, `ExploreViewModel`, `ProfileHighlightsViewModel`, `EchoService`

- [ ] **Step 1:** Grep:

```bash
rg 'FirestoreService\(\)' Moments/Moments --glob '*.swift'
```

- [ ] **Step 2:** Reemplazar por `FirestoreService.shared` (o inyección desde environment si el archivo ya usa DI).

- [ ] **Step 3:** Verificar que no se duplican listeners al abrir Feed + Profile.

- [ ] **Step 4:** Commit `refactor: use FirestoreService.shared in top-level views`

---

## Task 5: Deep links muertos en MomentsApp

**Files:**
- Modify: `Moments/MomentsApp.swift`
- Modify: `Moments/Notifications/Services/NotificationNavigationService.swift`

- [ ] **Step 1:** Localizar handlers vacíos `NavigateToMoment`, `NavigateToConversation` (~líneas 126–138).

- [ ] **Step 2:** Opción A: delegar a `NotificationNavigationService` existente. Opción B: eliminar observers si no hay emisor activo.

- [ ] **Step 3:** Grep emisores de esas notificaciones; si hay emisores, implementar handler mínimo.

- [ ] **Step 4:** Commit `fix: wire or remove dead navigation handlers in MomentsApp`

---

## Verificación de fase

- [ ] `xcodebuild build -scheme Moments` — BUILD SUCCEEDED
- [ ] Feed muestra skeleton + error banner (simular offline en simulador)
- [ ] Explore errores en idioma del sistema

**Handoff:** Abrir PR `phase-a/foundation` → `requesting-code-review` → merge.
