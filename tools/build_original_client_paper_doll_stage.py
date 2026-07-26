#!/usr/bin/env python3
"""Build the source-faithful male equipment-page paper-doll contract.

This generator intentionally performs no foreground extraction. Prguse and
StateItem records are decoded as complete RGBA rectangles and keep their
original WIL HotX/HotY values. In particular, helmet pixels which look like
the equipment-page background are meaningful restore patches.
"""

from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/original_client/Data"
PRGUSE = CLIENT_DATA / "Prguse.wil"
STATE_ITEM = CLIENT_DATA / "stateitem.wil"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
OUTPUT = ROOT / "assets/art/items/client/original_paper_doll_stage"
STATE_OUTPUT = OUTPUT / "stateitem"
MANIFEST = ROOT / "assets/data/equipment_original_client_paper_doll_stage.json"

CONTRACT_ID = "equipment.paper_doll.original_client_stage.v1"
BASE_INDEX = 376
HAIR_INDEX = 442
# MirClient/FState.pas::TFrmDlg.DStateWinDirectPaint draws Prguse #376 at
# (38, 52), then switches to the (31, 96) anchor for hair and equipment.
# WIL HotX/HotY are only consumed by GetCachedImage for the latter records;
# they are *not* the position of the opaque Prguse stage image.
BASE_SCREEN_ORIGIN = (38, 52)
EQUIPMENT_ANCHOR = (31, 96)
DRAW_ORDER = ("base", "hair", "dress", "weapon", "helmet")
STAGE_CANVAS_SIZE = (232, 325)
VIEWPORT_ORIGIN = (0, 0)

CATEGORY_WEAPON = "\u6b66\u5668"
CATEGORY_ARMOR = "\u76d4\u7532"
CATEGORY_HELMET = "\u5934\u76d4"
GENDER_MALE = "\u7537"
SLOT_BY_CATEGORY = {
    CATEGORY_WEAPON: "\u6b66\u5668",
    CATEGORY_ARMOR: "\u8863\u670d",
    CATEGORY_HELMET: "\u5934\u76d4",
}
EXPECTED_COUNTS = {
    CATEGORY_WEAPON: 37,
    CATEGORY_ARMOR: 12,
    CATEGORY_HELMET: 12,
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def decode_record(
    data: bytes,
    palette: list[tuple[int, int, int, int]],
    offsets: list[int],
    index: int,
) -> tuple[Image.Image, dict]:
    if index < 0 or index >= len(offsets):
        raise IndexError(f"record {index} outside library size {len(offsets)}")
    image, metadata = decode_sprite(data, offsets[index], palette)
    return image.convert("RGBA"), metadata


def selected_male_items(catalog: dict) -> list[tuple[int, dict, dict]]:
    selected: list[tuple[int, dict, dict]] = []
    for item_key, item in catalog.get("itemsById", {}).items():
        paper_doll = item.get("paperDoll", {})
        category = item.get("category", "")
        if category == CATEGORY_WEAPON or category == CATEGORY_HELMET:
            selected.append((int(item_key), item, paper_doll))
        elif category == CATEGORY_ARMOR and paper_doll.get("gender") == GENDER_MALE:
            selected.append((int(item_key), item, paper_doll))
    selected.sort(key=lambda row: row[0])
    counts = Counter(item.get("category", "") for _item_id, item, _paper in selected)
    if counts != Counter(EXPECTED_COUNTS):
        raise AssertionError(f"male paper-doll selection mismatch: {dict(counts)}")
    return selected


def write_record(image: Image.Image, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, format="PNG", optimize=False)


def main() -> None:
    for source in (PRGUSE, STATE_ITEM, VISUAL_CATALOG):
        if not source.exists():
            raise FileNotFoundError(f"missing source: {source}")

    catalog = json.loads(VISUAL_CATALOG.read_text(encoding="utf-8"))
    selected = selected_male_items(catalog)

    prguse_data, prguse_palette, prguse_offsets, prguse_info = read_library(PRGUSE)
    base_image, base_meta = decode_record(
        prguse_data, prguse_palette, prguse_offsets, BASE_INDEX
    )
    hair_image, hair_meta = decode_record(
        prguse_data, prguse_palette, prguse_offsets, HAIR_INDEX
    )
    base_path = OUTPUT / f"prguse_{BASE_INDEX:05d}.png"
    hair_path = OUTPUT / f"prguse_{HAIR_INDEX:05d}.png"
    write_record(base_image, base_path)
    write_record(hair_image, hair_path)

    state_data, state_palette, state_offsets, state_info = read_library(STATE_ITEM)
    items_by_id: dict[str, dict] = {}
    unique_records: dict[int, dict] = {}
    source_rectangles = [
        (
            BASE_SCREEN_ORIGIN[0],
            BASE_SCREEN_ORIGIN[1],
            BASE_SCREEN_ORIGIN[0] + base_image.width,
            BASE_SCREEN_ORIGIN[1] + base_image.height,
        ),
        (
            EQUIPMENT_ANCHOR[0] + int(hair_meta["x"]),
            EQUIPMENT_ANCHOR[1] + int(hair_meta["y"]),
            EQUIPMENT_ANCHOR[0] + int(hair_meta["x"]) + hair_image.width,
            EQUIPMENT_ANCHOR[1] + int(hair_meta["y"]) + hair_image.height,
        ),
    ]
    for item_id, item, source_mapping in selected:
        source_index = int(source_mapping.get("sourceIndex", -1))
        image, metadata = decode_record(
            state_data, state_palette, state_offsets, source_index
        )
        expected_hot = source_mapping.get("rawDrawOffset", [])
        actual_hot = [int(metadata["x"]), int(metadata["y"])]
        if list(expected_hot) != actual_hot:
            raise AssertionError(
                f"item {item_id} source {source_index} Hot mismatch: "
                f"catalog={expected_hot} decoded={actual_hot}"
            )
        expected_size = source_mapping.get("size", [])
        actual_size = [image.width, image.height]
        if list(expected_size) != actual_size:
            raise AssertionError(
                f"item {item_id} source {source_index} size mismatch: "
                f"catalog={expected_size} decoded={actual_size}"
            )

        target = (
            STATE_OUTPUT
            / f"item_{item_id:05d}_stateitem_{source_index:05d}.png"
        )
        write_record(image, target)
        record = {
            "status": "exact_complete_client_record",
            "slot": SLOT_BY_CATEGORY[item["category"]],
            "source": "stateitem.wil",
            "sourceIndex": source_index,
            "path": resource_path(target),
            "size": actual_size,
            "hotX": actual_hot[0],
            "hotY": actual_hot[1],
            "stagePosition": [
                EQUIPMENT_ANCHOR[0] + actual_hot[0],
                EQUIPMENT_ANCHOR[1] + actual_hot[1],
            ],
            "rgbaSha256": rgba_sha256(image),
            "recordPolicy": (
                "complete original rectangle; no crop, matte, alpha rewrite, "
                "or background key"
            ),
        }
        items_by_id[str(item_id)] = {
            "itemId": item_id,
            "itemName": item.get("itemName", ""),
            "category": item.get("category", ""),
            "originalClientPaperDoll": record,
        }
        unique_records[str(source_index)] = {
            "sourceIndex": source_index,
            "size": actual_size,
            "hotX": actual_hot[0],
            "hotY": actual_hot[1],
            "rgbaSha256": record["rgbaSha256"],
        }
        source_rectangles.append((
            record["stagePosition"][0],
            record["stagePosition"][1],
            record["stagePosition"][0] + actual_size[0],
            record["stagePosition"][1] + actual_size[1],
        ))

    source_union_bounds = [
        min(rectangle[0] for rectangle in source_rectangles),
        min(rectangle[1] for rectangle in source_rectangles),
        max(rectangle[2] for rectangle in source_rectangles),
        max(rectangle[3] for rectangle in source_rectangles),
    ]

    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "sex": "male",
        "sourcePolicy": {
            "sourceCode": (
                "MirClient/FState.pas::TFrmDlg.DStateWinDirectPaint "
                "(equipment StatePage=0)"
            ),
            "sourceCodePath": (
                "reference/original_gameofmir/MirClient/FState.pas:2896-2969"
            ),
            "baseScreenOrigin": list(BASE_SCREEN_ORIGIN),
            "equipmentScreenAnchor": list(EQUIPMENT_ANCHOR),
            "recordPolicy": (
                "Prguse #376 is the one opaque stage/background pass; "
                "hair and StateItem records retain their original transparent "
                "color-key pixels and are subsequent overlay passes"
            ),
            "runtimeComposition": {
                "output": "single_composited_paper_doll_layer",
                "stageLayerMode": "opaque",
                "overlayLayerMode": "transparent_color_key",
                "consumerRule": (
                    "draw stage exactly once at stage.stagePosition, then draw "
                    "hair/dress/weapon/helmet at their stagePosition in drawOrder; "
                    "never add a second anatomy/base texture or independently "
                    "translate the Prguse stage by its HotX/HotY"
                ),
            },
            "forbiddenOperations": [
                "opaque-bounds crop",
                "border-connected background removal",
                "dark-pixel keying",
                "base-difference matting",
            ],
        },
        "canvasSize": list(STAGE_CANVAS_SIZE),
        "viewportOrigin": list(VIEWPORT_ORIGIN),
        "viewportBounds": [
            VIEWPORT_ORIGIN[0],
            VIEWPORT_ORIGIN[1],
            VIEWPORT_ORIGIN[0] + STAGE_CANVAS_SIZE[0],
            VIEWPORT_ORIGIN[1] + STAGE_CANVAS_SIZE[1],
        ],
        "sourceUnionBounds": source_union_bounds,
        "stage": {
            "source": "Prguse.wil",
            "sourceIndex": BASE_INDEX,
            "path": resource_path(base_path),
            "size": [base_image.width, base_image.height],
            "hotX": int(base_meta["x"]),
            "hotY": int(base_meta["y"]),
            "stagePosition": list(BASE_SCREEN_ORIGIN),
            "rgbaSha256": rgba_sha256(base_image),
            "recordPolicy": "complete original Prguse record",
        },
        "hair": {
            "source": "Prguse.wil",
            "sourceIndex": HAIR_INDEX,
            "path": resource_path(hair_path),
            "size": [hair_image.width, hair_image.height],
            "hotX": int(hair_meta["x"]),
            "hotY": int(hair_meta["y"]),
            "stagePosition": [
                EQUIPMENT_ANCHOR[0] + int(hair_meta["x"]),
                EQUIPMENT_ANCHOR[1] + int(hair_meta["y"]),
            ],
            "rgbaSha256": rgba_sha256(hair_image),
            "recordPolicy": "complete original Prguse record",
        },
        "composition": {
            "canvasSize": list(STAGE_CANVAS_SIZE),
            "viewportOrigin": list(VIEWPORT_ORIGIN),
            "viewportBounds": [
                VIEWPORT_ORIGIN[0],
                VIEWPORT_ORIGIN[1],
                VIEWPORT_ORIGIN[0] + STAGE_CANVAS_SIZE[0],
                VIEWPORT_ORIGIN[1] + STAGE_CANVAS_SIZE[1],
            ],
            "baseScreenOrigin": list(BASE_SCREEN_ORIGIN),
            "equipmentScreenAnchor": list(EQUIPMENT_ANCHOR),
            "drawOrder": list(DRAW_ORDER),
            "baseRule": "Prguse376 opaque stage at (38,52); do not apply its HotX/HotY",
            "cachedRecordRule": "(31,96) + record HotX/HotY",
        },
        "coverage": {
            "mappedItems": len(items_by_id),
            "uniqueStateItemRecords": len(unique_records),
            "byCategory": dict(Counter(
                item.get("category", "") for _item_id, item, _paper in selected
            )),
            "expectedByCategory": EXPECTED_COUNTS,
            "completeRectangles": len(items_by_id),
            "croppedOrMattedRecords": 0,
        },
        "libraries": {
            "Prguse.wil": prguse_info,
            "stateitem.wil": state_info,
        },
        "itemsById": items_by_id,
        "uniqueStateItemRecords": unique_records,
    }
    MANIFEST.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "ORIGINAL_CLIENT_PAPER_DOLL_STAGE_PASS "
        f"items={len(items_by_id)} unique_stateitem={len(unique_records)} "
        f"stage={BASE_INDEX} hair={HAIR_INDEX}"
    )


if __name__ == "__main__":
    main()
