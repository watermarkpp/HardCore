#!/usr/bin/env python3
"""Extract classic client skeleton/zombie/corpse-king five-action atlases."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
OUTPUT = ROOT / "assets/art/monsters/client_undead"
MANIFEST = ROOT / "assets/data/bich_undead_client_art_sources.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


CELL = (160, 160)
FOOT = (80, 138)
ACTIONS = {
    "idle": {"start": 0, "frames": 4, "frameMs": 200},
    "walk": {"start": 80, "frames": 6, "frameMs": 160},
    "attack": {"start": 160, "frames": 6, "frameMs": 110},
    "hit": {"start": 240, "frames": 2, "frameMs": 120},
    "death": {"start": 260, "frames": 10, "frameMs": 140},
}

# Appearance values come from each existing 21cq monster source page image path.
# RaceImg/action table choices are classic candidates; all selected tables share
# these exact frame ranges, while table-specific timing remains recorded below.
MONSTERS = {
    "骷髅": {"slug": "skeleton", "appearance": 20, "raceImg": 14, "actionTable": "MA14"},
    "掷斧骷髅": {"slug": "axe_skeleton", "appearance": 21, "raceImg": 15, "actionTable": "MA15"},
    "骷髅战士": {"slug": "skeleton_fighter", "appearance": 22, "raceImg": 14, "actionTable": "MA14"},
    "骷髅战将": {"slug": "skeleton_warrior", "appearance": 23, "raceImg": 14, "actionTable": "MA14"},
    "僵尸1": {"slug": "shaman_zombie", "appearance": 40, "raceImg": 40, "actionTable": "MA19"},
    "僵尸2": {"slug": "digout_zombie", "appearance": 50, "raceImg": 41, "actionTable": "MA20"},
    "僵尸3": {"slug": "cl_zombie", "appearance": 51, "raceImg": 42, "actionTable": "MA20"},
    "僵尸4": {"slug": "nd_zombie", "appearance": 52, "raceImg": 42, "actionTable": "MA20"},
    "僵尸5": {"slug": "crawler_zombie", "appearance": 53, "raceImg": 42, "actionTable": "MA20"},
    "骷髅精灵": {"slug": "skeleton_spirit", "appearance": 150, "raceImg": 14, "actionTable": "MA14"},
    "尸王": {"slug": "corpse_king", "appearance": 152, "raceImg": 42, "actionTable": "MA20"},
}


def source_location(appearance: int) -> tuple[Path, int, str]:
    group, position = divmod(appearance, 10)
    library = CLIENT_DATA / f"Mon{group + 1}.wil"
    if group in {2, 3, 7, 8, 9, 10, 11, 12, 14, 15, 16}:
        base = position * 360
    elif group == 4:
        base = 600 if position == 1 else position * 360
    elif group == 5:
        base = position * 430
    else:
        raise ValueError(f"本任务未登记appearance分组：{appearance}")
    return library, base, f"Mon{group + 1}.wil"


def build_monster(name: str, spec: dict) -> dict:
    library, base, library_name = source_location(int(spec["appearance"]))
    data, palette, offsets, info = read_library(library)
    output_dir = OUTPUT / str(spec["slug"])
    output_dir.mkdir(parents=True, exist_ok=True)
    actions = {}
    for action_name, action_spec in ACTIONS.items():
        frame_count = int(action_spec["frames"])
        atlas = Image.new("RGBA", (CELL[0] * frame_count, CELL[1] * 8), (0, 0, 0, 0))
        frames, missing = [], []
        for direction in range(8):
            for frame in range(frame_count):
                index = base + int(action_spec["start"]) + direction * 10 + frame
                if index >= len(offsets):
                    missing.append(index)
                    continue
                try:
                    image, meta = decode_sprite(data, offsets[index], palette)
                except ValueError:
                    missing.append(index)
                    continue
                paste = (frame * CELL[0] + FOOT[0] + meta["x"], direction * CELL[1] + FOOT[1] + meta["y"])
                atlas.alpha_composite(image.convert("RGBA"), paste)
                frames.append({"index": index, "direction": direction, "frame": frame, "drawOffset": [meta["x"], meta["y"]]})
        target = output_dir / f"{spec['slug']}_{action_name}.png"
        atlas.save(target)
        actions[action_name] = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": frame_count,
            "frameMs": int(action_spec["frameMs"]),
            "sourceStart": base + int(action_spec["start"]),
            "sourceFrames": frames,
            "missingFrames": missing,
            "confidence": "A",
        }
    return {
        "name": name,
        "appearance": spec["appearance"],
        "raceImg": spec["raceImg"],
        "actionTable": spec["actionTable"],
        "mappingConfidence": "B",
        "appearanceSource": f"https://www.21cq.com/files/monsters/{spec['appearance']}.gif",
        "clientLibrary": f"dev_art_sources/reference/mir2_client_raw/Data/{library_name}",
        "clientLibraryImageCount": info["image_count"],
        "blockBase": base,
        "frameSize": list(CELL),
        "footAnchor": list(FOOT),
        "directions": 8,
        "actions": actions,
    }


def main() -> None:
    mappings, rejected = {}, []
    for name, spec in MONSTERS.items():
        try:
            record = build_monster(name, spec)
        except (FileNotFoundError, ValueError, IndexError) as exc:
            rejected.append({"name": name, "appearance": spec["appearance"], "error": str(exc)})
            continue
        missing = sum(len(action["missingFrames"]) for action in record["actions"].values())
        if missing:
            rejected.append({"name": name, "appearance": spec["appearance"], "error": f"客户端动作缺帧{missing}"})
            continue
        mappings[name] = record
    payload = {
        "schemaVersion": 1,
        "baseline": "2003官服1.76基准优先",
        "clientFormulaEvidence": {
            "library": "Client/Actor.pas aGetMonImg: appearance div 10 selects MonN",
            "offset": "Client/Actor.pas GetOffset",
            "actions": "Client/Actor.pas MA14/MA15/MA19/MA20",
            "confidence": "A",
        },
        "mappingPolicy": "客户端库、偏移、帧和像素为A；名称到Appearance/RaceImg为B候选。缺帧条目拒绝运行，不用其他怪物冒充。",
        "runtimeMappings": mappings,
        "rejectedMappings": rejected,
        "generatedAtlases": len(mappings) * len(ACTIONS),
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BICH_UNDEAD_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
