from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "public" / "assets" / "game"
SOURCE = ROOT / "tmp" / "game-art-sources"


def remove_green(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = []
    for red, green, blue, _ in rgba.getdata():
        dominance = green - max(red, blue)
        alpha = 255
        if green > 150 and dominance > 35:
            alpha = max(0, min(255, int(255 - (dominance - 35) * 2.5)))
        if alpha < 255:
            spill = max(0, green - max(red, blue))
            green = max(0, green - spill)
        pixels.append((red, green, blue, alpha))
    rgba.putdata(pixels)
    return rgba


def trim_and_square(image: Image.Image, size: int) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds:
        image = image.crop(bounds)
    longest = max(image.size)
    padding = max(12, int(longest * 0.08))
    canvas_size = longest + padding * 2
    canvas = Image.new("RGBA", (canvas_size, canvas_size))
    canvas.alpha_composite(image, ((canvas_size - image.width) // 2, (canvas_size - image.height) // 2))
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def save_grid(source_name: str, columns: int, rows: int, names: list[str], folder: str, size: int):
    source = Image.open(SOURCE / source_name)
    cell_width = source.width // columns
    cell_height = source.height // rows
    output = ASSETS / folder
    output.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(names):
        row, column = divmod(index, columns)
        crop = source.crop((column * cell_width, row * cell_height, (column + 1) * cell_width, (row + 1) * cell_height))
        final = trim_and_square(remove_green(crop), size)
        final.save(output / name, optimize=True)


def save_single(source_name: str, name: str, folder: str, size: int):
    source = remove_green(Image.open(SOURCE / source_name))
    final = trim_and_square(source, size)
    output = ASSETS / folder
    output.mkdir(parents=True, exist_ok=True)
    final.save(output / name, optimize=True)


def save_horizontal_logo():
    source = Image.open(SOURCE / "logo.png")
    upper = remove_green(source.crop((0, 0, source.width, source.height // 2)))
    bounds = upper.getchannel("A").getbbox()
    if bounds:
        upper = upper.crop(bounds)
    target_width = 1200
    target_height = round(upper.height * target_width / upper.width)
    upper = upper.resize((target_width, target_height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (target_width + 64, target_height + 64))
    canvas.alpha_composite(upper, (32, 32))
    output = ASSETS / "logo"
    output.mkdir(parents=True, exist_ok=True)
    canvas.save(output / "forge-village-logo.png", optimize=True)

    lower = remove_green(source.crop((0, source.height // 2, source.width, source.height)))
    trim_and_square(lower, 512).save(output / "forge-village-icon.png", optimize=True)


def save_background(source_name: str, name: str):
    source = Image.open(SOURCE / source_name).convert("RGB")
    target_ratio = 1080 / 1920
    current_ratio = source.width / source.height
    if current_ratio > target_ratio:
        width = round(source.height * target_ratio)
        left = (source.width - width) // 2
        source = source.crop((left, 0, left + width, source.height))
    elif current_ratio < target_ratio:
        height = round(source.width / target_ratio)
        top = (source.height - height) // 2
        source = source.crop((0, top, source.width, top + height))
    source = source.resize((1080, 1920), Image.Resampling.LANCZOS)
    output = ASSETS / "backgrounds"
    output.mkdir(parents=True, exist_ok=True)
    source.save(output / name, "WEBP", quality=84, method=6)


def main():
    for folder in ["backgrounds", "buildings", "characters", "bosses", "chests", "coins", "icons", "logo"]:
        (ASSETS / folder).mkdir(parents=True, exist_ok=True)

    save_background("loading.png", "loading-background.webp")
    save_background("village.png", "village-background.webp")
    save_background("boss-arena.png", "boss-battle-background.webp")

    save_grid("buildings.png", 3, 2, ["iron-mine.png", "coal-mine.png", "forge.png", "royal-workshop.png", "dragon-foundry.png"], "buildings", 640)
    save_grid("chests.png", 2, 2, ["common-chest.png", "rare-chest.png", "epic-chest.png", "legendary-chest.png"], "chests", 512)
    save_grid("characters.png", 3, 2, ["novice-blacksmith.png", "master-blacksmith.png", "merchant.png", "knight.png", "king.png"], "characters", 768)
    save_grid("navigation.png", 5, 2, ["village-icon.png", "missions-icon.png", "boss-icon.png", "wallet-icon.png", "profile-icon.png", "village-icon-selected.png", "missions-icon-selected.png", "boss-icon-selected.png", "wallet-icon-selected.png", "profile-icon-selected.png"], "icons", 256)
    save_grid("missions.png", 3, 2, ["daily-login-icon.png", "collect-production-icon.png", "upgrade-building-icon.png", "attack-boss-icon.png", "watch-ad-icon.png", "invite-friend-icon.png"], "icons", 256)
    save_horizontal_logo()
    save_single("coin.png", "forge-coin.png", "coins", 512)
    save_single("dragon.png", "ancient-dragon.png", "bosses", 1024)


if __name__ == "__main__":
    main()
