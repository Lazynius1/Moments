#!/usr/bin/env bash
# Monta el vídeo de previsualización de la App Store (886 × 1920, 30 fps, ≤ 30 s).
# Uso: scripts/preview/build.sh <tomas_raw> <overlays> <salida.mp4>
# Las tomas se graban del simulador en modo capturas (s8_reveal, s2_feed … s7_privacy).
set -euo pipefail
RAW="$1"; OV="$2"; OUT="$3"
TMP="$(mktemp -d)"
VF="fps=30,scale=886:-2,crop=886:1920:0:(ih-1920)/2,setsar=1"
ENC=(-c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 -b:v 10M -maxrate 12M -bufsize 20M -an)

# toma: <nº> <clip> <inicio> <fotogramas> [overlay] [velocidad]
clip() {
  local n="$1" src="$2" ss="$3" frames="$4" overlay="${5:-}" speed="${6:-1}"
  local dur; dur=$(python3 -c "print($frames/30*$speed)")
  local VF="setpts=PTS/$speed,$VF"
  if [[ -n "$overlay" ]]; then
    ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$RAW/$src.mp4" -framerate 30 -i "$OV/$overlay/%04d.png" \
      -filter_complex "[0:v]$VF[v];[v][1:v]overlay=0:0:eof_action=pass,trim=end_frame=$frames" "${ENC[@]}" "$TMP/$n.mp4"
  else
    ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$RAW/$src.mp4" -vf "$VF,trim=end_frame=$frames" "${ENC[@]}" "$TMP/$n.mp4"
  fi
}
# tarjeta: <nº> <overlay>
card() {
  ffmpeg -v error -y -framerate 30 -i "$OV/$2/%04d.png" -vf "format=yuv420p,setsar=1" "${ENC[@]}" "$TMP/$1.mp4"
}

clip 01 s8_reveal 21.0 135 t1_people 2
card 02 c2_pressure
clip 03 s2_feed    0.8 90 t3_feed
card 04 c4_tea
clip 05 s3_poll    6.3 96
clip 06 s4_hidden  1.0 96 t6_secrets
card 07 c7_chat
clip 08 s5_chat    1.0 66
clip 09 s6_map     0.8 72 t9_map
clip 10 s7_privacy 0.8 72 t10_privacy
card 11 c11_logo

for f in "$TMP"/*.mp4; do echo "file '$f'"; done | sort > "$TMP/list.txt"
ffmpeg -v error -y -f concat -safe 0 -i "$TMP/list.txt" -f lavfi -i anullsrc=r=44100:cl=stereo \
  -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest -movflags +faststart "$OUT"
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of compact "$OUT"
rm -rf "$TMP"
