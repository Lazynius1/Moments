#!/usr/bin/env python3
"""Encola en un ComfyUI de la red las imágenes de demo del modo capturas y las descarga.

Uso:
  python3 comfy_generate.py --host http://192.168.1.135:8188 --out <carpeta> [--only avatar_lucia,...] [--seed N]
Las imágenes salen con los nombres que espera import_demo_images.py.
"""
import argparse
import json
import os
import random
import time
import urllib.parse
import urllib.request

STYLE = (
    "candid photo taken with a recent smartphone, natural light, realistic skin texture, "
    "clean warm colors, shallow depth of field, authentic everyday moment"
)
NEGATIVE = (
    "text, watermark, logo, signature, frame, border, user interface, deformed hands, extra fingers, "
    "blurry, lowres, cartoon, illustration, child, teenager, minor, nudity, cleavage, swimwear, celebrity, oversaturated, orange skin"
)

# nombre → (ancho, alto, descripción)
SQUARE = (1024, 1024)
PORTRAIT = (896, 1120)
STORY = (720, 1280)
IMAGES = {
    "avatar_lucia": (*SQUARE, "head and shoulders portrait of a young woman with wavy brown hair, warm smile, sunset light, blurred outdoor background"),
    "avatar_theo": (*SQUARE, "head and shoulders portrait of a young man with a short beard and a wool beanie, city street blurred behind"),
    "avatar_aiko": (*SQUARE, "head and shoulders portrait of a young Japanese woman with bangs, soft indoor window light"),
    "avatar_mateo": (*SQUARE, "head and shoulders portrait of a young Latino man with curly hair, white t-shirt, beach blurred behind"),
    "avatar_nora": (*SQUARE, "head and shoulders portrait of a young Black woman with braids, sunglasses on her head, green park blurred behind"),
    "avatar_sam": (*SQUARE, "head and shoulders portrait of an androgynous adult in their late twenties with short dyed hair, light stubble and a hoodie, city lights at night"),
    "avatar_ines": (*SQUARE, "head and shoulders portrait of a young woman with straight dark hair and a denim jacket, cafe terrace"),
    "avatar_kai": (*SQUARE, "head and shoulders portrait of a young Southeast Asian man with a big smile, mountains behind"),
    "avatar_me": (*SQUARE, "head and shoulders portrait of a young adult man in his late twenties with dark tousled hair and a light beard, olive overshirt, relaxed smile, golden hour on a city terrace"),
    "moment_beach_sunset": (*PORTRAIT, "group of friends seen from behind watching the sunset on a Mediterranean beach"),
    "moment_rooftop_dinner": (*PORTRAIT, "dinner on a Barcelona rooftop with string lights, plates and glasses on the table, evening"),
    "moment_mountain_lake": (*PORTRAIT, "person sitting on a rock in front of a turquoise mountain lake at sunrise"),
    "moment_latte": (*PORTRAIT, "top-down view of a latte with latte art on a wooden table, a hand holding the cup"),
    "moment_concert": (*PORTRAIT, "concert crowd from inside, purple and blue stage lights, hands raised"),
    "moment_night_market": (*PORTRAIT, "street food stall at night with steam and warm lights"),
    "moment_dog_park": (*PORTRAIT, "golden retriever running happily in a park in autumn"),
    "moment_road_trip": (*PORTRAIT, "camper van on a coastal road, side door open, golden hour"),
    "moment_picnic": (*PORTRAIT, "top-down view of a picnic blanket on grass with fruit, bread, cheese and lemonade glasses, no people"),
    "moment_ski": (*PORTRAIT, "two friends in ski gear laughing on a snowy summit, blue sky"),
    "moment_birthday": (*PORTRAIT, "birthday cake with lit candles on a table, friends blurred in the background"),
    "moment_lisbon_tram": (*PORTRAIT, "yellow tram on a steep street in Lisbon at golden hour"),
    "story_festival": (*STORY, "wide shot of an outdoor music festival crowd at dusk seen from behind, stage lights, string lights and confetti in the air"),
    "story_sunrise": (*STORY, "sunrise on a beach with the shoreline in the foreground"),
    "story_cooking": (*STORY, "hands making fresh pasta in a bright kitchen"),
    "hidden_polaroid": (*SQUARE, "old analog film photo of two friends laughing, film grain, faded colors"),
    "chat_photo": (*PORTRAIT, "view from an airplane window over snowy mountains"),
    "chat_background": (*STORY, "soft abstract gradient background in pastel lilac, peach and blue, subtle film grain, no objects"),
}


def workflow(name, width, height, description, seed):
    is_background = name == "chat_background"
    positive = description if is_background else f"{description}, {STYLE}"
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "uncannyPhotorealism_v13_full_fp8.safetensors", "weight_dtype": "default"}},
        "22": {"class_type": "LoraLoaderModelOnly", "inputs": {"model": ["1", 0], "lora_name": "estilo\\lenovo_chroma.safetensors", "strength_model": 0.0 if is_background else 0.5}},
        "3": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["22", 0], "shift": 1.0}},
        "4": {"class_type": "CLIPLoader", "inputs": {"clip_name": "t5xxl_fp8_e4m3fn.safetensors", "type": "chroma", "device": "default"}},
        "5": {"class_type": "T5TokenizerOptions", "inputs": {"clip": ["4", 0], "min_padding": 1, "min_length": 0}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["5", 0], "text": positive}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["5", 0], "text": NEGATIVE}},
        "8": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "10": {"class_type": "BasicScheduler", "inputs": {"model": ["3", 0], "scheduler": "bong_tangent", "steps": 35, "denoise": 1.0}},
        "11": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "res_2m"}},
        "102": {"class_type": "CFGGuider", "inputs": {"model": ["3", 0], "positive": ["6", 0], "negative": ["7", 0], "cfg": 3.3}},
        "103": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "104": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["103", 0], "guider": ["102", 0], "sampler": ["11", 0], "sigmas": ["10", 0], "latent_image": ["8", 0]}},
        "14": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "105": {"class_type": "VAEDecode", "inputs": {"samples": ["104", 0], "vae": ["14", 0]}},
        "106": {"class_type": "SaveImage", "inputs": {"images": ["105", 0], "filename_prefix": f"moments_demo/{name}"}},
    }


def request(host, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(host + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as res:
        return res.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    parser.add_argument("--seed", type=int, default=None)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    names = [n for n in args.only.split(",") if n] or list(IMAGES)

    pending = {}
    for name in names:
        width, height, description = IMAGES[name]
        seed = args.seed if args.seed is not None else random.randint(1, 2**31)
        prompt_id = json.loads(request(args.host, "/prompt", {"prompt": workflow(name, width, height, description, seed)}))["prompt_id"]
        pending[prompt_id] = name
        print(f"en cola {name} ({prompt_id})", flush=True)

    while pending:
        time.sleep(15)
        for prompt_id, name in list(pending.items()):
            history = json.loads(request(args.host, f"/history/{prompt_id}")).get(prompt_id)
            if not history:
                continue
            for output in history.get("outputs", {}).values():
                for image in output.get("images", []):
                    query = urllib.parse.urlencode({k: image[k] for k in ("filename", "subfolder", "type")})
                    with open(os.path.join(args.out, f"{name}.png"), "wb") as f:
                        f.write(request(args.host, f"/view?{query}"))
            print(f"lista {name}", flush=True)
            del pending[prompt_id]


if __name__ == "__main__":
    main()
