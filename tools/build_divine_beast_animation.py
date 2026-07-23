#!/usr/bin/env python3
"""Build the transformed divine beast's complete MA29 action set from Mon18.wil."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Mon18.wil"
OUTPUT_DIR = ROOT / "assets/art/characters/taoist/effects/divine_beast"
MANIFEST_PATH = ROOT / "assets/data/vanilla_176/divine_beast_animation.json"
SOURCE_CODE = ROOT / "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas"
BLOCK_BASE = 350
PADDING = 4
ACTOR_GROUND_OFFSET = (32, 28)

# Actor.pas MA29, used by race 55 TWarriorElfMonster after the divine beast
# changes from its initial race-54 appearance. Values are relative to the
# appearance-171 Mon18 block base (GetOffset(171) = 350).
ACTIONS = {
    "idle": {"start": 80, "frames": 4, "skip": 6, "frame_ms": 200},
    "walk": {"start": 160, "frames": 6, "skip": 4, "frame_ms": 160},
    "attack": {"start": 240, "frames": 6, "skip": 4, "frame_ms": 100},
    "hit": {"start": 320, "frames": 2, "skip": 0, "frame_ms": 100},
    "death": {"start": 340, "frames": 10, "skip": 0, "frame_ms": 120},
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build() -> None:
    data, palette, offsets, library_info = read_library(SOURCE)
    decoded: dict[str, dict] = {}
    bounds: list[tuple[int, int, int, int]] = []
    for action_name, spec in ACTIONS.items():
        stride = int(spec["frames"]) + int(spec["skip"])
        frames: dict[tuple[int, int], tuple[Image.Image, dict, int]] = {}
        for direction in range(8):
            for frame in range(int(spec["frames"])):
                index = BLOCK_BASE + int(spec["start"]) + direction * stride + frame
                image, meta = decode_sprite(data, offsets[index], palette)
                image = image.convert("RGBA")
                alpha_bounds = image.getchannel("A").getbbox()
                if alpha_bounds is None:
                    raise RuntimeError(f"{action_name} direction={direction} frame={frame} index={index} is empty")
                frames[(direction, frame)] = (image, meta, index)
                bounds.append(
                    (
                        int(meta["x"]) + alpha_bounds[0],
                        int(meta["y"]) + alpha_bounds[1],
                        int(meta["x"]) + alpha_bounds[2],
                        int(meta["y"]) + alpha_bounds[3],
                    )
                )
        decoded[action_name] = {"frames": frames, "stride": stride}

    min_x = min(0, min(row[0] for row in bounds))
    min_y = min(0, min(row[1] for row in bounds))
    max_x = max(0, max(row[2] for row in bounds))
    max_y = max(0, max(row[3] for row in bounds))
    cell_width = ((max_x - min_x + PADDING * 2 + 15) // 16) * 16
    cell_height = ((max_y - min_y + PADDING * 2 + 15) // 16) * 16
    foot_anchor = (-min_x + PADDING, -min_y + PADDING)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    action_records: dict[str, dict] = {}
    for action_name, spec in ACTIONS.items():
        frame_count = int(spec["frames"])
        atlas = Image.new("RGBA", (cell_width * frame_count, cell_height * 8), (0, 0, 0, 0))
        source_frames = []
        for (direction, frame), (image, meta, index) in decoded[action_name]["frames"].items():
            isolated = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
            isolated.alpha_composite(
                image,
                (foot_anchor[0] + int(meta["x"]), foot_anchor[1] + int(meta["y"])),
            )
            atlas.alpha_composite(isolated, (frame * cell_width, direction * cell_height))
            source_frames.append(
                {
                    "index": index,
                    "direction": direction,
                    "frame": frame,
                    "drawOffset": [int(meta["x"]), int(meta["y"])],
                }
            )
        target = OUTPUT_DIR / f"divine_beast_{action_name}.png"
        atlas.save(target, optimize=True, compress_level=9)
        action_records[action_name] = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": frame_count,
            "frameMs": int(spec["frame_ms"]),
            "sourceStart": BLOCK_BASE + int(spec["start"]),
            "sourceDirectionStride": int(decoded[action_name]["stride"]),
            "validatedSourceFrameCount": frame_count * 8,
            "missingFrames": [],
            "sourceFrames": sorted(source_frames, key=lambda row: (row["direction"], row["frame"])),
            "confidence": "A",
        }

    payload = {
        "schemaVersion": 1,
        "contract_id": "summon.visual.divine_beast.directional.v1",
        "skill_id": "taoist.summon_divine_beast",
        "summon_id": "divine_beast",
        "appearance": 171,
        "race": 55,
        "actionTable": "MA29",
        "directionMode": "mir2_north_first",
        "frameSize": [cell_width, cell_height],
        "footAnchor": [foot_anchor[0], foot_anchor[1]],
        "actorGroundOffset": list(ACTOR_GROUND_OFFSET),
        "clientLibrary": "dev_art_sources/reference/mir2_client_raw/Data/Mon18.wil",
        "clientLibrarySha256": sha256(SOURCE),
        "clientLibraryImageCount": int(library_info["image_count"]),
        "blockBase": BLOCK_BASE,
        "mappingSource": "MirClient/Actor.pas GetOffset(171)=350 + race 55 MA29; AxeMon.pas TWarriorElfMonster",
        "mappingSourceSha256": sha256(SOURCE_CODE),
        "pixelConfidence": "A",
        "mappingConfidence": "A",
        "actions": action_records,
    }
    MANIFEST_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "DIVINE_BEAST_ANIMATION_BUILT "
        f"contract={payload['contract_id']} frame={cell_width}x{cell_height} "
        f"frames={sum(int(spec['frames']) * 8 for spec in ACTIONS.values())}"
    )


if __name__ == "__main__":
    build()
