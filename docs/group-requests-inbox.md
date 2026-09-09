# Solicitudes de grupos en Mensajes

Implementación del flujo aprobado en la imagen de tres pantallas: conversaciones, recibidas y enviadas.

## Experiencia en iOS y Android

- La bandeja sustituye las invitaciones desplegadas por una fila «Solicitudes de grupos» debajo del buscador, con el total de invitaciones recibidas y peticiones de entrada enviadas. El acceso se mantiene si el total es cero; en ese caso se oculta el contador.
- La pantalla de solicitudes tiene dos pestañas, cada una con su contador. Muestra avatar, nombre, fecha relativa y estado de cada grupo, sin acceso al historial antes de ser miembro.
- Recibidas permite Aceptar y Rechazar. Aceptar abre la conversación; rechazar retira la invitación. Pie: «Acepta una invitación para entrar al chat.»
- Enviadas muestra «Pendiente de aprobación» y «Cancelar solicitud». Pie: «El grupo aparecerá en tus conversaciones cuando te acepten.»
- Al cancelar se elimina la petición del usuario y de la lista de pendientes del administrador. Si la aceptación ya ganó la carrera, cancelar no expulsa al nuevo miembro.
- Las listas se actualizan mediante listeners. Incluyen carga, estados vacíos, errores con reintento y prevención de acciones repetidas durante una petición.
- Textos sincronizados en los 16 idiomas existentes, preservando los textos de botones y pies del diseño aprobado.

## Backend y acceso

`manageGroup` incorpora dos acciones:

- `listJoinRequests`: consulta las peticiones del usuario autenticado y resuelve en el servidor el nombre y avatar del grupo. Permite mostrar también solicitudes anteriores a este cambio, sin migración ni acceso del solicitante al documento privado del grupo. La respuesta solo incluye identificador, grupo, nombre, avatar y fecha.
- `cancelJoin`: elimina exclusivamente la petición de quien realiza la llamada y actualiza `pendingJoinIds` y `pendingJoinNames` en la misma transacción. Reintentar una cancelación ya resuelta no modifica la pertenencia al grupo.

Las reglas permiten al solicitante leer sus propios documentos de `groupJoinRequests`; las escrituras siguen reservadas al backend. Las consultas usan igualdad por `recipientId`, sin índices compuestos nuevos.

## Archivos principales

- iOS: `GroupChatStore.swift` (`GroupRequestsStore`), `GroupChatViews.swift` (entrada, pantalla y filas) y `MessagingView.swift` (navegación).
- Android: los equivalentes `GroupChatStore.kt`, `GroupChatViews.kt` y `MessagingView.kt`.
- Backend: `functions/src/registers/http-groups.js` y `firestore.rules`.
- Copy: `scripts/sync-group-requests-localizations.py` actualiza solo las claves de esta pantalla.

## Validación

Revisión de los cambios, `node --check`, `git diff --check`, lectura de XML Android y `plutil -lint` para localizaciones iOS. No se han ejecutado builds ni tests de aplicaciones por indicación del usuario.

Despliegue completado en `glowsy-6a40e`: actualización de `manageGroup` en `europe-southwest1` y publicación de las reglas de Firestore. Firebase confirmó `Successful update operation` y `Deploy complete`. No se han publicado binarios de las apps.
