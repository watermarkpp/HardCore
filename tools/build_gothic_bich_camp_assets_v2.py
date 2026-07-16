"""Build clean-alpha gothic Bich camp assets from the user's green-screen boards."""
from pathlib import Path
import re
import numpy as np
from PIL import Image

SOURCE = Path(r"C:\Users\Administrator\Desktop\sucai")
ROOT = Path(r"C:\Users\Administrator\Documents\Codex\2026-06-28\xian\work\legend176_game")
OUTPUT = ROOT / "assets/presentation/skins/gothic_bich_camp/sprites"


def source(number: int) -> Image.Image:
    for path in SOURCE.glob("*.png"):
        match = re.search(r"\((\d+)\)\.png$", path.name)
        if match and int(match.group(1)) == number:
            return Image.open(path).convert("RGB")
    raise FileNotFoundError(f"green-screen board {number}")


def chroma_key(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image, dtype=np.float32)
    # Distance to the actual neon-green board. Dark natural greens remain opaque.
    key = np.array([4.0, 250.0, 18.0], dtype=np.float32)
    distance = np.linalg.norm(rgb - key, axis=2)
    alpha = np.clip((distance - 62.0) / 72.0, 0.0, 1.0)
    dominance = np.minimum(rgb[:, :, 1] - rgb[:, :, 0], rgb[:, :, 1] - rgb[:, :, 2])
    green_candidate = (rgb[:, :, 1] > 60.0) & (dominance > 25.0)
    alpha = np.where(green_candidate, alpha, 1.0)
    # Remove green spill only on translucent edge pixels.
    edge = (alpha < 0.98) | ((rgb[:, :, 1] > 60.0) & (dominance > 25.0))
    neutral_green = np.maximum(rgb[:, :, 0], rgb[:, :, 2])
    rgb[:, :, 1] = np.where(edge, np.minimum(rgb[:, :, 1], neutral_green), rgb[:, :, 1])
    rgba = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def chroma_key_light(image: Image.Image) -> Image.Image:
	result = np.asarray(chroma_key(image), dtype=np.uint8).copy()
	rgb = result[:, :, :3].astype(np.int16)
	dominance = np.minimum(rgb[:, :, 1] - rgb[:, :, 0], rgb[:, :, 1] - rgb[:, :, 2])
	keyed = (rgb[:, :, 1] > 55) & (dominance > 12)
	result[:, :, 3] = np.where(keyed, 0, result[:, :, 3]).astype(np.uint8)
	result[keyed, :3] = 0
	visible = result[:, :, 3] > 0
	red = result[:, :, 0].astype(np.float32)
	result[:, :, 1] = np.where(visible, np.minimum(result[:, :, 1], red * 0.82), result[:, :, 1]).astype(np.uint8)
	result[:, :, 2] = np.where(visible, np.minimum(result[:, :, 2], red * 0.35), result[:, :, 2]).astype(np.uint8)
	return Image.fromarray(result, "RGBA")


def cut(board: Image.Image, box, size, name: str, margin=2, bottom=True) -> None:
    crop = board.crop(box)
    item = chroma_key_light(crop) if name.startswith("bich_camp_light_") and size == (128, 128) else chroma_key(crop)
    bbox = item.getchannel("A").point(lambda p: 255 if p >= 10 else 0).getbbox()
    if bbox:
        item = item.crop(bbox)
    scale = min((size[0] - margin * 2) / item.width, (size[1] - margin * 2) / item.height)
    item = item.resize((max(1, round(item.width * scale)), max(1, round(item.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - item.width) // 2
    y = size[1] - margin - item.height if bottom else (size[1] - item.height) // 2
    canvas.alpha_composite(item, (x, y))
    canvas.save(OUTPUT / f"{name}.png", optimize=True)


OUTPUT.mkdir(parents=True, exist_ok=True)
for old in OUTPUT.glob("*.png"):
    old.unlink()

# 1 — central public zone.
b = source(1)
for spec in [
    ((0, 0, 710, 380), (96, 128), "bich_camp_center_campfire_01"),
    ((690, 0, 1448, 380), (128, 64), "bich_camp_center_campfire_ground_01"),
    ((0, 300, 720, 730), (96, 128), "bich_camp_center_log_bench_01"),
    ((700, 300, 1448, 730), (96, 128), "bich_camp_center_log_bench_02"),
    ((0, 650, 690, 1086), (96, 128), "bich_camp_center_signpost_01"),
    ((650, 650, 1448, 1086), (96, 128), "bich_camp_center_supplies_01"),
]: cut(b, *spec)

# 2 — six functional tents/shelters.
b = source(2)
names = ["common_tent_01", "common_tent_02", "healer_tent_01", "forge_shelter_01", "stash_tent_01", "scroll_tent_01"]
for i, name in enumerate(names):
    col, row = i % 3, i // 3
    box = (col * 480, row * 520, min(1448, (col + 1) * 480 + 20), min(1086, (row + 1) * 520 + 46))
    size = (192, 256) if name == "forge_shelter_01" else (192, 128)
    cut(b, box, size, f"bich_camp_{name}")

# 3 — storage zone.
b = source(3)
storage = [
    (0, 0, 480, 400, "stash_chest_01", (96, 128)), (440, 0, 960, 400, "stash_crate_01", (64, 64)),
    (900, 0, 1448, 400, "stash_crate_02", (64, 64)), (0, 330, 480, 760, "stash_barrel_01", (64, 64)),
    (430, 330, 960, 760, "stash_barrel_02", (64, 64)), (900, 330, 1448, 760, "stash_sack_01", (64, 64)),
    (0, 680, 500, 1086, "stash_sack_02", (64, 64)), (430, 650, 1000, 1086, "stash_cart_01", (192, 128)),
    (900, 650, 1448, 1086, "stash_shelf_01", (96, 128)),
]
for x1, y1, x2, y2, name, size in storage: cut(b, (x1, y1, x2, y2), size, f"bich_camp_{name}")

# 4 — forge zone.
b = source(4)
forge = [
    (0, 0, 480, 400, "forge_furnace_01", (96, 128)), (440, 0, 960, 400, "forge_anvil_01", (64, 64)),
    (900, 0, 1448, 400, "forge_workbench_01", (96, 128)), (0, 330, 480, 760, "forge_weapon_rack_01", (96, 128)),
    (430, 330, 960, 760, "forge_weapon_rack_02", (96, 128)), (900, 330, 1448, 760, "forge_armor_stand_01", (96, 128)),
    (0, 680, 500, 1086, "forge_shield_rack_01", (96, 128)), (430, 680, 960, 1086, "forge_coal_01", (64, 64)),
    (900, 680, 1448, 1086, "forge_tool_rack_01", (96, 128)),
]
for x1, y1, x2, y2, name, size in forge: cut(b, (x1, y1, x2, y2), size, f"bich_camp_{name}")

# 5 — healer zone.
b = source(5)
healer = [
    (0, 0, 500, 560, "healer_herb_rack_01", (96, 128)), (450, 0, 1000, 560, "healer_worktable_01", (96, 128)),
    (920, 0, 1448, 560, "healer_medicine_box_01", (64, 64)), (0, 500, 500, 1086, "healer_herb_basket_01", (64, 64)),
    (450, 500, 1000, 1086, "healer_herb_basket_02", (64, 64)), (920, 500, 1448, 1086, "light_lamp_object_01", (64, 64)),
]
for x1, y1, x2, y2, name, size in healer: cut(b, (x1, y1, x2, y2), size, f"bich_camp_{name}")

# 6 — scroll/trainer zone.
b = source(6)
scroll = [
    (0, 0, 720, 420, "scroll_worktable_01", (96, 128)), (700, 0, 1448, 420, "scroll_bookshelf_01", (96, 128)),
    (0, 350, 720, 760, "scroll_chest_01", (64, 64)), (700, 350, 1448, 760, "scroll_books_01", (64, 64)),
    (0, 680, 720, 1086, "scroll_lamp_01", (64, 64)), (700, 680, 1448, 1086, "border_flag_01", (96, 128)),
]
for x1, y1, x2, y2, name, size in scroll: cut(b, (x1, y1, x2, y2), size, f"bich_camp_{name}")

# 7 — camp boundary and gate.
b = source(7)
boundary = [
    (0, 0, 480, 360, "border_fence_straight_01"), (430, 0, 960, 360, "border_fence_straight_02"),
    (900, 0, 1448, 360, "border_fence_corner_01"), (0, 300, 520, 720, "border_barricade_01"),
    (450, 300, 780, 720, "border_gate_left_01"), (700, 300, 1030, 720, "border_gate_right_01"),
    (0, 650, 400, 1086, "border_flag_02"), (350, 650, 750, 1086, "border_flag_03"),
    (700, 650, 1100, 1086, "border_guard_brazier_01"), (1050, 650, 1448, 1086, "border_direction_sign_01"),
]
for x1, y1, x2, y2, name in boundary: cut(b, (x1, y1, x2, y2), (96, 128), f"bich_camp_{name}")

# 8 — life-detail props.
b = source(8)
misc = [
    (0, 0, 380, 450, "misc_bucket_01", (64, 64)), (340, 0, 750, 450, "misc_stool_01", (64, 64)),
    (700, 0, 1100, 450, "misc_firewood_01", (64, 64)), (1050, 0, 1448, 450, "misc_rope_01", (64, 64)),
    (0, 400, 380, 820, "misc_cloth_01", (64, 64)), (340, 400, 750, 820, "misc_toolbox_01", (64, 64)),
    (700, 400, 1100, 820, "misc_water_trough_01", (96, 128)), (1050, 400, 1448, 820, "misc_training_dummy_01", (96, 128)),
]
for x1, y1, x2, y2, name, size in misc: cut(b, (x1, y1, x2, y2), size, f"bich_camp_{name}")

# 10 — four runtime light textures.
b = source(10)
lights = [
    ((0, 0, 720, 520), "light_campfire_01"), ((700, 0, 1448, 520), "light_furnace_01"),
    ((0, 480, 480, 1086), "light_lamp_01"), ((450, 480, 960, 1086), "light_brazier_01"),
]
for box, name in lights: cut(b, box, (128, 128), f"bich_camp_{name}", 0, False)

# 9 — eight base ground tiles and transparent decals.
b = source(9)
ground = [
    ((0, 0, 365, 300), "ground_dirt_01"), ((350, 0, 725, 300), "ground_dirt_02"),
    ((710, 0, 1080, 300), "ground_road_01"), ((1060, 0, 1448, 300), "ground_road_02"),
    ((0, 260, 365, 570), "ground_stone_01"), ((350, 260, 725, 570), "ground_stone_02"),
    ((710, 260, 1080, 570), "ground_grass_01"), ((1060, 260, 1448, 570), "ground_grass_02"),
]
for box, name in ground: cut(b, box, (64, 32), f"bich_camp_{name}", 0, False)
atlas = Image.new("RGBA", (512, 32), (0, 0, 0, 0))
for index, (_, name) in enumerate(ground):
    atlas.alpha_composite(Image.open(OUTPUT / f"bich_camp_{name}.png").convert("RGBA"), (index * 64, 0))
atlas.save(OUTPUT.parent / "gothic_bich_ground_tiles.png", optimize=True)

print(f"GOTHIC_BICH_GREENSCREEN_ASSETS={len(list(OUTPUT.glob('*.png')))}")
