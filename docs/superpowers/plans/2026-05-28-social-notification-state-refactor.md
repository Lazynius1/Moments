# Social Notifications Refactor Plan

## Goal

Dejar el sistema social de notificaciones (`follow`, `unfollow`, `follow request`, `request accepted`, `mutual`) funcionando con una separación clara entre:

- estado real de la relación
- estado activo de notificación social
- documentos visibles del inbox

La idea es que `notifications` deje de ser fuente de verdad y pase a ser solo una proyección visual.

---

## Current Problems

- [x] `newFollower` podía acumular docs legacy y romper el agregado `X y N más`.
- [x] `mutualConnection` podía quedarse zombie al romperse la relación.
- [x] `followRequest` y `requestAccepted` no estaban completamente alineadas con el estado real.
- [x] Se han introducido ids estables y cleanup básico.
- [ ] El sistema sigue dependiendo demasiado de `notifications` para decisiones que deberían salir del grafo social.
- [ ] No existe todavía una capa explícita de `active social state`.

---

## Target Model

### 1. Relationship state

Fuente de verdad:

- `users/{userId}/followers/{followerId}`
- `users/{userId}/following/{followingId}`
- `users/{userId}/receivedFollowRequests/{requestId}`
- `users/{userId}/sentFollowRequests/{requestId}`

### 2. Active social notification state

Estado derivado, reconciliable y barato de consultar:

- `users/{userId}/activeFollowNotifications/{senderId}`
- `users/{userId}/activeMutualConnections/{otherUserId}`
- opcionalmente, estado derivado para requests si hiciera falta

### 3. Visible notifications

Inbox visible para la app:

- `users/{userId}/notifications/{notificationId}`

Esto ya no decide la verdad del sistema; solo muestra eventos o estados proyectados.

---

## Design Decisions

- [ ] `newFollower` debe representar un follow activo reciente, no un historial infinito.
- [ ] `mutualConnection` debe existir solo mientras la mutual siga viva, o marcarse como no pendiente al romperse.
- [ ] `followRequest` debe reconciliarse siempre desde `receivedFollowRequests`.
- [ ] `requestAccepted` puede seguir siendo un evento histórico independiente.
- [ ] El agregado tipo `X y N más` debe salir del estado activo, no del inbox.

---

## Phase 1: Model Active Social State

### Follow state

- [ ] Definir el schema de `activeFollowNotifications/{senderId}`
- [ ] Campos mínimos:
  - [ ] `senderId`
  - [ ] `senderUsername`
  - [ ] `senderProfileImage`
  - [ ] `createdAt`
  - [ ] `updatedAt`
  - [ ] `kind = "newFollower"`

### Mutual state

- [ ] Definir el schema de `activeMutualConnections/{otherUserId}`
- [ ] Campos mínimos:
  - [ ] `otherUserId`
  - [ ] `username`
  - [ ] `profileImage`
  - [ ] `activatedAt`
  - [ ] `updatedAt`
  - [ ] `source` (`follow` / `requestAccepted`)

### Requests

- [ ] Decidir si `followRequest` necesita una capa activa propia o si `receivedFollowRequests` ya basta como fuente de verdad

---

## Phase 2: Rebuild Server Flows

### `onFollowerAdded`

- [ ] Crear o actualizar `activeFollowNotifications/{senderId}`
- [ ] Si el follow crea mutual:
  - [ ] borrar follows redundantes activos para ese par si ya no tienen sentido
  - [ ] crear / actualizar `activeMutualConnections` en ambos lados
  - [ ] reconciliar inbox visible

### `onFollowerRemoved`

- [ ] Borrar `activeFollowNotifications/{senderId}`
- [ ] Borrar `activeMutualConnections/{otherUserId}` donde aplique
- [ ] Reconciliar `newFollower` y `mutualConnection` visibles

### `onFollowRequestReceived`

- [ ] Mantener `receivedFollowRequests` como fuente de verdad
- [ ] Crear / actualizar notificación visible estable

### `onFollowRequestRemoved`

- [ ] Limpiar notificación visible
- [ ] Limpiar cualquier estado activo derivado si se añade

### `request accepted`

- [ ] Enviar `requestAccepted`
- [ ] Crear follow real
- [ ] Si hay mutual, crear `activeMutualConnections`
- [ ] Asegurar que no se salta la reconciliación mutual

---

## Phase 3: Make Push Aggregation Read from Active State

- [ ] Reemplazar `getPendingFollowerCount(...)` para que lea desde `activeFollowNotifications`
- [ ] Dejar de usar `notifications` como base de conteo para follows
- [ ] Revisar si `mutualConnection` necesita agregado o siempre una fila por persona
- [ ] Definir ventana temporal si el agregado debe ser “reciente” y no infinito

---

## Phase 4: Inbox Projection Rules

- [ ] Mantener ids estables en `notifications`
  - [ ] `newFollower_{senderId}`
  - [ ] `mutualConnection_{otherUserId}`
  - [ ] `followRequest_{senderId}`
  - [ ] `requestAccepted_{accepterId}`
- [ ] Decidir qué tipos son:
  - [ ] activos y reconciliables
  - [ ] históricos
  - [ ] agregables

### Proposed policy

- [ ] `newFollower`: activo + reconciliable
- [ ] `mutualConnection`: activo + reconciliable
- [ ] `followRequest`: activo + reconciliable
- [ ] `requestAccepted`: histórico

---

## Phase 5: Migration and Cleanup

- [ ] Escribir script de backfill para `activeFollowNotifications`
- [ ] Escribir script de backfill para `activeMutualConnections`
- [ ] Deduplicar `notifications` legacy de tipo:
  - [ ] `newFollower`
  - [ ] `mutualConnection`
  - [ ] `followRequest`
- [ ] Eliminar docs visibles cuyo estado real ya no exista

---

## Phase 6: iOS Alignment

- [ ] Revisar `NotificationsView` para asegurar que social notifications siguen agrupando una fila por sender cuando toque
- [ ] Revisar `NotificationService` y badge counts para que lean correctamente el nuevo estado visible
- [ ] Revisar `FirestoreService` en:
  - [ ] aceptar request
  - [ ] rechazar request
  - [ ] unfollow
- [ ] Confirmar que la UI no depende accidentalmente de duplicados legacy

---

## QA Checklist

### Follow / unfollow

- [ ] usuario A sigue a B
- [ ] B recibe `newFollower`
- [ ] A deja de seguir a B
- [ ] `newFollower` activa desaparece o deja de estar pendiente
- [ ] A vuelve a seguir a B
- [ ] no aparece duplicado ni `X y N más` inflado

### Mutuals

- [ ] A sigue a B
- [ ] B sigue a A
- [ ] ambos reciben `mutualConnection`
- [ ] A deja de seguir a B
- [ ] la mutual desaparece o deja de estar activa en ambos lados

### Private follow requests

- [ ] A envía request a B privado
- [ ] B recibe `followRequest`
- [ ] B rechaza
- [ ] desaparece la request visible
- [ ] A vuelve a enviar
- [ ] no aparecen duplicados

### Request accepted

- [ ] A ya seguía a B
- [ ] B acepta la request de A
- [ ] A recibe `requestAccepted`
- [ ] si ahora existe mutual, ambos reciben / mantienen `mutualConnection`

### Stress

- [ ] Apple Review follow/unfollow/follow muchas veces
- [ ] no se infla el agregado
- [ ] no quedan mutuals zombies

---

## Success Criteria

- [ ] `notifications` deja de ser fuente de verdad para follows/mutuals/requests
- [ ] el agregado de followers sale de estado activo real
- [ ] `mutualConnection` ya no sobrevive cuando la mutual se rompe
- [ ] no aparecen duplicados por re-follow o request repetida
- [ ] el sistema queda más cerca del comportamiento de Instagram, manteniendo la capa propia de mutuals

---

## Notes

- Este plan es mejor a largo plazo que seguir optimizando `getPendingFollowerCount(...)` alrededor del inbox.
- Si durante la implementación aparece demasiada complejidad, se puede ejecutar primero:
  - modelado de `activeFollowNotifications`
  - modelado de `activeMutualConnections`
  - y luego migrar el push
- La prioridad conceptual es:
  1. relación real
  2. estado activo derivado
  3. inbox visible
