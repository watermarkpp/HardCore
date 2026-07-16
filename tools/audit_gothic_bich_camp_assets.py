from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets/presentation/skins/gothic_bich_camp/sprites"
errors = []
files = sorted(SPRITES.glob("*.png"))
if len(files) < 70:
    errors.append(f"expected at least 70 sprites, got {len(files)}")
allowed = {(64, 64), (64, 32), (96, 128), (128, 64), (128, 128), (192, 128), (192, 256)}
for path in files:
    image = Image.open(path).convert("RGBA")
    if image.size not in allowed:
        errors.append(f"invalid size {path.name}: {image.size}")
    rgba = np.asarray(image)
    if rgba[:, :, 3].min() != 0:
        errors.append(f"no transparent background: {path.name}")
    rgb16 = rgba[:, :, :3].astype(np.int16)
    neon = (rgb16[:, :, 1] > 150) & (rgb16[:, :, 1] > rgb16[:, :, 0] + 45) & (rgb16[:, :, 1] > rgb16[:, :, 2] + 45) & (rgba[:, :, 3] > 32)
    if int(neon.sum()) > max(12, image.width * image.height // 80):
        errors.append(f"green spill remains: {path.name} ({int(neon.sum())} px)")
if errors:
    raise SystemExit("GOTHIC_BICH_ASSET_AUDIT_FAIL\n" + "\n".join(errors))
print(f"GOTHIC_BICH_ASSET_AUDIT_PASS sprites={len(files)}")
