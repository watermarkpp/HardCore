#!/usr/bin/env python3
"""Create the Wooma-floor color variant of the standard temple wall pack.

Geometry, alpha, anchors, seams, lengths, and collision policy are copied
unchanged. Only RGB tone is transformed. The target palette is measured from
the six ground tiles actually painted across wooma_temple_1.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "assets" / "data" / "assets"
STANDARD_CATALOG = DATA / "map_wooma_temple_wall_asset_catalog.json"
WARM_CATALOG = DATA / "map_wooma_temple_warm_wall_asset_catalog.json"
MODULE_CATALOG = DATA / "wall_module_catalog.json"
FAMILY_CATALOG = DATA / "wall_family_catalog.json"

STANDARD_FAMILY_ID = "wooma_temple_gothic_stone_u0"
WARM_FAMILY_ID = "wooma_temple_floor_warm_stone_u0"
STANDARD_SOCKET_ID = "wooma_temple_gothic_stone_socket_u0"
WARM_SOCKET_ID = "wooma_temple_floor_warm_stone_socket_u0"
STANDARD_ASSET_PREFIX = "wooma_temple_wall_"
WARM_ASSET_PREFIX = "wooma_temple_warm_wall_"
STANDARD_PROFILE_ID = "wooma_temple_native_2to1_wall_v3"
WARM_PROFILE_ID = "wooma_temple_floor_match_v1"
STANDARD_ART_SEGMENT = (
    "assets/art/maps/_shared/walls/wooma_temple/"
    "wooma_temple_gothic_stone_u0/"
)
WARM_ART_SEGMENT = (
    "assets/art/maps/_shared/walls/wooma_temple/"
    "wooma_temple_floor_warm_stone_u0/"
)
WARM_ART_ROOT = ROOT / WARM_ART_SEGMENT

# Actual wooma_temple_1 paint usage at calibration time.
GROUND_REFERENCE_ASSET_COUNTS = {
    "mse.new_ground.stone_platform.07": 526,
    "mse.new_ground.stone_platform.08": 547,
    "mse.new_ground.stone_platform.09": 523,
    "mse.new_ground.stone_platform.10": 522,
    "mse.new_ground.stone_platform.11": 546,
    "mse.new_ground.stone_platform.12": 546,
}
GROUND_WEIGHTED_MEDIAN_RGB = (148, 136, 112)
COLOR_MATCH_CONTRACT_ID = "wooma_floor_weighted_palette_match_v1"


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


def warm_asset_id(asset_id: str) -> str:
    if not asset_id.startswith(STANDARD_ASSET_PREFIX):
        raise RuntimeError(f"unexpected standard asset id: {asset_id}")
    return asset_id.replace(STANDARD_ASSET_PREFIX, WARM_ASSET_PREFIX, 1)


def warm_resource_path(path: str) -> str:
    return (
        path.replace(STANDARD_ART_SEGMENT, WARM_ART_SEGMENT, 1)
        .replace(STANDARD_ASSET_PREFIX, WARM_ASSET_PREFIX, 1)
        .replace(STANDARD_PROFILE_ID, WARM_PROFILE_ID, 1)
    )


def recolor_pixel(pixel: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return pixel
    luma = (54 * red + 183 * green + 19 * blue) / 256.0
    lifted = min(235.0, luma * 1.15 + 10.0)
    target_red, target_green, target_blue = GROUND_WEIGHTED_MEDIAN_RGB
    target_luma = float(target_green)
    preserve_chroma = 0.25
    warm_red = (
        lifted * target_red / target_luma
        + (red - luma) * preserve_chroma
    )
    warm_green = (
        lifted * target_green / target_luma
        + (green - luma) * preserve_chroma
    )
    warm_blue = (
        lifted * target_blue / target_luma
        + (blue - luma) * preserve_chroma
    )
    return (
        max(0, min(255, round(warm_red))),
        max(0, min(255, round(warm_green))),
        max(0, min(255, round(warm_blue))),
        alpha,
    )


def recolor_png(source: Path, destination: Path) -> None:
    with Image.open(source) as opened:
        rgba = opened.convert("RGBA")
    output = Image.new("RGBA", rgba.size)
    output.putdata(
        [recolor_pixel(pixel) for pixel in rgba.get_flattened_data()]
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(destination, format="PNG", optimize=True)


def transform_image_path(path: str, generated: set[str]) -> str:
    if not path:
        return ""
    destination_path = warm_resource_path(path)
    if destination_path in generated:
        return destination_path
    source = ROOT / path
    destination = ROOT / destination_path
    if not source.is_file():
        raise RuntimeError(f"missing standard wall image: {source}")
    recolor_png(source, destination)
    generated.add(destination_path)
    return destination_path


def transform_render_parts(
    parts: list[dict],
    generated: set[str],
) -> list[dict]:
    result = copy.deepcopy(parts)
    for part in result:
        for field in ("base_image", "front_image", "shadow_image"):
            part[field] = transform_image_path(str(part.get(field, "")), generated)
    return result


def transform_module(
    standard: dict,
    generated: set[str],
) -> dict:
    module = copy.deepcopy(standard)
    module["asset_id"] = warm_asset_id(str(standard["asset_id"]))
    module["display_name"] = str(standard.get("display_name", "")).replace(
        "标准哥特直墙",
        "沃玛寺庙暖灰褐直墙",
    )
    module["wall_family_id"] = WARM_FAMILY_ID
    module["socket_profile_id"] = WARM_SOCKET_ID
    module["theme"] = "wooma_temple_floor_warm"
    module["material"] = "warm_olive_taupe_sandstone"
    module["visual_profile_id"] = WARM_PROFILE_ID
    module["color_match_contract_id"] = COLOR_MATCH_CONTRACT_ID
    module["render_parts"] = transform_render_parts(
        module.get("render_parts", []),
        generated,
    )
    for connector in module.get("connectors", []):
        connector["socket_profile_id"] = WARM_SOCKET_ID
    return module


def transform_asset(
    standard: dict,
    generated: set[str],
) -> dict:
    asset = transform_module(standard, generated)
    asset["image"] = transform_image_path(str(standard["image"]), generated)
    asset["thumbnail"] = transform_image_path(
        str(standard.get("thumbnail", standard["image"])),
        generated,
    )
    image_path = ROOT / str(asset["image"])
    asset["source_standard_asset_id"] = str(standard["asset_id"])
    asset["source_standard_output_sha256"] = str(
        standard.get("output_sha256", "")
    )
    asset["output_sha256"] = sha256(image_path)
    asset["thumbnail_source_sha256"] = sha256(
        ROOT / str(asset["thumbnail"])
    )
    asset["processing"] = "standard_wall_weighted_ground_palette_transfer"
    asset["palette_path"] = str(asset.get("palette_path", "")).replace(
        "沃玛寺庙墙体",
        "沃玛寺庙暖灰褐墙",
    )
    tags = [
        tag
        for tag in asset.get("tags", [])
        if tag not in [STANDARD_FAMILY_ID, "standard_reusable"]
    ]
    tags.extend(
        [
            WARM_FAMILY_ID,
            "wooma_floor_color_match",
            "warm_olive_taupe",
        ]
    )
    asset["tags"] = list(dict.fromkeys(tags))
    return asset


def warm_family(standard_family: dict, asset_ids: list[str]) -> dict:
    family = copy.deepcopy(standard_family)
    family.update(
        {
            "wall_family_id": WARM_FAMILY_ID,
            "display_name": "沃玛寺庙暖灰褐石墙 U0",
            "theme": "wooma_temple_floor_warm",
            "material": "warm_olive_taupe_sandstone",
            "socket_profile_id": WARM_SOCKET_ID,
            "palette_id": WARM_FAMILY_ID,
            "palette_role": "wooma_temple_floor_matched_wall",
            "color_match_contract_id": COLOR_MATCH_CONTRACT_ID,
            "ground_reference_map_id": "wooma_temple_1",
            "ground_reference_asset_counts": GROUND_REFERENCE_ASSET_COUNTS,
            "ground_weighted_median_rgb": list(GROUND_WEIGHTED_MEDIAN_RGB),
            "asset_ids": asset_ids,
        }
    )
    return family


def main() -> None:
    standard_catalog = read_json(STANDARD_CATALOG)
    standard_assets = standard_catalog.get("assets", [])
    if len(standard_assets) != 16:
        raise RuntimeError(
            f"expected 16 standard wall assets, found {len(standard_assets)}"
        )

    module_catalog = read_json(MODULE_CATALOG)
    standard_modules = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") == STANDARD_FAMILY_ID
    ]
    if len(standard_modules) != 16:
        raise RuntimeError(
            f"expected 16 standard wall modules, found {len(standard_modules)}"
        )

    if WARM_ART_ROOT.exists():
        shutil.rmtree(WARM_ART_ROOT)
    WARM_ART_ROOT.mkdir(parents=True)
    generated: set[str] = set()
    warm_modules = [
        transform_module(module, generated)
        for module in standard_modules
    ]
    warm_assets = [
        transform_asset(asset, generated)
        for asset in standard_assets
    ]

    module_catalog["modules"] = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") != WARM_FAMILY_ID
    ] + warm_modules
    write_json(MODULE_CATALOG, module_catalog)

    family_catalog = read_json(FAMILY_CATALOG)
    standard_family = next(
        (
            family
            for family in family_catalog.get("wall_families", [])
            if family.get("wall_family_id") == STANDARD_FAMILY_ID
        ),
        None,
    )
    if standard_family is None:
        raise RuntimeError("standard wall family missing")
    family_catalog["wall_families"] = [
        family
        for family in family_catalog.get("wall_families", [])
        if family.get("wall_family_id") != WARM_FAMILY_ID
    ]
    family_catalog["wall_families"].append(
        warm_family(
            standard_family,
            [str(asset["asset_id"]) for asset in warm_assets],
        )
    )
    write_json(FAMILY_CATALOG, family_catalog)

    write_json(
        WARM_CATALOG,
        {
            "asset_schema_version": 2,
            "catalog_id": "wooma_temple_warm_wall_pack",
            "display_name": "沃玛寺庙地面配色无柱直墙素材包",
            "derived_from_catalog_id": str(
                standard_catalog.get("catalog_id", "")
            ),
            "color_match_contract_id": COLOR_MATCH_CONTRACT_ID,
            "ground_reference_map_id": "wooma_temple_1",
            "ground_reference_asset_counts": GROUND_REFERENCE_ASSET_COUNTS,
            "ground_weighted_median_rgb": list(GROUND_WEIGHTED_MEDIAN_RGB),
            "geometry_contract_id": str(
                standard_catalog.get("native_projection_contract_id", "")
            ),
            "placement_contract_id": str(
                standard_catalog.get("placement_contract_id", "")
            ),
            "corner_join_mode": "straight_overlap",
            "wall_family_ids": [WARM_FAMILY_ID],
            "collision_authority": "manual_by_user",
            "assets": warm_assets,
        },
    )
    print(
        "WOOMA_TEMPLE_WARM_WALL_BUILD_OK "
        f"modules={len(warm_modules)} assets={len(warm_assets)} "
        f"images={len(generated)} target_rgb={GROUND_WEIGHTED_MEDIAN_RGB}"
    )


if __name__ == "__main__":
    main()
