#!/usr/bin/env python3
"""Build male-warrior Hum/Weapon action atlases from Shape candidates."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
SOURCE_CSV = ROOT / "dev_art_sources/reference/mir2_database/angelk727/2_物品数据.csv"
CATALOG = ROOT / "assets/data/legend176_data.json"
OUTPUT = ROOT / "assets/art/characters/warrior/wear"
MANIFEST = ROOT / "assets/data/warrior_wear_sources.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


BODY_CELL = (192, 160)
BODY_FOOT_ANCHOR = (64, 80)
# Weapon.wil attacks extend as far as y=-109 relative to the classic actor
# origin.  The former 160px-high body cell started at y=-80 and silently
# cropped long weapons in W/NW/SE attack frames.  Weapons keep the same actor
# origin but receive an independent cell large enough for every mapped frame.
WEAPON_CELL = (192, 224)
WEAPON_FOOT_ANCHOR = (68, 112)
LAYOUTS = {
    "dressAppearance": {"cell": BODY_CELL, "foot_anchor": BODY_FOOT_ANCHOR},
    "weaponAppearance": {"cell": WEAPON_CELL, "foot_anchor": WEAPON_FOOT_ANCHOR},
}
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
# The imported CSV is only a candidate data source.  Its Judgement Staff entry
# uses the wrong Shape (21, the thin staff block).  Classic Weapon.wil tables
# map 裁决之杖 to Shape 24; male feature is Shape * 2 = 48.
CLASSIC_SHAPE_OVERRIDES = {
    "裁决之杖": 24,
}


def source_rows() -> dict[str, dict]:
    with SOURCE_CSV.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    result = {}
    for row in rows:
        name = str(row.get("ItemName", ""))
        if name and name not in result:
            result[name] = row
    return result


def weapon_tip_offset(image: Image.Image, meta: dict) -> list[int]:
    """Return the centroid of the distal opaque weapon-head pixels."""
    rgba = image.convert("RGBA")
    points = [
        (x + int(meta["x"]), y + int(meta["y"]))
        for y in range(rgba.height)
        for x in range(rgba.width)
        if rgba.getpixel((x, y))[3] > 32
    ]
    if not points:
        return [0, 0]
    max_distance = max(x * x + y * y for x, y in points)
    distal = [(x, y) for x, y in points if x * x + y * y >= max_distance * 0.85]
    return [round(sum(x for x, _ in distal) / len(distal)), round(sum(y for _, y in distal) / len(distal))]


def build_action(library: Path, feature: int, action: str, target: Path, appearance_type: str) -> dict:
    data, palette, offsets, info = read_library(library)
    spec = ACTIONS[action]
    frame_count = int(spec["frames"])
    layout = LAYOUTS[appearance_type]
    cell = layout["cell"]
    foot_anchor = layout["foot_anchor"]
    atlas = Image.new("RGBA", (cell[0] * frame_count, cell[1] * 8), (0, 0, 0, 0))
    frames, missing = [], []
    for direction in range(8):
        for frame in range(frame_count):
            within_block = int(spec["start"]) + direction * 8 + frame
            index = feature * 600 + within_block
            if index >= len(offsets):
                missing.append(index)
                continue
            try:
                image, meta = decode_sprite(data, offsets[index], palette)
            except ValueError:
                missing.append(index)
                continue
            local_x = foot_anchor[0] + meta["x"]
            local_y = foot_anchor[1] + meta["y"]
            if local_x < 0 or local_y < 0 or local_x + image.width > cell[0] or local_y + image.height > cell[1]:
                raise RuntimeError(
                    f"{appearance_type} feature={feature} {action} direction={direction} frame={frame} "
                    f"does not fit cell={cell} anchor={foot_anchor}: "
                    f"offset=({meta['x']},{meta['y']}) size={image.size}"
                )
            paste = (frame * cell[0] + local_x, direction * cell[1] + local_y)
            atlas.alpha_composite(image.convert("RGBA"), paste)
            frame_record = {
                "index": index,
                "direction": direction,
                "frame": frame,
                "drawOffset": [meta["x"], meta["y"]],
                "sourceSize": [image.width, image.height],
            }
            if appearance_type == "weaponAppearance" and action == "attack":
                frame_record["weaponTipOffset"] = weapon_tip_offset(image, meta)
            frames.append(frame_record)
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(target)
    return {
        "path": f"res://{target.relative_to(ROOT).as_posix()}",
        "cell": list(cell),
        "footAnchor": list(foot_anchor),
        "directions": 8,
        "framesPerDirection": frame_count,
        "sourceFeature": feature,
        "sourceFrames": frames,
        "missingFrames": missing,
        "libraryImageCount": info["image_count"],
        "confidence": "A",
    }


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")).get("items", [])
    candidates = source_rows()
    target_names = {
        str(item.get("name", "")): item
        for item in catalog
        if item.get("category") in ["武器", "盔甲"] and item.get("profession") in ["通用", "战士"]
        and not (item.get("category") == "盔甲" and "(女)" in str(item.get("name", "")))
    }
    libraries = {
        "weaponAppearance": CLIENT_DATA / "Weapon.wil",
        "dressAppearance": CLIENT_DATA / "Hum.wil",
    }
    decoded = {key: read_library(path) for key, path in libraries.items()}
    max_features = {key: len(value[2]) // 600 for key, value in decoded.items()}
    del decoded

    mappings, rejected = {}, []
    atlas_cache = {}
    for name, item in target_names.items():
        row = candidates.get(name)
        if row is None or not str(row.get("ItemShape", "")).isdigit():
            rejected.append({"name": name, "reason": "候选数据库无同名Shape"})
            continue
        shape = CLASSIC_SHAPE_OVERRIDES.get(name, int(row["ItemShape"]))
        mapping_source = (
            "经典 Weapon.wil 外观表：裁决之杖 Shape 24（覆盖候选CSV Shape 21）"
            if name in CLASSIC_SHAPE_OVERRIDES
            else "angelk727/Mir2ServerDatabases Exports/2_物品数据.csv"
        )
        appearance_type = "weaponAppearance" if item.get("category") == "武器" else "dressAppearance"
        # This task targets the current male warrior; classic server feature = Shape*2 + gender(0).
        feature = shape * 2
        if feature >= max_features[appearance_type]:
            rejected.append({"name": name, "shape": shape, "feature": feature, "reason": "候选Shape超出当前客户端库容量"})
            continue
        if appearance_type == "weaponAppearance" and feature < 2:
            mappings[name] = {
                appearance_type: {
                    "shape": shape,
                    "feature": feature,
                    "visible": False,
                    "actions": {},
                    "mappingConfidence": "B",
                    "mappingSource": mapping_source,
                    "runtimeRule": "经典客户端m_btWeapon<2不绘制武器层",
                }
            }
            continue
        cache_key = (appearance_type, feature)
        if cache_key not in atlas_cache:
            actions = {}
            library = libraries[appearance_type]
            prefix = "weapon" if appearance_type == "weaponAppearance" else "dress"
            for action in ACTIONS:
                target = OUTPUT / prefix / f"{prefix}_{feature:03d}_{action}.png"
                actions[action] = build_action(library, feature, action, target, appearance_type)
            atlas_cache[cache_key] = actions
        mappings[name] = {
            appearance_type: {
                "shape": shape,
                "feature": feature,
                "visible": True,
                "actions": atlas_cache[cache_key],
                "mappingConfidence": "B",
                "mappingSource": mapping_source,
                "clientSource": f"dev_art_sources/reference/mir2_client_raw/Data/{libraries[appearance_type].name}",
            }
        }

    payload = {
        "schemaVersion": 2,
        "target": "当前男性战士",
        "formulaEvidence": {
            "server": "M2Server/ObjBase.pas GetFeature: Shape*2+gender",
            "client": "Client/Actor.pas HUMANFRAME=600 and HA action table",
            "confidence": "A",
        },
        "shapeCandidateSource": {
            "repository": "https://github.com/angelk727/Mir2ServerDatabases",
            "path": "Exports/2_物品数据.csv",
            "confidence": "B",
            "reason": "非2003官服StdItems；仅在名称匹配且客户端容量有效时采用",
        },
        "sourcePolicy": {
            "lane": "client_assets",
            "distributionId": "client.classic_raw_complete",
            "priority": 100,
            "role": "primary",
        },
        "actionLayouts": {
            "dressAppearance": {"cell": list(BODY_CELL), "footAnchor": list(BODY_FOOT_ANCHOR)},
            "weaponAppearance": {"cell": list(WEAPON_CELL), "footAnchor": list(WEAPON_FOOT_ANCHOR)},
            "blockFrames": 600,
            "actions": ACTIONS,
        },
        "runtimeMappings": mappings,
        "rejectedMappings": rejected,
        "generatedAtlases": len(atlas_cache) * len(ACTIONS),
        "policy": "帧公式和客户端像素为A；逐件Shape为B。越界、缺名或不兼容值拒绝运行，不猜测替换。",
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WARRIOR_WEAR_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
