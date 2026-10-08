"""Generate art for 15 new common + 15 new uncommon Mythreon heroes, upload, upsert into hero_catalog.

Usage: python3 scripts/mythreon_hero_expansion_v3.py
Needs: LOVABLE_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""
import base64
import io
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import requests
from PIL import Image

API_KEY = os.environ["LOVABLE_API_KEY"]
SUPA = os.environ["SUPABASE_URL"].rstrip("/")
SRK = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BUCKET = "hero-images"
OUT = "/tmp/hero-expansion-v3"
os.makedirs(OUT, exist_ok=True)

# (slug, name, class, look, atk, hp, power)
COMMON = [
    ("mx3_ferrant", "Ferrant Punho Rachado", "warrior", "weathered town militiaman in patched ring mail gripping a nicked shortsword", 120, 928, 2130),
    ("mx3_maevin", "Maevin Corda Gasta", "archer", "lean orchard hunter in coarse linen with a worn shortbow", 131, 806, 2125),
    ("mx3_dolgur", "Dolgur Ombro Largo", "tank", "thickset dock hauler using a barrel lid bound in iron as a shield", 95, 1185, 2135),
    ("mx3_teressa", "Teressa Brasa Fraca", "mage", "young hearth acolyte in ash-stained robes cupping a dim ember", 138, 802, 2180),
    ("mx3_slyvor", "Slyvor Sombra Curta", "assassin", "wiry gutter cutthroat in a frayed grey hood with a bent dagger", 153, 702, 2230),
    ("mx3_bethra", "Bethra Atadura Simples", "support", "plain field healer with rolled bandages and a clay salve jar", 93, 1042, 1972),
    ("mx3_hargen", "Hargen Lâmina Cega", "warrior", "stubbled quarry warden with a blunt falchion and leather bracers", 119, 938, 2118),
    ("mx3_corwen", "Corwen Mira Baixa", "archer", "hunched road watcher with a small hand crossbow and mud-spattered cloak", 132, 794, 2112),
    ("mx3_rukmar", "Rukmar Muro de Palha", "tank", "broad farm guard in stitched scale holding a heavy wooden door-shield", 96, 1178, 2132),
    ("mx3_ilsabet", "Ilsabet Lanterna Fria", "support", "quiet crypt tender with a pale blue lantern and grey wool cloak", 94, 1030, 1962),
    ("mx3_vosk", "Vosk Dente Torto", "assassin", "sneering canal thief with a jagged shiv and bandaged knuckles", 156, 696, 2242),
    ("mx3_ondrelle", "Ondrelle Névoa Rasa", "mage", "damp bog student with thin mist curling around a crooked branch staff", 136, 808, 2178),
    ("mx3_grothan", "Grothan Cinta Rota", "warrior", "squat road mercenary in cracked leather with a spiked club and buckler", 122, 916, 2138),
    ("mx3_liraen", "Liraen Trilha Baixa", "archer", "barefoot moor trapper with a bent bow and snare cords at her hip", 129, 796, 2078),
    ("mx3_baldrek", "Baldrek Elmo Torto", "tank", "aging watch corporal in a crooked pot helm with a scratched round shield", 97, 1196, 2150),
]

UNCOMMON = [
    ("mx3_aurenth", "Aurenth Fio Reto", "warrior", "poised swordsman in burnished plate with a slender longsword and blue tabard", 177, 1268, 3030),
    ("mx3_selvaine", "Selvaine Flecha Rubra", "archer", "elite crimson-cloaked ranger with a lacquered recurve bow", 184, 1118, 2962),
    ("mx3_thorgun", "Thorgun Muro de Aço", "tank", "bulwark sentinel in riveted plate with a broad iron-banded tower shield", 138, 1690, 3062),
    ("mx3_calyxia", "Calyxia Chama Azul", "mage", "arcane scholar in sapphire robes with blue fire circling a runed rod", 206, 1118, 3162),
    ("mx3_dravyn", "Dravyn Passo Oco", "assassin", "hooded duelist in matte black leather with twin curved daggers", 210, 1038, 3132),
    ("mx3_ysolwen", "Ysolwen Voz Serena", "support", "serene temple healer in ivory and silver holding a glowing censer", 143, 1548, 2962),
    ("mx3_orvakar", "Orvakar Runa Rubra", "warrior", "rune-scarred champion in fur-trimmed scale with a red-etched greataxe", 180, 1248, 3042),
    ("mx3_neriath", "Neriath Olho de Falcão", "archer", "feather-mantled marksman in tooled leather with an engraved warbow", 186, 1108, 2982),
    ("mx3_ghorbek", "Ghorbek Casco Cravado", "tank", "hulking warden in studded steel with a rectangular battered shield", 137, 1712, 3072),
    ("mx3_vaelisse", "Vaelisse Véu Escarlate", "mage", "veiled sorceress with scarlet sigils hovering above her open palms", 207, 1112, 3166),
    ("mx3_kaerdun", "Kaerdun Fio Silente", "assassin", "scarred hunter in charcoal wrappings holding a needle-thin stiletto", 211, 1026, 3138),
    ("mx3_elowyn", "Elowyn Mão de Luz", "support", "battlefield chaplain in white and gold with a radiant open tome", 144, 1532, 2952),
    ("mx3_varkhal", "Varkhal Presa Cinza", "warrior", "bear-pelted berserker in steel and fur wielding twin bearded axes", 179, 1288, 3068),
    ("mx3_sarielle2", "Sariel Flecha Nívea", "archer", "snow-cloaked archer in pale leather with a frost-glinting nocked arrow", 183, 1128, 2958),
    ("mx3_haldreth", "Haldreth Coração Firme", "tank", "veteran shield-captain with a heraldic kite shield and short broadspear", 140, 1668, 3058),
]

ROSTER = [(*e, "common") for e in COMMON] + [(*e, "uncommon") for e in UNCOMMON]

TIER_LOOK = {
    "common": "humble low-tier equipment, plain materials, understated",
    "uncommon": "well-crafted detailed equipment, some metal trim and colored accents",
}


def prompt_for(cls, look, rarity):
    return (
        f"Dark medieval fantasy character art of a {cls} hero: {look}. "
        f"{TIER_LOOK[rarity]}. Photorealistic cinematic render, dramatic rim lighting, "
        "single character centered, three-quarter body vertical composition for a mobile game card, "
        "moody desaturated background with atmospheric haze, no text, no letters, no logo, "
        "no user interface, no frame, no border."
    )


def generate(entry):
    slug, name, cls, look, atk, hp, power, rarity = entry
    path = f"{OUT}/{slug}.jpg"
    if os.path.exists(path) and os.path.getsize(path) > 10000:
        return slug, True, "cached"
    body = {
        "model": "google/gemini-3.1-flash-image",
        "messages": [{"role": "user", "content": prompt_for(cls, look, rarity)}],
        "modalities": ["image", "text"],
    }
    last = "unknown"
    for _ in range(3):
        try:
            r = requests.post(
                "https://ai.gateway.lovable.dev/v1/images/generations",
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
                json=body,
                timeout=600,
            )
            if r.status_code != 200:
                last = f"{r.status_code} {r.text[:200]}"
                continue
            b64 = (r.json().get("data") or [{}])[0].get("b64_json")
            if not b64:
                last = "no image payload"
                continue
            img = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
            img.thumbnail((768, 1024), Image.Resampling.LANCZOS)
            img.save(path, "JPEG", quality=86, optimize=True)
            return slug, True, "generated"
        except Exception as exc:  # noqa: BLE001
            last = str(exc)[:200]
    return slug, False, last


def upload(slug):
    path = f"{OUT}/{slug}.jpg"
    key = f"heroes/{slug}-v1.jpg"
    r = requests.post(
        f"{SUPA}/storage/v1/object/{BUCKET}/{key}",
        headers={"Authorization": f"Bearer {SRK}", "Content-Type": "image/jpeg", "x-upsert": "true"},
        data=open(path, "rb").read(),
        timeout=120,
    )
    if r.status_code not in (200, 201):
        raise RuntimeError(f"upload {slug}: {r.status_code} {r.text[:200]}")
    s = requests.post(
        f"{SUPA}/storage/v1/object/sign/{BUCKET}/{key}",
        headers={"Authorization": f"Bearer {SRK}", "Content-Type": "application/json"},
        json={"expiresIn": 60 * 60 * 24 * 365 * 10},
        timeout=60,
    )
    if s.status_code != 200:
        raise RuntimeError(f"sign {slug}: {s.status_code} {s.text[:200]}")
    return f"{SUPA}/storage/v1{s.json()['signedURL']}"


def main():
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(generate, ROSTER))
    failed = [slug for slug, ok, _ in results if not ok]
    for slug, ok, info in results:
        if not ok:
            print("FAIL", slug, info)
    print(f"generated ok: {len(results) - len(failed)}/{len(results)}")
    if failed:
        sys.exit(1)

    slugs = [e[0] for e in ROSTER]
    with ThreadPoolExecutor(max_workers=8) as pool:
        urls = dict(zip(slugs, pool.map(upload, slugs)))

    rows = [
        {
            "hero_key": s, "name": n, "hero_class": c, "rarity": r,
            "base_atk": a, "base_hp": h, "power": p, "image": urls[s],
            "enabled": True, "in_shop": False, "drop_weight": 1,
            "fusion_pool_enabled": True,
            "sort_order": 100 if r == "common" else 200,
        }
        for s, n, c, _l, a, h, p, r in ROSTER
    ]
    with open(f"{OUT}/rows.json", "w") as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=1)

    up = requests.post(
        f"{SUPA}/rest/v1/hero_catalog?on_conflict=hero_key",
        headers={
            "apikey": SRK, "Authorization": f"Bearer {SRK}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=representation",
        },
        json=rows,
        timeout=180,
    )
    print("upsert", up.status_code, len(up.json()) if up.status_code < 300 else up.text[:400])


if __name__ == "__main__":
    main()
