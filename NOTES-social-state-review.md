# Social State Review Notes

Pendientes para revisar mas adelante:

- Endurecer Firestore Rules de `followers`/`following`; ahora hay reglas temporales demasiado permisivas para `create`.
- Asegurar bloqueos en reglas, no solo en UI/backend feed.
- Revisar lectura de perfiles inactivos: desactivado, suspendido, baneado y eliminado.
- Revisar exposicion de `customAudienceLists`; evitar filtrar nombres o miembros si no toca.
- Auditar Storage Rules para media privada, stories, mensajes y cuentas eliminadas.
- Validar acciones offline antiguas contra estado actual: bloqueado, eliminado, suspendido o privacidad cambiada.
- Unificar helper de disponibilidad publica de usuario.
- Revisar busqueda, explore, sugeridos, menciones y listas para usuarios no disponibles.
