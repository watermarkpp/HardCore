#!/usr/bin/env python3
"""Build the Wooma Temple wall family from reviewed generated source sheets.

The source sheets live under outputs/wooma_temple_generated and are intentionally
not versioned. The generated, transparent, calibrated wall modules and their
catalog records are versioned project assets.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "outputs" / "wooma_temple_generated"
ART_ROOT = (
    ROOT
    / "assets"
    / "art"
    / "maps"
    / "_shared"
    / "walls"
    / "wooma_temple"
    / "wooma_temple_gothic_stone_u0"
)
MODULE_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_module_catalog.json"
FAMILY_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_family_catalog.json"
ASSET_CATALOG = (
    ROOT
    / "assets"
    / "data"
    / "assets"
    / "map_wooma_temple_wall_asset_catalog.json"
)

SOURCE_REFERENCE = (
    r"C:\Users\Administrator\Desktop\sucai\新增\立柱"
    r"\ChatGPT Image 2026年7月19日 22_29_59.png"
)
FAMILY_ID = "wooma_temple_gothic_stone_u0"
SOCKET_ID = "wooma_temple_gothic_stone_socket_u0"
SOURCE_FAMILY_ID = "orc_tomb_rough_stone_u0"
SOURCE_PREFIX = "orc_tomb_wall_"
TARGET_PREFIX = "wooma_temple_wall_"

STRAIGHT_BOXES = [
    (76, 220, 419, 658),
    (517, 221, 858, 662),
    (975, 222, 1249, 625),
    (1379, 223, 1679, 640),
]
ADAPTER_BOXES = [
    (52, 222, 413, 652),
    (483, 222, 845, 655),
    (914, 235, 1282, 667),
    (1362, 235, 1725, 667),
]
PILLAR_BOXES = [
    (40, 298, 211, 617),
    (265, 297, 431, 616),
    (485, 298, 650, 617),
    (700, 298, 865, 616),
    (920, 299, 1083, 618),
    (1135, 299, 1298, 617),
    (1351, 299, 1515, 618),
    (1568, 302, 1733, 618),
]

RESAMPLE = Image.Resampling.LANCZOS


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def alpha_trim(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    box = rgba.getchannel("A").getbbox()
    if box is None:
        raise RuntimeError("source crop has no visible pixels")
    return rgba.crop(box)


def crop_sheet(sheet: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    return alpha_trim(sheet.crop(box))


def fit_on_canvas(
    image: Image.Image,
    canvas_size: tuple[int, int],
    target_size: tuple[int, int],
    *,
    center_x: int,
    bottom_y: int,
) -> Image.Image:
    source = alpha_trim(image)
    ratio = min(target_size[0] / source.width, target_size[1] / source.height)
    size = (
        max(1, int(round(source.width * ratio))),
        max(1, int(round(source.height * ratio))),
    )
    resized = source.resize(size, RESAMPLE)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    left = int(round(center_x - resized.width / 2))
    top = bottom_y - resized.height
    canvas.alpha_composite(resized, (left, top))
    return canvas


def mirror(image: Image.Image) -> Image.Image:
    return image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


def composite(images: list[Image.Image], size: tuple[int, int]) -> Image.Image:
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    for image in images:
        result.alpha_composite(image)
    return result


def place_anchored(
    source: Image.Image,
    source_anchor: tuple[int, int],
    target_size: tuple[int, int],
    target_anchor: tuple[int, int],
) -> Image.Image:
    result = Image.new("RGBA", target_size, (0, 0, 0, 0))
    position = (
        target_anchor[0] - source_anchor[0],
        target_anchor[1] - source_anchor[1],
    )
    result.alpha_composite(source, position)
    return result


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def res_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def display_name(module: dict) -> str:
    topology = str(module["topology"])
    axis = str(module.get("axis") or "")
    length = int(module.get("length_tiles", 1))
    variant = int(module.get("variant", 1))
    names = {
        "straight": "直墙",
        "inner_corner": "内转角",
        "outer_corner": "外转角",
        "end_cap": "墙体端头",
        "door_adapter": "门洞墙",
        "broken_adapter": "破损墙",
        "seam_cover": "接缝立柱",
    }
    axis_name = {"iso_x": "X向", "iso_y": "Y向"}.get(axis, "")
    suffix = f" {length}格" if topology in {"straight", "door_adapter", "broken_adapter"} else ""
    return f"沃玛寺庙{names[topology]} {axis_name}{suffix} 变体{variant}".replace("  ", " ")


def normalized_straights() -> tuple[list[Image.Image], list[Image.Image]]:
    with Image.open(SOURCE_DIR / "straight_sheet_alpha.png") as opened:
        sheet = opened.convert("RGBA")
    x_variants: list[Image.Image] = []
    for box in STRAIGHT_BOXES:
        crop = crop_sheet(sheet, box)
        x_variants.append(
            fit_on_canvas(
                crop,
                (96, 160),
                (92, 150),
                center_x=48,
                bottom_y=158,
            )
        )
    return x_variants, [mirror(image) for image in x_variants]


def normalized_adapters() -> list[Image.Image]:
    with Image.open(SOURCE_DIR / "adapter_sheet_alpha.png") as opened:
        sheet = opened.convert("RGBA")
    result: list[Image.Image] = []
    for box in ADAPTER_BOXES:
        crop = crop_sheet(sheet, box)
        result.append(
            fit_on_canvas(
                crop,
                (160, 192),
                (156, 186),
                center_x=80,
                bottom_y=190,
            )
        )
    return result


def normalized_pillars() -> list[Image.Image]:
    with Image.open(SOURCE_DIR / "pillar_sheet_alpha.png") as opened:
        sheet = opened.convert("RGBA")
    result: list[Image.Image] = []
    for box in PILLAR_BOXES:
        crop = crop_sheet(sheet, box)
        result.append(
            fit_on_canvas(
                crop,
                (96, 128),
                (88, 124),
                center_x=48,
                bottom_y=127,
            )
        )
    return result


def straight_art(
    module: dict,
    x_variants: list[Image.Image],
    y_variants: list[Image.Image],
    variant_seed: int,
) -> tuple[Image.Image, list[Image.Image]]:
    axis = str(module["axis"])
    length = int(module["length_tiles"])
    size = tuple(int(value) for value in module["canvas_size"])
    anchor = tuple(int(value) for value in module["anchor"])
    base_anchor = (48, 128)
    variants = x_variants if axis == "iso_x" else y_variants
    parts: list[Image.Image] = []
    for index in range(length):
        source = variants[(variant_seed + index) % len(variants)]
        delta = (32 * index, 16 * index) if axis == "iso_x" else (-32 * index, 16 * index)
        target_anchor = (anchor[0] + delta[0], anchor[1] + delta[1])
        parts.append(place_anchored(source, base_anchor, size, target_anchor))
    return composite(parts, size), parts


def corner_art(
    module: dict,
    x_variants: list[Image.Image],
    y_variants: list[Image.Image],
    pillars: list[Image.Image],
    variant_seed: int,
) -> Image.Image:
    size = tuple(int(value) for value in module["canvas_size"])
    anchor = tuple(int(value) for value in module["anchor"])
    x_part = place_anchored(x_variants[variant_seed % 4], (48, 128), size, anchor)
    y_part = place_anchored(y_variants[(variant_seed + 1) % 4], (48, 128), size, anchor)
    pillar = place_anchored(pillars[(variant_seed + 2) % 8], (48, 104), size, anchor)
    return composite([x_part, y_part, pillar], size)


def pillar_art(module: dict, pillars: list[Image.Image], variant_seed: int) -> Image.Image:
    size = tuple(int(value) for value in module["canvas_size"])
    anchor = tuple(int(value) for value in module["anchor"])
    return place_anchored(
        pillars[variant_seed % len(pillars)],
        (48, 104),
        size,
        anchor,
    )


def adapter_art(module: dict, adapters: list[Image.Image]) -> Image.Image:
    topology = str(module["topology"])
    axis = str(module["axis"])
    source_index = {
        ("door_adapter", 1): 0,
        ("door_adapter", 2): 1,
        ("broken_adapter", 1): 2,
        ("broken_adapter", 2): 3,
    }[(topology, int(module.get("variant", 1)))]
    source = adapters[source_index]
    if axis == "iso_y":
        source = mirror(source)
    return source


def build_module(
    source_module: dict,
    x_variants: list[Image.Image],
    y_variants: list[Image.Image],
    adapters: list[Image.Image],
    pillars: list[Image.Image],
) -> tuple[dict, dict]:
    module = copy.deepcopy(source_module)
    asset_id = str(module["asset_id"]).replace(SOURCE_PREFIX, TARGET_PREFIX, 1)
    module["asset_id"] = asset_id
    module["display_name"] = display_name(module)
    module["category"] = "dungeon_wall"
    module["theme"] = "wooma_temple"
    module["wall_family_id"] = FAMILY_ID
    module["socket_profile_id"] = SOCKET_ID
    module["content_layer"] = "personal_expansion"
    module["collision_cells"] = []
    module["placement_clearance_cells"] = []
    module["collision_policy"] = "none"
    module["navigation_policy"] = "ignore"
    module["manual_collision_expected"] = True
    module["collision_authority"] = "manual_by_user"
    module["collision_profile_id"] = "none_visual"
    module["calibration_status"] = "placeable"
    module["placeable"] = True
    module["repeat_group"] = str(module.get("repeat_group", "")).replace(
        "orc_tomb_", "wooma_temple_", 1
    )
    for connector in module.get("connectors", []):
        connector["socket_profile_id"] = SOCKET_ID

    topology = str(module["topology"])
    variant_seed = max(0, int(module.get("variant", 1)) - 1)
    if topology == "straight":
        artwork, parts = straight_art(
            module, x_variants, y_variants, variant_seed
        )
    elif topology in {"inner_corner", "outer_corner"}:
        artwork = corner_art(
            module, x_variants, y_variants, pillars, variant_seed
        )
        parts = [artwork]
    elif topology in {"door_adapter", "broken_adapter"}:
        artwork = adapter_art(module, adapters)
        parts = [artwork]
        module["render_mode"] = "single_part"
    elif topology in {"end_cap", "seam_cover"}:
        artwork = pillar_art(module, pillars, variant_seed)
        parts = [artwork]
    else:
        raise RuntimeError(f"unsupported topology: {topology}")

    asset_dir = ART_ROOT / asset_id
    if asset_dir.exists():
        shutil.rmtree(asset_dir)
    asset_dir.mkdir(parents=True)
    composite_path = asset_dir / "composite.png"
    save_png(artwork, composite_path)

    render_parts: list[dict] = []
    for index, part_image in enumerate(parts):
        part_path = asset_dir / f"part_{index:02d}_base.png"
        save_png(part_image, part_path)
        if topology == "straight":
            tile_offset = [index, 0] if module["axis"] == "iso_x" else [0, index]
        elif topology in {"door_adapter", "broken_adapter"}:
            tile_offset = [1, 0] if module["axis"] == "iso_x" else [0, 1]
        else:
            tile_offset = [0, 0]
        render_parts.append(
            {
                "part_id": f"p{index:02d}",
                "tile_offset": tile_offset,
                "base_image": res_path(part_path),
                "front_image": "",
                "shadow_image": "",
                "anchor": list(module["anchor"]),
                "sort_tile_offset": tile_offset,
                "draw_order_index": index,
            }
        )
    module["render_parts"] = render_parts

    size = list(artwork.size)
    digest = sha256(composite_path)
    asset = {
        **copy.deepcopy(module),
        "category": "wall_module",
        "object_class": "wall",
        "image": res_path(composite_path),
        "thumbnail": res_path(composite_path),
        "image_size": size,
        "visible_bounds_px": [0, 0, size[0], size[1]],
        "anchor_px": list(module["anchor"]),
        "placement_anchor_px": list(module["anchor"]),
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "visual_footprint_tiles": list(module["footprint_tiles"]),
        "occupancy_footprint_tiles": list(module["footprint_tiles"]),
        "base_footprint_tiles": list(module["footprint_tiles"]),
        "collision_footprint_tiles": [0, 0],
        "tile_size": [64, 32],
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_object_role": "terrain",
        "palette_path": (
            "洞穴与地下城/墙体模块/沃玛寺庙墙体/"
            f"{topology}/{module.get('axis') or '通用'}"
        ),
        "source_external_path": SOURCE_REFERENCE,
        "source_sha256": digest,
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "codex_imagegen_chroma_key_crop_grid_calibration",
        "generation_source_ids": [
            "call_xXn4eC7qB47nNHjtEWxSeT1w",
            "call_RkPJjEbxRLq4GslLL27OVQx1",
            "call_yV5OeDNzIezU9yrVumYXQqEu",
            "call_QwTKuxDXelxir3RMaDjAzlXe",
        ],
        "tags": [
            "cave_dungeon",
            "wooma_temple",
            "wall_module",
            FAMILY_ID,
            topology,
            "manual_collision",
        ],
        "editable": True,
        "runtime_export": True,
    }
    return module, asset


def update_family_catalog() -> None:
    catalog = read_json(FAMILY_CATALOG)
    catalog["wall_families"] = [
        family
        for family in catalog.get("wall_families", [])
        if family.get("wall_family_id") != FAMILY_ID
    ]
    catalog["wall_families"].append(
        {
            "wall_family_id": FAMILY_ID,
            "display_name": "沃玛寺庙哥特旧石墙 U0",
            "theme": "wooma_temple",
            "material": "gothic_gray_green_stone",
            "socket_profile_id": SOCKET_ID,
            "tile_size": [64, 32],
            "wall_height_px": 96,
            "side_pad_px": 16,
            "allowed_lengths": [1, 2, 3, 4],
            "primary_lengths": [4, 3],
            "repair_lengths": [2, 1],
            "default_blocked_side": "outside",
            "seam_guard_px": 16,
            "seam_overlap_px": 2,
            "seam_cover_asset_ids": [
                f"{TARGET_PREFIX}seam_cover_{index:02d}" for index in range(1, 7)
            ],
            "palette_id": "wooma_temple_gothic_stone_u0",
            "content_layer": "personal_expansion",
            "collision_authority": "manual_by_user",
            "enabled": True,
        }
    )
    write_json(FAMILY_CATALOG, catalog)


def main() -> None:
    required = [
        SOURCE_DIR / "straight_sheet_alpha.png",
        SOURCE_DIR / "adapter_sheet_alpha.png",
        SOURCE_DIR / "pillar_sheet_alpha.png",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError(f"missing reviewed source sheets: {missing}")

    module_catalog = read_json(MODULE_CATALOG)
    source_modules = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") == SOURCE_FAMILY_ID
    ]
    if len(source_modules) != 42:
        raise RuntimeError(f"expected 42 source modules, found {len(source_modules)}")

    x_variants, y_variants = normalized_straights()
    adapters = normalized_adapters()
    pillars = normalized_pillars()

    modules: list[dict] = []
    assets: list[dict] = []
    for source_module in source_modules:
        module, asset = build_module(
            source_module,
            x_variants,
            y_variants,
            adapters,
            pillars,
        )
        modules.append(module)
        assets.append(asset)

    module_catalog["modules"] = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") != FAMILY_ID
    ] + modules
    write_json(MODULE_CATALOG, module_catalog)
    update_family_catalog()
    write_json(
        ASSET_CATALOG,
        {
            "asset_schema_version": 2,
            "catalog_id": "wooma_temple_wall_pack",
            "display_name": "沃玛寺庙墙体素材包",
            "source_policy": "codex_imagegen_reviewed_chroma_key_calibrated",
            "wall_family_ids": [FAMILY_ID],
            "collision_authority": "manual_by_user",
            "assets": assets,
        },
    )
    print(
        f"WOOMA_TEMPLE_WALL_BUILD_OK modules={len(modules)} "
        f"assets={len(assets)} root={ART_ROOT}"
    )


if __name__ == "__main__":
    main()
