# Group chat — huecos y cómo montarlos

Updated: 8 September 2026.

Fuente de verdad: iOS. Android se porta 1:1 después de cada trozo. Copy nueva: `scripts/sync-group-chat-localizations.py` (16 locales). Backend solo `manageGroup` / `sendGroupMessage` / `onGroupMessageAdded` + rules, sin colecciones inventadas.

**Fuera de esta lista (ya está):** “Leído por” vive en el context menu del mensaje propio (`groupReadReceipts` / `GroupReadReceiptsRow`). No va en el hilo ni en el header.

**No copiar de messengers grandes:** foros, bots, slow mode, grupos públicos, llamadas, vanish en grupo, nicknames.

Orden de implementación (impacto vs riesgo):

1. Typing en el header (solo UI)
2. Buscar miembros (solo UI)
3. Menciones
4. Descripción
5. Solo admins envían
6. Silenciar un rato
7. Disolver
8. Reportar grupo
9. Enlace con aprobación

Cada trozo: iOS → Android → functions/rules si toca servidor → locales → deploy puntual.

---

## 1. Menciones de miembros

### Qué se nota
El bubble ya pinta `@usuario` y abre perfil. No hay picker al escribir `@`. El servidor no avisa al mencionado (el push de grupo es genérico: `groups.notification`).

### Qué hay
- Pintado y tap: `ChatLinkOpener.applyDetectedMentions` / `openMentionIfNeeded` (`moments-mention://profile?username=`).
- Token al escribir: `MentionParsing.detectActiveToken` (comentarios).
- Overlay global de gente: `CommentMentionSearchOverlay` — **no reutilizar** para grupos (busca en toda la red).
- Mensajes de grupo van cifrados. El servidor **no puede** parsear `@` del `content`. Hay que mandar IDs explícitos.
- `sendGroupMessage` allowlist **no** incluye `mentionedUserIds`.
- `onGroupMessageAdded` manda el mismo push a todos los no silenciados.

### Cómo
1. En el composer del chat (`GlassmorphicInputBar` / `GlassmorphicChatView+ComposerAndChrome`), si `conversation.isGroup` y el texto tiene token `@…`, mostrar lista **solo de miembros** (`GroupDirectory` / `participantData`), filtrada por username. Al elegir: sustituir el token por `@username ` (espacio).
2. Al enviar, resolver usernames del texto contra `participants` (nunca gente de fuera). Campo en claro, no cifrado: `mentionedUserIds: [uid]`. Máx. 50, sin el sender.
3. `sendGroupMessage`: añadir `mentionedUserIds` a `allowed`. Validar `⊆ group.participants`, quitar el sender. Si no, ignorar el campo (no fallar el envío).
4. `onGroupMessageAdded`: si el uid está en `mentionedUserIds`, loc-key distinta (`groups.notification.mention`, args: sender + groupName). **Respeta mute** (igual que el resto). No meter ciphertext en el push.
5. Tap de `@` en grupo: abrir perfil **dentro del hilo** (mismo `FeedProfileSheetRoute` que la lista de miembros), no saltar a otra tab.

### Archivos
- iOS: composer + `ChatViewModel.sendTextMessage`, `GroupChatAPI` / persistencia de mensaje.
- Android: composer + `ChatService` send.
- `functions/src/registers/http-groups.js` (`sendGroupMessage`, `onGroupMessageAdded`).
- Locales: `groups.notification.mention`, `groups.mention.placeholder`.

### No hacer
- Picker de toda la red.
- `@everyone`.
- Saltar mute por mención (salvo decisión de producto explícita).

---

## 2. “Está escribiendo” en el header

### Qué se nota
Las bolitas de typing **ya salen** en la lista (misma fila `.typing` que el 1:1). El subtitle del grupo **solo** muestra el recuento.

Path ya existe: `groupConversations/{id}/typing/{uid}` (`ChatService.startTyping` usa `messagingThread`). Rules de grupo ya permiten read/write al propio uid.

### Cómo
En `GlassmorphicChatView+Toolbar.chatToolbarSubtitle` (y `GlassmorphicChatViewToolbar.kt`):

- Si hay `typingUsers` y el indicador no está apagado en ajustes: “X está escribiendo” / “X e Y…” / “varias personas…”.
- Nombres desde `GroupDirectory.shared.groups[id].members`.
- Si no hay typing: el recuento de siempre.

Misma preferencia `typingIndicatorEnabled` (ya hay copy `.group`).

### Archivos
- iOS: `GlassmorphicChatView+Toolbar.swift`
- Android: `GlassmorphicChatViewToolbar.kt`
- Locales: `groups.typing.one`, `groups.typing.two`, `groups.typing.several`

### No hacer
- Nueva colección.
- Mostrar tu propio uid.
- Cambiar el path `typing/` (el cliente escribe `userId`+`timestamp`; las rules de grupo aceptan opcional `isTyping`).

---

## 3. Descripción del grupo

### Qué se nota
Nombre + foto + miembros. No hay texto corto bajo el nombre.

### Cómo
- Campo `groupDescription` (string trim, máx. **280**, vacío = sin descripción).
- Acción `setDescription` en `manageGroup` (admin, `revision` igual que `rename`).
- UI: `GroupEditView` (campo bajo el nombre) y lectura en `GroupDetailsView` + hero de `ConversationSettingsHeroHeader`.
- Crear grupo: opcional; por defecto `''`.

### Archivos
- `http-groups.js` (`applyGroupCommand`)
- `GroupConversation` / `GroupChatStore`
- `GroupEditView`, `GroupDetailsView`, hero
- Android equivalentes
- Locales: `groups.description`, `groups.descriptionPlaceholder`

### No hacer
- Markdown, @mentions ni links ricos en la descripción.
- Que un miembro no-admin la edite.

---

## 4. Solo admins pueden enviar

### Qué se nota
Cualquier miembro escribe. No hay forma de cerrar el ruido.

### Cómo
- Campo `sendPermission`: `'everyone' | 'admins'`. Default `'everyone'`.
- Acción `setSendPermission` (solo **owner**, o admin si preferimos el mismo listón que rename; recomendar **owner + admins** como rename).
- **Servidor:** `sendGroupMessage` rechaza si `sendPermission === 'admins'` y `uid` no está en `adminIds` → `adminRequired` 403. Cubrir texto, media, voz, stickers, view-once. Los `chatNotice` del servidor siguen igual.
- **Cliente:** si no puedes enviar, sustituir el composer (mismo patrón que `BlockedByMeChatInputBar` / `UnavailableChatInputBar`) por un aviso “Solo los admins pueden enviar”. No ocultar la lista ni la info.
- Toggle en ajustes del grupo / `GroupEditView`, visible a todos, editable por admins.

### Archivos
- `http-groups.js` (`sendGroupMessage` + `setSendPermission`)
- `GlassmorphicChatView+ComposerAndChrome.swift` (+ Android)
- `ConversationSettingsView` / `GroupEditView`
- Locales: `groups.send.everyone`, `groups.send.admins`, `groups.send.locked`

### No hacer
- Solo deshabilitar el TextField y dejar adjuntos.
- Confiar en el cliente.

---

## 5. Disolver el grupo

### Qué se nota
Salir transmite el owner. No hay “eliminar para todos”.

Hoy `leave`/`remove` (`http-groups.js`): si sale el owner, `ownerId` pasa al primer admin restante.

### Cómo
- Acción `dissolve`. Solo `uid === ownerId`.
- En la transacción: borrar `groupInviteLinks/{id}`, `groupInvitations/{id}_*`, futuras join requests; vaciar `participants` / `adminIds`; `ownerId: null`; `dissolvedAt`; `groupRevision++`; notice `dissolved`.
- **No** borrar `groupMessages` en el mismo request (caro). Sin participantes, las rules ya impiden leer.
- Cliente: fila destructiva en ajustes, solo owner, confirmación distinta de `leaveBody`. Al disolver, cerrar el hilo (mismo cierre que expulsión).
- Inbox: el listener deja de ver el doc (ya no eres participant) → desaparece.

### Archivos
- `http-groups.js`
- `ConversationSettingsView` (menú ellipsis / zona peligrosa)
- `GroupChatStore.command`
- `GroupChatScope.noticeText` (añadir `dissolved`)
- Locales: `groups.dissolve`, `groups.dissolveBody`, `groups.notice.dissolved`

### No hacer
- Disolver al salir el owner.
- Reciclar `leave` con un flag en el cliente.

---

## 6. Enlace con aprobación

### Qué se nota
El link une al momento (`joinLink`). Solo se corta revocándolo. No hay cola.

Hoy: `getLink` / `setLink` / `revokeLink` / `previewLink` / `joinLink`. Token 64 hex. Preview no mete al usuario.

### Cómo
- Flag en el doc del link (o del grupo): `requiresApproval` (default `false`). Acción `setLinkApproval` (admin).
- Si `requiresApproval` y el uid no es miembro: `joinLink` **no** añade. Crea `groupJoinRequests/{groupId}_{uid}` (mismo envelope de clave que una invitación). Respuesta `{ pending: true }`.
- UI de join: “Solicitud enviada” en vez de entrar al chat.
- Admins: lista en `GroupDetailsView` (junto a invitaciones pendientes). `approveJoin` / `declineJoin` (admin, `revision`). Approve = misma inserción que `acceptInvite` (participants, wrappedKeys, notice `joined`).
- Cap 50 cuenta solicitudes pendientes + miembros + invitaciones.

### Archivos
- `http-groups.js`
- `GroupInviteLinkManageView` (toggle)
- `GroupJoinLinkView`, `GroupDetailsView`, `GroupChatStore`
- Firestore: rules de `groupJoinRequests` **create/delete false** (solo Admin SDK).
- Locales: `groups.link.approval`, `groups.join.requested`, `groups.joinRequests`

### No hacer
- Caducidad / cupo numérico del link en el mismo trozo (se puede después).
- Auto-join si ya eres miembro (ya return `{ conversationId }`).

---

## 7. Silenciar un rato (8 h / 1 semana / siempre)

### Qué se nota
Mute es on/off. Inbox swipe y campana del hero llaman `ChatService.muteConversation` (arrayUnion en `mutedByUserIds` + `mutedByTimestamps.{uid}`).

`manageGroup` `mute` solo toca el array (camino viejo). El inbox **no** lo usa.

Push de grupo ya omite `mutedByUserIds`.

Rules de grupo ya dejan al miembro tocar `mutedByUserIds` / `mutedByTimestamps`.

### Cómo
- Campo `mutedUntil.{uid}`: Timestamp o delete. `null`/ausente + uid en el array = **siempre**. Timestamp futuro = hasta entonces. Pasada la hora = tratar como no silenciado **sin escribir** (el cliente puede limpiar al abrir).
- Rules: añadir `mutedUntil` a affectedKeys + `ownMap('mutedUntil')`.
- UI: el toggle del hero / swipe largo abre menú: 8 h, 1 semana, siempre, reactivar. 1:1 puede reutilizar el mismo menú (mismo campo).
- `onGroupMessageAdded` (y triggers 1:1): silenciado si está en el array **y** (`mutedUntil[uid]` ausente **o** `> now`).
- Preferir `ChatService.muteConversation` con `until: Date?`; no duplicar en `manageGroup`.

### Archivos
- `ChatService.swift` / `.kt`
- `firestore.rules` (grupo y, si se unifica, 1:1)
- `onGroupMessageAdded` + `triggers-messaging.js`
- `MessagingView.muteConversation`, hero mute
- Locales: `groups.mute.8h`, `groups.mute.week`, `groups.mute.always`

### No hacer
- Cloud Function programada para desmutear.
- Tres listas distintas (`muted8hIds`, etc.).

---

## 8. Buscar en la lista de miembros

### Qué se nota
`GroupMemberPicker` ya es `.searchable`. `GroupDetailsView` lista hasta 50 sin filtro (tú / following / others).

### Cómo
- `@State search` + `.searchable(prompt: groups.searchMembers)` en `GroupDetailsView`.
- Filtrar los tres buckets por `member.name.localizedCaseInsensitiveContains`.
- Vacío: `groups.noMembersFound`.
- Mismo patrón en Android (`GroupChatViews.kt`).

Sin backend.

---

## 9. Reportar grupo

### Qué se nota
El ellipsis del 1:1 tiene Reportar usuario (`ReportBottomSheet(userId:)`). En grupo solo Salir / Ocultar. No hay tipo `group` en reportes.

Pipeline: `LocalPersistenceService.reportContent` → `CachedAction.reportContent` (`reportedContentType`, `reportedContentId`, `reportedUserId`, categoría).

### Cómo
- Nuevo init de `ReportBottomSheet` / contenido tipo grupo: `reportedContentType = "group"`, `reportedContentId = groupId`, `reportedUserId = ownerId` (para moderación).
- Reutilizar categorías de `UserReportReason` o un subset (spam, odio, otro).
- Fila `groups.report` en el menú ellipsis de `ConversationSettingsView` (todos los miembros; no el owner reportándose a sí mismo si molesta, pero dejarlo: el owner puede reportar contenido, no el grupo — **ocultar al owner**).
- Tras enviar, no expulsar ni salir solos.

### Archivos
- `ReportBottomSheet.swift`, `UserReportContent` o hoja hermana
- `ConversationSettingsView` ellipsis
- Android settings + report sheet
- Locales: `groups.report`, `groups.report.subtitle`

### No hacer
- Bloquear a todos los miembros.
- Colección nueva si el pipeline de reports ya guarda `contentType`.

---

## Contrato que no se rompe

- IDs `group-UUID`. Mensajes en `groupConversations/{id}/groupMessages`.
- Clave de grupo envuelta por miembro; el cliente no inventa `chatIdentities`.
- Publish de historias **no** entra aquí.
- Vanish y buzz siguen fuera.
- iOS primero; Android igual comportamiento y mismas llamadas.
- Locales: no strings sueltas; el script de grupos.

## Deploy

Trozo con functions/rules: solo `manageGroup` y/o `sendGroupMessage` y/o `onGroupMessageAdded`, más `firestore:rules` si cambian keys. No redeploy masivo.
