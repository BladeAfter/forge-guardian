from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\Allan\.codex\generated_images\019fcdb5-1681-7f53-b5ed-d8b029beb461")
OUTPUT = ROOT / "public" / "assets" / "game" / "heroes" / "shop"
OUTPUT.mkdir(parents=True, exist_ok=True)

FILES = {
    "common-2": "exec-9fcd6cf5-4092-409e-9614-2876c9239272.png",
    "common-3": "exec-42b72318-38e8-4d4e-af4b-965d91fea0a6.png",
    "common-4": "exec-606cc784-c39b-4726-8b59-a18efd7cf750.png",
    "common-5": "exec-2ff8a641-fc97-47b9-9c3f-04f5788165b8.png",
    "uncommon-2": "exec-a8ce632d-0a1d-4268-91b2-eb1cdcd2d11f.png",
    "uncommon-3": "exec-cfbd972f-ed9b-4a70-8b1c-ed93d5238f5f.png",
    "uncommon-4": "exec-34dc6fd1-b340-4750-b2ff-1581cd9b6863.png",
    "uncommon-5": "exec-488fd76e-b3cc-4d0b-bc80-faa04878ccb8.png",
    "rare-2": "exec-59244b03-e13f-4dc4-8c52-9413707e71e7.png",
    "rare-3": "exec-ded8e594-8b36-4d4e-82be-21f856b588e0.png",
    "rare-4": "exec-29a1401c-1c13-43ae-9b8f-dabd0b3379f2.png",
    "rare-5": "exec-3d4990dc-fdb0-4ed4-8f9c-6f15f4fc492c.png",
    "epic-2": "exec-0e91cbb2-a828-4f10-aca3-870429a473cf.png",
    "epic-3": "exec-f7391408-98fc-423f-9467-052035c5334f.png",
    "epic-4": "exec-f0723e52-4338-44aa-8749-e7525e0e8f1d.png",
    "epic-5": "exec-a4d4add1-ca7b-4723-b0ca-c7e1fe28373e.png",
    "legendary-2": "exec-fff7f90f-0a41-44f2-b025-1716440d60eb.png",
    "legendary-3": "exec-9c908c59-3d7d-41fa-a552-d1d7069f0ce9.png",
    "legendary-4": "exec-50b68013-76f7-47af-8dcd-2b3ed0bd01b2.png",
    "legendary-5": "exec-f72ae355-4bf2-46c7-9284-9337e309495b.png",
}

for name, filename in FILES.items():
    image = Image.open(GENERATED / filename).convert("RGB")
    image.thumbnail((384, 384), Image.Resampling.LANCZOS)
    image.save(OUTPUT / f"{name}.webp", "WEBP", quality=84, method=6)
