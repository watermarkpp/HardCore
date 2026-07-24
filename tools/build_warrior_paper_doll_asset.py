#!/usr/bin/env python3
"""Build the equipment paper doll from the downloaded classic client.

The original client does not crop equipment out of screenshots.  It decodes
one WIL record per equipped item and draws that record at its stored x/y
offset over Prguse image 376.  Keeping the record rectangle intact is
important for helmets: their dark pixels are an intentional occlusion mask
which hides the bald head and hair below the helmet.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/original_client/Data"
PRGUSE = CLIENT_DATA / "Prguse.wil"
STATE_ITEM = CLIENT_DATA / "stateitem.wil"
SOURCE_CSV = ROOT / "dev_art_sources/reference/mir2_database/angelk727/2_物品数据.csv"
CATALOG = ROOT / "assets/data/legend176_data.json"
OUTPUT = ROOT / "assets/art/characters/warrior/paper_doll/classic"
LAYERS = OUTPUT / "layers"
MANIFEST = ROOT / "assets/data/warrior_paper_doll_sources.json"

CONTRACT_ID = "equipment.paper_doll.original_client_stage.v1"
BASE_INDEX = 376
FEMALE_BASE_INDEX = 377
HAIR_INDEX = 442
BASE_SCREEN_ORIGIN = (0, 0)
EQUIPMENT_ANCHOR = (31, 96)
DRAW_ORDER = ("base", "hair", "dress", "weapon", "helmet")
SUPPORTED_CATEGORIES = {"武器", "盔甲", "头盔"}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def decode_record(library: Path, index: int):
    data, palette, offsets, info = read_library(library)
    if index < 0 or index >= len(offsets):
        raise IndexError(f"{library.name} record {index} is outside {len(offsets)} records")
    image, meta = decode_sprite(data, offsets[index], palette)
    return image.convert("RGBA"), meta, info


def build_complete_stage(source: Image.Image) -> Image.Image:
    """Return the complete Prguse record without differential extraction."""

    return source.convert("RGBA").copy()


def _legacy_main() -> None:
    for source in (PRGUSE, STATE_ITEM, SOURCE_CSV, CATALOG):
        if not source.exists():
            raise FileNotFoundError(f"Missing paper-doll source: {source}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    LAYERS.mkdir(parents=True, exist_ok=True)

    base_source, base_meta, prguse_info = decode_record(PRGUSE, BASE_INDEX)
    base = build_complete_stage(base_source)
    base_path = OUTPUT / "prguse_00376_complete.png"
    base.save(base_path)

    hair, hair_meta, _ = decode_record(PRGUSE, HAIR_INDEX)
    hair_path = OUTPUT / f"hair_male_{HAIR_INDEX:05d}.png"
    hair.save(hair_path)

    state_data, state_palette, state_offsets, state_info = read_library(STATE_ITEM)
    with SOURCE_CSV.open("r", encoding="utf-8-sig", newline="") as handle:
        source_rows = {
            row["ItemName"]: row
            for row in csv.DictReader(handle)
            if row.get("ItemName")
        }
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")).get("items", [])

    mappings: dict[str, dict] = {}
    rejected: list[dict] = []
    written: dict[int, str] = {}
    for item in catalog:
        name = str(item.get("name", ""))
        category = str(item.get("category", ""))
        if category not in SUPPORTED_CATEGORIES:
            continue
        if category == "盔甲" and "(女)" in name:
            continue
        row = source_rows.get(name)
        image_value = str(row.get("ItemImage", "")) if row else ""
        if not image_value.isdigit():
            rejected.append({"name": name, "reason": "原客户端物品表无 ItemImage"})
            continue
        source_index = int(image_value)
        if source_index >= len(state_offsets):
            rejected.append({"name": name, "sourceIndex": source_index, "reason": "超出 StateItem 库"})
            continue
        try:
            image, meta = decode_sprite(state_data, state_offsets[source_index], state_palette)
        except ValueError:
            rejected.append({"name": name, "sourceIndex": source_index, "reason": "StateItem 记录为空"})
            continue
        if source_index not in written:
            target = LAYERS / f"stateitem_{source_index:05d}.png"
            # Source-faithful original-client composition keeps every pixel in
            # the StateItem record. Helmet records use stage-coloured pixels
            # to restore/erase lower hair, dress, and weapon layers.
            image.save(target)
            written[source_index] = resource_path(target)

        # Original client composition uses window-local (0, 0) as its base
        # origin. Every cached equipment record is drawn at (31, 96) plus
        # that record's untouched HotX/HotY values.
        composition_offset = [
            int(meta["x"] - base_meta["x"]),
            int(meta["y"] - base_meta["y"]),
        ]
        mappings[name] = {
            "slot": "衣服" if category == "盔甲" else category,
            "sourceIndex": source_index,
            "path": written[source_index],
            "drawOffset": composition_offset,
            "rawDrawOffset": [int(meta["x"]), int(meta["y"])],
            "size": [image.width, image.height],
            "source": "stateitem.wil",
            "mappingSource": "同名物品 ItemImage",
            "recordPolicy": "decode complete WIL record; never crop by opaque bounds",
            "foregroundPolicy": {
                "applied": False,
                "policy": "complete original record; no crop, matte, or background key",
            },
        }

    required = {
        "战神盔甲(男)": 62,
        "裁决之杖": 55,
        "黑铁头盔": 344,
    }
    for name, expected in required.items():
        actual = int(mappings.get(name, {}).get("sourceIndex", -1))
        if actual != expected:
            raise AssertionError(f"{name} mapping mismatch: expected {expected}, got {actual}")

    hair_draw_offset = [
        int(hair_meta["x"] - base_meta["x"]),
        int(hair_meta["y"] - base_meta["y"]),
    ]
    payload = {
        "schemaVersion": 2,
        "source": "downloaded classic client Data/Prguse.wil + Data/stateitem.wil",
        "renderEvidence": "MirClient/FState.pas DStateWinDirectPaint",
        "base": {
            "sourceIndex": BASE_INDEX,
            "pairedBackgroundIndex": FEMALE_BASE_INDEX,
            "path": resource_path(base_path),
            "size": [base.width, base.height],
            "rawDrawOffset": [int(base_meta["x"]), int(base_meta["y"])],
            "recordPolicy": "complete original Prguse record; no differential extraction",
        },
        "hair": {
            "sourceIndex": HAIR_INDEX,
            "path": resource_path(hair_path),
            "drawOffset": hair_draw_offset,
            "size": [hair.width, hair.height],
        },
        "composition": {
            "canvasSize": [base.width, base.height],
            "drawOrder": ["base", "footRing", "hair", "衣服", "武器", "头盔"],
            "baseScreenOrigin": [0, 0],
            "equipmentScreenAnchor": [31, 96],
            "rule": "equipmentOffset = recordOffset - baseRecordOffset",
        },
        "libraries": {
            "Prguse.wil": prguse_info,
            "stateitem.wil": state_info,
        },
        "runtimeMappings": mappings,
        "rejectedMappings": rejected,
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "CLASSIC_PAPER_DOLL_PASS "
        f"mapped={len(mappings)} layers={len(written)} "
        "battle_armor=62 judgement=55 black_iron=344"
    )


def main() -> None:
    """Compatibility entry point for the formal source-faithful generator."""

    from build_original_client_paper_doll_stage import main as build_formal_stage

    build_formal_stage()


if __name__ == "__main__":
    main()
