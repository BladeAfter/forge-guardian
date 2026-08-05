from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "public" / "assets" / "game"


def convert(source: Path, destination: Path, size: int) -> None:
    if not source.exists():
        return
    image = Image.open(source)
    image.thumbnail((size, size), Image.Resampling.LANCZOS)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, "WEBP", quality=86, method=6)


convert(GAME / "characters" / "blacksmith-avatar.png", GAME / "characters" / "blacksmith-avatar.webp", 384)
convert(GAME / "ui" / "village-level-crest.png", GAME / "ui" / "village-level-crest.webp", 256)
convert(GAME / "ui" / "daily-streak.png", GAME / "ui" / "daily-streak.webp", 256)
convert(GAME / "ui" / "mission-ingots.png", GAME / "ui" / "mission-ingots.webp", 256)
convert(ROOT / "tmp" / "imagegen" / "main-forge-tower.png", GAME / "buildings" / "main-forge-tower.webp", 900)
convert(ROOT / "tmp" / "imagegen" / "production-anvil.png", GAME / "ui" / "production-anvil.webp", 192)
convert(ROOT / "tmp" / "imagegen" / "hero-shop.png", GAME / "ui" / "hero-shop.webp", 256)
convert(GAME / "ui" / "pool.webp", GAME / "ui" / "pool.webp", 256)
convert(GAME / "ui" / "pvp.webp", GAME / "ui" / "pvp.webp", 256)
convert(GAME / "ui" / "invite.webp", GAME / "ui" / "invite.webp", 256)
convert(GAME / "ui" / "invite-referral.webp", GAME / "ui" / "invite-referral.webp", 256)
