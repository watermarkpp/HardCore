#!/usr/bin/env python3
"""Catalog correctly-strided human, head, and weapon appearance libraries.

This is the second-stage catalog used after the all-WIL inventory.  It applies
the animation stride for each client family, composites the front idle frame at
the classic draw origin, and exposes both the whole layer and its head region.
It intentionally scans body and weapon libraries too: database and WIL category
names are not treated as authoritative equipment classifications.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT_DIR = ROOT / "outputs/resource_catalog/mir2_dynamic_appearances"
FRONT_IDLE_OFFSET = 4 * 8
CLASSIC_CELL = (128, 112)
CLASSIC_ORIGIN = (64, 80)
# WIL x/y values are the library draw offset, not a centred sprite origin.
# Front-facing human sprites begin near x=64+offset and their head occupies the
# right side of the classic cell.  The old 38..90 crop clipped that head and
# mixed in the left shoulder; 76..128 is calibrated against Hum/Hair at the
# shared draw origin.
HEAD_RECT = (76, 8, 128, 58)

LAYOUTS = {
    # Source-proven in the paired 2013 PlayerObject.cs.
    "Hair.wil": (2224, "source-proven common AOffSet"),
    "Hum.wil": (2224, "source-proven common AOffSet"),
    "Hum2.wil": (2224, "common-family structure"),
    "Weapon.wil": (1200, "source-proven common WOffSet"),
    "Hair_Killer.wil": (1456, "source-proven killer AOffSet"),
    "Hum_Killer.wil": (1456, "source-proven killer AOffSet"),
    "Hum_Killer2.wil": (1456, "killer-family structure"),
    "Weapon_Killer_Left.wil": (1456, "source-proven killer WOffSet"),
    "Weapon_Killer_Right.wil": (1456, "source-proven killer WOffSet"),
    # Ten Hair looks and matching HumUp/Weapon counts prove these family strides.
    "Hair_Common.wil": (2224, "paired-count inferred"),
    "HumUp_Common.wil": (2224, "paired-count inferred"),
    "Weapon_Common.wil": (1200, "common weapon-family inferred"),
    "Hair_Assassin.wil": (1824, "paired-count inferred"),
    "HumUp_Assassin.wil": (1824, "paired-count inferred"),
    "Weapon_Assassin_Left.wil": (1824, "paired-count inferred"),
    "Weapon_Assassin_Right.wil": (1824, "paired-count inferred"),
    "Hair_Monk.wil": (1440, "paired-count inferred"),
    "HumUp_Monk.wil": (1440, "paired-count inferred"),
    "Weapon_Monk.wil": (1440, "paired-count inferred"),
    "Hair_Warrior.wil": (1568, "paired-count inferred"),
    "HumUp_Warrior.wil": (1568, "paired-count inferred"),
    "Weapon_Warrior.wil": (1568, "paired-count inferred"),
    "Hair_Wizard.wil": (1440, "paired-count inferred"),
    "HumUp_Wizard.wil": (1440, "paired-count inferred"),
    "Weapon_Wizard.wil": (1440, "paired-count inferred"),
    "Helmet.wil": (600, "unmapped exact-block structure"),
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def composite_at_origin(image: Image.Image, x: int, y: int) -> Image.Image:
    cell = Image.new("RGBA", CLASSIC_CELL, (0, 0, 0, 0))
    cell.alpha_composite(image.convert("RGBA"), (CLASSIC_ORIGIN[0] + x, CLASSIC_ORIGIN[1] + y))
    return cell


def build_library(path: Path, stride: int, evidence: str) -> tuple[dict, list[dict]]:
    data, palette, offsets, info = read_library(path)
    count = len(offsets) // stride
    records: list[dict] = []
    cells: list[tuple[Image.Image, dict]] = []
    for appearance in range(count):
        index = appearance * stride + FRONT_IDLE_OFFSET
        record = {"library": path.name, "appearance": appearance, "index": index}
        try:
            image, meta = decode_sprite(data, offsets[index], palette)
        except (IndexError, ValueError) as error:
            record["error"] = str(error)
            records.append(record)
            continue
        cell = composite_at_origin(image, int(meta["x"]), int(meta["y"]))
        head = cell.crop(HEAD_RECT)
        record.update(
            {
                "sourceSize": [image.width, image.height],
                "drawOffset": [int(meta["x"]), int(meta["y"])],
                "cellOpaqueBox": list(cell.getchannel("A").getbbox() or ()),
                "headOpaqueBox": list(head.getchannel("A").getbbox() or ()),
            }
        )
        records.append(record)
        cells.append((cell, record))

    columns = 6
    tile = (154, 142)
    rows = (len(cells) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], 28 + rows * tile[1]), (14, 15, 18, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 7), f"{path.name} stride={stride} ({evidence})", fill=(235, 235, 235, 255))
    for position, (cell, record) in enumerate(cells):
        x0 = position % columns * tile[0]
        y0 = 28 + position // columns * tile[1]
        enlarged = cell.resize((CLASSIC_CELL[0], CLASSIC_CELL[1]), Image.Resampling.NEAREST)
        sheet.alpha_composite(enlarged, (x0 + 13, y0 + 18))
        draw.rectangle((x0 + 13 + HEAD_RECT[0], y0 + 18 + HEAD_RECT[1], x0 + 13 + HEAD_RECT[2], y0 + 18 + HEAD_RECT[3]), outline=(65, 210, 255, 255))
        draw.text((x0 + 4, y0 + 3), f"LOOK {record['appearance']:02d} I{record['index']}", fill=(255, 218, 84, 255))
        draw.text((x0 + 4, y0 + tile[1] - 14), f"{record['sourceSize']} @{record['drawOffset']}", fill=(185, 195, 208, 255))
    target = OUTPUT_DIR / "libraries" / f"{path.stem}_front_idle.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return (
        {
            "library": f"res://{path.relative_to(ROOT).as_posix()}",
            "imageCount": int(info["image_count"]),
            "appearanceStride": stride,
            "appearanceCount": count,
            "trailingFrames": len(offsets) % stride,
            "strideEvidence": evidence,
            "contactSheet": f"res://{target.relative_to(ROOT).as_posix()}",
            "records": records,
        },
        [{**record, "_head": cell.crop(HEAD_RECT)} for cell, record in cells],
    )


def build_master_head_sheet(records: list[dict]) -> Path:
    columns = 8
    tile = (132, 132)
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], 26 + rows * tile[1]), (12, 13, 16, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 6), "Correct-stride head regions from every dynamic library", fill=(235, 235, 235, 255))
    for position, record in enumerate(records):
        x0 = position % columns * tile[0]
        y0 = 26 + position // columns * tile[1]
        head = record["_head"].resize((104, 100), Image.Resampling.NEAREST)
        sheet.alpha_composite(head, (x0 + 14, y0 + 18))
        draw.text((x0 + 3, y0 + 2), f"{record['library'][:15]}", fill=(255, 218, 84, 255))
        draw.text((x0 + 3, y0 + tile[1] - 13), f"LOOK {record['appearance']:02d}", fill=(190, 198, 208, 255))
    target = OUTPUT_DIR / "all_dynamic_head_regions.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def build_body_head_detail_sheet(records: list[dict]) -> Path:
    body_records = [
        record
        for record in records
        if record["library"].startswith("Hum")
        and record.get("sourceSize", [0])[0] >= 40
        and record["_head"].getchannel("A").getbbox() is not None
    ]
    columns = 5
    tile = (228, 226)
    rows = (len(body_records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], 28 + rows * tile[1]), (12, 13, 16, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 7), "Body-library head details (correct stride, front idle)", fill=(235, 235, 235, 255))
    for position, record in enumerate(body_records):
        x0 = position % columns * tile[0]
        y0 = 28 + position // columns * tile[1]
        enlarged = record["_head"].resize((208, 200), Image.Resampling.NEAREST)
        sheet.alpha_composite(enlarged, (x0 + 10, y0 + 18))
        draw.text((x0 + 4, y0 + 2), f"{record['library']} LOOK {record['appearance']:02d}", fill=(255, 218, 84, 255))
    target = OUTPUT_DIR / "body_head_details.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def main() -> None:
    libraries: list[dict] = []
    head_records: list[dict] = []
    for name, (stride, evidence) in LAYOUTS.items():
        path = DATA_DIR / name
        if not path.exists():
            raise FileNotFoundError(path)
        entry, records = build_library(path, stride, evidence)
        libraries.append(entry)
        head_records.extend(records)
    master = build_master_head_sheet(head_records)
    body_details = build_body_head_detail_sheet(head_records)
    clean_records = []
    for record in head_records:
        clean = dict(record)
        clean.pop("_head", None)
        clean_records.append(clean)
    payload = {
        "schemaVersion": 1,
        "policy": "Scan by versioned animation stride across all categories; filenames are hints only.",
        "frontIdleOffset": FRONT_IDLE_OFFSET,
        "classicCell": list(CLASSIC_CELL),
        "classicOrigin": list(CLASSIC_ORIGIN),
        "headRect": list(HEAD_RECT),
        "libraries": libraries,
        "headRegionRecords": clean_records,
        "masterHeadSheet": f"res://{master.relative_to(ROOT).as_posix()}",
        "bodyHeadDetailSheet": f"res://{body_details.relative_to(ROOT).as_posix()}",
    }
    (OUTPUT_DIR / "manifest.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MIR2_DYNAMIC_APPEARANCE_CATALOG_PASS libraries={len(libraries)} looks={len(head_records)}")


if __name__ == "__main__":
    main()
