#!/usr/bin/env python3
"""Build a category-independent catalog of every known human appearance layer.

MIR2 database categories and archive names are treated only as provenance.  The
catalog uses source-proven or structure-proven animation strides, samples the
same front-idle frame from every appearance, and records the actual head-region
pixels.  This prevents a helmet search from being limited to ``Helmet.wil`` and
also prevents the old 600-frame slicing error on later client families.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "outputs/resource_catalog/mir2_cross_category_appearances"
CELL = (128, 112)
ORIGIN = (64, 80)
HEAD_RECT = (76, 8, 128, 58)
FRONT_IDLE_OFFSET = 4 * 8

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


SOURCEFORGE_LAYOUTS = {
    "Hair.wil": (2224, "source-proven common AOffSet"),
    "Hum.wil": (2224, "source-proven common AOffSet"),
    "Hum2.wil": (2224, "common-family structure"),
    "Weapon.wil": (1200, "source-proven common WOffSet"),
    "Hair_Killer.wil": (1456, "source-proven killer AOffSet"),
    "Hum_Killer.wil": (1456, "source-proven killer AOffSet"),
    "Hum_Killer2.wil": (1456, "killer-family structure"),
    "Weapon_Killer_Left.wil": (1456, "source-proven killer WOffSet"),
    "Weapon_Killer_Right.wil": (1456, "source-proven killer WOffSet"),
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
    "Helmet.wil": (600, "exact-block structure; runtime mapping unknown"),
}


def wil_sources() -> list[dict]:
    base = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
    result = [
        {
            "sourceId": f"sourceforge-2013/{name}",
            "path": base / name,
            "stride": stride,
            "strideEvidence": evidence,
        }
        for name, (stride, evidence) in SOURCEFORGE_LAYOUTS.items()
    ]
    classic = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
    result.extend(
        [
            {
                "sourceId": "classic-client/Hair.wil",
                "path": classic / "Hair.wil",
                "stride": 600,
                "strideEvidence": "classic client exact 600-frame looks",
            },
            {
                "sourceId": "classic-client/Hum.wil",
                "path": classic / "Hum.wil",
                "stride": 600,
                "strideEvidence": "classic client exact 600-frame looks",
            },
            {
                "sourceId": "classic-client/Weapon.wil",
                "path": classic / "Weapon.wil",
                "stride": 600,
                "strideEvidence": "classic client 600-frame weapon looks with trailer",
            },
        ]
    )
    result.append(
        {
            "sourceId": "mirfiles-data-hum/Hum.wil",
            "path": ROOT
            / "dev_art_sources/external/mirfiles_selected/mirfiles_hum/hum/Hum.wil",
            "stride": 600,
            "strideEvidence": "61200 images form 102 exact 600-frame looks",
        }
    )
    return result


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def pixel_stats(image: Image.Image) -> dict:
    rgba = image.convert("RGBA")
    opaque = [pixel for pixel in rgba.getdata() if pixel[3] > 0]
    if not opaque:
        return {"opaquePixels": 0, "darkRatio": 0.0, "neutralMetalRatio": 0.0}
    dark = sum(max(r, g, b) <= 105 for r, g, b, _a in opaque)
    metal = sum(
        40 <= max(r, g, b) <= 210 and max(r, g, b) - min(r, g, b) <= 36
        for r, g, b, _a in opaque
    )
    return {
        "opaquePixels": len(opaque),
        "darkRatio": round(dark / len(opaque), 4),
        "neutralMetalRatio": round(metal / len(opaque), 4),
    }


def safe_name(source_id: str) -> str:
    return source_id.replace("/", "__").replace("\\", "__").replace(".", "_")


def render_source_sheet(source_id: str, records: list[dict]) -> Path:
    columns = 6
    tile = (154, 142)
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], 28 + rows * tile[1]), (13, 14, 17, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 7), source_id, fill=(235, 235, 235, 255))
    for position, record in enumerate(records):
        cell = record.pop("_cell")
        x0 = position % columns * tile[0]
        y0 = 28 + position // columns * tile[1]
        sheet.alpha_composite(cell, (x0 + 13, y0 + 18))
        draw.rectangle(
            (
                x0 + 13 + HEAD_RECT[0],
                y0 + 18 + HEAD_RECT[1],
                x0 + 13 + HEAD_RECT[2],
                y0 + 18 + HEAD_RECT[3],
            ),
            outline=(63, 211, 255, 255),
        )
        draw.text((x0 + 4, y0 + 3), f"LOOK {record['appearance']:03d}", fill=(255, 218, 84, 255))
        draw.text(
            (x0 + 4, y0 + tile[1] - 14),
            f"I{record['index']} {record['sourceSize']} @{record['drawOffset']}",
            fill=(183, 194, 208, 255),
        )
    target = OUTPUT_DIR / "libraries" / f"{safe_name(source_id)}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def scan_wil_source(spec: dict) -> tuple[dict, list[dict]]:
    path = Path(spec["path"])
    if not path.exists():
        raise FileNotFoundError(path)
    data, palette, offsets, info = read_library(path)
    stride = int(spec["stride"])
    appearance_count = len(offsets) // stride
    records: list[dict] = []
    head_records: list[dict] = []
    for appearance in range(appearance_count):
        index = appearance * stride + FRONT_IDLE_OFFSET
        record = {"appearance": appearance, "index": index}
        try:
            image, meta = decode_sprite(data, offsets[index], palette)
        except (IndexError, ValueError) as error:
            record["error"] = str(error)
            records.append(record)
            continue
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        draw_offset = [int(meta["x"]), int(meta["y"])]
        cell.alpha_composite(image.convert("RGBA"), (ORIGIN[0] + draw_offset[0], ORIGIN[1] + draw_offset[1]))
        head = cell.crop(HEAD_RECT)
        record.update(
            {
                "sourceSize": [image.width, image.height],
                "drawOffset": draw_offset,
                "cellOpaqueBox": list(cell.getchannel("A").getbbox() or ()),
                "headOpaqueBox": list(head.getchannel("A").getbbox() or ()),
                "headStats": pixel_stats(head),
                "_cell": cell,
            }
        )
        records.append(record)
        if record["headStats"]["opaquePixels"]:
            head_records.append(
                {
                    "sourceId": spec["sourceId"],
                    "appearance": appearance,
                    "index": index,
                    "stats": record["headStats"],
                    "_head": head,
                }
            )
    sheet = render_source_sheet(spec["sourceId"], records)
    return (
        {
            "sourceId": spec["sourceId"],
            "path": f"res://{path.relative_to(ROOT).as_posix()}",
            "sha256": file_sha256(path),
            "bytes": path.stat().st_size,
            "imageCount": int(info["image_count"]),
            "stride": stride,
            "strideEvidence": spec["strideEvidence"],
            "appearanceCount": appearance_count,
            "trailingFrames": len(offsets) % stride,
            "frontContactSheet": f"res://{sheet.relative_to(ROOT).as_posix()}",
            "records": records,
        },
        head_records,
    )


def scan_extracted_hair() -> tuple[list[dict], list[dict]]:
    root = ROOT / "dev_art_sources/external/mirfiles_selected/mirfiles_2hairs/hair"
    libraries: list[dict] = []
    heads: list[dict] = []
    for placement_dir in sorted(root.rglob("Placements"), key=lambda path: path.as_posix()):
        image_dir = placement_dir.parent
        relative = image_dir.relative_to(root).as_posix()
        index = FRONT_IDLE_OFFSET
        image_path = image_dir / f"{index:05d}.PNG"
        placement_path = placement_dir / f"{index:05d}.txt"
        if not image_path.exists() or not placement_path.exists():
            continue
        values = [int(value.strip()) for value in placement_path.read_text(encoding="utf-8-sig").splitlines() if value.strip()]
        if len(values) != 2:
            raise ValueError(f"Bad placement: {placement_path}")
        image = Image.open(image_path).convert("RGBA")
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        cell.alpha_composite(image, (ORIGIN[0] + values[0], ORIGIN[1] + values[1]))
        head = cell.crop(HEAD_RECT)
        source_id = f"mirfiles-2hairs/{relative}"
        record = {
            "appearance": 0,
            "index": index,
            "sourceSize": [image.width, image.height],
            "drawOffset": values,
            "cellOpaqueBox": list(cell.getchannel("A").getbbox() or ()),
            "headOpaqueBox": list(head.getchannel("A").getbbox() or ()),
            "headStats": pixel_stats(head),
            "_cell": cell,
        }
        sheet = render_source_sheet(source_id, [record])
        libraries.append(
            {
                "sourceId": source_id,
                "path": f"res://{image_dir.relative_to(ROOT).as_posix()}",
                "imageCount": len(list(image_dir.glob("*.PNG"))),
                "stride": 600,
                "strideEvidence": "archive supplies one complete 600-frame PNG sequence",
                "appearanceCount": 1,
                "trailingFrames": 0,
                "frontContactSheet": f"res://{sheet.relative_to(ROOT).as_posix()}",
                "records": [record],
            }
        )
        heads.append(
            {
                "sourceId": source_id,
                "appearance": 0,
                "index": index,
                "stats": record["headStats"],
                "_head": head,
            }
        )
    return libraries, heads


def render_master_heads(records: list[dict]) -> Path:
    records.sort(
        key=lambda record: (
            -record["stats"]["neutralMetalRatio"],
            -record["stats"]["darkRatio"],
            record["sourceId"],
            record["appearance"],
        )
    )
    columns = 8
    tile = (148, 126)
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], 28 + rows * tile[1]), (11, 12, 15, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 7), "All actual head regions, sorted by neutral-metal then darkness", fill=(235, 235, 235, 255))
    for position, record in enumerate(records):
        head = record.pop("_head")
        x0 = position % columns * tile[0]
        y0 = 28 + position // columns * tile[1]
        enlarged = head.resize((HEAD_RECT[2] - HEAD_RECT[0], HEAD_RECT[3] - HEAD_RECT[1]), Image.Resampling.NEAREST)
        sheet.alpha_composite(enlarged, (x0 + (tile[0] - enlarged.width) // 2, y0 + 27))
        draw.text((x0 + 3, y0 + 3), record["sourceId"][-22:], fill=(255, 218, 84, 255))
        draw.text((x0 + 3, y0 + 16), f"LOOK {record['appearance']:03d} I{record['index']}", fill=(210, 218, 229, 255))
        draw.text(
            (x0 + 3, y0 + tile[1] - 17),
            f"metal {record['stats']['neutralMetalRatio']:.2f} dark {record['stats']['darkRatio']:.2f}",
            fill=(175, 188, 204, 255),
        )
    target = OUTPUT_DIR / "all_head_regions_sorted.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def main() -> None:
    libraries: list[dict] = []
    heads: list[dict] = []
    for spec in wil_sources():
        library, source_heads = scan_wil_source(spec)
        libraries.append(library)
        heads.extend(source_heads)
    extracted, extracted_heads = scan_extracted_hair()
    libraries.extend(extracted)
    heads.extend(extracted_heads)
    master = render_master_heads(heads)
    payload = {
        "schemaVersion": 1,
        "policy": "Search every actual appearance layer; database category and filename are non-authoritative.",
        "frontIdleOffset": FRONT_IDLE_OFFSET,
        "headRect": list(HEAD_RECT),
        "libraryCount": len(libraries),
        "appearanceCount": sum(library["appearanceCount"] for library in libraries),
        "nonemptyHeadRegionCount": len(heads),
        "masterHeadSheet": f"res://{master.relative_to(ROOT).as_posix()}",
        "libraries": libraries,
    }
    manifest = OUTPUT_DIR / "manifest.json"
    manifest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "MIR2_CROSS_CATEGORY_APPEARANCE_CATALOG_PASS "
        f"libraries={len(libraries)} appearances={payload['appearanceCount']} heads={len(heads)}"
    )


if __name__ == "__main__":
    main()
