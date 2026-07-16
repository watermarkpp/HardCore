#!/usr/bin/env python3
"""Build runtime NPC idle atlases from the primary classic client's Npc.wil."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/npc.wil"
OUTPUT = ROOT / "assets/art/npcs/classic"
MANIFEST = ROOT / "assets/data/classic_npc_art_sources.json"
ACCEPTANCE = ROOT / "outputs/visual_acceptance/classic_npc_eight_direction_acceptance.png"

DIRECTIONS = ("S", "SW", "W", "NW", "N", "NE", "E", "SE")
# Source: 0=SW/front, 1=S/front, 2=SE/front, 3=NE/back, 4=N/back, 5=NW/back.
LOGICAL_TO_SOURCE_GROUP = (1, 0, 0, 5, 4, 3, 2, 2)
FRAMES = 4
PADDING = 4


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build() -> dict:
    data, palette, offsets, library_info = read_library(SOURCE)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest: dict = {
        "schemaVersion": 1,
        "taskId": "NPC-FACING-1",
        "sourceTier": "primary",
        "sourceLibrary": SOURCE.relative_to(ROOT).as_posix(),
        "sourceLibrarySha256": sha256(SOURCE),
        "sourceRules": "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas",
        "originalRuntimeRule": "TNpcActor used m_btDir mod 3",
        "extensionRule": "activate all six genuine Npc.wil view groups; no generated or mirrored pixels",
        "directionOrder": list(DIRECTIONS),
        "logicalToSourceGroup": list(LOGICAL_TO_SOURCE_GROUP),
        "sourceGroupMeaning": ["SW-front", "S-front", "SE-front", "NE-back", "N-back", "NW-back"],
        "framesPerDirection": FRAMES,
        "appearanceStride": 60,
        "directionStride": 10,
        "libraryInfo": library_info,
        "appearances": {},
    }
    acceptance_rows = []
    for appearance in range(23):
        decoded = []
        for logical_row, source_group in enumerate(LOGICAL_TO_SOURCE_GROUP):
            for frame in range(FRAMES):
                source_index = appearance * 60 + source_group * 10 + frame
                image, metadata = decode_sprite(data, offsets[source_index], palette)
                decoded.append({"logicalRow": logical_row, "direction": DIRECTIONS[logical_row],
                    "sourceGroup": source_group, "frame": frame, "sourceIndex": source_index,
                    "image": image, **metadata})
        min_x = min(int(r["x"]) for r in decoded) - PADDING
        min_y = min(int(r["y"]) for r in decoded) - PADDING
        max_x = max(int(r["x"]) + int(r["width"]) for r in decoded) + PADDING
        max_y = max(int(r["y"]) + int(r["height"]) for r in decoded) + PADDING
        cell = (max_x - min_x, max_y - min_y)
        anchor = (-min_x, -min_y)
        atlas = Image.new("RGBA", (cell[0] * FRAMES, cell[1] * 8), (0, 0, 0, 0))
        provenance = []
        for record in decoded:
            target = (int(record["frame"]) * cell[0] + int(record["x"]) - min_x,
                      int(record["logicalRow"]) * cell[1] + int(record["y"]) - min_y)
            atlas.alpha_composite(record["image"], target)
            provenance.append({key: record[key] for key in ("logicalRow", "direction", "sourceGroup",
                "frame", "sourceIndex", "offset", "width", "height", "x", "y")})
        output = OUTPUT / f"appearance_{appearance:03d}_idle.png"
        atlas.save(output)
        manifest["appearances"][str(appearance)] = {
            "path": "res://" + output.relative_to(ROOT).as_posix(), "frameSize": list(cell),
            "footAnchor": list(anchor), "framesPerDirection": FRAMES, "sourceFrames": provenance,
        }
        if appearance in (0, 8, 10, 11, 14, 15, 22):
            acceptance_rows.append((appearance, atlas.copy(), cell, anchor))
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    build_acceptance(acceptance_rows)
    return manifest


def build_acceptance(rows) -> None:
    cell_w, cell_h, header = 128, 130, 34
    sheet = Image.new("RGBA", (cell_w * 8, header + cell_h * len(rows)), (20, 18, 17, 255))
    draw = ImageDraw.Draw(sheet)
    for direction, name in enumerate(DIRECTIONS):
        draw.text((direction * cell_w + 54, 10), name, fill=(245, 205, 125, 255))
    for row, (appearance, atlas, source_cell, anchor) in enumerate(rows):
        baseline_y = header + row * cell_h + 106
        draw.text((4, header + row * cell_h + 4), f"#{appearance:02d}", fill=(245, 205, 125, 255))
        for direction in range(8):
            crop = atlas.crop((0, direction * source_cell[1], source_cell[0], (direction + 1) * source_cell[1]))
            sheet.alpha_composite(crop, (direction * cell_w + cell_w // 2 - anchor[0], baseline_y - anchor[1]))
    ACCEPTANCE.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(ACCEPTANCE)


if __name__ == "__main__":
    result = build()
    print(f"CLASSIC_NPC_ASSETS_PASS appearances={len(result['appearances'])} directions=8 frames=4")
