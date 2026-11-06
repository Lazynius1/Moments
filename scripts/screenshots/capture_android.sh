#!/usr/bin/env bash
# Capturas de Google Play con el modo captura de Android (solo builds debug).
#
# Uso:
#   scripts/screenshots/capture_android.sh [carpeta_salida]
#
# Variables opcionales:
#   SERIAL=<id adb>          dispositivo (por defecto el único conectado)
#   LANGS="es en"            idiomas a capturar (por defecto los 16)
#   SCREENS="feed chat"      pantallas a capturar (por defecto las de la ficha)
#   STORY_INDEX=1            historia que abre el visor (0, 1 o 2)
#
# Cambia el idioma solo de la app y lo devuelve como estaba al terminar.
# La barra de estado usa el modo demo del sistema (09:41, batería llena).
# Resultado: <salida>/android/<idioma>/<NN>_<pantalla>.png
set -euo pipefail

OUT_DIR="${1:-$(cd "$(dirname "$0")" && pwd)/out}"
PKG="com.momentsapp"
ACTIVITY="com.moments.android.MainActivity"
STORY_INDEX="${STORY_INDEX:-1}"
ADB=(adb ${SERIAL:+-s "$SERIAL"})

ALL_LANGS="es en ca de fr it pt-BR pt-PT hi id ja ko nl pl tr zh-Hant"
ALL_SCREENS="feed storyViewer hiddenLayers chat map privacy appIcons nova"
LANGS="${LANGS:-$ALL_LANGS}"
SCREENS="${SCREENS:-$ALL_SCREENS}"

locale_for() {
  case "$1" in
    es) echo "es-ES" ;; en) echo "en-US" ;; ca) echo "ca-ES" ;; de) echo "de-DE" ;;
    fr) echo "fr-FR" ;; it) echo "it-IT" ;; pt-BR) echo "pt-BR" ;; pt-PT) echo "pt-PT" ;;
    hi) echo "hi-IN" ;; id) echo "in-ID" ;; ja) echo "ja-JP" ;; ko) echo "ko-KR" ;;
    nl) echo "nl-NL" ;; pl) echo "pl-PL" ;; tr) echo "tr-TR" ;; zh-Hant) echo "zh-TW" ;;
    *) echo "$1" ;;
  esac
}

# Mismos números de archivo que en iOS.
index_of() {
  case "$1" in
    feed) echo 01 ;; aiLabel) echo 02 ;; storyViewer) echo 03 ;; hiddenLayers) echo 04 ;;
    chat) echo 05 ;; chatInbox) echo 06 ;; echo) echo 07 ;; map) echo 08 ;;
    privacy) echo 09 ;; appIcons) echo 10 ;; nova) echo 11 ;; *) echo 99 ;;
  esac
}

wait_for() {
  case "$1" in
    map) echo 10 ;; hiddenLayers) echo 12 ;; *) echo 7 ;;
  esac
}

# Idioma de la app antes de empezar (vacío = el del sistema).
ORIGINAL_LOCALES="$("${ADB[@]}" shell cmd locale get-app-locales "$PKG" | sed -E 's/.*\[(.*)\].*/\1/' | tr -d ' \r')"

# No molestar al terminar como estaba (0 = desactivado): sin notificaciones encima de las capturas.
ORIGINAL_ZEN="$("${ADB[@]}" shell settings get global zen_mode | tr -d '\r')"

demo_mode() {
  "${ADB[@]}" shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null
}

restore() {
  "${ADB[@]}" shell am force-stop "$PKG" || true
  # Vacío = idioma del sistema (hay que pasar las comillas literales).
  "${ADB[@]}" shell cmd locale set-app-locales "$PKG" --locales "${ORIGINAL_LOCALES:-\"\"}" || true
  "${ADB[@]}" shell svc power stayon false || true
  if [[ "$ORIGINAL_ZEN" == "0" ]]; then "${ADB[@]}" shell cmd notification set_dnd off >/dev/null || true; fi
  demo_mode exit || true
  "${ADB[@]}" shell settings put global sysui_demo_allowed 0 >/dev/null || true
}
trap restore EXIT

# Pantalla siempre encendida mientras captura (si se apaga, las capturas salen en negro).
"${ADB[@]}" shell svc power stayon usb
"${ADB[@]}" shell input keyevent KEYCODE_WAKEUP
"${ADB[@]}" shell cmd notification set_dnd on >/dev/null

# Barra de estado limpia: 09:41, wifi y cobertura llenas, batería al 100 %, sin notificaciones.
"${ADB[@]}" shell settings put global sysui_demo_allowed 1 >/dev/null
demo_mode enter
demo_mode clock -e hhmm 0941
demo_mode battery -e level 100 -e plugged false
demo_mode network -e wifi show -e level 4
demo_mode network -e mobile show -e datatype none -e level 4
demo_mode notifications -e visible false

for lang in $LANGS; do
  dest="$OUT_DIR/android/$lang"
  mkdir -p "$dest"
  "${ADB[@]}" shell cmd locale set-app-locales "$PKG" --locales "$(locale_for "$lang")"
  for screen in $SCREENS; do
    nn="$(index_of "$screen")"
    echo "→ $lang / $screen"
    # -S detiene la app antes; -f nueva tarea limpia (si no, la pantalla puede no cambiar).
    "${ADB[@]}" shell am start -S -W -f 0x10008000 -n "$PKG/$ACTIVITY" \
      --es MomentsScreenshotMode "$screen" \
      --es MomentsScreenshotStoryIndex "$STORY_INDEX" >/dev/null
    sleep "$(wait_for "$screen")"
    "${ADB[@]}" exec-out screencap -p > "$dest/${nn}_${screen}.png"
    # Una captura casi vacía significa pantalla apagada o bloqueada: mejor parar.
    if [[ $(wc -c < "$dest/${nn}_${screen}.png") -lt 100000 ]]; then
      echo "Captura vacía en $lang / $screen: ¿pantalla apagada o bloqueada?" >&2
      exit 1
    fi
  done
done

echo "Listo: $OUT_DIR/android"
