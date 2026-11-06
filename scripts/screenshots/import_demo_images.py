#!/usr/bin/env python3
"""Imágenes de demostración del modo captura (solo Debug).

Copia las imágenes reales de una carpeta a ScreenshotAssets.xcassets,
recortando al centro a la proporción de cada asset y guardando JPEG.

Uso:
    python3 scripts/screenshots/import_demo_images.py <carpeta>
    python3 scripts/screenshots/import_demo_images.py --placeholders

Nombres esperados en la carpeta (png/jpg/jpeg/webp):
    avatar_lucia, avatar_theo, avatar_aiko, avatar_mateo, avatar_nora,
    avatar_sam, avatar_ines, avatar_kai, avatar_me (o me)
    moment_beach_sunset, moment_rooftop_dinner, moment_mountain_lake,
    moment_latte, moment_concert, moment_night_market, moment_dog_park,
    moment_road_trip, moment_picnic, moment_ski, moment_birthday,
    moment_lisbon_tram
    story_festival, story_sunrise, story_cooking
    hidden_polaroid, chat_photo, chat_background (-> ss_wallpaper)

Requiere Pillow.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = REPO_ROOT / "Moments" / "DebugScreenshots" / "ScreenshotAssets.xcassets"

SQUARE = (1024, 1024)
PORTRAIT = (1080, 1350)
TALL = (1080, 1920)

AVATARS = ["lucia", "theo", "aiko", "mateo", "nora", "sam", "ines", "kai"]
MOMENTS = [
    "beach_sunset", "rooftop_dinner", "mountain_lake", "latte", "concert",
    "night_market", "dog_park", "road_trip", "picnic", "ski", "birthday",
    "lisbon_tram",
]
STORIES = ["festival", "sunrise", "cooking"]

# asset -> (tamaño, nombres de origen aceptados)
ASSETS = {}
for name in AVATARS:
    ASSETS[f"ss_avatar_{name}"] = (SQUARE, [f"avatar_{name}"])
ASSETS["ss_me"] = (SQUARE, ["avatar_me", "me"])
for name in MOMENTS:
    ASSETS[f"ss_moment_{name}"] = (PORTRAIT, [f"moment_{name}"])
for name in STORIES:
    ASSETS[f"ss_story_{name}"] = (TALL, [f"story_{name}"])
ASSETS["ss_hidden_polaroid"] = (SQUARE, ["hidden_polaroid"])
ASSETS["ss_chat_photo"] = (PORTRAIT, ["chat_photo"])
ASSETS["ss_wallpaper"] = (TALL, ["chat_background", "wallpaper"])

SOURCE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".heic")
IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".heic", ".pdf")


def center_crop(image, size):
    target_w, target_h = size
    target_ratio = target_w / target_h
    w, h = image.size
    if w / h > target_ratio:
        new_w = int(round(h * target_ratio))
        left = (w - new_w) // 2
        box = (left, 0, left + new_w, h)
    else:
        new_h = int(round(w / target_ratio))
        top = (h - new_h) // 2
        box = (0, top, w, top + new_h)
    return image.crop(box).resize(size, Image.LANCZOS)


def write_imageset(catalog, asset, image):
    imageset = catalog / f"{asset}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    for old in imageset.iterdir():
        if old.suffix.lower() in IMAGE_EXTENSIONS:
            old.unlink()
    filename = f"{asset}.jpg"
    image.convert("RGB").save(imageset / filename, "JPEG", quality=90, optimize=True)
    contents = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def ensure_catalog(catalog):
    catalog.mkdir(parents=True, exist_ok=True)
    root = catalog / "Contents.json"
    if not root.exists():
        root.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def find_source(folder, names):
    for name in names:
        for ext in SOURCE_EXTENSIONS:
            for candidate in (folder / f"{name}{ext}", folder / f"{name}{ext.upper()}"):
                if candidate.exists():
                    return candidate
    return None


def import_folder(folder, catalog):
    ensure_catalog(catalog)
    imported, missing = [], []
    for asset, (size, names) in ASSETS.items():
        source = find_source(folder, names)
        if source is None:
            missing.append(names[0])
            continue
        with Image.open(source) as image:
            write_imageset(catalog, asset, center_crop(image, size))
        imported.append(f"{source.name} -> {asset}")
    for line in imported:
        print(f"  {line}")
    print(f"Importadas {len(imported)} de {len(ASSETS)}.")
    if missing:
        print("Sin archivo (se mantiene el actual): " + ", ".join(missing))


def placeholder(asset, size, index):
    palettes = [
        ((91, 44, 111), (200, 109, 215)),
        ((11, 18, 21), (63, 111, 143)),
        ((255, 159, 28), (255, 107, 107)),
        ((6, 214, 160), (17, 138, 178)),
        ((58, 134, 255), (131, 56, 236)),
        ((247, 220, 111), (255, 160, 122)),
    ]
    top, bottom = palettes[index % len(palettes)]
    w, h = size
    gradient = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        gradient.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    image = gradient.resize(size)
    draw = ImageDraw.Draw(image)
    label = asset.replace("ss_", "")
    font = None
    for candidate in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            font = ImageFont.truetype(candidate, max(28, w // 16))
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
    box = draw.textbbox((0, 0), label, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    draw.text(((w - tw) / 2, (h - th) / 2), label, fill=(255, 255, 255), font=font)
    return image


def generate_placeholders(catalog):
    ensure_catalog(catalog)
    for index, (asset, (size, _)) in enumerate(ASSETS.items()):
        write_imageset(catalog, asset, placeholder(asset, size, index))
    print(f"Generados {len(ASSETS)} placeholders en {catalog}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", nargs="?", help="Carpeta con las imágenes reales")
    parser.add_argument("--placeholders", action="store_true", help="Genera degradados con el nombre del asset")
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG), help="Ruta a ScreenshotAssets.xcassets")
    args = parser.parse_args()

    catalog = Path(args.catalog)
    if args.placeholders:
        generate_placeholders(catalog)
        return 0
    if not args.folder:
        parser.error("indica una carpeta o --placeholders")
    folder = Path(args.folder).expanduser()
    if not folder.is_dir():
        parser.error(f"no existe la carpeta {folder}")
    import_folder(folder, catalog)
    return 0


if __name__ == "__main__":
    sys.exit(main())
