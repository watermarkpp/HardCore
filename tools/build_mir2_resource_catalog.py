#!/usr/bin/env python3
"""Build a structural and visual catalog for every WIL/WIX client library.

Legacy MIR2 item categories are not reliable visual-library boundaries.  This
tool therefore indexes every library, then probes every complete 600-frame
block at the same front-idle position used by human overlay libraries.  The
result is evidence for later mappings, not a mapping inferred from filenames.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT_DIR = ROOT / "outputs/resource_catalog/mir2_client_data"
BLOCK_FRAMES = 600
FRONT_DIRECTION = 4
FRAMES_PER_DIRECTION = 8
PROBE_INDEX_IN_BLOCK = FRONT_DIRECTION * FRAMES_PER_DIRECTION
SHEET_COLUMNS = 8
SHEET_CELL = (128, 112)

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def is_head_overlay(width: int, height: int, x: int, y: int) -> bool:
    """Broad geometry filter; intentionally independent of library names."""
    return 6 <= width <= 48 and 6 <= height <= 48 and -20 <= x <= 45 and -90 <= y <= -24


def opaque_stats(image: Image.Image) -> dict:
    rgba = image.convert("RGBA")
    pixels = [pixel for pixel in rgba.getdata() if pixel[3] > 0]
    if not pixels:
        return {"opaquePixels": 0, "darkRatio": 0.0, "neutralMetalRatio": 0.0}
    dark = sum(1 for r, g, b, _a in pixels if max(r, g, b) <= 105)
    neutral = sum(
        1
        for r, g, b, _a in pixels
        if 45 <= max(r, g, b) <= 205 and max(r, g, b) - min(r, g, b) <= 32
    )
    count = len(pixels)
    return {
        "opaquePixels": count,
        "darkRatio": round(dark / count, 4),
        "neutralMetalRatio": round(neutral / count, 4),
    }


def draw_contact_sheet(records: list[dict], output: Path, title: str) -> None:
    if not records:
        return
    rows = (len(records) + SHEET_COLUMNS - 1) // SHEET_COLUMNS
    sheet = Image.new(
        "RGBA",
        (SHEET_COLUMNS * SHEET_CELL[0], 28 + rows * SHEET_CELL[1]),
        (15, 16, 19, 255),
    )
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 7), title, fill=(235, 235, 235, 255))
    for position, record in enumerate(records):
        image = record.pop("_image")
        column = position % SHEET_COLUMNS
        row = position // SHEET_COLUMNS
        x0 = column * SHEET_CELL[0]
        y0 = 28 + row * SHEET_CELL[1]
        scale = min(
            5,
            max(
                1,
                min(
                    (SHEET_CELL[0] - 12) // max(1, image.width),
                    (SHEET_CELL[1] - 30) // max(1, image.height),
                ),
            ),
        )
        enlarged = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
        px = x0 + (SHEET_CELL[0] - enlarged.width) // 2
        py = y0 + 20 + (SHEET_CELL[1] - 26 - enlarged.height) // 2
        sheet.alpha_composite(enlarged, (px, py))
        label = f"{record['library']} F{record['feature']:03d}"
        draw.text((x0 + 4, y0 + 3), label[:20], fill=(255, 218, 92, 255))
        draw.text(
            (x0 + 4, y0 + SHEET_CELL[1] - 17),
            f"{record['size'][0]}x{record['size'][1]} @ {record['drawOffset'][0]},{record['drawOffset'][1]}",
            fill=(190, 198, 208, 255),
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def scan_library(path: Path) -> tuple[dict, list[dict]]:
    stat = path.stat()
    entry = {
        "library": path.name,
        "source": f"res://{path.relative_to(ROOT).as_posix()}",
        "wilBytes": stat.st_size,
        "wixPresent": path.with_suffix(".WIX").exists() or path.with_suffix(".wix").exists(),
    }
    probes: list[dict] = []
    try:
        data, palette, offsets, info = read_library(path)
    except Exception as error:  # keep the full inventory even for unsupported libraries
        entry["error"] = str(error)
        return entry, probes

    image_count = int(info["image_count"])
    block_count = image_count // BLOCK_FRAMES
    entry.update(
        {
            "imageCount": image_count,
            "wilVersion": int(info["version"]),
            "complete600FrameBlocks": block_count,
            "remainderFrames": image_count % BLOCK_FRAMES,
        }
    )
    for feature in range(block_count):
        index = feature * BLOCK_FRAMES + PROBE_INDEX_IN_BLOCK
        try:
            image, meta = decode_sprite(data, offsets[index], palette)
        except Exception as error:
            probes.append(
                {
                    "library": path.name,
                    "feature": feature,
                    "index": index,
                    "error": str(error),
                    "headGeometryCandidate": False,
                }
            )
            continue
        width, height = image.size
        record = {
            "library": path.name,
            "feature": feature,
            "index": index,
            "size": [width, height],
            "drawOffset": [int(meta["x"]), int(meta["y"])],
            "headGeometryCandidate": is_head_overlay(width, height, int(meta["x"]), int(meta["y"])),
            **opaque_stats(image),
            "_image": image.convert("RGBA"),
        }
        probes.append(record)
    return entry, probes


def main() -> None:
    paths = sorted(DATA_DIR.glob("*.wil"), key=lambda path: path.name.casefold())
    if not paths:
        raise FileNotFoundError(f"No WIL libraries found under {DATA_DIR}")

    libraries: list[dict] = []
    all_probes: list[dict] = []
    for path in paths:
        entry, probes = scan_library(path)
        libraries.append(entry)
        all_probes.extend(probes)

    head_candidates = [record for record in all_probes if record.get("headGeometryCandidate")]
    head_candidates.sort(
        key=lambda record: (
            -(record.get("darkRatio", 0.0) + record.get("neutralMetalRatio", 0.0)),
            record["library"].casefold(),
            record["feature"],
        )
    )
    draw_contact_sheet(head_candidates, OUTPUT_DIR / "head_geometry_candidates.png", "All-library head geometry candidates")

    serializable_probes = []
    for record in all_probes:
        clean = dict(record)
        clean.pop("_image", None)
        serializable_probes.append(clean)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schemaVersion": 1,
        "policy": "Library/category names are hints only; mappings require visual and source evidence.",
        "libraryCount": len(libraries),
        "probeRule": {
            "blockFrames": BLOCK_FRAMES,
            "frontDirection": FRONT_DIRECTION,
            "frameWithinDirection": 0,
        },
        "libraries": libraries,
        "blockProbes": serializable_probes,
        "headGeometryCandidateCount": len(head_candidates),
        "headCandidateSheet": "res://outputs/resource_catalog/mir2_client_data/head_geometry_candidates.png",
    }
    (OUTPUT_DIR / "catalog.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    with (OUTPUT_DIR / "libraries.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        fields = [
            "library",
            "source",
            "wilBytes",
            "wixPresent",
            "imageCount",
            "wilVersion",
            "complete600FrameBlocks",
            "remainderFrames",
            "error",
        ]
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(libraries)
    print(
        "MIR2_RESOURCE_CATALOG_PASS "
        f"libraries={len(libraries)} probes={len(all_probes)} headCandidates={len(head_candidates)}"
    )


if __name__ == "__main__":
    main()
