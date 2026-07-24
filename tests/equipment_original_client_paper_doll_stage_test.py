#!/usr/bin/env python3
"""Exact-pixel contract test for the original-client equipment paper doll."""

from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/equipment_original_client_paper_doll_stage.json"
PRGUSE = ROOT / "dev_art_sources/original_client/Data/Prguse.wil"
STATE_ITEM = ROOT / "dev_art_sources/original_client/Data/stateitem.wil"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def raw_rgba(image: Image.Image) -> bytes:
    return image.convert("RGBA").tobytes()


def assert_record_matches_library(
    record: dict,
    data: bytes,
    palette: list[tuple[int, int, int, int]],
    offsets: list[int],
) -> None:
    source_index = int(record["sourceIndex"])
    decoded, metadata = decode_sprite(data, offsets[source_index], palette)
    decoded = decoded.convert("RGBA")
    exported = Image.open(disk_path(record["path"])).convert("RGBA")
    assert exported.size == decoded.size == tuple(record["size"])
    assert [int(metadata["x"]), int(metadata["y"])] == [
        int(record["hotX"]),
        int(record["hotY"]),
    ]
    assert raw_rgba(exported) == raw_rgba(decoded), (
        f"record {source_index} differs from the complete WIL rectangle"
    )
    assert hashlib.sha256(raw_rgba(exported)).hexdigest() == record["rgbaSha256"]


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest["contractId"] == "equipment.paper_doll.original_client_stage.v1"
    assert manifest["sex"] == "male"
    assert manifest["canvasSize"] == [232, 325]
    assert manifest["viewportOrigin"] == [0, -44]
    assert manifest["viewportBounds"] == [0, -44, 232, 281]

    composition = manifest["composition"]
    assert composition["baseScreenOrigin"] == [0, 0]
    assert composition["equipmentScreenAnchor"] == [31, 96]
    assert composition["viewportOrigin"] == [0, -44]
    assert composition["viewportBounds"] == [0, -44, 232, 281]
    assert composition["drawOrder"] == [
        "base",
        "hair",
        "dress",
        "weapon",
        "helmet",
    ]

    coverage = manifest["coverage"]
    assert coverage["mappedItems"] == 61
    assert coverage["uniqueStateItemRecords"] == 55
    assert coverage["completeRectangles"] == 61
    assert coverage["croppedOrMattedRecords"] == 0
    assert Counter(coverage["byCategory"].values()) == Counter([37, 12, 12])

    prguse_data, prguse_palette, prguse_offsets, _info = read_library(PRGUSE)
    state_data, state_palette, state_offsets, _state_info = read_library(STATE_ITEM)

    stage = manifest["stage"]
    assert stage["sourceIndex"] == 376
    assert [stage["hotX"], stage["hotY"]] == [7, -44]
    assert stage["stagePosition"] == [7, -44]
    assert_record_matches_library(
        stage, prguse_data, prguse_palette, prguse_offsets
    )

    hair = manifest["hair"]
    assert hair["sourceIndex"] == 442
    assert [hair["hotX"], hair["hotY"]] == [87, 0]
    assert hair["stagePosition"] == [118, 96]
    assert_record_matches_library(
        hair, prguse_data, prguse_palette, prguse_offsets
    )

    items = manifest["itemsById"]
    assert len(items) == 61
    seen_stateitem: set[int] = set()
    by_category: Counter[str] = Counter()
    rectangles: list[tuple[int, int, int, int]] = []
    rectangles.append((
        int(stage["stagePosition"][0]),
        int(stage["stagePosition"][1]),
        int(stage["stagePosition"][0]) + int(stage["size"][0]),
        int(stage["stagePosition"][1]) + int(stage["size"][1]),
    ))
    rectangles.append((
        int(hair["stagePosition"][0]),
        int(hair["stagePosition"][1]),
        int(hair["stagePosition"][0]) + int(hair["size"][0]),
        int(hair["stagePosition"][1]) + int(hair["size"][1]),
    ))
    for item_id, entry in items.items():
        assert int(item_id) == int(entry["itemId"])
        by_category[str(entry["category"])] += 1
        record = entry["originalClientPaperDoll"]
        assert record["status"] == "exact_complete_client_record"
        assert record["stagePosition"] == [
            31 + int(record["hotX"]),
            96 + int(record["hotY"]),
        ]
        assert "no crop" in record["recordPolicy"]
        assert_record_matches_library(
            record, state_data, state_palette, state_offsets
        )
        seen_stateitem.add(int(record["sourceIndex"]))
        rectangles.append((
            int(record["stagePosition"][0]),
            int(record["stagePosition"][1]),
            int(record["stagePosition"][0]) + int(record["size"][0]),
            int(record["stagePosition"][1]) + int(record["size"][1]),
        ))

    assert len(seen_stateitem) == 55
    assert Counter(by_category.values()) == Counter([37, 12, 12])
    union_bounds = [
        min(rect[0] for rect in rectangles),
        min(rect[1] for rect in rectangles),
        max(rect[2] for rect in rectangles),
        max(rect[3] for rect in rectangles),
    ]
    assert union_bounds == [7, -44, 177, 250]
    assert manifest["sourceUnionBounds"] == union_bounds
    assert all(
        union_bounds[index] >= manifest["viewportBounds"][index]
        for index in (0, 1)
    )
    assert all(
        union_bounds[index] <= manifest["viewportBounds"][index]
        for index in (2, 3)
    )

    print(
        "EQUIPMENT_ORIGINAL_CLIENT_PAPER_DOLL_STAGE_TEST_PASS "
        "items=61 unique_stateitem=55 union=[7,-44,177,250]"
    )


if __name__ == "__main__":
    main()
