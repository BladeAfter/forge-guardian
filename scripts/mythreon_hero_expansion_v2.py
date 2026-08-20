"""Generate art for 15 new common + 15 new uncommon Mythreon heroes, upload, emit rows.json.

Usage: python3 scripts/mythreon_hero_expansion_v2.py
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
OUT = "/tmp/hero-expansion-v2"
os.makedirs(OUT, exist_ok=True)

# (slug, name, class, look, atk, hp, power)
COMMON = [
    ("mx2_harlon", "Harlon Cinza-Ferro", "warrior", "rugged village swordsman in worn ring mail with a chipped broadsword", 121, 925, 2135),
    ("mx2_brenna", "Brenna Corda Curta", "archer", "farm-girl bowwoman in patched leather vest with a simple hunting bow", 130, 810, 2120),
    ("mx2_stovik", "Stovik Costa Rija", "tank", "burly mill worker with an iron-rimmed cart lid as a shield", 95, 1190, 2140),
    ("mx2_ilvara", "Ilvara Chama Curta", "mage", "novice fire acolyte in dusty robes with a small flickering flame in her palm", 139, 800, 2185),
    ("mx2_denrik", "Denrik Passo Mudo", "assassin", "gaunt back-alley knifeman with a short rusty dirk and grey hood", 152, 705, 2225),
    ("mx2_othela", "Othela Linho Branco", "support", "modest village nurse with linen wraps and a wooden herb box", 93, 1045, 1975),
    ("mx2_gundrek", "Gundrek Machado Torto", "warrior", "grizzled woodcutter with a bent felling axe and fur shoulder pad", 118, 940, 2115),
    ("mx2_pellin", "Pellin Olho Seco", "archer", "squinting road sentry with a small crossbow and travel cloak", 133, 792, 2115),
    ("mx2_borvald", "Borvald Portão Baixo", "tank", "heavyset gate guard in dull scale with a plank-and-iron shield", 96, 1175, 2130),
    ("mx2_sanwyn", "Sanwyn Vela Trêmula", "support", "young shrine keeper with a guttering candle lamp and grey shawl", 94, 1035, 1965),
    ("mx2_karvek", "Karvek Faca de Pedra", "assassin", "scrappy quarry thug with a flint-bladed knife and bare arms", 155, 698, 2240),
    ("mx2_nelira", "Nelira Poça Fria", "mage", "damp marsh apprentice with weak water swirling around a bent staff", 137, 806, 2180),
    ("mx2_orbrik", "Orbrik Cinta de Couro", "warrior", "stocky caravan guard in stiff leather with a mace and small buckler", 122, 918, 2140),
    ("mx2_wenda", "Wenda Trilha Torta", "archer", "hill-country trapper with a crude bow and rabbit pelts on her belt", 128, 798, 2075),
    ("mx2_thalric", "Thalric Elmo Amassado", "tank", "old militia sergeant in a dented kettle helm with a battered shield", 97, 1200, 2155),
]

UNCOMMON = [
    ("mx2_aldreth", "Aldreth Lâmina Firme", "warrior", "disciplined swordsman in polished steel plate with a straight arming sword", 178, 1265, 3035),
    ("mx2_sarielle", "Sarielle Flecha Verde", "archer", "elite forest ranger in green scale-leather with a recurve bow and steel arrows", 184, 1120, 2965),
    ("mx2_hurgan", "Hurgan Torre Baixa", "tank", "bulwark knight in riveted steel with a heavy tower shield and stone sigil", 139, 1685, 3060),
    ("mx2_maribel", "Maribel Chama Índigo", "mage", "arcane adept in indigo robes with blue flame coiling around a carved staff", 205, 1120, 3160),
    ("mx2_valkros", "Valkros Passo Fino", "assassin", "silent duelist in dark studded leather with paired kris daggers", 209, 1040, 3130),
    ("mx2_eluvien", "Eluvien Canto Claro", "support", "silver-embroidered cleric with a softly glowing chalice", 142, 1550, 2965),
    ("mx2_dornhal", "Dornhal Punho Rúnico", "warrior", "rune-tattooed champion in scale and fur with an engraved war axe", 181, 1245, 3045),
    ("mx2_ysolde", "Ysolde Olho de Gavião", "archer", "hawk-mantled sharpshooter in ornate leather aiming a decorated bow", 185, 1110, 2985),
    ("mx2_grimbold", "Grimbold Casco Pesado", "tank", "heavy warden in spiked steel pauldrons with a broad rectangular shield", 137, 1715, 3075),
    ("mx2_nyvessa", "Nyvessa Véu Violeta", "mage", "shadow-veiled enchantress with violet sigils floating around her hands", 207, 1110, 3165),
    ("mx2_korvane", "Korvane Fio Frio", "assassin", "scarred killer in charcoal wraps holding a serrated stiletto", 211, 1028, 3140),
    ("mx2_elandra", "Elandra Mão Dourada", "support", "battlefield chaplain in white and gold with a radiant amulet", 144, 1535, 2955),
    ("mx2_varhelm", "Varhelm Sangue Cinza", "warrior", "wolf-crested berserker in fur and steel with twin hand axes", 179, 1290, 3070),
    ("mx2_lisenne", "Lisenne Flecha Pálida", "archer", "moonlit archer in pale blue leather with a faintly glowing arrow nocked", 183, 1130, 2960),
    ("mx2_baldrun", "Baldrun Coração de Aço", "tank", "veteran shield-captain with a proud heraldic shield and short spear", 140, 1670, 3060),
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
    print("wrote", f"{OUT}/rows.json")


if __name__ == "__main__":
    main()
