#!/usr/bin/env python3
"""Extract verified Bich surface/cave monster atlases from the bundled client."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
CLIENT_ACTOR = ROOT / "dev_art_sources/reference/original_gameofmir/Client/Actor.pas"
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
# from filenames.  In particular, the five formerly provisional monsters are
# Mon1 position 1, Mon2 position 0, Mon3 positions 6/7, and Mon4 position 0.
MONSTERS = {
    "森林雪人": {"slug": "forest_yeti", "appearance": 1, "raceImg": 12, "actionTable": "MA12"},
    "食人花": {"slug": "cannibal_flower", "appearance": 10, "raceImg": 13, "actionTable": "MA13"},
    "洞蛆": {"slug": "cave_maggot", "appearance": 24, "raceImg": 16, "actionTable": "MA16"},
    "多钩猫": {"slug": "hook_cat", "appearance": 25, "raceImg": 17, "actionTable": "MA14"},
    "钉耙猫": {"slug": "rake_cat", "appearance": 26, "raceImg": 17, "actionTable": "MA14"},
    "稻草人": {"slug": "strawman", "appearance": 27, "raceImg": 18, "actionTable": "MA14"},
    "半兽人": {"slug": "half_orc", "appearance": 30, "raceImg": 19, "actionTable": "MA19"},
    "山洞蝙蝠": {"slug": "cave_bat", "appearance": 80, "raceImg": 31, "actionTable": "MA17"},
    "蝎子": {"slug": "scorpion", "appearance": 83, "raceImg": 32, "actionTable": "MA24"},
    "毒蜘蛛": {"slug": "spitting_spider", "appearance": 114, "raceImg": 19, "actionTable": "MA14"},
    "蛤蟆": {"slug": "yob", "appearance": 162, "raceImg": 19, "actionTable": "MA14"},
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
        for direction in range(8):
            for frame in range(frame_count):
                index = base + start + direction * direction_stride + frame
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

    if not bounds:
        raise ValueError("monster contains no drawable frames")
    min_x = min(row[0] for row in bounds)
    min_y = min(row[1] for row in bounds)
    max_x = max(row[2] for row in bounds)
    max_y = max(row[3] for row in bounds)
    cell_w = ((max_x - min_x + PADDING * 2 + 15) // 16) * 16
    cell_h = ((max_y - min_y + PADDING * 2 + 15) // 16) * 16
    foot = (-min_x + PADDING, -min_y + PADDING)

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
        actions[action_name] = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": frame_count,
            "frameMs": int(action["frame_ms"]),
            "sourceStart": base + int(action["start"]),
            "sourceDirectionStride": int(action["direction_stride"]),
            "sourceFrames": sorted(frames, key=lambda row: (row["direction"], row["frame"])),
            "missingFrames": action["missing"],
            "confidence": "A",
        }

    return {
        "name": name,
        "appearance": spec["appearance"],
        "raceImg": spec["raceImg"],
        "actionTable": spec["actionTable"],
        "mappingConfidence": "A",
        "mappingSource": "bundled client WIL pixels + Client/Actor.pas aGetMonImg/GetOffset/TMonsterAction",
        "clientLibrary": f"dev_art_sources/reference/mir2_client_raw/Data/{library_name}",
        "clientLibraryImageCount": info["image_count"],
        "blockBase": base,
        "frameSize": [cell_w, cell_h],
        "footAnchor": [foot[0], foot[1]],
        "directions": 8,
        "actions": actions,
    }


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
        "runtimeMappings": mappings,
        "rejectedMappings": rejected,
        "generatedAtlases": len(mappings) * 5,
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BICH_COMMON_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
