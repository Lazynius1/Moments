#!/usr/bin/env python3
"""Prepara las capturas de Android para el montaje de Google Play.

Quita los iconos de la barra de estado (hora, notificaciones del móvil) y la barra de
navegación del sistema. Donde el fondo de arriba es liso, añade una franja de ese mismo
color para que la UI no quede pegada al borde del marco (como en iPhone, que conserva su
barra de estado); donde no lo es (mapa, fondo del chat) recorta la barra entera.

Uso:
    python3 scripts/screenshots/prepare_android.py <capturas>/android <salida>
Requiere Pillow.
"""

import sys
from pathlib import Path

from PIL import Image

STATUS_BAR = 104      # alto de la barra de estado del móvil de capturas (px)
ICONS_END = 92        # los iconos acaban antes de esta fila
NAV_BAR = 130         # barra de navegación de tres botones (px)
TOP_BAND = 60         # franja añadida arriba cuando el fondo es liso


def is_flat(row):
    """Fila casi de un solo color (fondo de la app)."""
    first = row[0]
    return all(sum(abs(a - b) for a, b in zip(px, first)) < 12 for px in row)


def prepare(src: Path, dst: Path):
    image = Image.open(src).convert("RGB")
    width, height = image.size
    body = image.crop((0, ICONS_END, width, height - NAV_BAR))
    top_row = [body.getpixel((x, 0)) for x in range(0, width, 4)]
    if is_flat(top_row):
        out = Image.new("RGB", (width, body.height + TOP_BAND), top_row[0])
        out.paste(body, (0, TOP_BAND))
    else:
        out = body.crop((0, STATUS_BAR - ICONS_END, width, body.height))
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    files = sorted(source.glob("*/*.png"))
    for src in files:
        prepare(src, output / src.parent.name / src.name)
    print(f"Preparadas {len(files)} capturas en {output}")


if __name__ == "__main__":
    main()
