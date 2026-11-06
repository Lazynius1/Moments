#!/usr/bin/env bash
# Capturas de la App Store con el modo captura (solo builds Debug).
#
# Uso:
#   scripts/screenshots/capture.sh <udid> <ruta/Moments Social.app> [etiqueta_dispositivo] [carpeta_salida]
#
# Variables opcionales:
#   LANGS="es en"            idiomas a capturar (por defecto los 16)
#   SCREENS="feed chat"      pantallas a capturar (por defecto todas)
#   SCREEN_DISPLAY=<uuid>    pantalla concreta (Duo: interior abierto o exterior)
#   STORY_INDEX=1            historia que abre el visor (0, 1 o 2)
#
# Resultado: <salida>/<dispositivo>/<idioma>/<NN>_<pantalla>.png
set -euo pipefail

if [[ $# -lt 2 ]]; then
  sed -n '2,12p' "$0"
  exit 1
fi

UDID="$1"
APP_PATH="$2"
DEVICE_LABEL="${3:-$(xcrun simctl list devices | grep "$UDID" | sed -E 's/^ *([^(]+) \(.*/\1/' | sed -E 's/ +$//' | tr ' ' '_')}"
OUT_DIR="${4:-$(cd "$(dirname "$0")" && pwd)/out}"
BUNDLE_ID="com.glowsyapp"
STORY_INDEX="${STORY_INDEX:-1}"

ALL_LANGS="es en ca de fr it pt-BR pt-PT hi id ja ko nl pl tr zh-Hant"
ALL_SCREENS="feed aiLabel storyViewer hiddenLayers chat chatInbox echo map privacy appIcons nova"
LANGS="${LANGS:-$ALL_LANGS}"
SCREENS="${SCREENS:-$ALL_SCREENS}"

locale_for() {
  case "$1" in
    es) echo "es_ES" ;;
    en) echo "en_US" ;;
    ca) echo "ca_ES" ;;
    de) echo "de_DE" ;;
    fr) echo "fr_FR" ;;
    it) echo "it_IT" ;;
    pt-BR) echo "pt_BR" ;;
    pt-PT) echo "pt_PT" ;;
    hi) echo "hi_IN" ;;
    id) echo "id_ID" ;;
    ja) echo "ja_JP" ;;
    ko) echo "ko_KR" ;;
    nl) echo "nl_NL" ;;
    pl) echo "pl_PL" ;;
    tr) echo "tr_TR" ;;
    zh-Hant) echo "zh_TW" ;;
    *) echo "en_US" ;;
  esac
}

wait_for() {
  case "$1" in
    map) echo 9 ;;
    hiddenLayers) echo 13 ;;
    *) echo 7 ;;
  esac
}

index_of() {
  local target="$1" i=1
  for screen in $ALL_SCREENS; do
    if [[ "$screen" == "$target" ]]; then
      printf "%02d" "$i"
      return
    fi
    i=$((i + 1))
  done
  echo "99"
}

echo "Simulador: $UDID ($DEVICE_LABEL)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --operatorName "" \
  --batteryState charged \
  --batteryLevel 100

xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" || true
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID" || true
xcrun simctl location "$UDID" set 41.3874,2.1686

for lang in $LANGS; do
  locale="$(locale_for "$lang")"
  dest="$OUT_DIR/$DEVICE_LABEL/$lang"
  mkdir -p "$dest"
  for screen in $SCREENS; do
    nn="$(index_of "$screen")"
    echo "→ $lang / $screen"
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
      -MomentsScreenshotMode "$screen" \
      -MomentsScreenshotStoryIndex "$STORY_INDEX" \
      -AppleLanguages "($lang)" \
      -AppleLocale "$locale" >/dev/null
    sleep "$(wait_for "$screen")"
    # SCREEN_DISPLAY: pantalla a capturar en dispositivos con varias (p. ej. el Duo abierto).
    xcrun simctl io "$UDID" screenshot ${SCREEN_DISPLAY:+--display="$SCREEN_DISPLAY"} "$dest/${nn}_${screen}.png" >/dev/null
  done
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear || true
echo "Listo: $OUT_DIR/$DEVICE_LABEL"
