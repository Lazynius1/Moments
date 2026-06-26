#!/usr/bin/env bash
# Localization guardrails for Moments iOS app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOMENTS_DIR="$ROOT/Moments"
FAILED=0

echo "==> Checking hardcoded Spanish locales in Swift..."
if rg -n 'Locale\(identifier:\s*"(es|es_ES)"' "$MOMENTS_DIR" --glob '*.swift' 2>/dev/null; then
  echo "ERROR: Found hardcoded es/es_ES locale identifiers."
  FAILED=1
else
  echo "OK: No hardcoded es/es_ES locales."
fi

echo "==> Checking RelativeDateTimeFormatter outside MomentsFormat..."
if rg -l 'RelativeDateTimeFormatter' "$MOMENTS_DIR" --glob '*.swift' | rg -v 'MomentsFormat.swift' 2>/dev/null; then
  echo "ERROR: RelativeDateTimeFormatter found outside MomentsFormat.swift"
  FAILED=1
else
  echo "OK: RelativeDateTimeFormatter centralized."
fi

echo "==> Comparing Localizable.strings key counts..."
BASE="$MOMENTS_DIR/en.lproj/Localizable.strings"
BASE_COUNT=$(rg -o '^"[^"]+"' "$BASE" | sort -u | wc -l | tr -d ' ')
for locale in es ca de fr it pt-BR pt-PT; do
  FILE="$MOMENTS_DIR/$locale.lproj/Localizable.strings"
  COUNT=$(rg -o '^"[^"]+"' "$FILE" | sort -u | wc -l | tr -d ' ')
  DELTA=$((BASE_COUNT - COUNT))
  if (( DELTA > 25 )); then
    echo "WARN: $locale is missing $DELTA keys vs en ($COUNT vs $BASE_COUNT)"
  else
    echo "OK: $locale key parity ($COUNT / $BASE_COUNT)"
  fi
done

if (( FAILED > 0 )); then
  exit 1
fi

echo "All localization checks passed."
