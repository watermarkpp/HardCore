#!/usr/bin/env python3
"""Probe every head-layer library with its actual per-appearance stride.

The 2013 client package mixes several human animation layouts.  A universal
600-frame cut is incorrect for these files and causes neighbouring appearances
to leak into one another.  The common and killer strides are proven by the
matching PlayerObject.cs.  Other class strides are derived from the exact
``10 * stride + small trailer`` structure shared by their Hair/HumUp pairs and
are marked as inferred rather than source-proven.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT_DIR = ROOT / "outputs/visual_acceptance/headwear_cross_category_probe_v2"
FRONT_DIRECTION = 4
FRAMES_PER_DIRECTION = 8
IDLE_FRAME = 0
TILE = (144, 128)
COLUMNS = 5

# Normal human: AOffSet=2224; assassin/killer: AOffSet=1456.  See the matching
# 2013 PlayerObject.cs copied under dev_art_sources/reference.
LAYOUTS = {
    "Hair.wil": {"stride": 2224, "confidence": "source-proven", "family": "common"},
    "Hair_Common.wil": {"stride": 2224, "confidence": "structure-inferred", "family": "common"},
    "Hair_Killer.wil": {"stride": 1456, "confidence": "source-proven", "family": "killer"},
    "Hair_Assassin.wil": {"stride": 1824, "confidence": "structure-inferred", "family": "assassin"},
    "Hair_Monk.wil": {"stride": 1440, "confidence": "structure-inferred", "family": "monk"},
    "Hair_Warrior.wil": {"stride": 1568, "confidence": "structure-inferred", "family": "warrior"},
    "Hair_Wizard.wil": {"stride": 1440, "confidence": "structure-inferred", "family": "wizard"},
    # Helmet is not referenced by the paired runtime.  Its 3600 images form six
    # exact 600-frame blocks, so this remains a structural candidate only.
    "Helmet.wil": {"stride": 600, "confidence": "structure-only", "family": "unmapped-helmet"},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def render_sheet(path: Path, layout: dict) -> tuple[dict, list[dict]]:
    data, palette, offsets, info = read_library(path)
    stride = int(layout["stride"])
    appearance_count = len(offsets) // stride
    records: list[dict] = []
    sheet_rows = (appearance_count + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * TILE[0], 28 + sheet_rows * TILE[1]), (14, 15, 18, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text(
        (6, 7),
        f"{path.name}: stride={stride}, confidence={layout['confidence']}",
        fill=(235, 235, 235, 255),
    )
    for appearance in range(appearance_count):
        index = appearance * stride + FRONT_DIRECTION * FRAMES_PER_DIRECTION + IDLE_FRAME
        column = appearance % COLUMNS
        row = appearance // COLUMNS
        tile_x = column * TILE[0]
        tile_y = 28 + row * TILE[1]
        record = {"appearance": appearance, "index": index}
        try:
            image, meta = decode_sprite(data, offsets[index], palette)
        except (IndexError, ValueError) as error:
            record["error"] = str(error)
            records.append(record)
            continue
        rgba = image.convert("RGBA")
        scale = min(6, max(1, min((TILE[0] - 12) // max(1, rgba.width), (TILE[1] - 32) // max(1, rgba.height))))
        enlarged = rgba.resize((rgba.width * scale, rgba.height * scale), Image.Resampling.NEAREST)
        paste = (
            tile_x + (TILE[0] - enlarged.width) // 2,
            tile_y + 22 + (TILE[1] - 30 - enlarged.height) // 2,
        )
        sheet.alpha_composite(enlarged, paste)
        draw.text((tile_x + 4, tile_y + 3), f"LOOK {appearance:02d} / I{index}", fill=(255, 218, 84, 255))
        draw.text(
            (tile_x + 4, tile_y + TILE[1] - 17),
            f"{rgba.width}x{rgba.height} @ {meta['x']},{meta['y']}",
            fill=(185, 195, 208, 255),
        )
        record.update({"size": [rgba.width, rgba.height], "drawOffset": [int(meta["x"]), int(meta["y"])]})
        records.append(record)
    target = OUTPUT_DIR / f"{path.stem}_correct_stride_front.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return (
        {
            "library": f"res://{path.relative_to(ROOT).as_posix()}",
            "imageCount": int(info["image_count"]),
            "appearanceStride": stride,
            "appearanceCount": appearance_count,
            "trailingFrames": len(offsets) % stride,
            "confidence": layout["confidence"],
            "family": layout["family"],
            "frontContactSheet": f"res://{target.relative_to(ROOT).as_posix()}",
            "records": records,
        },
        records,
    )


def main() -> None:
    missing = [name for name in LAYOUTS if not (SOURCE_DIR / name).exists()]
    if missing:
        raise FileNotFoundError(f"Missing head-layer libraries: {missing}")
    libraries = []
    for name, layout in LAYOUTS.items():
        entry, _records = render_sheet(SOURCE_DIR / name, layout)
        libraries.append(entry)
    payload = {
        "schemaVersion": 2,
        "policy": "Never infer an appearance from item category or a universal stride.",
        "sourceEvidence": {
            "playerObject": "res://dev_art_sources/reference/mir2opensource_2013_client/MirObjects/PlayerObject.cs",
            "humanFrames": "res://dev_art_sources/reference/mir2opensource_2013_client/MirObjects/Frames.cs",
            "commonStride": "AOffSet=2224",
            "killerStride": "AOffSet=1456",
            "headFormula": "ImageIndex + appearance*stride + male/female offset",
        },
        "frontDirection": FRONT_DIRECTION,
        "libraries": libraries,
    }
    manifest = OUTPUT_DIR / "manifest.json"
    manifest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"HEADWEAR_CORRECT_STRIDE_PROBE_PASS libraries={len(libraries)}")


if __name__ == "__main__":
    main()
