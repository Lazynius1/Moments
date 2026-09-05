# Para ti — ranking compartido v2

Implementación en iOS, Android y `getFeedPage`. Pendiente de despliegue del backend; no se han publicado las apps ni la función desde esta tarea.

## Comportamiento

- Las cuentas nuevas entran en Para ti. Al cambiar entre Siguiendo y Para ti, la lista vuelve al inicio y las respuestas de red antiguas se descartan.
- Ranking normalizado: intereses del autor 35 %, afinidad 25 %, actualidad 25 %, cercanía social 15 %. Los pesos sin historial se redistribuyen entre intereses y actualidad. La actualidad tiene una semivida de tres días.
- Cada quinto puesto intenta descubrir un autor fuera de los intereses/afinidad conocidos. Se separan autores consecutivos cuando hay alternativas y se conservan los posts vistos para el final del conjunto de candidatos.
- «No me interesa» se encuentra en el ellipsis del post del feed Para ti. Oculta optimistamente el post, confirma el guardado y ofrece Deshacer. Un fallo revierte el cambio local. No bloquea al autor, no denuncia el contenido ni afecta a Siguiendo.
- La penalización del autor es moderada; la de los intereses compartidos es menor. Ambas decaen con semivida de siete días y la penalización total está acotada. La ocultación del post concreto persiste en el servidor hasta Deshacer.
- Ocho cadenas nuevas en los 16 Localizable.strings de iOS y los 16 conjuntos equivalentes de recursos de Android.

## Datos y API

Los clientes envían `rankingVersion: 2` a `getFeedPage`, con hasta 200 puntuaciones agregadas de afinidad y las últimas 500 impresiones de hasta 30 días. Los conteos detallados y el contenido de los mensajes no se envían. Las impresiones nuevas requieren visibilidad sostenida de 1,5 segundos y no se registran en incógnito. Los datos locales se separan por cuenta.

El ranking se ordena en el servidor. Los cursores v2 utilizan el campo existente `momentId` con un identificador opaco `fy2_…`, sin añadir campos obligatorios al contrato anterior. Los clientes anteriores conservan la ruta existente; Siguiendo sigue cronológico.

`action: forYouFeedback`, junto a `authorId`, `momentId` e `intent: hide|undo`, utiliza el mismo endpoint autenticado. El servidor confirma con `accepted: true`; una respuesta de una versión anterior del endpoint no se interpreta como guardado correcto.

## Audiencias y paginación

La elegibilidad se calcula antes del ranking y se vuelve a comprobar al servir cada página. Se revisan autor, cuenta activa, bloqueos, silencios, hiddenFromUsers, archivo, programación y audiencia. No se cachean cuerpos de publicaciones en las sesiones, solo su orden y señales agregadas.

Para ti mantiene la exclusión existente de autores seguidos. Por ello, las publicaciones de mutuos quedan en Siguiendo. Solo yo queda excluido. Mejores amigos, audiencia personalizada y lista personalizada requieren permiso explícito; la restricción de perfil privado se comprueba además, de acuerdo con las reglas collectionGroup de Firestore.

Las preferencias persistentes se guardan en `users/{uid}/recommendationHidden`. Las sesiones de navegación se guardan en `users/{uid}/recommendationSessions`, son privadas al backend y mantienen un historial acotado de sesiones recientes y hasta 4.000 candidatos por sesión. Cada flujo de candidatos conserva su cursor cronológico; el orden de relevancia se congela por conjunto para evitar saltos al paginar. Las escrituras de sesión usan control de revisión para que un reintento tardío no sobrescriba un conjunto más nuevo.

La diversidad y el reparto de descubrimiento se aplican al conjunto disponible: no garantizan una proporción exacta si faltan autores alternativos. La afinidad e impresiones iniciales proceden del dispositivo; las ocultaciones persistentes son compartidas por cuenta. Un cambio de señales afecta al siguiente refresco; un cambio de permisos u ocultación se aplica al servir la siguiente página.

## Validación y entrega

Se realizaron comprobaciones iniciales durante la implementación. A petición del usuario se detuvieron los builds y tests, y se retiraron los archivos de test añadidos. Los cambios posteriores se revisaron únicamente en código. El build final de iOS lo realiza el usuario.

Corregido el orden de `.adoptForFloatingTabBar()` antes de `.id(selectedFeedType)`. En Android también se añadió el import ausente de `FeedInk` que impedía compilar Notificaciones; se conservaron las otras modificaciones preexistentes de esa pantalla.

Para activar el ranking y guardar el feedback en producción hace falta desplegar la versión actualizada de `getFeedPage` desde este repositorio.
