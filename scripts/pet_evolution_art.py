"""Generate the 5 evolution artworks (evo1..final) for pets and upload to the CDN.

Usage: python3 scripts/pet_evolution_art.py <slug=Name=species=descr> ...
Prints SQL UPDATE statements for public.pets on success.
Needs: LOVABLE_API_KEY, lovable-assets CLI.
"""
import base64
import io
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import requests
from PIL import Image

API_KEY = os.environ["LOVABLE_API_KEY"]
OUT = "/tmp/pet-evo"
os.makedirs(OUT, exist_ok=True)

STAGES = [
    ("evo1", "young awakened form, slightly larger, first magical markings glowing faintly"),
    ("evo2", "adolescent form, stronger build, clear elemental aura and ornamental details"),
    ("evo3", "adult form, imposing and battle-ready, rich elemental effects and armored accents"),
    ("evo4", "ascended form, majestic and powerful, radiant energy, ornate magical regalia"),
    ("final", "divine cosmic apex form, colossal presence, brilliant energy storms, celestial ornaments"),
]


def prompt_for(name, species, descr, stage_look):
    kind = species.replace("_", " ")
    return (
        f"Dark epic fantasy creature companion art: {kind} named {name}. {descr} "
        f"Evolution stage: {stage_look}. Single creature centered, full body, facing viewer, "
        "highly detailed painterly 3D render, dramatic rim lighting, vibrant magical effects, "
        "mobile gacha game companion asset, on a solid white background, "
        "no text, no letters, no logo, no interface, no frame, no border."
    )


def generate(job):
    slug, name, species, descr, stage, look = job
    path = f"{OUT}/{slug}-{stage}.png"
    if os.path.exists(path) and os.path.getsize(path) > 10000:
        return slug, stage, path, None
    body = {
        "model": "openai/gpt-image-1-mini",
        "prompt": prompt_for(name, species, descr, look),
        "size": "1024x1024",
        "quality": "medium",
        "background": "transparent",
        "n": 1,
    }
    last = "unknown"
    for _ in range(3):
        try:
            r = requests.post(
                "https://ai.gateway.lovable.dev/v1/images/generations",
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
                json=body,
                timeout=900,
            )
            if r.status_code != 200:
                last = f"{r.status_code} {r.text[:200]}"
                continue
            b64 = (r.json().get("data") or [{}])[0].get("b64_json")
            if not b64:
                last = "no image payload"
                continue
            img = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGBA")
            img.thumbnail((768, 768), Image.Resampling.LANCZOS)
            img.save(path, "PNG", optimize=True)
            return slug, stage, path, None
        except Exception as exc:  # noqa: BLE001
            last = str(exc)[:200]
    return slug, stage, None, last


def upload(path, slug, stage):
    out = subprocess.run(
        ["lovable-assets", "create", "--file", path, "--filename", f"{slug}-{stage}.png"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)["url"]


def main():
    pets = []
    for arg in sys.argv[1:]:
        slug, name, species, descr = arg.split("=", 3)
        pets.append((slug, name, species, descr))
    jobs = [(s, n, sp, d, st, lk) for s, n, sp, d in pets for st, lk in STAGES]

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(generate, jobs))
    failed = [(s, st, e) for s, st, p, e in results if not p]
    for s, st, e in failed:
        print("FAIL", s, st, e, file=sys.stderr)
    if failed:
        sys.exit(1)

    urls = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        uploaded = list(pool.map(lambda r: (r[0], r[1], upload(r[2], r[0], r[1])), results))
    for s, st, url in uploaded:
        urls.setdefault(s, {})[st] = url

    for slug, m in urls.items():
        sets = ", ".join(f"image_{st}_url = '{m[st]}'" for st, _ in STAGES)
        print(f"UPDATE public.pets SET {sets} WHERE slug = '{slug}';")


if __name__ == "__main__":
    main()
