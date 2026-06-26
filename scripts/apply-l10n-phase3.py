#!/usr/bin/env python3
"""Apply or update phase-3 localization keys in Moments .lproj files."""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_PATH = os.path.join(ROOT, "scripts", "l10n-phase3-keys.json")

LOCALE_DIRS = {
    "en": "en",
    "es": "es",
    "ca": "ca",
    "de": "de",
    "fr": "fr",
    "it": "it",
    "pt-BR": "pt-BR",
    "pt-PT": "pt-PT",
}

KEY_LINE_RE = re.compile(r'^("(?P<key>[^"]+)"\s*=\s*")(?P<value>(?:\\.|[^"])*)(";\s*)$')


def escape_strings_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def upsert_keys(strings_path: str, keys: dict[str, str]) -> tuple[int, int]:
    with open(strings_path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    existing_indexes: dict[str, int] = {}
    for index, line in enumerate(lines):
        match = KEY_LINE_RE.match(line)
        if match:
            existing_indexes[match.group("key")] = index

    updated = 0
    inserted = 0
    for key, value in keys.items():
        escaped = escape_strings_value(value)
        new_line = f'"{key}" = "{escaped}";'
        if key in existing_indexes:
            lines[existing_indexes[key]] = new_line
            updated += 1
        else:
            lines.append(new_line)
            inserted += 1

    with open(strings_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    return updated, inserted


def main() -> None:
    with open(JSON_PATH, encoding="utf-8") as f:
        catalog = json.load(f)

    for locale_code, folder in LOCALE_DIRS.items():
        if locale_code not in catalog:
            print(f"skip missing catalog locale {locale_code}")
            continue
        strings_path = os.path.join(ROOT, "Moments", f"{folder}.lproj", "Localizable.strings")
        if not os.path.exists(strings_path):
            print(f"skip missing {strings_path}")
            continue
        updated, inserted = upsert_keys(strings_path, catalog[locale_code])
        print(f"{locale_code}: updated {updated}, inserted {inserted}")


if __name__ == "__main__":
    main()
