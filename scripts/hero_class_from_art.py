"""Classify each hero's artwork with a vision model and align hero_class to the art.

Usage: python3 scripts/hero_class_from_art.py [--apply]
Needs: LOVABLE_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import requests

API_KEY = os.environ["LOVABLE_API_KEY"]
SUPA = os.environ["SUPABASE_URL"].rstrip("/")
SRK = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
CLASSES = ["warrior", "tank", "archer", "mage", "assassin", "support"]
CACHE = "/tmp/hero-class-art.json"

PROMPT = (
    "Look at this fantasy game hero artwork and pick the single class that best matches "
    "what the character visibly wears and wields.\n"
    "warrior = sword/axe/spear melee fighter, medium-heavy armor, no huge shield\n"
    "tank = very heavy armor and/or a large shield, defensive bulk\n"
    "archer = bow or crossbow visible\n"
    "mage = staff/wand/orb/visible spell or magic energy, robes\n"
    "assassin = daggers/short blades, hood or light dark leather, stealthy\n"
    "support = healer/priest/cleric look: chalice, censer, holy light, tome, bandages, robes without offensive weapon\n"
    "Answer with exactly one word from: warrior, tank, archer, mage, assassin, support."
)

HEADERS = {"Authorization": f"Bearer {SRK}", "apikey": SRK, "Content-Type": "application/json"}


def fetch_heroes():
    r = requests.get(
        f"{SUPA}/rest/v1/hero_catalog",
        headers=HEADERS,
        params={"select": "hero_key,name,rarity,hero_class,image"},
        timeout=120,
    )
    r.raise_for_status()
    return [h for h in r.json() if h.get("image")]


def classify(hero):
    url = hero["image"]
    if url.startswith("/"):
        return hero["hero_key"], None
    body = {
        "model": "google/gemini-2.5-flash",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {"type": "image_url", "image_url": {"url": url}},
                ],
            }
        ],
    }
    for _ in range(3):
        try:
            r = requests.post(
                "https://ai.gateway.lovable.dev/v1/chat/completions",
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
                json=body,
                timeout=180,
            )
            if r.status_code != 200:
                continue
            txt = (r.json()["choices"][0]["message"]["content"] or "").strip().lower()
            for c in CLASSES:
                if c in txt:
                    return hero["hero_key"], c
        except Exception:
            continue
    return hero["hero_key"], None


def main():
    heroes = fetch_heroes()
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    todo = [h for h in heroes if h["hero_key"] not in cache]
    print(f"heroes: {len(heroes)} | to classify: {len(todo)}")
    with ThreadPoolExecutor(max_workers=8) as pool:
        for key, cls in pool.map(classify, todo):
            if cls:
                cache[key] = cls
    json.dump(cache, open(CACHE, "w"), indent=1)

    changes = [
        {"hero_key": h["hero_key"], "name": h["name"], "rarity": h["rarity"],
         "from": h["hero_class"], "to": cache[h["hero_key"]]}
        for h in heroes
        if cache.get(h["hero_key"]) and cache[h["hero_key"]] != h["hero_class"]
    ]
    print(f"mismatches: {len(changes)}/{len(heroes)}")
    for c in changes:
        print(f"  {c['rarity']:12} {c['name'][:34]:34} {c['from']} -> {c['to']}")
    json.dump(changes, open("/tmp/hero-class-changes.json", "w"), ensure_ascii=False, indent=1)

    if "--apply" in sys.argv:
        for c in changes:
            r = requests.patch(
                f"{SUPA}/rest/v1/hero_catalog",
                headers=HEADERS,
                params={"hero_key": f"eq.{c['hero_key']}"},
                json={"hero_class": c["to"]},
                timeout=60,
            )
            if r.status_code not in (200, 204):
                print("FAIL", c["hero_key"], r.status_code, r.text[:120])
        print("applied", len(changes))


if __name__ == "__main__":
    main()
