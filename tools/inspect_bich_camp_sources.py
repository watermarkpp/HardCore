from pathlib import Path
from PIL import Image, ImageDraw

SOURCE = Path(r"C:\Users\Administrator\Desktop\sucai")
OUTPUT = Path(r"C:\Users\Administrator\Documents\Codex\2026-06-28\xian\work\legend176_game\.tmp_asset_inspect\contact_sheet.png")
files = sorted(SOURCE.glob("*.png"))
thumbs = []
for index, path in enumerate(files, 1):
    image = Image.open(path).convert("RGB")
    image.thumbnail((420, 315), Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (440, 350), "#181512")
    tile.paste(image, ((440 - image.width) // 2, 20))
    ImageDraw.Draw(tile).text((12, 326), f"{index}: {path.name}", fill="white")
    thumbs.append(tile)
sheet = Image.new("RGB", (880, 350 * ((len(thumbs) + 1) // 2)), "#100e0c")
for index, tile in enumerate(thumbs):
    sheet.paste(tile, ((index % 2) * 440, (index // 2) * 350))
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUTPUT)
print(OUTPUT)
