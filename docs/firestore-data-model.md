# Modelo de datos de Firestore — contrato compartido iOS ↔ Android

> Generado a partir de `Moments/Models/` (21 archivos), cruzado con `firestore.rules` (rutas reales de colecciones y validaciones de servidor) y `firestore.indexes.json` (consultas soportadas). Se incluyen también los modelos de mensajería, que viven fuera de `Moments/Models/` (`Moments/Views/Messaging/Core/MessageModel.swift`) pero forman parte del mismo contrato.
> Fecha: 2026-07-24. Regenerar si cambian `Moments/Models/`, `MessageModel.swift` o `firestore.rules`.

Documentos hermanos: [android-port-assessment.md](android-port-assessment.md) (plan general) · [android-port-ios-feature-map.md](android-port-ios-feature-map.md) (mapa de código) · [android-port-cloud-functions-inventory.md](android-port-cloud-functions-inventory.md) (contrato HTTP).

## Cómo usar este documento

Firestore no tiene esquema: **el esquema real es lo que escribe el cliente**. Este doc es la fuente de verdad de lo que iOS escribe hoy en producción, y por tanto lo que Android debe leer y escribir para no romper la app existente.

Reglas de oro para el cliente Android:

1. **No inventar campos nuevos.** Si Android escribe un campo que iOS no conoce, iOS lo ignora, pero las Cloud Functions y las reglas de seguridad pueden rechazar la escritura (varias colecciones validan `keys().hasAll([...])` y tipos).
2. **No omitir campos que iOS decodifica sin fallback.** Marcados abajo como *requerido*: si faltan, el decoder de iOS lanza y el documento desaparece de la UI de iOS.
3. **Escribir siempre `Timestamp` de Firestore** para fechas, nunca millis ni ISO string. iOS acepta variantes al leer (compatibilidad histórica) pero escribe siempre `Timestamp`.
4. Los valores de los enums son **strings literales**; están listados textualmente más abajo. Un valor desconocido cae al default de iOS, no revienta.

---

## 1. Convenciones de serialización

| Concepto iOS | En Firestore | En Kotlin / Android |
|---|---|---|
| `@DocumentID var id: String?` | **No es un campo**, es el ID del documento | `@DocumentId val id: String?` |
| `Date` | `Timestamp` | `com.google.firebase.Timestamp` (o `Date`) |
| `[String: [String]]` (reacciones) | map de arrays | `Map<String, List<String>>` |
| `[String]` | array | `List<String>` |
| `Int64` (tamaños de fichero) | number | `Long` |
| `CGPoint` (posición de sticker) | map `{x, y}` | `data class Point(val x: Double, val y: Double)` |
| `Data` (`drawingData`) | Blob | `Blob` — ver §9, es PencilKit, ilegible en Android |
| enum `String` | string literal | `enum class` con `val raw: String` |

**Ojo con los IDs.** Hay dos patrones distintos y conviven:

- La mayoría de modelos usan `@DocumentID` → el `id` **no** está dentro del documento.
- `Moment` y `FollowRequest` **también** escriben `id` como campo dentro del documento (`Moment.encode` hace `encodeIfPresent(id, forKey: .id)`). Android debe replicarlo en `Moment` para no romper código que lo lee del cuerpo.
- `Connection` y `FollowerRecord` derivan su `id` del campo `userId`, no del ID de documento.

**Campos legacy que hay que seguir escribiendo:**

- `Moment.imagePath` se serializa con la clave **`imageUrl`** en Firestore (`case imagePath = "imageUrl"`). En Android el campo se llama `imageUrl`.
- `Story` escribe `mediaItem` (nuevo) **y además** `imagePath`/`videoUrl` (viejo) según el tipo de media, por compatibilidad con clientes antiguos. Replicar.
- `StickerData` acepta al leer `position` (map) o `positionX`/`positionY` (planos); escribe siempre `position`.
- `Notification` acepta al leer `isPending` o su inverso `isRead`; escribe `isPending`.

---

## 2. Árbol de colecciones

Extraído de `firestore.rules`. `{x}` = ID de documento variable.

```
users/{userId}
├── devices/{deviceId}                 tokens FCM / dispositivos
├── passkeys/{passkeyId}               credenciales WebAuthn
├── chatRecovery/{bundleId}            ChatRecoveryBundle (§7)
├── novaConversations/{conversationId}  IA (Nova)
├── novaMemory/{memory|context}         IA (Nova), doc fijo
├── following/{followedUserId}         Connection
├── followers/{followerId}             FollowerRecord
├── mutuals/{mutualUserId}
├── sentFollowRequests/{requestId}     FollowRequest
├── receivedFollowRequests/{requestId} FollowRequest
├── customAudienceLists/{listId}       CustomAudienceList
├── customAudiences/{audienceId}
├── moments/{momentId}                 Moment  ← colección principal
│   ├── hiddenLayers/{layerId}         MomentHiddenLayer
│   │   └── discoveries/{viewerId}     HiddenLayerDiscovery
│   ├── hiddenLayerDiscoverers/{viewerId}
│   ├── comments/{commentId}           Comment
│   ├── reactions/{reactionId}         reacción individual (§4.4)
│   └── likes/{likeId}                 legacy
├── stories/{storyId}                  Story
│   ├── viewers/{viewerId}
│   ├── reactions/{reactionId}
│   ├── pollVotes/{pollStickerId}/votes/{viewerId}
│   ├── questionResponses/{questionStickerId}/responses/{responseId}
│   ├── emojiSliders/{stickerId}/votes/{viewerId}
│   └── stickerInteractions/{interactionId}
├── highlights/{highlightId}           HighlightedStory
│   └── stories/{storyId}
├── connections/{targetUserDocId}
├── admirers/{admirerDocId}
├── visits/{visitId}                   Visit
├── visitSummaries/{summaryId}
├── accountHistory/{historyId}         AccountHistoryItem
├── notifications/{notificationDocId}  Notification
├── savedMoments/{momentId}
├── recentlyDeleted/{deletedId}
├── storySeen/{authorId}
├── dataExportRequests/{requestId}
├── loginActivity/{activityId}
├── dailyStats/{dateString}            analítica
├── events/{eventId}                   analítica
├── sessions/{sessionId}               analítica
├── featureUsage/{dateString}          analítica
├── userActivity/{activityId}          analítica
└── accountAudit/{auditId}

conversations/{conversationId}          Conversation
├── messages/{messageId}                EnhancedMessage
│   └── messageReactions/{userId}
├── buzzEvents/{buzzId}
└── typing/{userId}

echoes/{echoId}                         Echo
storyChains/{chainId}                   §4.9
messageRequests/{requestId}             MessageRequest
usernames/{username}                    índice de unicidad de usernames
interests/{interestId}
appConfig/{configId}
reactions/{reactionId}                  legacy raíz
geminiConversations/{conversationId}    IA
geminiConversationTitles/{conversationId}

reports/{reportId}                      moderación
appeals/{appealId}
moderationLogs/ · mediaModerationLogs/ · moderationReviewQueue/ · moderationSettings/
auditLogs/ · appealAuditLogs/ · appealNotificationQueue/
scheduledDeletions/ · emailQueue/ · globalExportRequests/
```

**Consecuencia arquitectónica clave:** `moments` y `stories` son **subcolecciones de cada usuario**, no colecciones raíz. El feed no se construye leyendo una colección global: se usa `collectionGroup("moments")` (hay índices de collection-group para ello) o, en la práctica, los endpoints HTTP `getFeedPage` / `getProfileMomentsPage` del backend. Para Android, **el camino recomendado es el HTTP** (ver inventario de Cloud Functions); las lecturas directas a Firestore son para el detalle y los listeners en tiempo real.

---

## 3. Usuario

### 3.1 `users/{userId}` — `AppUser`

`id` = UID de Firebase Auth. **Aquí sí se escribe `id` dentro del documento** (`decode(String.self, forKey: .id)` es requerido, sin fallback: un doc de usuario sin campo `id` rompe el decoder de iOS).

| Campo | Tipo | Default al leer | Notas |
|---|---|---|---|
| `id` | String | **requerido** | == UID de Auth |
| `username` | String | `"Usuario Desconocido"` | unicidad vía colección `usernames/` |
| `email` | String | `""` | |
| `interests` | List\<String\> | `[]` | **claves en español** — ver §8.1 |
| `isPlusSubscriber` | Bool | `false` | |
| `profileImagePath` | String? | null | URL de Storage |
| `bio`, `websiteUrl`, `profileNote` | String? | null | |
| `blockedUsers` | List\<String\> | `[]` | |
| `isPrivate` | Bool | `false` | cuenta privada → requiere aprobación de follow |
| `showMutuals`, `showFollowing`, `showFollowers` | Bool | `true` | |
| `activeHoursStart`, `activeHoursEnd` | String? | null | |
| `notificationPreferences` | Map\<String, Bool\>? | null | |
| `bestFriends` | List\<String\> | `[]` | audiencia `bestFriends` |
| `followersCount`, `followingCount`, `momentsCount` | Int | `0` | denormalizados, los mantienen triggers |
| `isActive` | Bool | `true` | `false` = cuenta desactivada; **las rules lo comprueban en casi toda escritura** |
| `deactivatedAt` | Double (epoch s) | null | ⚠️ único campo de fecha que **no** es `Timestamp`: iOS lo lee como `Double` |
| `deactivatedBy` | String? | null | |
| `ownedBadges` | List\<UserBadge\> | `[]` | array de mapas embebido (§3.2) |
| `plusSubscription` | PlusSubscription? | null | mapa embebido (§3.2) |
| `primaryBadgeId` | String? | null | |
| `showBadge`, `showPlusBadge` | Bool | `true` | |
| `selectedProfileTheme` | String? | null | `default`/`supporter`/`earlyAdopter`/`champion`/`vip`/`plus` |
| `isVerified` | Bool | `false` | |
| `onlineStatus` | String | `"offline"` | §8.2 |
| `lastSeen` | Timestamp? | null | |
| `isOnline` | Bool | `false` | |
| `showReadReceipts` | Bool | `true` | |
| `messageRequestPolicy` | String | `"everyone"` | §8.2 |
| `lastUsernameChange` | Timestamp? | null | cooldown de cambio de username |

### 3.2 Mapas embebidos en el usuario

**`UserBadge`** (elemento de `ownedBadges`): `id: String`, `badgeId: String`, `name: String`, `emoji: String`, `colors: List<String>` (hex, **sin `#`**), `purchaseDate: Timestamp`, `isVisible: Bool`, `price: String` (formato `"€2.99"`, se parsea quitando `€` y cambiando `,` por `.`).

**`PlusSubscription`**: `isActive: Bool`, `startDate: Timestamp?`, `expiryDate: Timestamp?`, `autoRenew: Bool`, `plan: String` (`"monthly"` | `"yearly"`).

### 3.3 Grafo social

| Colección | Modelo | Campos |
|---|---|---|
| `users/{u}/following/{followedUserId}` | `Connection` | `userId: String`, `timestamp: Timestamp` |
| `users/{u}/followers/{followerId}` | `FollowerRecord` | `userId: String`, `timestamp: Timestamp` |
| `users/{u}/mutuals/{mutualUserId}` | — | mismo patrón |

En ambos el `id` del modelo se toma del **campo `userId`**, no del ID de documento (aunque en la práctica coincidan). Las escrituras aquí disparan `onFollowerAdded` / `onFollowerRemoved` / `onFollowingRemoved`, que mantienen los contadores.

### 3.4 Solicitudes de seguimiento — `FollowRequest`

En `users/{u}/sentFollowRequests/{id}` y `users/{u}/receivedFollowRequests/{id}`. Aquí **sí** se escribe `id` en el cuerpo.

`id: String`, `senderId: String`, `senderUsername: String`, `recipientId: String`, `status: String` (§8.2), `timestamp: Timestamp`, `expirationDate: Timestamp?` (iOS pone +30 días al crear).

### 3.5 `users/{u}/visits/{visitId}` — `Visit`

`visitorId: String`, `timestamp: Timestamp`. **El `id` siempre se decodifica como `nil` en iOS** (`Visit.init(from:)` fuerza `DocumentID(wrappedValue: nil)`); la UI agrupa por `visitorId`. Android puede quedarse con el docId, pero no debe depender de él para la paridad.

### 3.6 `users/{u}/accountHistory/{id}` — `AccountHistoryItem`

`type: String` (§8.2), `oldValue: String?`, `newValue: String?`, `timestamp: Timestamp`.

---

## 4. Contenido

### 4.1 `users/{authorId}/moments/{momentId}` — `Moment`

El documento más grande del modelo. Ningún campo obligatorio revienta el decoder de iOS: todos tienen fallback (`?? ""`, `?? 0`, `?? false`). Aun así, Android debe escribir el set completo que escribe iOS.

**Identidad y autoría:** `id` (String, también como campo), `authorId`, `username`, `profileImagePath` (String?) — **datos de autor denormalizados**, no se resuelven por join.

**Contenido:**

| Campo | Tipo | Notas |
|---|---|---|
| `content` | String | texto del post |
| `imageUrl` | String? | ⚠️ en Swift se llama `imagePath` — legacy, un solo medio |
| `videoUrl` | String? | legacy, un solo medio |
| `mediaItems` | List\<MediaItem\>? | **camino actual** (carrusel). Si es `nil`, se usa el fallback legacy `imageUrl`/`videoUrl` |
| `aspectRatio` | String? | `"W:H"`, p. ej. `"4:5"` |
| `thumbnailUrl`, `videoDuration` (Double), `videoFileSize` (Long), `videoResolution` (`"1080x1920"`) | | legacy a nivel de moment; en `mediaItems` van por elemento |
| `timestamp` | Timestamp | |

**Social:** `reactions: Map<String, List<String>>` (emoji/clave → lista de userIds), `commentCount: Int`, `taggedUsers: List<String>?`, `mentionedUsers: List<String>?`.

**Ubicación:** `location: String?` (nombre legible), `locationCoordinate: {latitude: Double, longitude: Double}?`. Hay índices sobre `locationCoordinate.latitude` para el mapa.

**Audiencia:** `audience: String?` (§8.3), `customListId: String?` (apunta a `customAudienceLists`), `originalAudience: String?`.

**Ajustes del post:** `disableComments: Bool` (def. `false`), `hideLikeCounts: Bool` (def. `false`), `allowSharing: Bool` (def. **`true`**).

**Ciclo de vida:** `scheduledDate: Timestamp?` (publicación programada; `isScheduled` = fecha futura), `isArchived: Bool?` + `archivedAt: Timestamp?`, `isPinned: Bool?` + `pinnedAt: Timestamp?`.

**Preview en la grid del perfil:** `gridPreviewScale: Double?`, `gridPreviewOffsetX/Y: Double?`, `gridPreviewFitMode: String?`, `gridPreviewBackground: String?`.

**Capas ocultas:** `hasHiddenLayers: Bool` (def. `false`), `hiddenLayerCount: Int` (def. `0`) — contadores denormalizados de la subcolección `hiddenLayers`.

**Moderación:** `isModerationHidden: Bool?`, `reviewRequired: Bool?`, `canRestore: Bool?`. Los escribe el backend (`moderateMediaContent`), el cliente los lee.

### 4.2 `MediaItem` (mapa embebido en `Moment.mediaItems` y en `Story.mediaItem`)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | String | requerido al escribir; al leer cae a un UUID nuevo si falta |
| `type` | String | **`"image"` \| `"video"`** — requerido |
| `url` | String | requerido |
| `aspectRatio` | String? | `"W:H"` |
| `thumbnailUrl` | String? | poster de vídeo |
| `videoDuration` | Double? | segundos |
| `videoFileSize` | Long? | bytes |
| `videoResolution` | String? | `"1080x1920"` |
| `videoProcessingStatus` | String? | `pending`/`processing`/`ready`/`failed`/`skipped` — lo escribe `processMomentVideos` |
| `originalVideoUrl` | String? | |
| `videoVariants` | map? | variantes de transcodificado que genera el backend |
| `tags` | List\<PhotoTag\>? | etiquetas espaciales |
| `moderationState` | String? | `"visible"` \| `"hidden"` |
| `moderationReason`, `moderationCategory`, `moderationConfidence` | String? | |
| `moderatedAt` | Timestamp \| millis (Double/Int) | ⚠️ **acepta tres formatos** al leer; el backend escribe millis. Android debe tolerar ambos |

`PhotoTag`: `id: String` (UUID), `userId: String`, `username: String`, `x: Double`, `y: Double` — coordenadas **normalizadas 0.0–1.0** relativas a la imagen.

**Regla de render que Android debe replicar:** un `MediaItem` con `moderationState == "hidden"` o `url` vacía **no se muestra**. `visibleMediaItems` filtra ambos; si `mediaItems` es `nil` (no vacío — `nil`) se cae al legacy `imageUrl`/`videoUrl`.

### 4.3 `.../moments/{id}/comments/{commentId}` — `Comment`

`authorId: String`, `username: String`, `content: String`, `timestamp: Timestamp`, `profileImagePath: String?`, `updatedAt: Timestamp?`, `reactions: Map<String, List<String>>` (def. `{}`), `parentCommentId: String?` (hilos de un nivel), `isEdited: Bool?`, `editedTimestamp: Timestamp?`, `mentions: List<CommentMentionEntity>`.

`CommentMentionEntity`: `userId: String`, `username: String`, `rangeStart: Int`, `rangeLength: Int` — offsets sobre `content`. ⚠️ **`rangeStart`/`rangeLength` están calculados en unidades de `NSString` (UTF-16)**. Kotlin `String` también indexa en UTF-16, así que coinciden — pero no convertir a code points.

`isPending` existe en el modelo Swift para la cola offline y **no se persiste** (no está en `encode`).

### 4.4 `.../moments/{id}/reactions/{reactionId}` — reacción individual

No hay struct Swift dedicado; el contrato lo imponen las rules, que exigen `keys().hasAll(['userId', 'reactionType', 'timestamp'])` y **restringen `reactionType` a esta lista cerrada**:

```
vibe, fire, real, mood, glow, feel, love, wow,
laugh, cry, respect, power, genius, creative, chill, hype
```

Cualquier otro valor es rechazado por el servidor. Convive con el mapa denormalizado `Moment.reactions` y con la subcolección legacy `likes/`.

### 4.5 `.../moments/{id}/hiddenLayers/{layerId}` — `MomentHiddenLayer`

Capas ocultas que el espectador descubre tocando la foto.

`id`, `type` (`text`/`audio`/`image`), `anchorX`/`anchorY`/`width`/`height` (Double, normalizados), `shape` (`circle`/`roundedRect`), `zIndex: Int`, `text: String?`, `mediaURL`/`thumbnailURL: String?`, `duration: Double?`, `caption: String?`, `imageOffsetX/Y: Double?`, `imageScale: Double?`, `imageFrameStyle` (`classic`/`clean`/`vintage`), `textStyle` (`clean`/`serif`/`handwritten`/`mono`/`bubble`/`editorial`), `presentationStyle` (`glassCard`/`captionPill`/`paperNote`/`markerLabel`/`floatingQuote`/`minimalText`), `unlockMode` (`immediate`/`scheduled`), `unlockAt: Timestamp?`, `authorTimezoneIdentifier: String?`, `discoverCount: Int?`, `uniqueDiscovererCount: Int?`, `lastDiscoveredAt: Timestamp?`, `moderationState` (`visible`/`hidden`/`pending`), `moderationReason`/`moderationCategory: String?`, `moderatedAt: Timestamp?`, `createdAt: Timestamp`.

Lógica de visibilidad a replicar: visible solo si `moderationState` es `visible` (ausente == `visible`); desbloqueada si `unlockMode == immediate`, o si `unlockAt <= now` (si `unlockAt` es `nil` con modo `scheduled`, **se considera desbloqueada**).

Subcolección `discoveries/{viewerId}` → `HiddenLayerDiscovery`: `viewerId`, `username: String?`, `profileImagePath: String?`, `discoveredAt: Timestamp`.

### 4.6 `users/{authorId}/stories/{storyId}` — `Story`

**Campos requeridos** (sin fallback en el decoder de iOS): `authorId`, `username`, `duration` (Double), `timestamp`, `expirationDate`. Además debe existir **uno de** `mediaItem`, `imagePath` o `videoUrl`, o el decoder lanza.

| Campo | Tipo | Notas |
|---|---|---|
| `mediaItem` | MediaItem | mapa embebido (§4.2); un solo medio por story |
| `duration` | Double | segundos de reproducción |
| `expirationHours` | Int? | al leer, si falta: **48 si hay `chainId`, 24 si no** |
| `expirationDate` | Timestamp | requerido |
| `audience`, `customListId` | String? | §8.3 |
| `aspectRatio` | String? | |
| `backgroundFrameURL`, `backgroundBlurredFrameURL` | String? | fondo para vídeo horizontal |
| `stickers` | List\<StickerData\>? | §4.7 |
| `drawingData` | Blob? | ⚠️ **PencilKit — ilegible en Android**, ver §9 |
| `chainId`, `chainTitle` | String? | story chains |
| `chainPosition` | Int? | 1, 2, 3… |

**Texto sobre la story** — hay dos generaciones y conviven:

- *Legacy, un solo bloque:* `text`, `textPosition` (Blob: un `CGPoint` codificado en JSON — evitar), `textPositionNormX`/`textPositionNormY` (Double, **normalizados 0–1, este es el bueno**), `textStyle`, `textColorHex`, `textFontSize`, `textAlignment`, `textBackgroundFill`, `textStroke`, `textVisualEffect`, `textMotion`, `forcesAllCaps`, `textLayerOrder`, `textOverlayLive`.
- *Actual, múltiples bloques:* `textOverlays: List<StoryTextOverlayMetadata>` con `id`, `text`, `normalizedPosition` ({x,y} 0–1), `layerOrder: Int`, `styleRaw`, `colorHex`, `fontSize: Double`, `alignmentRaw`, `backgroundFillRaw`, `strokeRaw`, `visualEffectRaw`, `motionRaw`, `forcesAllCaps: Bool`, `isLiveOverlay: Bool`, `gradientStopHexes: List<String>?`, `gradientAngle: Int?`.

`textOverlayLive == true` ⇒ el texto se renderiza en vivo en el visor; si es `false`, ya está *quemado* en el media y no hay que dibujarlo otra vez (doble render = bug visual).

Subcolecciones de interacción: `viewers/`, `reactions/`, `pollVotes/{stickerId}/votes/{viewerId}`, `questionResponses/{stickerId}/responses/{responseId}`, `emojiSliders/{stickerId}/votes/{viewerId}`, `stickerInteractions/`.

### 4.7 `StickerData` (array embebido en `Story.stickers` y `EnhancedMessage.stickers`)

Un único struct plano para ~20 tipos de sticker; los campos irrelevantes van `null`.

**Transform:** `stickerId: String?` (si falta, iOS reconstruye un ID estable como `"{type}_{x}_{y}"`), `type: String` (§8.4), `content: String`, `position: {x, y}`, `scale: Double`, `rotation: Double` (**radianes**), `zIndex: Int?`.

**`content` es polimórfico según `type`** — esto es lo más delicado del modelo:

| Tipo de sticker | Qué hay en `content` |
|---|---|
| `generic`, `sticker`, `emoji`, `time`, `selfie`, `questionResponse`, `shareMoment`, `link`, `countdown`, `emojiSlider`, `frame`, `quiz` | **imagen rasterizada en Base64** (JPEG q0.6; PNG para `selfie`; JPEG q0.42 máx. 900px para `frame`) |
| `mention` | `"@usuario"` |
| `hashtag` | `"#tag"` |
| `location` | nombre del sitio |
| `question` | texto de la pregunta |
| `poll` | opciones unidas por `\|` |
| `weather` | símbolo del clima |
| animados | URL del GIF |

Es decir: los stickers "de plantilla" viajan como **píxeles pregenerados por iOS**, más metadatos para reconstruirlos. Android puede (a) pintar el Base64 tal cual — paridad visual instantánea, pero con la estética iOS; o (b) reconstruirlo desde los metadatos con estilo propio. Al **escribir** desde Android habrá que rasterizar algo equivalente, o los clientes iOS antiguos verán un placeholder.

**Metadatos por tipo:** `username`/`userId` (mention), `hashtag`, `location`+`latitude`+`longitude`, `styleVariant: Int?`, `questionText`, `pollOptions: List<String>?`, `weatherSymbol`, `linkURL`/`linkTitle`, `countdownTitle`/`countdownTargetAtMs: Double` (epoch **ms**), `sliderEmoji`/`sliderPrompt`, `caption`, `profileImagePath`, `momentId`/`mediaCount` (shareMoment), `quizQuestion`/`quizOptions`/`quizCorrectIndex`, `revealType`/`revealPattern`/`revealPrimaryColor`/`revealSecondaryColor`/`revealEffectColor`, `frameStyle`, `contentScale`/`contentOffsetX`/`contentOffsetY`, `audioURL`/`audioDuration`, `isAnimated: Bool`, `gifURL`/`videoURL: String?`, `moderationState`/`moderationReason`/`moderationCategory`.

Un sticker con `moderationState == "hidden"` **se omite por completo** al renderizar.

### 4.8 `users/{u}/highlights/{id}` — `HighlightedStory`

`title: String`, `coverImageUrl: String?`, `storiesCount: Int`, `createdAt: Timestamp`, `storyIds: List<String>`, `authorId: String`. Subcolección `stories/{storyId}` con las copias.

### 4.9 `storyChains/{chainId}` — colección raíz

No hay struct Swift; el contrato lo definen las **rules**, que exigen al crear `id`, `title` (1–100 chars), `createdBy` (== uid), `createdAt` (timestamp), `partCount` (int, **== 1** en la creación). Opcionales: `description` (≤500), `tags` (lista ≤10). En update, quien no es el creador solo puede tocar `partCount`, `lastUpdated`, `isExpired`, `expiredAt`, `lastPartBy`, `lastPartUsername`.

### 4.10 `echoes/{echoId}` — `Echo`

Momentos coincidentes por ubicación y tiempo.

`hostId: String`, `participants: List<EchoParticipant>`, `participantIds: List<String>` (**array plano duplicado solo para poder consultar con `array-contains`** — mantener sincronizado con `participants` o las rules deniegan el acceso), `location: {latitude, longitude}`, `locationName: String?`, `createdAt`/`expiresAt: Timestamp` (ventana de 24 h), `status: String` (`pending`/`active`/`expired`/`completed`), `moments: List<EchoMomentRef>`, `vibeSummary: String?` (lo genera la IA).

`EchoParticipant`: `userId`, `username`, `profileImagePath: String?`, `status` (`pending`/`accepted`/`declined`).
`EchoMomentRef`: `momentId`, `authorId`, `username`, `timestamp`, `mediaType` (`"image"`/`"video"`), `mediaUrl`, `aspectRatio?`, `thumbnailUrl?`, `audience?`, `customListId?` — snapshot denormalizado para validar privacidad en el momento de mostrar.

Solo se muestran los `moments` cuyo autor tiene `status == accepted`.

⚠️ `Echo` **no** escribe `id` en el cuerpo (está explícitamente quitado del `encode`); solo `@DocumentID`.

### 4.11 `users/{u}/customAudienceLists/{listId}` — `CustomAudienceList`

`name: String`, `description: String?`, `members: List<String>`, `createdAt`/`updatedAt: Timestamp`, `color: String?`, `icon: String?`. Referenciada por `Moment.customListId` y `Story.customListId` cuando `audience == "custom"`.

### 4.12 Stickers de pregunta — `QuestionResponse` / `QuestionData`

`QuestionResponse` (en `.../questionResponses/{stickerId}/responses/{id}`): `id: String` (en el cuerpo), `userId: String`, `response: String`, `timestamp: Timestamp`, `isAnonymous: Bool` (**siempre `true`**; el `userId` se guarda pero no se muestra nunca en la UI — respetar esto en Android).

`QuestionData`: `questionText: String`, `responses: List<QuestionResponse>`, `responseCount: Int`, `createdAt: Timestamp`.

---

## 5. Notificaciones — `users/{userId}/notifications/{id}`

Documento único y ancho: los campos que aplican dependen de `type`.

**Base:** `type: String` (§8.5, requerido — valor desconocido cae a `newFollower`), `senderId: String` (def. `""`), `senderUsername: String` (def. `""`), `timestamp: Timestamp`, `isPending: Bool` (def. `true`; acepta el inverso `isRead` al leer), `title`/`message: String?`.

**Referencias según tipo:** `momentId`, `commentId`, `storyId`, `storyAuthorId`, `storyPreviewUrl`, `conversationId`, `messageId`, `messageType`, `echoId`, `buzzEventId`, `downloadURL` (export de datos), `visitCount: Int?`, `mentionContext`, `targetAuthorId`/`targetAuthorUsername`, `moderationScope` (`post`/`story`/`storySticker`), `reminderVariant`.

**Story chains:** `chainId`, `chainTitle`, `chainPosition: Int?`, `totalParts: Int?`, `chainRole` (`"creator"` | `"participant"`).

**Reacciones:** `reaction: String?`, `reactionCount: Int?`, `isReactionPlural: Bool?`.

⚠️ **Tres alias del mismo dato.** iOS lee `reaction` con esta cascada: `reaction` → si no, `reactionType` (lo escriben las Cloud Functions para reacciones a moments) → si no, `commentText` (lo escriben para comentarios). Al escribir usa siempre `reaction`. Android debe leer los tres.

⚠️ `isReactionPlural` puede llegar como **Bool o como String** (`"1"`/`"true"`).

---

## 6. Mensajería

Definida en `Moments/Views/Messaging/Core/MessageModel.swift`, no en `Models/`. **Los mensajes van cifrados extremo a extremo** — ver §7.

### 6.1 `conversations/{conversationId}` — `Conversation`

**Identidad:** `participants: List<String>` (los uids; la consulta base es `whereArrayContains("participants", uid).orderBy("timestamp", DESC)` — hay índice), `otherParticipantId: String` + `otherParticipantUsername`/`otherParticipantProfileImagePath` (denormalizados, **asumen chat 1-a-1**).

**Último mensaje:** `lastMessage: String?`, `timestamp: Timestamp`, `lastMessageSenderId: String?`, `lastMessageType: String?` (§8.6), `lastMessageSeenAt: Map<String, Timestamp>?`, `lastMessageReaction: {messageId, emoji, byUserId}?`, `lastMessageViewOncePending: Bool`.

**Estado por usuario (todos son maps `uid → valor`):** `readStatus: Map<String, Bool>`, `lastReadAt: Map<String, Timestamp>?`, `lastDeletedAt: Map<String, Timestamp>?` (**punto de corte**: los mensajes con `timestamp <=` este valor se ocultan a ese usuario — es un borrado por-usuario, no un borrado real), `readReceiptPreferences`, `buzzPreferences`, `forwardingPreferences: Map<String, Bool>?`.

**Flags de conversación:** `pinnedByUserIds`, `mutedByUserIds`, `archivedByUserIds: List<String>?` (y los legacy escalares `isPinned`/`pinnedBy`/`isMuted`/`mutedBy`).

**Vanish mode:** `vanishModeActive: Bool?`, `vanishModeEnabledBy`, `vanishModeEnabledAt`, `vanishMessageTimer: String?`, `vanishSettingsNoticeMessageId`, `vanishDisabledNoticeMessageId`.

**Cifrado:** `encryptionVersion: String?`, `conversationKeyVersion: Int?`, `wrappedKeys: Map<String, WrappedConversationKey>?` (§7).

### 6.2 `conversations/{id}/messages/{messageId}` — `EnhancedMessage`

`id` **sí** va en el cuerpo (no es `@DocumentID`; es una `class`, no un `struct`).

**Base:** `conversationId`, `senderId`, `type: String` (§8.6), `content: String?` (**cifrado**), `timestamp: Timestamp`, `status: String` (§8.6), `isRead`, `isDeleted: Bool`, `deletedAt`/`editedAt: Timestamp?`, `replyTo: String?` (id del mensaje citado), `expirationDate: Timestamp?`.

**Media (cifrada):** `mediaUrl`/`thumbnailUrl: String?` (URLs firmadas efímeras — **no persistir**), `mediaObjectPath`/`thumbnailObjectPath: String?` (rutas estables de Storage, esto es lo que se guarda), `mediaEncryption`/`thumbnailEncryption: EncryptedChatMediaMetadata?`, `duration: Double?`, `audioWaveform: List<Float>?`, `fileName`, `fileSize: Long?`, `mediaWidth`/`mediaHeight: Int?`, `mediaBatchId: String?` (agrupa envíos múltiples).

`EncryptedChatMediaMetadata`: `version`, `algorithm`, `purpose` (`primary`/`thumbnail`), `mediaId`, `contentType`, `fileExtension`, `plaintextSize: Long`.

**Ubicación:** `latitude`/`longitude: Double?`, `locationName`, `locationAddress`, `isLiveLocation: Bool?`, `liveLocationExpiresAt`, `liveLocationStoppedAt`, `liveLocationDuration: String?`, `liveLocationSessionId`, `locationUpdatedAt`.

**View-once / vanish:** `viewedBy: List<String>?`, `allowReplay: Bool?`, `replayedBy: List<String>?`, `isVanishModeMessage: Bool?`, `vanishedFor: List<String>?`, `vanishExpiresAt: Timestamp?`.

**Otros:** `readBy`, `starredBy: List<String>?`, `isForwarded: Bool?`, `reactions: Map<String, List<String>>?`, `storyReplyData`/`sharedMomentData`/`sharedStoryData: Map<String, String>?`, y `textOverlayLive`/`textOverlays`/`stickers`/`drawingData` (mismo formato que en `Story`, para respuestas a stories editadas).

Subcolección `messageReactions/{userId}` (con índice de collection-group por `conversationId` + `messageId`).

`Message` (el struct simple: `conversationId`, `senderId`, `content`, `timestamp`, `isRead`, `reaction?`, `expirationDate?`, `isViewed`) es el **modelo legacy**; lo vigente es `EnhancedMessage`.

### 6.3 `messageRequests/{requestId}` — `MessageRequest`

Colección raíz. `senderId`, `senderUsername: String?`, `senderProfileImagePath: String?`, `receiverId`, `message: String`, `timestamp: Timestamp`, `status` (`pending`/`accepted`/`rejected`/`blocked`), `messageType: String` (§8.6), `mediaUrl`/`thumbnailUrl: String?`. Se acepta vía la Cloud Function `acceptMessageRequest`, que devuelve `{conversationId, messageId}`.

---

## 7. Cifrado del chat (E2E)

Modelos en `Moments/Models/ChatSecurityModels.swift`. Estos structs **no** usan `Codable` contra Firestore: tienen `init?(map:)` / `asFirestoreData()` manuales, así que Android debe mapearlos a mano igual.

**`ChatIdentityRecord`** — clave pública del usuario: `keyId: String`, `publicKeyBase64: String`, `algorithm: String` (def. `"curve25519"`), `updatedAt` (`serverTimestamp()` al escribir).

**`ChatRecoveryBundle`** — en `users/{u}/chatRecovery/{bundleId}`. Clave privada cifrada con el PIN del usuario: `keyId: String?`, `encryptedPrivateKey`, `nonce`, `salt` (Base64), `kdf: String` (def. `"PBKDF2"`), `kdfParams: {iterations: Int (def. 200000), keyLength: Int (def. 32), hash: String (def. "SHA256")}`, `keyVersion: Int` (def. 1), `encryptedUserKey: String?`, `createdAt`/`updatedAt`.

**`WrappedConversationKey`** — valor de `Conversation.wrappedKeys[uid]`: `wrappedKey`, `senderPublicKey`, `recipientKeyId`, `wrappedBy: String`, `wrappedAt`.

`ChatRecoveryAttemptState` (5 intentos, lockout) y `ChatAccessState` son **estado en memoria**, no se persisten.

> **Este es el punto de mayor riesgo del port.** Android tiene que reimplementar exactamente el mismo esquema criptográfico (Curve25519 + PBKDF2-SHA256 200k/32B + el formato de wrapping) o los chats existentes serán ilegibles y los mensajes que envíe Android serán ilegibles en iOS. Los parámetros de arriba son el contrato exacto; el algoritmo de sellado/apertura hay que leerlo en `Moments/Services/Security` y `Moments/Services/Messaging`. Ya hay discrepancias detectadas en el port actual — verificarlas contra esta sección.

---

## 8. Enums — valores literales

### 8.1 Intereses

⚠️ **Las claves en la base de datos están en español** (p. ej. `"Fotografía"`, `"Viajes"`, `"K-pop"`, `"Senderismo"`). Colección `interests/{slug}` con campos `name` (clave ES), `slug`, `emoji`, `order`. Catálogo canónico: `Moments/shared/interest-catalog.json` (71 intereses, v2). Seed: `node scripts/seed-interests.mjs` desde `Moments/` (requiere `firebase login`). La localización es en cliente (`InterestCatalog` / `interest.*`). Valores legacy (`Viajar`, `Lectura`, `Kpop`…) se resuelven por alias. Valores no reconocidos se muestran tal cual.

### 8.2 Usuario y social

| Enum | Valores |
|---|---|
| `onlineStatus` | `online`, `away`, `busy`, `offline`, `invisible` |
| `messageRequestPolicy` | `everyone`, `following`, `nobody` |
| `FollowRequest.status` | `pending`, `accepted`, `rejected`, `cancelled` |
| `AccountHistoryItem.type` | `join`, `username`, `bio`, `website`, `privacy` |
| `PlusSubscription.plan` | `monthly`, `yearly` |

### 8.3 Audiencia (`Moment.audience`, `Story.audience`)

`everyone`, `mutuals`, `bestFriends`, `custom`. Ausente o desconocido ⇒ `everyone`. Con `custom`, `customListId` apunta a `users/{u}/customAudienceLists/{id}`.

### 8.4 Tipos de sticker (`StickerData.type`)

`emoji`, `sticker`, `mention`, `hashtag`, `location`, `poll`, `question`, `link`, `countdown`, `emojiSlider`, `questionResponse`, `generic`, `weather`, `time`, `shareMoment`, `selfie`, `quiz`, `frame`, `reveal`, `audio`.

### 8.5 Tipos de notificación (`Notification.type`)

`like` (reacción a comentario), `reaction` (reacción a moment), `comment`, `mention`, `newFollower`, `followRequest`, `requestAccepted`, `mutualConnection`, `storyReaction`, `message`, `messageReaction`, `chatBuzz`, `gentleReminder`, `photoTag`, `echoSuggestion`, **`data_export_ready`** (⚠️ snake_case, el único), `storyChainContinued`, `mediaModeration`.

### 8.6 Mensajería

| Enum | Valores |
|---|---|
| `MessageType` | `text`, `image`, `video`, `audio`, `gif`, `sticker`, `location`, `file`, `ephemeral`, `sharedMoment`, `sharedStory`, `viewOnceImage`, `viewOnceVideo`, `chatNotice` |
| `MessageStatus` | `pending`, `sending`, `sent`, `delivered`, `read`, `failed` |
| `MessageRequest.status` | `pending`, `accepted`, `rejected`, `blocked` |
| `ChatMediaPurpose` | `primary`, `thumbnail` |

### 8.7 Otros

| Enum | Valores |
|---|---|
| `MediaItem.type` | `image`, `video` |
| `MediaItem.videoProcessingStatus` | `pending`, `processing`, `ready`, `failed`, `skipped` |
| `MediaItem.moderationState` | `visible`, `hidden` |
| `MomentHiddenLayer.moderationState` | `visible`, `hidden`, `pending` |
| `EchoStatus` | `pending`, `active`, `expired`, `completed` |
| `EchoParticipantStatus` | `pending`, `accepted`, `declined` |
| reacciones a moments | ver lista cerrada en §4.4 |

---

## 9. Modelos que **no** son contrato de Firestore

Estos archivos de `Moments/Models/` son locales de iOS. Android necesita el equivalente funcional, pero **no** el mismo formato — no se sincronizan.

| Archivo | Qué es | Equivalente Android |
|---|---|---|
| `Cache/Cached*.swift` (9) | Espejos SwiftData de Moment/Story/User/Conversation/Message/Notification/Connection/Search/Action para offline local-first | Room `@Entity` |
| `UserAffinity.swift` | Puntuación de afinidad calculada en el dispositivo para ordenar feed. **Nunca sale del dispositivo** | Room |
| `OutboxPayloads.swift` | Payloads de la cola offline (reacción, comentario, follow, block, report, borrado, update de perfil, mensajes). Serialización local | WorkManager + Room |
| `StickerItem.swift` | Modelo de UI en runtime (`UIImage`, `Angle`). Se persiste convertido a `StickerData` | modelo de UI Compose |
| `BestFriendsView.swift`, `VisitsView.swift` | Vistas SwiftUI (solo `Visit` y `UserBadge`/`PlusSubscription` son modelos reales) | — |
| `InterestModels.swift` | Solo capa de localización sobre las claves en español | — |

**`Story.drawingData` es un caso aparte:** es un blob de **PencilKit** que sí viaja por Firestore. Android no puede decodificarlo (no hay equivalente). Opciones: (a) ignorarlo y no mostrar el dibujo en stories creadas desde iOS — degradación aceptable, el dibujo suele ir además quemado en el media; (b) migrar ambos clientes a un formato neutro (lista de trazos) escribiendo un campo nuevo en paralelo. Decisión pendiente.

---

## 10. Consultas soportadas (índices compuestos)

43 índices en `firestore.indexes.json`. Android solo puede hacer estas consultas compuestas sin desplegar índices nuevos:

**Contenido**
- `moments` (collection-group): `authorId + timestamp` (asc/desc) · `audience + timestamp` · `audience + location [+ timestamp]` · `audience + locationCoordinate.latitude` · `taggedUsers array-contains + timestamp desc`
- `moments` (collection): `isArchived + archivedAt desc` · `isModerationHidden + moderatedAt desc`
- `stories` (collection-group): `authorId + expirationDate` · `authorId + chainId + timestamp desc` · `chainId + chainPosition`
- `stories` (collection): `timestamp + expirationDate` · `timestamp desc + chainId desc` · `isModerationHidden + moderatedAt desc`
- `comments` (collection-group): `authorId + timestamp desc`
- `reactions`, `pollVotes`, `questionResponses` (collection-group): `userId + timestamp desc`

**Social y mensajería**
- `conversations`: `participants array-contains + timestamp desc` ← la consulta principal de la bandeja
- `messages` (collection-group): `isDeleted + type + expirationDate` · `isVanishModeMessage + vanishExpiresAt` · `senderId + type + isDeleted + expirationDate`
- `messageRequests`: `receiverId + status + timestamp desc` · `senderId + status + timestamp desc`
- `messageReactions` (collection-group): `conversationId + messageId`
- `sentFollowRequests`: `recipientId + status` · `recipientId + timestamp desc`; `receivedFollowRequests`: `senderId + status`
- `notifications`: `isPending + timestamp` · `senderId + type` · `timestamp desc + type desc`
- `visits`: `visitorId + timestamp`
- `buzzEvents`: `senderId + createdAt desc`
- `appeals`: `userId + submittedAt`

Los índices de **collection-group** sobre `moments`/`stories`/`comments` son los que hacen posible el feed y la búsqueda global pese a que el contenido cuelgue de cada usuario.

---

## 11. Checklist para el cliente Android

Estado del port: la capa de vistas todavía está incompleta — este documento es el contrato de datos, es independiente de ese avance y sirve como referencia de verificación para lo ya escrito.

1. **Verificar el `data class` de `Moment`**: campo `imageUrl` (no `imagePath`), `id` duplicado en el cuerpo, `allowSharing` con default `true`.
2. **`mediaItems == null` ≠ lista vacía**: solo `null` activa el fallback legacy de un solo medio.
3. **Filtrar por `moderationState`** en `MediaItem`, `MomentHiddenLayer` y `StickerData` antes de renderizar.
4. **`Notification.reaction`**: leer la cascada `reaction` → `reactionType` → `commentText`; `isReactionPlural` puede ser Bool o String.
5. **`MediaItem.moderatedAt`**: tolerar `Timestamp`, Double-millis e Int-millis.
6. **`AppUser.deactivatedAt`** es epoch en segundos (Double), no `Timestamp`.
7. **`Echo.participantIds`** debe ir siempre sincronizado con `participants`, o las rules deniegan el acceso.
8. **Intereses en español**, con tildes, como identidad.
9. **Reacciones**: solo los 16 valores de la lista cerrada; cualquier otro lo rechaza el servidor.
10. **`Conversation.lastDeletedAt[uid]`** es un corte de visibilidad por usuario, no un borrado — hay que aplicarlo al listar mensajes o aparecerá historial que en iOS está oculto.
11. **Cripto del chat**: replicar §7 exactamente, o los chats existentes quedan ilegibles. Máxima prioridad de verificación.
12. **Escribir siempre `Timestamp`**, nunca millis ni ISO.
