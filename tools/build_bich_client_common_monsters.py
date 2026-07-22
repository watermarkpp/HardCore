#!/usr/bin/env python3
"""Extract verified Bich surface/cave monster atlases from the bundled client."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = Path(os.environ.get("MIR2_CLIENT_DATA", ROOT / "dev_art_sources/reference/mir2_client_raw/Data"))
CLIENT_ACTOR = Path(os.environ.get("MIR2_CLIENT_ACTOR", ROOT / "dev_art_sources/reference/original_gameofmir/Client/Actor.pas"))
OUTPUT = ROOT / "assets/art/monsters/client_bich_common"
MANIFEST = ROOT / "assets/data/bich_common_client_art_sources.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


PADDING = 8

# Client/Actor.pas TMonsterAction records.  Direction stride is frame + skip,
# and is action-specific for MA12/MA13 rather than globally fixed at ten.
TABLES = {
    "MA12": {
        "idle": (0, 4, 200, 8),
        "walk": (64, 6, 120, 8),
        "attack": (128, 6, 150, 8),
        "hit": (192, 2, 150, 2),
        "death": (208, 4, 160, 8),
    },
    "MA13": {
        "idle": (0, 4, 200, 10),
        "walk": (10, 8, 160, 10),
        "attack": (30, 6, 120, 10),
        "hit": (110, 2, 100, 2),
        "death": (130, 10, 120, 10),
    },
    "MA14": {
        "idle": (0, 4, 200, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 100, 10),
        "hit": (240, 2, 100, 2),
        "death": (260, 10, 120, 10),
    },
    "MA16": {
        "idle": (0, 4, 200, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 160, 10),
        "hit": (240, 2, 100, 2),
        "death": (260, 4, 160, 10),
    },
    "MA17": {
        "idle": (0, 4, 60, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 100, 10),
        "hit": (240, 2, 100, 2),
        "death": (260, 10, 100, 10),
    },
    "MA19": {
        "idle": (0, 4, 200, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 100, 10),
        "hit": (240, 2, 100, 2),
        "death": (260, 10, 140, 10),
    },
    "MA24": {
        "idle": (0, 4, 200, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 100, 10),
        "hit": (320, 2, 100, 2),
        "death": (340, 10, 140, 10),
    },
}

# Appearance blocks were verified against the bundled WIL pixels, not inferred
# from filenames.  A-grade rows have a version-bound RaceImg binding.  B-grade
# rows use the archived 21cq appearance path plus a complete local WIL block;
# they remain explicitly graded until the matching Paradox Monster.DB is
# exported and its RaceImg field can be reconciled.
MONSTERS = {
    "森林雪人": {"slug": "forest_yeti", "appearance": 1, "raceImg": 12, "actionTable": "MA12", "monsterIds": [28, 29]},
    # The service actor cannot turn or walk. MA13 reuses the adjacent slots for
    # emerge/hide sequences, so interpreting those slots as eight directions
    # produces buried/death poses when the Godot actor faces northeast.
    "食人花": {
        "slug": "cannibal_flower",
        "appearance": 10,
        "raceImg": 13,
        "actionTable": "MA13",
        "monsterIds": [30],
        "fixedSourceDirection": 0,
    },
    "洞蛆": {"slug": "cave_maggot", "appearance": 24, "raceImg": 16, "actionTable": "MA16", "monsterIds": [46]},
    "多钩猫": {"slug": "hook_cat", "appearance": 25, "raceImg": 17, "actionTable": "MA14", "monsterIds": [24, 25]},
    "钉耙猫": {"slug": "rake_cat", "appearance": 26, "raceImg": 17, "actionTable": "MA14", "monsterIds": [26, 27]},
    "稻草人": {"slug": "strawman", "appearance": 27, "raceImg": 18, "actionTable": "MA14", "monsterIds": [21, 23]},
    "半兽人": {"slug": "half_orc", "appearance": 100, "raceImg": 19, "actionTable": "MA19", "monsterIds": [34, 35], "mappingConfidence": "B"},
    "山洞蝙蝠": {"slug": "cave_bat", "appearance": 80, "raceImg": 31, "actionTable": "MA17", "monsterIds": [43, 44]},
    "蝎子": {"slug": "scorpion", "appearance": 83, "raceImg": 32, "actionTable": "MA24", "monsterIds": [45]},
    "毒蜘蛛": {"slug": "spitting_spider", "appearance": 163, "raceImg": 19, "actionTable": "MA14", "monsterIds": [18], "mappingConfidence": "B"},
    "蛤蟆": {"slug": "yob", "appearance": 162, "raceImg": 19, "actionTable": "MA14", "monsterIds": [19]},
    "半兽战士": {"slug": "oma_fighter", "appearance": 101, "raceImg": 17, "actionTable": "MA14", "monsterIds": [36, 37], "mappingConfidence": "B"},
    "半兽勇士": {"slug": "oma_warrior", "appearance": 102, "raceImg": 18, "actionTable": "MA14", "monsterIds": [38, 39, 41], "mappingConfidence": "B"},
    "粪虫": {"slug": "dung", "appearance": 29, "raceImg": 19, "actionTable": "MA19", "monsterIds": [60], "mappingConfidence": "B"},
    "暗黑战士": {"slug": "dark_warrior", "appearance": 28, "raceImg": 19, "actionTable": "MA19", "monsterIds": [62, 63], "mappingConfidence": "B"},
    "沃玛战士": {"slug": "wooma_soldier", "appearance": 30, "raceImg": 19, "actionTable": "MA19", "monsterIds": [64, 65], "mappingConfidence": "B"},
    "沃玛勇士": {"slug": "wooma_fighter", "appearance": 32, "raceImg": 19, "actionTable": "MA19", "monsterIds": [66, 67], "mappingConfidence": "B"},
    "沃玛战将": {"slug": "wooma_warrior", "appearance": 33, "raceImg": 19, "actionTable": "MA19", "monsterIds": [68, 69], "mappingConfidence": "B"},
    "火焰沃玛": {"slug": "flaming_wooma", "appearance": 31, "raceImg": 19, "actionTable": "MA19", "monsterIds": [70, 71], "mappingConfidence": "B"},
    "沃玛卫士": {"slug": "wooma_guardian", "appearance": 151, "raceImg": 19, "actionTable": "MA19", "monsterIds": [73, 74, 75], "mappingConfidence": "B", "legacyAliases": ["沃玛护卫"]},
    "红蛇": {"slug": "red_snake", "appearance": 36, "raceImg": 19, "actionTable": "MA19", "monsterIds": [92, 93], "mappingConfidence": "B"},
    "虎蛇": {"slug": "tiger_snake", "appearance": 38, "raceImg": 19, "actionTable": "MA19", "monsterIds": [94, 95], "mappingConfidence": "B"},
}


def source_location(appearance: int) -> tuple[Path, int, str]:
    """Apply the exact GetOffset group rules used by the bundled client."""
    group, position = divmod(appearance, 10)
    name = f"Mon{group + 1}.wil"
    if group == 0:
        base = position * 280
    elif group == 1:
        base = position * 230
    elif group in {2, 3, 7, 8, 9, 10, 11, 12, 14, 15, 16}:
        base = position * 360
    elif group == 4:
        base = 600 if position == 1 else position * 360
    elif group == 5:
        base = position * 430
    elif group == 6:
        base = position * 440
    else:
        raise ValueError(f"unregistered classic GetOffset group: {group}")
    return CLIENT_DATA / name, base, name


def build_monster(name: str, spec: dict) -> dict:
    library, base, library_name = source_location(int(spec["appearance"]))
    data, palette, offsets, info = read_library(library)
    output_dir = OUTPUT / str(spec["slug"])
    output_dir.mkdir(parents=True, exist_ok=True)
    decoded: dict = {}
    bounds: list[tuple[int, int, int, int]] = []
    idle_top_by_direction: list[int | None] = [None] * 8

    for action_name, (start, frame_count, frame_ms, direction_stride) in TABLES[str(spec["actionTable"])].items():
        action = {
            "frames": {},
            "frame_count": frame_count,
            "frame_ms": frame_ms,
            "start": start,
            "direction_stride": direction_stride,
            "missing": [],
        }
        decoded[action_name] = action
        fixed_source_direction = spec.get("fixedSourceDirection")
        for direction in range(8):
            source_direction = int(fixed_source_direction) if fixed_source_direction is not None else direction
            for frame in range(frame_count):
                index = base + start + source_direction * direction_stride + frame
                if index >= len(offsets):
                    action["missing"].append(index)
                    continue
                try:
                    image, meta = decode_sprite(data, offsets[index], palette)
                except ValueError:
                    action["missing"].append(index)
                    continue
                image = image.convert("RGBA")
                alpha_bounds = image.getchannel("A").getbbox()
                if alpha_bounds is None:
                    action["missing"].append(index)
                    continue
                action["frames"][(direction, frame)] = (image, meta, index)
                bounds.append(
                    (
                        meta["x"] + alpha_bounds[0],
                        meta["y"] + alpha_bounds[1],
                        meta["x"] + alpha_bounds[2],
                        meta["y"] + alpha_bounds[3],
                    )
                )
                if action_name == "idle":
                    source_top = meta["y"] + alpha_bounds[1]
                    previous_top = idle_top_by_direction[direction]
                    idle_top_by_direction[direction] = (
                        source_top if previous_top is None else min(previous_top, source_top)
                    )

    if not bounds:
        raise ValueError("monster contains no drawable frames")
    min_x = min(row[0] for row in bounds)
    min_y = min(row[1] for row in bounds)
    max_x = max(row[2] for row in bounds)
    max_y = max(row[3] for row in bounds)
    cell_w = ((max_x - min_x + PADDING * 2 + 15) // 16) * 16
    cell_h = ((max_y - min_y + PADDING * 2 + 15) // 16) * 16
    foot = (-min_x + PADDING, -min_y + PADDING)
    if any(value is None for value in idle_top_by_direction):
        raise ValueError("monster contains a direction without an idle-pose top")
    health_bar_top_by_direction = [
        foot[1] + int(value) for value in idle_top_by_direction
    ]

    actions = {}
    for action_name, action in decoded.items():
        frame_count = int(action["frame_count"])
        atlas = Image.new("RGBA", (cell_w * frame_count, cell_h * 8), (0, 0, 0, 0))
        frames = []
        for (direction, frame), (image, meta, index) in action["frames"].items():
            isolated = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
            isolated.alpha_composite(image, (foot[0] + meta["x"], foot[1] + meta["y"]))
            atlas.alpha_composite(isolated, (frame * cell_w, direction * cell_h))
            frames.append(
                {
                    "index": index,
                    "direction": direction,
                    "frame": frame,
                    "drawOffset": [meta["x"], meta["y"]],
                }
            )
        target = output_dir / f"{spec['slug']}_{action_name}.png"
        atlas.save(target)
        action_record = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": frame_count,
            "frameMs": int(action["frame_ms"]),
            "sourceStart": base + int(action["start"]),
            "sourceDirectionStride": 0 if spec.get("fixedSourceDirection") is not None else int(action["direction_stride"]),
            "sourceFrames": sorted(frames, key=lambda row: (row["direction"], row["frame"])),
            "missingFrames": action["missing"],
            "confidence": "A",
        }
        if spec.get("fixedSourceDirection") is not None:
            action_record["fixedSourceDirection"] = int(spec["fixedSourceDirection"])
        actions[action_name] = action_record

    mapping_confidence = str(spec.get("mappingConfidence", "A"))
    record = {
        "name": name,
        "monsterIds": spec["monsterIds"],
        "appearance": spec["appearance"],
        "raceImg": spec["raceImg"],
        "actionTable": spec["actionTable"],
        "mappingConfidence": mapping_confidence,
        "mappingSource": (
            "bundled client WIL pixels + Client/Actor.pas aGetMonImg/GetOffset/TMonsterAction"
            if mapping_confidence == "A"
            else "21cq monster-page appearance path + bundled client WIL pixels + Client/Actor.pas standard action layout"
        ),
        "appearanceSource": f"https://www.21cq.com/files/monsters/{spec['appearance']}.gif" if mapping_confidence == "B" else "version-bound client/server evidence",
        "bindingNote": "RaceImg/action table remains B until the matching Paradox Monster.DB is exported" if mapping_confidence == "B" else "version-bound RaceImg/action table",
        "legacyAliases": spec.get("legacyAliases", []),
        "clientLibrary": f"dev_art_sources/reference/mir2_client_raw/Data/{library_name}",
        "clientLibraryImageCount": info["image_count"],
        "blockBase": base,
        "frameSize": [cell_w, cell_h],
        "footAnchor": [foot[0], foot[1]],
        "contentBounds": [min_x, min_y, max_x, max_y],
        "contentPadding": PADDING,
        "atlasCellIsolation": "per_frame",
        "healthBarTopByDirection": health_bar_top_by_direction,
        "directions": 8,
        "actions": actions,
    }
    if spec.get("fixedSourceDirection") is not None:
        record["directionPolicy"] = "fixed_source_direction"
    return record


def main() -> None:
    if not CLIENT_ACTOR.exists():
        raise FileNotFoundError(CLIENT_ACTOR)
    mappings, rejected = {}, []
    for name, spec in MONSTERS.items():
        try:
            record = build_monster(name, spec)
        except (FileNotFoundError, ValueError, IndexError) as exc:
            rejected.append({"name": name, "appearance": spec["appearance"], "error": str(exc)})
            continue
        missing = sum(len(action["missingFrames"]) for action in record["actions"].values())
        if missing:
            rejected.append({"name": name, "appearance": spec["appearance"], "error": f"client action missing {missing} frames"})
            continue
        mappings[name] = record

    by_id = {
        str(monster_id): record["name"]
        for record in mappings.values()
        for monster_id in record["monsterIds"]
    }
    aliases = {
        alias: name
        for name, record in mappings.items()
        for alias in record.get("legacyAliases", [])
    }
    payload = {
        "schemaVersion": 2,
        "baseline": "2003 official 1.76 client, bundled local copy",
        "excludedByProjectDecision": ["鸡", "鹿", "羊"],
        "clientFormulaEvidence": {
            "library": "dev_art_sources/reference/original_gameofmir/Client/Actor.pas aGetMonImg",
            "offset": "dev_art_sources/reference/original_gameofmir/Client/Actor.pas GetOffset",
            "actions": "dev_art_sources/reference/original_gameofmir/Client/Actor.pas MA12/MA13/MA14/MA16/MA17/MA19/MA24",
            "confidence": "A",
        },
        "mappingPolicy": "Every mapping is verified against local WIL pixels and the version-bound client frame table; missing frames reject the mapping.",
        "identityKey": "monsterId",
        "compatibilityKey": "runtimeMappings/legacyAliases",
        "runtimeMappingsByMonsterId": by_id,
        "runtimeMappings": mappings,
        "legacyAliases": aliases,
        "rejectedMappings": rejected,
        "generatedAtlases": len(mappings) * 5,
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BICH_COMMON_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
