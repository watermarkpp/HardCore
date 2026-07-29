#!/usr/bin/env python3
"""Refresh only item 224's derived NE/NW rows from the formal atlases."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OVERRIDES = ROOT / "assets/data/equipment_helmet_visual_v2_overrides.json"
CONTRACT = ROOT / "assets/data/equipment_helmet_visual_v2.json"
ACTIONS = ("idle", "walk", "attack", "cast", "hit", "death")
CELL_HEIGHT = 160
TARGET_ROWS = (1, 7)


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def disk_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"expected res:// path, got {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


def main() -> None:
    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    before_item_overrides = json.dumps(
        overrides.get("itemOverrides", {}),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    prayer_override = overrides["visualAssetOverrides"]["prayer"]
    if float(prayer_override["uniform_scale_percent"]) != 100.0:
        raise ValueError(
            "prayer row refresh requires the saved 100% uniform scale"
        )
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    prayer = contract["visualAssets"]["prayer"]

    source_hashes: dict[str, str] = {}
    derived_hashes: dict[str, str] = {}
    for action in ACTIONS:
        source_path = disk_path(
            prayer["directions"]["N"]["texturesByAction"][action]
        )
        derived_path = disk_path(
            prayer_override["derivedAtlases"][action]
        )
        source = Image.open(source_path).convert("RGBA")
        derived = Image.open(derived_path).convert("RGBA")
        if source.size != derived.size:
            raise ValueError(
                f"{action} source/derived size mismatch: "
                f"{source.size} != {derived.size}"
            )
        before_rows = {
            row: derived.crop(
                (
                    0,
                    row * CELL_HEIGHT,
                    derived.width,
                    (row + 1) * CELL_HEIGHT,
                )
            ).tobytes()
            for row in range(8)
        }
        for row in TARGET_ROWS:
            source_row = source.crop(
                (
                    0,
                    row * CELL_HEIGHT,
                    source.width,
                    (row + 1) * CELL_HEIGHT,
                )
            )
            derived.paste(source_row, (0, row * CELL_HEIGHT))
        for row in range(8):
            if row in TARGET_ROWS:
                continue
            after = derived.crop(
                (
                    0,
                    row * CELL_HEIGHT,
                    derived.width,
                    (row + 1) * CELL_HEIGHT,
                )
            ).tobytes()
            if after != before_rows[row]:
                raise AssertionError(
                    f"{action} non-target derived row {row} changed"
                )
        derived.save(
            derived_path,
            format="PNG",
            optimize=False,
            compress_level=9,
        )
        source_hashes[action] = file_sha(source_path)
        derived_hashes[action] = file_sha(derived_path)

    prayer_override["sourceAtlasSha256"] = source_hashes
    prayer_override["derivedAtlasSha256"] = derived_hashes
    prayer_override["bakePolicy"]["sourceRecipeId"] = (
        "prayer_224.user_approved_ne_nw_rows.v1"
    )
    after_item_overrides = json.dumps(
        overrides.get("itemOverrides", {}),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    if after_item_overrides != before_item_overrides:
        raise AssertionError("itemOverrides changed during prayer row refresh")
    OVERRIDES.write_text(
        json.dumps(overrides, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "REFRESH_PRAYER_224_CALIBRATION_ROWS_PASS "
        "rows=1,7 actions=6 item_overrides_unchanged=true"
    )


if __name__ == "__main__":
    main()
