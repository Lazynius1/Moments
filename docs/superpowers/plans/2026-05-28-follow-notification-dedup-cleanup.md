# Follow notifications: dedup + cleanup (implementado en local)

## Cambios

- **Functions:** IDs estables, `onFollowerRemoved`, `onFollowRequestRemoved`, purge al mutual, conteo push por senders únicos.
- **iOS:** Agrupación por `senderId`, limpieza `mutualConnection` en unfollow, accept/reject borra `followRequest_{senderId}`.
- **Migración:** `functions/scripts/migrate-follow-notifications.js`

## Probar en local

### 1. Functions (emulador o proyecto dev)

```bash
cd Moments/functions
npm install
firebase deploy --only functions:onFollowerAdded,functions:onFollowerRemoved,functions:onFollowRequestReceived,functions:onFollowRequestRemoved
```

O emulador:

```bash
firebase emulators:start --only functions,firestore
```

### 2. App iOS

Compilar y ejecutar contra el mismo proyecto Firebase que despliegues.

### 3. Limpiar datos viejos (tu usuario)

```bash
cd Moments/functions
node scripts/migrate-follow-notifications.js TU_USER_ID
```

### 4. QA manual

1. Usuario A follow/unfollow a B ×3 → B ve **una** fila de A (o ninguna si no le sigue).
2. A unfollow → notificación de A desaparece en B sin tocar la app.
3. A→B luego B→A → ambos `mutualConnection`; B **no** conserva `newFollower` de A si el mutual purga bien.
4. Solicitud repetida → una fila `followRequest` por solicitante.

## Subir al repo

Cuando pase QA: commit de `functions/index.js`, `NotificationsView.swift`, `FirestoreService.swift`, docs y script de migración.
