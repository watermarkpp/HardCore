"""Import the MSE wall pack and two user-supplied transparent asset sheets.

The importer is deterministic: it never redraws source artwork.  It extracts the
wall package, crops the two already-transparent PNG sheets using reviewed cells,
trims transparent padding, and writes one editor extension catalog.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import zipfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "assets/data/assets"
DEST = ROOT / "assets/art/maps/_shared/cave_dungeon_palette"
CATALOG = DATA / "map_cave_dungeon_asset_catalog.json"


@dataclass(frozen=True)
class Crop:
    asset_id: str
    display_name: str
    box: tuple[int, int, int, int]
    category: str
    footprint: tuple[int, int]
    collision: tuple[int, int]
    role: str
    layer: str = "object_base"
    anchor_mode: str = "foot_tile"


SHEET_1_CROPS = (
    Crop("terrain_tile_01", "洞穴沙土地块", (28, 92, 340, 300), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("road_tile_01", "地下城石路地块", (345, 92, 675, 300), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("water_tile_01", "洞穴水面地块", (675, 92, 1010, 300), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("stone_ring_overlay_2x2", "石环地形覆盖 2×2", (20, 380, 345, 600), "terrain_overlay", (2, 2), (0, 0), "decoration"),
    Crop("forest_overlay_3x5", "洞穴林地覆盖 3×5", (345, 380, 680, 600), "terrain_overlay", (3, 5), (2, 3), "obstacle"),
    Crop("ruin_overlay_4x4", "遗迹地形覆盖 4×4", (665, 380, 1015, 600), "terrain_overlay", (4, 4), (3, 3), "terrain"),
    Crop("barrel_crates_01", "木桶木箱组合", (45, 675, 350, 880), "small_prop", (2, 2), (2, 2), "obstacle"),
    Crop("brazier_01", "地下城火盆", (405, 670, 605, 880), "small_prop", (1, 1), (1, 1), "obstacle"),
    Crop("campfire_01", "洞穴篝火", (675, 675, 990, 880), "medium_prop", (2, 2), (1, 1), "obstacle"),
    Crop("hide_tent_01", "洞穴兽皮帐篷", (25, 930, 355, 1180), "large_prop", (5, 4), (4, 3), "building"),
    Crop("rock_cluster_01", "洞穴岩石群", (350, 930, 690, 1180), "terrain_stamp", (4, 3), (3, 2), "terrain"),
    Crop("ground_shadow_01", "洞穴地面阴影", (690, 930, 1000, 1180), "shadow", (3, 2), (0, 0), "decoration", "shadow"),
)


SHEET_2_CROPS = (
    # Small ground diamonds.
    Crop("ground_sand_02", "沙土地块 02", (35, 10, 165, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_moss_01", "苔藓地块 01", (160, 10, 285, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_sand_03", "沙土地块 03", (280, 10, 402, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_stone_01", "石土地块 01", (395, 10, 515, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dark_01", "暗石地块 01", (510, 10, 632, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_stone_02", "石土地块 02", (625, 10, 750, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_water_01", "深水地块 01", (745, 10, 865, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dirt_01", "泥土地块 01", (860, 10, 985, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dark_02", "暗石地块 02", (975, 10, 1098, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dark_03", "暗石地块 03", (1090, 10, 1222, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dark_04", "暗石地块 04", (1215, 10, 1335, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_dark_05", "暗石地块 05", (1325, 10, 1500, 92), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_stone_03", "石土地块 03", (35, 90, 166, 170), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_moss_02", "苔藓地块 02", (160, 90, 287, 170), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_water_02", "浅水地块 02", (280, 90, 405, 170), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_mud_01", "泥泞地块 01", (395, 90, 515, 172), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    Crop("ground_mud_02", "泥泞地块 02", (505, 90, 630, 172), "ground", (1, 1), (0, 0), "decoration", "ground_base", "tile_center"),
    # Water and dark boundary strips.
    Crop("water_edge_01", "水岸边缘 01", (625, 88, 730, 185), "terrain_overlay", (2, 1), (0, 0), "decoration"),
    Crop("water_edge_02", "水岸边缘 02", (720, 88, 825, 185), "terrain_overlay", (2, 1), (0, 0), "decoration"),
    Crop("water_edge_03", "水岸边缘 03", (815, 88, 925, 185), "terrain_overlay", (2, 1), (0, 0), "decoration"),
    Crop("water_edge_04", "水岸边缘 04", (915, 88, 1032, 185), "terrain_overlay", (2, 1), (0, 0), "decoration"),
    Crop("dark_edge_01", "暗墙边缘 01", (1025, 88, 1170, 188), "terrain_wall", (3, 1), (3, 1), "terrain"),
    Crop("dark_edge_02", "暗墙边缘 02", (1165, 88, 1298, 188), "terrain_wall", (3, 1), (3, 1), "terrain"),
    Crop("dark_edge_03", "暗墙边缘 03", (1290, 88, 1418, 188), "terrain_wall", (3, 1), (3, 1), "terrain"),
    Crop("dark_edge_04", "暗墙边缘 04", (1408, 88, 1502, 188), "terrain_wall", (2, 1), (2, 1), "terrain"),
    # Terrain overlays and cliffs.
    Crop("moss_patch_01", "苔藓碎石覆盖 01", (30, 168, 250, 275), "terrain_overlay", (3, 2), (0, 0), "decoration"),
    Crop("stone_slab_01", "洞穴石板 01", (245, 168, 430, 278), "terrain_overlay", (3, 2), (0, 0), "decoration"),
    Crop("stone_slab_02", "洞穴石板 02", (425, 168, 635, 280), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("moss_patch_02", "苔藓碎石覆盖 02", (25, 260, 288, 405), "terrain_overlay", (4, 3), (0, 0), "decoration"),
    Crop("large_sand_overlay_01", "大型沙土地形覆盖", (280, 255, 635, 410), "terrain_overlay", (6, 4), (0, 0), "decoration"),
    Crop("cliff_wall_01", "洞穴峭壁 01", (630, 175, 878, 405), "terrain_stamp", (4, 4), (4, 3), "terrain"),
    Crop("cliff_wall_02", "洞穴峭壁 02", (870, 170, 1098, 405), "terrain_stamp", (4, 4), (4, 3), "terrain"),
    Crop("cliff_wall_03", "洞穴峭壁 03", (1080, 175, 1238, 405), "terrain_stamp", (3, 4), (3, 3), "terrain"),
    Crop("cliff_wall_04", "洞穴峭壁 04", (1225, 170, 1500, 405), "terrain_stamp", (5, 4), (5, 3), "terrain"),
    # Rocks, containers and ruins.
    Crop("rock_pillar_01", "岩柱 01", (30, 395, 155, 555), "terrain_stamp", (2, 3), (2, 2), "terrain"),
    Crop("rock_pillar_02", "岩柱 02", (145, 395, 275, 555), "terrain_stamp", (2, 3), (2, 2), "terrain"),
    Crop("rock_pillar_03", "岩柱 03", (270, 395, 405, 555), "terrain_stamp", (2, 3), (2, 2), "terrain"),
    Crop("rock_pillar_04", "岩柱 04", (395, 395, 540, 555), "terrain_stamp", (2, 3), (2, 2), "terrain"),
    Crop("pottery_cluster_01", "陶罐杂物组合", (535, 398, 645, 555), "small_prop", (2, 2), (1, 1), "obstacle"),
    Crop("wood_crate_01", "木箱 01", (640, 395, 775, 555), "small_prop", (2, 2), (2, 2), "obstacle"),
    Crop("wood_crate_02", "木箱 02", (765, 395, 880, 555), "small_prop", (2, 2), (2, 2), "obstacle"),
    Crop("pottery_cluster_02", "陶罐补给组合", (875, 395, 1110, 555), "small_prop", (3, 2), (2, 1), "obstacle"),
    Crop("broken_crate_01", "破损木箱", (1135, 398, 1260, 550), "small_prop", (2, 2), (1, 1), "obstacle"),
    Crop("ruined_cart_01", "破损木车", (1245, 395, 1375, 550), "medium_prop", (3, 2), (2, 2), "obstacle"),
    Crop("rock_arch_01", "洞穴岩门", (1360, 395, 1505, 550), "terrain_stamp", (3, 3), (3, 2), "terrain"),
    Crop("ruined_temple_01", "地下城残破神殿", (25, 535, 305, 715), "large_prop", (6, 5), (5, 4), "building"),
    Crop("thatched_house_01", "地下洞居", (295, 535, 530, 715), "large_prop", (5, 4), (4, 3), "building"),
    Crop("ruined_workshop_01", "地下城破屋", (525, 535, 750, 715), "large_prop", (5, 4), (4, 3), "building"),
    Crop("shrine_pair_01", "地下城祭柱组合", (685, 535, 805, 710), "medium_prop", (2, 3), (2, 2), "obstacle"),
    Crop("cave_entrance_01", "洞穴入口", (775, 535, 950, 715), "terrain_stamp", (4, 4), (3, 3), "terrain"),
    Crop("boss_rock_shrine_01", "岩石祭坛", (930, 535, 1130, 715), "terrain_stamp", (4, 4), (3, 3), "terrain"),
    Crop("monolith_cluster_01", "巨型岩柱群", (1090, 485, 1505, 715), "terrain_stamp", (7, 5), (6, 4), "terrain"),
    # Ground stamps.
    Crop("dark_ground_stamp_01", "暗色地面覆盖 01", (35, 700, 225, 785), "terrain_overlay", (3, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_02", "暗色地面覆盖 02", (225, 700, 455, 795), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_03", "暗色地面覆盖 03", (445, 700, 675, 798), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_04", "暗色地面覆盖 04", (665, 700, 915, 802), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_05", "暗色地面覆盖 05", (905, 700, 1200, 805), "terrain_overlay", (5, 3), (0, 0), "decoration"),
    Crop("dark_ground_stamp_06", "暗色地面覆盖 06", (1190, 695, 1505, 810), "terrain_overlay", (5, 3), (0, 0), "decoration"),
    Crop("dark_ground_stamp_07", "暗色地面覆盖 07", (35, 790, 245, 882), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_08", "暗色地面覆盖 08", (235, 790, 490, 882), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_09", "暗色地面覆盖 09", (480, 790, 690, 882), "terrain_overlay", (4, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_10", "暗色地面覆盖 10", (35, 870, 202, 975), "terrain_overlay", (3, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_11", "暗色地面覆盖 11", (195, 870, 400, 975), "terrain_overlay", (3, 2), (0, 0), "decoration"),
    Crop("dark_ground_stamp_12", "暗色地面覆盖 12", (395, 870, 675, 980), "terrain_overlay", (5, 2), (0, 0), "decoration"),
    # Static magic-fire variants.
    Crop("magic_fire_orange_01", "橙色魔法火焰", (665, 795, 842, 980), "effect_prop", (2, 2), (1, 1), "interactable"),
    Crop("magic_fire_blue_01", "蓝色魔法火焰", (835, 795, 998, 980), "effect_prop", (2, 2), (1, 1), "interactable"),
    Crop("magic_fire_green_01", "绿色魔法火焰", (990, 795, 1150, 980), "effect_prop", (2, 2), (1, 1), "interactable"),
    Crop("magic_fire_gold_01", "金色魔法火焰", (1140, 795, 1315, 980), "effect_prop", (2, 2), (1, 1), "interactable"),
    Crop("magic_fire_white_01", "白色魔法火焰", (1305, 795, 1510, 980), "effect_prop", (2, 2), (1, 1), "interactable"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assert_safe_destination(path: Path) -> None:
    resolved = path.resolve()
    if ROOT.resolve() not in resolved.parents:
        raise RuntimeError(f"destination escapes workspace: {resolved}")


def extract_wall_pack(zip_path: Path) -> None:
    prefix = "MSE_V3_5_WALL_AssetPack_V1/"
    accepted = (
        "assets/art/maps/_shared/walls/",
        "assets/data/assets/wall_family_catalog.json",
        "assets/data/assets/wall_module_catalog.json",
        "assets/data/assets/walls/",
        "docs/mafa_scene_editor/walls/",
    )
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.is_dir() or not info.filename.startswith(prefix):
                continue
            relative = info.filename[len(prefix) :]
            if not any(relative.startswith(item) for item in accepted):
                continue
            target = ROOT / relative
            assert_safe_destination(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open("wb") as destination:
                shutil.copyfileobj(source, destination)


def trim_alpha(image: Image.Image, threshold: int = 1, padding: int = 4) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    box = alpha.getbbox()
    if box is None:
        raise RuntimeError("crop contains no visible pixels")
    left = max(0, box[0] - padding)
    top = max(0, box[1] - padding)
    right = min(rgba.width, box[2] + padding)
    bottom = min(rgba.height, box[3] + padding)
    return rgba.crop((left, top, right, bottom))


def isolate_reviewed_crop(image: Image.Image, threshold: int = 16, padding: int = 5) -> Image.Image:
    """Remove slivers from neighbouring sheet cells while preserving soft alpha.

    AI sprite sheets often leave glow pixels across a nominal cell boundary.  We
    identify opaque component cores, always retain the largest core, retain other
    meaningful cores that do not touch the crop edge (grouped pots/debris), then
    copy the original RGBA pixels around those cores.  This keeps antialiasing and
    fire glows but discards clipped neighbours.
    """
    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    values = alpha.load()
    visited = bytearray(width * height)
    components: list[tuple[int, bool, tuple[int, int, int, int]]] = []
    for start_y in range(height):
        for start_x in range(width):
            index = start_y * width + start_x
            if visited[index] or values[start_x, start_y] <= threshold:
                continue
            visited[index] = 1
            stack = [(start_x, start_y)]
            area = 0
            touches_edge = False
            min_x = max_x = start_x
            min_y = max_y = start_y
            while stack:
                x, y = stack.pop()
                area += 1
                touches_edge = touches_edge or x == 0 or y == 0 or x == width - 1 or y == height - 1
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
                for offset_x, offset_y in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
                    next_x = x + offset_x
                    next_y = y + offset_y
                    if next_x < 0 or next_y < 0 or next_x >= width or next_y >= height:
                        continue
                    next_index = next_y * width + next_x
                    if visited[next_index] or values[next_x, next_y] <= threshold:
                        continue
                    visited[next_index] = 1
                    stack.append((next_x, next_y))
            components.append((area, touches_edge, (min_x, min_y, max_x + 1, max_y + 1)))
    if not components:
        return rgba
    components.sort(key=lambda item: item[0], reverse=True)
    largest = components[0][0]
    minimum_area = max(18, math.ceil(largest * 0.004))
    retained = [components[0]]
    retained.extend(component for component in components[1:] if component[0] >= minimum_area and not component[1])
    mask = Image.new("L", rgba.size, 0)
    mask_pixels = mask.load()
    for _area, _touches_edge, box in retained:
        left = max(0, box[0] - padding)
        top = max(0, box[1] - padding)
        right = min(width, box[2] + padding)
        bottom = min(height, box[3] + padding)
        for y in range(top, bottom):
            for x in range(left, right):
                mask_pixels[x, y] = 255
    cleaned = rgba.copy()
    cleaned.putalpha(Image.composite(alpha, Image.new("L", rgba.size, 0), mask))
    return cleaned


def approved_scale(crop: Crop, width: int, height: int) -> float:
    if crop.category == "ground":
        return min(64.0 / width, 32.0 / height)
    span = crop.footprint[0] + crop.footprint[1]
    target_width = 32.0 * span
    vertical_allowance = 32.0 if crop.category in {"terrain_overlay", "shadow"} else 64.0
    target_height = 16.0 * span + vertical_allowance
    return round(max(0.15, min(1.0, target_width / width, target_height / height)), 6)


def palette_path(category: str) -> str:
    names = {
        "ground": "地块",
        "terrain_overlay": "地形覆盖",
        "terrain_wall": "地形墙边",
        "terrain_stamp": "岩壁与地形结构",
        "small_prop": "小型道具",
        "medium_prop": "中型道具",
        "large_prop": "建筑与大型道具",
        "effect_prop": "火焰与特效",
        "shadow": "阴影",
    }
    return "洞穴与地下城/补充素材/%s" % names.get(category, category)


def asset_type_for(crop: Crop) -> str:
    if crop.category == "ground":
        return "ground_brush"
    if crop.category in {"terrain_overlay", "shadow"}:
        return "terrain_overlay"
    if crop.category in {"terrain_wall", "terrain_stamp"}:
        return "terrain_stamp"
    return "large_prop"


def write_sheet_assets(source: Path, sheet_name: str, crops: tuple[Crop, ...]) -> list[dict]:
    output_root = DEST / sheet_name
    output_root.mkdir(parents=True, exist_ok=True)
    source_digest = sha256(source)
    source_copy = DEST / "_source" / f"{sheet_name}.png"
    source_copy.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, source_copy)
    result: list[dict] = []
    with Image.open(source) as sheet:
        rgba = sheet.convert("RGBA")
        for crop in crops:
            piece = trim_alpha(isolate_reviewed_crop(rgba.crop(crop.box)))
            output = output_root / f"{crop.asset_id}.png"
            piece.save(output, "PNG", optimize=True)
            width, height = piece.size
            scale = approved_scale(crop, width, height)
            anchor = [width // 2, height // 2 if crop.anchor_mode == "tile_center" else max(0, height - 1)]
            policy = "none" if crop.collision == (0, 0) else ("solid_footprint" if crop.role in {"building", "terrain"} else "preset")
            digest = sha256(output)
            result.append(
                {
                    "asset_id": f"cave_dungeon.{crop.asset_id}",
                    "display_name": crop.display_name,
                    "asset_type": asset_type_for(crop),
                    "category": crop.category,
                    "object_class": crop.category,
                    "theme": "cave_dungeon",
                    "image": output.relative_to(ROOT).as_posix(),
                    "thumbnail": output.relative_to(ROOT).as_posix(),
                    "canvas_size": [width, height],
                    "image_size": [width, height],
                    "visible_bounds_px": [0, 0, width, height],
                    "anchor_px": anchor,
                    "placement_anchor_px": anchor,
                    "anchor_tile": [0, 0],
                    "anchor_mode": crop.anchor_mode,
                    "footprint_tiles": list(crop.footprint),
                    "visual_footprint_tiles": list(crop.footprint),
                    "occupancy_footprint_tiles": list(crop.footprint),
                    "base_footprint_tiles": list(crop.footprint),
                    "collision_footprint_tiles": list(crop.collision),
                    "tile_size": [64, 32],
                    "approved_scale": scale,
                    "logical_scale_level": 0,
                    "scale_approved": True,
                    "anchor_approved": True,
                    "default_layer": crop.layer,
                    "default_object_role": crop.role,
                    "collision_policy": policy,
                    "collision_profile_id": "none_visual" if policy == "none" else "solid_logical_footprint",
                    "navigation_policy": "ignore" if policy == "none" else "block_player_and_monster",
                    "occlusion": crop.role in {"building", "terrain"},
                    "content_layer": "personal_expansion",
                    "placeable": True,
                    "calibration_status": "placeable",
                    "palette_path": palette_path(crop.category),
                    "source_external_path": str(source),
                    "source_sheet": sheet_name,
                    "source_crop_box": list(crop.box),
                    "source_sha256": source_digest,
                    "output_sha256": digest,
                    "thumbnail_source_sha256": digest,
                    "processing": "reviewed_alpha_sheet_crop_and_trim",
                    "tags": ["cave_dungeon", "sheet_asset", crop.category],
                    "editable": True,
                    "runtime_export": True,
                }
            )
    return result


def wall_assets() -> list[dict]:
    module_catalog = json.loads((DATA / "wall_module_catalog.json").read_text(encoding="utf-8"))
    result: list[dict] = []
    for module in module_catalog["modules"]:
        asset_id = str(module["asset_id"])
        family = str(module["wall_family_id"])
        topology = str(module["topology"])
        theme_name = "天然洞穴墙体" if str(module["theme"]) == "natural_cave" else "兽人古墓墙体"
        package = None
        for part in module.get("render_parts", []):
            image = ROOT / str(part["base_image"])
            package = image.parent
            break
        if package is None:
            raise RuntimeError(f"{asset_id}: missing render_parts")
        composite = package / "composite.png"
        preview = package / "preview.png"
        if not composite.is_file() or not preview.is_file():
            raise RuntimeError(f"{asset_id}: missing composite or preview")
        footprint = [max(1, int(value)) for value in module.get("footprint_tiles", [1, 1])]
        cells = [[int(cell[0]), int(cell[1])] for cell in module.get("collision_cells", [])]
        if cells:
            collision = [
                max(cell[0] for cell in cells) - min(cell[0] for cell in cells) + 1,
                max(cell[1] for cell in cells) - min(cell[1] for cell in cells) + 1,
            ]
        else:
            collision = [0, 0]
        with Image.open(composite) as image:
            size = list(image.size)
        digest = sha256(composite)
        result.append(
            {
                **module,
                "display_name": str(module.get("display_name", asset_id)),
                "category": "wall_module",
                "object_class": "wall",
                "image": composite.relative_to(ROOT).as_posix(),
                "thumbnail": preview.relative_to(ROOT).as_posix(),
                "image_size": size,
                "visible_bounds_px": [0, 0, size[0], size[1]],
                "anchor_px": module["anchor"],
                "placement_anchor_px": module["anchor"],
                "anchor_tile": [0, 0],
                "anchor_mode": "foot_tile",
                "footprint_tiles": footprint,
                "visual_footprint_tiles": footprint,
                "occupancy_footprint_tiles": footprint,
                "base_footprint_tiles": footprint,
                "collision_footprint_tiles": collision,
                "tile_size": [64, 32],
                "approved_scale": 1.0,
                "logical_scale_level": 0,
                "scale_approved": True,
                "anchor_approved": True,
                "default_object_role": "terrain",
                "collision_profile_id": "wall_explicit_cells" if cells else "none_visual",
                "content_layer": "personal_expansion",
                "calibration_status": "placeable",
                "palette_path": f"洞穴与地下城/墙体模块/{theme_name}/{topology}/{module.get('axis') or '通用'}",
                "source_external_path": "MSE_V3_5_WALL_AssetPack_V1.zip",
                "source_sha256": digest,
                "output_sha256": digest,
                "thumbnail_source_sha256": sha256(preview),
                "processing": "mse_wall_package_passthrough",
                "tags": ["cave_dungeon", "wall_module", family, topology],
                "editable": True,
            }
        )
    return result


def validate_assets(assets: list[dict]) -> None:
    ids: set[str] = set()
    errors: list[str] = []
    for asset in assets:
        asset_id = str(asset.get("asset_id", ""))
        if not asset_id or asset_id in ids:
            errors.append(f"duplicate_or_missing_asset_id:{asset_id}")
        ids.add(asset_id)
        image = ROOT / str(asset.get("image", ""))
        if not image.is_file():
            errors.append(f"{asset_id}:missing_image")
            continue
        with Image.open(image) as opened:
            if opened.mode != "RGBA":
                errors.append(f"{asset_id}:not_rgba")
            extrema = opened.getchannel("A").getextrema()
            if extrema[0] != 0 or extrema[1] == 0:
                errors.append(f"{asset_id}:invalid_alpha_range:{extrema}")
        footprint = asset.get("footprint_tiles", [])
        if len(footprint) != 2 or min(int(value) for value in footprint) <= 0:
            errors.append(f"{asset_id}:invalid_footprint")
        anchor = asset.get("anchor_px", [])
        size = asset.get("image_size", [])
        if len(anchor) != 2 or len(size) != 2 or not (0 <= int(anchor[0]) <= int(size[0]) and 0 <= int(anchor[1]) <= int(size[1])):
            errors.append(f"{asset_id}:invalid_anchor")
    if errors:
        raise RuntimeError("\n".join(errors))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wall-pack", type=Path, default=Path(r"C:\Users\Administrator\Downloads\MSE_V3_5_WALL_AssetPack_V1.zip"))
    parser.add_argument("--sheet-1", type=Path, default=Path(r"C:\Users\Administrator\Downloads\ChatGPT Image 2026年7月17日 20_32_57 (1).png"))
    parser.add_argument("--sheet-2", type=Path, default=Path(r"C:\Users\Administrator\Downloads\ChatGPT Image 2026年7月17日 20_32_58 (3).png"))
    args = parser.parse_args()
    for source in (args.wall_pack, args.sheet_1, args.sheet_2):
        if not source.is_file():
            raise SystemExit(f"missing source: {source}")
    assert_safe_destination(DEST)
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    extract_wall_pack(args.wall_pack)
    assets = []
    assets.extend(write_sheet_assets(args.sheet_1, "reference_sheet_01", SHEET_1_CROPS))
    assets.extend(write_sheet_assets(args.sheet_2, "reference_sheet_02", SHEET_2_CROPS))
    assets.extend(wall_assets())
    validate_assets(assets)
    payload = {
        "asset_schema_version": 2,
        "catalog_id": "cave_dungeon",
        "display_name": "洞穴与地下城",
        "source_policy": "mse_wall_pack_plus_reviewed_transparent_sheet_crops",
        "wall_family_ids": ["cave_granite_u0", "orc_tomb_rough_stone_u0"],
        "assets": assets,
    }
    CATALOG.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts: dict[str, int] = {}
    for asset in assets:
        category = str(asset["category"])
        counts[category] = counts.get(category, 0) + 1
    print(f"CAVE_DUNGEON_IMPORT_PASS assets={len(assets)} categories={json.dumps(counts, ensure_ascii=False, sort_keys=True)}")


if __name__ == "__main__":
    main()
