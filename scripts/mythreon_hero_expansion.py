"""Generate art for the 60-hero Mythreon expansion, upload to storage, emit SQL rows.

Usage: python3 scripts/mythreon_hero_expansion.py
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
OUT = "/tmp/hero-expansion"
os.makedirs(OUT, exist_ok=True)

# (slug, name, class, look)
COMMON = [
    ("mx_orlen", "Orlen da Ponte Baixa", "warrior", "young footman in worn chainmail and a dented iron sword, mud-stained tabard"),
    ("mx_habrik", "Habrik Punho de Ferro", "tank", "stocky militia guard with a battered round wooden shield and simple helm"),
    ("mx_selka", "Selka Olho de Corvo", "archer", "lean village bowwoman in leather jerkin, plain shortbow, hood down"),
    ("mx_ferrund", "Ferrund o Escudeiro", "warrior", "squire in mismatched plate scraps holding a broad short sword"),
    ("mx_omira", "Omira das Velas", "support", "modest candle-priestess in grey robes holding a small brass lantern"),
    ("mx_tarno", "Tarno Rasga-Bota", "assassin", "wiry alley cutthroat with two rusty daggers, ragged cloak"),
    ("mx_veskal", "Veskal Pele-de-Lobo", "warrior", "border raider in wolf pelt over crude leather, notched axe"),
    ("mx_brindal", "Brindal Cava-Pedra", "tank", "quarry worker turned defender with iron-banded buckler and pick"),
    ("mx_lunette", "Lunette Cinzas", "mage", "apprentice sorceress in plain dark robe, faint ember glow on fingertips"),
    ("mx_gorrad", "Gorrad Pé-Torto", "warrior", "limping veteran mercenary with a spear and patched gambeson"),
    ("mx_ithra", "Ithra Voz Baixa", "support", "quiet field healer with linen wraps and herb satchel"),
    ("mx_padric", "Padric Trilha Longa", "archer", "road scout with a crossbow and travel-worn cloak"),
    ("mx_umbo", "Umbo Casco Fundo", "tank", "heavyset gate warden with a tall plank shield"),
    ("mx_nerric", "Nerric Faca Curta", "assassin", "hooded thief with a single curved knife, soot on the face"),
    ("mx_alvenna", "Alvenna Chuvarada", "mage", "rain-soaked novice mage, water swirling weakly around her staff"),
    ("mx_dorvic", "Dorvic Martelo Velho", "warrior", "old smith wielding a forge hammer as a weapon, leather apron"),
    ("mx_seliad", "Seliad Passo Leve", "archer", "barefoot marsh hunter with a reed bow and bone arrows"),
    ("mx_muldrec", "Muldrec Barreira", "tank", "stoic town guard with a chipped kite shield and mace"),
    ("mx_yorna", "Yorna Trança Cinza", "support", "grey-braided camp cook turned medic with a ladle and bandages"),
    ("mx_kestel", "Kestel Sombra Rasa", "assassin", "young cutpurse crouching, twin bone-handled shivs"),
    ("mx_ravlin", "Ravlin Faísca", "mage", "soot-faced ember conjurer with a cracked wand"),
    ("mx_torbek", "Torbek Chifre Curto", "warrior", "brawny herder with a horned helmet and heavy club"),
    ("mx_ineska", "Ineska Névoa", "archer", "pale woodland archer half-veiled in fog, plain longbow"),
    ("mx_gralm", "Gralm Costa Larga", "tank", "shipyard bruiser with an iron-plated door as a shield"),
    ("mx_pellow", "Pellow Mão Firme", "support", "steady-handed field surgeon with rolled tools"),
    ("mx_dranik", "Dranik Corte Rápido", "assassin", "quick-footed knife fighter in dark linen wraps"),
    ("mx_solvane", "Solvane Luz Fraca", "mage", "hedge witch with a faint blue glow in a clay bowl"),
    ("mx_bohren", "Bohren Sela Torta", "warrior", "dismounted light cavalryman with a broken lance"),
    ("mx_wrenna", "Wrenna Pena Negra", "archer", "crow-feathered fletcher aiming a plain hunting bow"),
    ("mx_oskund", "Oskund Muro Vivo", "tank", "grizzled wall-sergeant in layered scale armor"),
]
UNCOMMON = [
    ("mx_calderyn", "Calderyn Lâmina Solar", "warrior", "disciplined swordsman in polished brass-trimmed plate, sun-etched blade"),
    ("mx_ysmara", "Ysmara Vento Cortante", "archer", "elite ranger in green scale-leather with a recurve bow and quiver of steel arrows"),
    ("mx_drenhold", "Drenhold Pedra-Guarda", "tank", "armored bulwark knight with a tower shield bearing a stone sigil"),
    ("mx_avelith", "Avelith Chama Azul", "mage", "arcane adept in indigo robes with blue flame coiling around both hands"),
    ("mx_shivrel", "Shivrel Passo Oco", "assassin", "silent duelist in dark studded leather with paired kris daggers"),
    ("mx_maerwyn", "Maerwyn Canto Prata", "support", "silver-embroidered cleric with a glowing chalice"),
    ("mx_holdric", "Holdric Punho Rúnico", "warrior", "rune-tattooed champion with an engraved war axe"),
    ("mx_talvira", "Talvira Olho de Falcão", "archer", "hawk-mantled sharpshooter on a rocky ledge, ornate bow"),
    ("mx_grumvar", "Grumvar Casco de Aço", "tank", "heavy warden in riveted steel with spiked pauldrons"),
    ("mx_nesrida", "Nesrida Véu Sombrio", "mage", "shadow-veiled enchantress with violet sigils floating nearby"),
    ("mx_korvash", "Korvash Garganta Fria", "assassin", "scarred killer in charcoal wraps with a serrated stiletto"),
    ("mx_elandor", "Elandor Mão Curativa", "support", "battlefield chaplain in white and gold with a radiant amulet"),
    ("mx_vargheim", "Vargheim Sangue de Lobo", "warrior", "wolf-crested berserker in fur and steel with twin hand axes"),
    ("mx_liriana", "Liriana Flecha Lunar", "archer", "moonlit archer in pale blue leather, glowing arrow nocked"),
    ("mx_baldrec", "Baldrec Coração Duro", "tank", "veteran shield-captain with a dented but proud heraldic shield"),
]
RARE = [
    ("mx_theodran", "Theodran, o Juramentado", "warrior", "noble knight-commander in ornate engraved plate with a flowing crimson cloak and jeweled longsword"),
    ("mx_ashvaine", "Ashvaine da Torre Negra", "mage", "high sorceress in black-and-gold layered robes, arcane runes orbiting a crystal staff"),
    ("mx_dornhelm", "Dornhelm Muralha Eterna", "tank", "colossal guardian in fluted steel plate with a gilded tower shield and warhammer"),
    ("mx_sylestra", "Sylestra Flecha Élfica", "archer", "elven marksman in filigreed leaf armor with a luminous composite bow"),
    ("mx_varexis", "Varexis Sussurro Letal", "assassin", "masked blademaster in lacquered dark armor with paired glowing shortswords"),
    ("mx_iolanthe", "Iolanthe Bênção Radiante", "support", "high priestess in white marble-toned vestments with golden light halo"),
    ("mx_rhogarn", "Rhogarn Fúria de Ferro", "warrior", "battle-scarred warlord in spiked crimson plate with a massive greatsword"),
    ("mx_myrellia", "Myrellia Canção de Gelo", "mage", "frost archmage with ice crystals forming midair, silver-blue mantle"),
    ("mx_stormgar", "Stormgar Trovão Antigo", "tank", "storm-marked juggernaut in rune-lit heavy armor with a thunder shield"),
    ("mx_faelwyn", "Faelwyn Olhar Prateado", "archer", "silver-eyed hunter in ornate ranger armor, twin quivers, wind-swept cloak"),
    ("mx_zarnick", "Zarnick Lâmina Sombria", "assassin", "elite shadow agent in black plated leather with a curved shadow blade"),
    ("mx_aurenhal", "Aurenhal Voz Sagrada", "support", "temple champion in gold-trimmed robes and light chain, glowing censer"),
    ("mx_belgorath", "Belgorath Punho da Montanha", "warrior", "mountain champion in layered steel with a two-handed rune axe"),
    ("mx_veskarra", "Veskarra Chama Carmesim", "mage", "crimson pyromancer with fire ribbons spiraling around an obsidian rod"),
    ("mx_thalgrim", "Thalgrim Sentinela Real", "tank", "royal sentinel in engraved silver plate holding a great kite shield and spear"),
]

ROSTER = [(s, n, c, l, "common") for s, n, c, l in COMMON]
ROSTER += [(s, n, c, l, "uncommon") for s, n, c, l in UNCOMMON]
ROSTER += [(s, n, c, l, "rare") for s, n, c, l in RARE]

TIER_LOOK = {
    "common": "humble low-tier equipment, plain materials, understated",
    "uncommon": "well-crafted detailed equipment, some metal trim and colored accents",
    "rare": "superior craftsmanship, ornate armor and distinctive weapon, subtle magical glow (not legendary-tier, no wings, no giant auras)",
}


def prompt_for(name, cls, look, rarity):
    return (
        f"Dark medieval fantasy character art of a {cls} hero: {look}. "
        f"{TIER_LOOK[rarity]}. Photorealistic cinematic render, dramatic rim lighting, "
        "single character centered, three-quarter body vertical composition for a mobile game card, "
        "moody desaturated background with atmospheric haze, no text, no letters, no logo, "
        "no user interface, no frame, no border."
    )


def generate(entry):
    slug, name, cls, look, rarity = entry
    path = f"{OUT}/{slug}.jpg"
    if os.path.exists(path) and os.path.getsize(path) > 10000:
        return slug, True, "cached"
    body = {
        "model": "google/gemini-3.1-flash-image",
        "messages": [{"role": "user", "content": prompt_for(name, cls, look, rarity)}],
        "modalities": ["image", "text"],
    }
    for attempt in range(3):
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
        headers={
            "Authorization": f"Bearer {SRK}",
            "Content-Type": "image/jpeg",
            "x-upsert": "true",
        },
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
        print("missing:", failed)
        sys.exit(1)

    with ThreadPoolExecutor(max_workers=8) as pool:
        urls = dict(zip([e[0] for e in ROSTER], pool.map(upload, [e[0] for e in ROSTER])))

    rows = [
        {"hero_key": s, "name": n, "hero_class": c, "rarity": r, "image": urls[s]}
        for s, n, c, _, r in ROSTER
    ]
    with open(f"{OUT}/rows.json", "w") as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=1)
    print("wrote", f"{OUT}/rows.json")


if __name__ == "__main__":
    main()
