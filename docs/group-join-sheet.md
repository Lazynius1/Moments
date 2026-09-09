# Sheet de acceso por enlace

Implementado en iOS y Android según el diseño aprobado de nueve estados:

1. Cargando: indicador y texto de preparación.
2. Entrada directa: avatar, nombre, descripción y «Unirme al grupo». Sin pie adicional.
3. Requiere aprobación: «Solicitar acceso» y pie «Podrás entrar al chat cuando te acepten».
4. Enviando/entrando: botón deshabilitado con indicador, según el modo de acceso.
5. Solicitud enviada: Lottie una sola vez, «Entendido» y «Ver solicitudes».
6. Pendiente de aprobación: estado recuperado del servidor, «Ver solicitudes» y «Cancelar solicitud».
7. Error: mensaje según la operación fallida, reintento y cerrar.
8. Enlace no disponible: explicación y «Entendido».
9. Grupo completo: explicación y «Entendido».

«Ver solicitudes» cierra el sheet y abre Enviadas. El acceso normal desde Mensajes abre Recibidas. El contenido permite desplazamiento y respeta Reducir movimiento con un check estático. El Lottie suministrado está en `group_join_request_sent.json` en ambos proyectos; referencia: https://lottiefiles.com/free-animation/message-sent-successfully-plane-QbtxbRhyJI.

El backend consulta pertenencia y solicitud pendiente antes de exigir que el enlace siga activo. Repetir una solicitud confirmada es idempotente, conserva su fecha y no vuelve a mostrar la celebración. Comprueba el aforo y detecta cambios en el requisito de aprobación entre la previsualización y el envío. Cancelar conserva una pertenencia ya aceptada. Un listener y la vuelta al primer plano refrescan el estado pendiente.

Archivos principales: `GroupJoinSheet.swift`, `GroupJoinSheetStore.swift` y sus equivalentes Kotlin; navegación en `MessagingView` y `TabBarView`; transporte `GroupChatAPI`; backend `functions/src/registers/http-groups.js`. Las 27 claves de texto se sincronizan en 16 idiomas mediante `scripts/sync-group-sheet-localizations.py`.

Validación: revisión de código, `node --check`, `git diff --check`, localizaciones iOS con `plutil`, XML Android, claves duplicadas y cobertura de textos. No se han ejecutado builds ni tests de aplicaciones, por indicación del usuario; la presentación en dispositivo queda sin verificar.

Despliegue completado el 9 de septiembre de 2026: `manageGroup` en `glowsy-6a40e`, región `europe-southwest1`. Firebase confirmó `Successful update operation` y `Deploy complete` con salida 0. Este cambio no requiere nuevas reglas ni índices. No se han publicado binarios de las apps.
