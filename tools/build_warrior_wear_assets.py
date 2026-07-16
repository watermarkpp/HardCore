#!/usr/bin/env python3
"""Build classic human Hum/Weapon atlases from pinned StdItems Shape values."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
STD_ITEMS = ROOT / "assets/data/equipment_stditems_176.json"
CATALOG = ROOT / "assets/data/vanilla_176/items.json"
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
WEAPON_CELL = (224, 240)
WEAPON_FOOT_ANCHOR = (80, 120)
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
GENDER_BITS = {"男": 0, "女": 1}


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
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")).get("records", [])
    source = json.loads(STD_ITEMS.read_text(encoding="utf-8"))
    candidates = {str(row.get("Name", "")): row for row in source.get("records", [])}
    target_names = {
        str(item.get("name", "")): item
        for item in catalog
        if item.get("category") in ["武器", "盔甲"]
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
        if row is None:
            rejected.append({"name": name, "reason": "锁定1.76 StdItems.DB无同名记录"})
            continue
        shape = int(row["Shape"])
        std_mode = int(row["Stdmode"])
        mapping_source = "community.mylgd.mir2server.176 StdItems.DB@3952c536"
        appearance_type = "weaponAppearance" if item.get("category") == "武器" else "dressAppearance"
        if appearance_type == "weaponAppearance":
            genders = ["男", "女"]
        elif std_mode == 10:
            genders = ["男"]
        elif std_mode == 11:
            genders = ["女"]
        else:
            rejected.append({"name": name, "stdMode": std_mode, "shape": shape, "reason": "盔甲StdMode不是10/11，拒绝猜测性别"})
            continue
        variants = {}
        invalid = []
        for gender in genders:
            feature = shape * 2 + GENDER_BITS[gender]
            if feature >= max_features[appearance_type]:
                invalid.append({"gender": gender, "feature": feature, "reason": "Shape超出当前客户端库容量"})
                continue
            if appearance_type == "weaponAppearance" and feature < 2:
                variants[gender] = {
                    "feature": feature, "visible": False, "actions": {},
                    "runtimeRule": "经典客户端m_btWeapon<2不绘制武器层",
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
            variants[gender] = {
                "feature": feature,
                "visible": True,
                "actions": atlas_cache[cache_key],
            }
        if invalid:
            rejected.append({"name": name, "stdMode": std_mode, "shape": shape, "variants": invalid, "reason": "一个或多个性别变体无法映射"})
        if not variants:
            continue
        mappings[name] = {
            appearance_type: {
                "shape": shape,
                "stdMode": std_mode,
                "genderVariants": variants,
                "mappingConfidence": "A",
                "mappingSource": mapping_source,
                "clientSource": f"dev_art_sources/reference/mir2_client_raw/Data/{libraries[appearance_type].name}",
            }
        }

    default_variants = {}
    for gender, bit in GENDER_BITS.items():
        cache_key = ("dressAppearance", bit)
        if cache_key not in atlas_cache:
            actions = {}
            for action in ACTIONS:
                target = OUTPUT / "dress" / f"dress_{bit:03d}_{action}.png"
                actions[action] = build_action(libraries["dressAppearance"], bit, action, target, "dressAppearance")
            atlas_cache[cache_key] = actions
        default_variants[gender] = {"feature": bit, "visible": True, "actions": atlas_cache[cache_key]}

    payload = {
        "schemaVersion": 3,
        "target": "战士/法师/道士男女经典动态穿戴",
        "formulaEvidence": {
            "server": "M2Server/ObjBase.pas GetFeature: Shape*2+gender",
            "client": "Client/Actor.pas HUMANFRAME=600 and HA action table",
            "confidence": "A",
        },
        "shapeSource": {
            "distributionId": source.get("distributionId", ""),
            "repository": source.get("source", {}).get("repository", ""),
            "commit": source.get("source", {}).get("commit", ""),
            "path": source.get("source", {}).get("path", ""),
            "sha256": source.get("source", {}).get("sha256", ""),
            "confidence": source.get("confidence", {}),
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
        "defaultHumanAppearance": {
            "shape": 0,
            "stdMode": 10,
            "genderVariants": default_variants,
        },
        "rejectedMappings": rejected,
        "generatedAtlases": len(atlas_cache) * len(ACTIONS),
        "coverage": {"professions": ["战士", "法师", "道士"], "genders": ["男", "女"]},
        "policy": "帧公式、客户端像素及锁定发行版逐件Shape为A；对官服等价性保持B。越界、缺名或不兼容值拒绝运行，不猜测替换。",
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WARRIOR_WEAR_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
