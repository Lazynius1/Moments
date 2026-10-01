# Música en historias y overlays del chat — 1 de octubre de 2026

## Música

- Integración de Soundstripe mediante Functions autenticadas; la clave permanece en Secret Manager.
- Catálogo con búsqueda y paginación automática, preview de audio y selección flotante antes de pasar al editor.
- Editor de música integrado en el canvas: selección de fragmento desplazando ondas reales bajo una ventana fija, selector de duración y línea de tiempo de la canción.
- Estilos oculto (solo header), título, tarjeta horizontal, portada vertical y disco giratorio. Lyrics desactivado en la interfaz mientras no haya sincronización karaoke.
- Iconos personalizados, selección con el degradado del story ring, paletas según el estilo y tamaños compartidos entre plataformas.
- Stickers con posición, escala y rotación normalizadas; conservan su forma y no interceptan los gestos del resto del canvas.
- Reproducción del fragmento en el viewer y adaptación del header: tiempo junto al username y canción debajo.
- Pestañas Canciones, Descubre con playlists de Soundstripe y Guardadas vinculadas a la cuenta.
- Ficha de pista desde el header del viewer: pausa la historia, permite escuchar y guardar/quitar favoritos; al cerrarla se reanuda el viewer.
- Grid vertical de tres columnas debajo de la ficha, todavía con placeholders. Los posts aún no admiten música y no se consulta ni muestra contenido de otros usuarios en ese grid.
- Confirmaciones de favoritos mediante el in-app banner habitual de dos segundos, después de confirmar la escritura en la DB.
- Textos de música y favoritos en los 16 idiomas de la aplicación.
- El acceso para añadir música sigue limitado a DEBUG. Los favoritos son acciones explícitas; no se almacena historial de búsqueda o escucha.

## Chat y galería

- Los medios enviados desde el editor con «mantener en el chat» conservan stickers y textos como metadata; el dibujo permanece integrado en el medio.
- Overlay estático compartido en bubbles, grupos de medios y galería de la conversación; overlay vivo en el detalle activo.
- Reveal conserva su estado por mensaje en el dispositivo para mostrar el contenido revelado en las distintas superficies del chat.
- Normalización de overlays siguiendo el canvas de archivo de historias y sus previews.
- Al abrir el detalle se conserva la metadata del mensaje seleccionado, aunque otra copia del listado todavía esté incompleta.
- Detalle con back a la izquierda y cápsula de cerrar/descargar a la derecha; se elimina el cierre mediante drag hacia abajo.
- Miniaturas visibles mientras se descarga o resuelve el medio, sin blur añadido sobre previews de calidad normal. La imagen local tiene prioridad y la miniatura se mantiene durante la transición de carga.

## Detalles iOS

- Render nativo de música desde metadata, incluyendo stickers creados en Android cuya imagen raster anterior era transparente.
- Componentes de glass nativos para las acciones; Previsualizar usa glassProminent con tint y contraste según color scheme.
- Barra de estado visible en el detalle de medios del chat.
- Se evita reconstruir los overlays codificando todo el payload en cada actualización de la vista; se actualizan cuando cambian sus datos o la escala.

## Backend

Functions incorporadas: getStoryMusicCatalog, getStoryMusicTrack, getStoryMusicDiscover, getStoryMusicSaved y setStoryMusicSaved.

Guardadas utiliza users/{uid}/savedMusic/{trackId}, con metadata de la pista y fecha. El uid procede del token autenticado, no del body. No se guardan URLs firmadas de audio en favoritos.

Las tres Functions nuevas de Descubre/Guardadas están desplegadas en glowsy-6a40e, europe-southwest1.

## Validación y límites

- Nueve tests de Functions pasan: normalización, cursores, errores, acceso autenticado a favoritos, eliminación y playlists paginadas.
- Se contrastó la respuesta real del API de playlists usando el secreto existente, sin exportar la clave.
- Sintaxis Swift revisada con swiftc -frontend -parse -D DEBUG.
- El usuario ha compilado iOS y confirma que funciona. El agente no ha ejecutado una compilación iOS; los recorridos completos siguen sujetos a comprobación en dispositivo.
