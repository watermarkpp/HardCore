#!/usr/bin/env python3
"""Expand the authored 64x64 Bich workspace to 80x80 without scaling its layout."""
from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = ROOT / "map_editor_workspace/bich_province"
DOCUMENT_PATH = WORKSPACE / "bich_province.editor.json"
GROUND = WORKSPACE / "ground"
MANIFEST_PATH = GROUND / "ground_manifest.json"
STATE_PATH = GROUND / "ground_state.json"
READY_PATH = ROOT / "assets/data/runtime/map_editor/bich_province.manual_ready.json"
BACKUP = ROOT / "outputs/map_editor_migrations/bich_before_80"
OLD_SIZE = [64, 64]
NEW_SIZE = [80, 80]
SHIFT = 8
CHUNK_SIZE = 1024


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def shift_pair(value: object, amount: int) -> object:
    if isinstance(value, list) and len(value) == 2:
        return [int(value[0]) + amount, int(value[1]) + amount]
    return value


def migrate_document(document: dict, amount: int) -> None:
    document["design"]["design_size"] = NEW_SIZE.copy()
    document["design"]["pre_scale_design_size"] = [256, 256]
    document["design"]["scale_factor"] = 0.3125
    document["design"]["scale_rounding"] = "nearest_integer_half_up"
    document["design"]["pre_resize_design_size"] = OLD_SIZE.copy()
    document["design"]["resize_policy"] = "center_with_equal_8_tile_border"
    document["design"]["size_status"] = "user_confirmed_final"
    document["design"]["size_decision_source"] = "user_2026-07-17_80x80"
    document["ground"]["origin_px"] = [NEW_SIZE[1] * 32, 16]
    document["editor_meta"]["runtime_approved"] = False
    document["editor_meta"]["size_migration"] = "bich_64_to_80_centered"
    if amount == 0:
        return
    for entries in document["layers"].values():
        for entry in entries:
            for key in ("tile", "tile_anchor", "return_tile"):
                if key in entry:
                    entry[key] = shift_pair(entry[key], amount)
            for key in ("npc_hull_tiles", "polygon_tiles"):
                if key in entry:
                    entry[key] = [shift_pair(point, amount) for point in entry[key]]


def chunk_id(tile: list[int]) -> str:
    px = NEW_SIZE[1] * 32 + (tile[0] - tile[1]) * 32
    py = 16 + (tile[0] + tile[1]) * 16
    return f"c_{math.floor(px / CHUNK_SIZE)}_{math.floor(py / CHUNK_SIZE)}"


def migrate_ground(state: dict, amount: int) -> tuple[dict, dict, int]:
    buckets: dict[str, list[dict]] = {}
    operation_count = 0
    for operations in state.get("operations_by_chunk", {}).values():
        for raw in operations:
            operation = dict(raw)
            operation["tile"] = shift_pair(operation.get("tile"), amount)
            bucket = chunk_id(operation["tile"])
            buckets.setdefault(bucket, []).append(operation)
            operation_count += 1

    pixel_size = [(NEW_SIZE[0] + NEW_SIZE[1]) * 32, (NEW_SIZE[0] + NEW_SIZE[1]) * 16]
    columns = math.ceil(pixel_size[0] / CHUNK_SIZE)
    rows = math.ceil(pixel_size[1] / CHUNK_SIZE)
    chunks = []
    for y in range(rows):
        for x in range(columns):
            cid = f"c_{x}_{y}"
            width = min(CHUNK_SIZE, pixel_size[0] - x * CHUNK_SIZE)
            height = min(CHUNK_SIZE, pixel_size[1] - y * CHUNK_SIZE)
            chunk = {
                "chunk_id": cid,
                "grid": [x, y],
                "rect_px": [x * CHUNK_SIZE, y * CHUNK_SIZE, width, height],
                "state": "virtual",
                "materialized": False,
                "fill_asset_id": "ground.old_grass.001",
            }
            if cid in buckets:
                chunk.update({"state": "dirty", "materialized": True, "workspace_chunk": f"ground/chunks/{cid}.json"})
                write_json(GROUND / f"chunks/{cid}.json", {"schema_version": 1, "chunk_id": cid, "operations": buckets[cid]})
            chunks.append(chunk)
    manifest = {
        "schema_version": 1,
        "map_id": "bich_province",
        "design_size": NEW_SIZE.copy(),
        "ground_pixel_size": pixel_size,
        "chunk_size_px": [CHUNK_SIZE, CHUNK_SIZE],
        "chunk_grid_size": [columns, rows],
        "blank_chunk_policy": "virtual_shared_until_dirty",
        "default_fill_asset_id": "ground.old_grass.001",
        "chunks": chunks,
    }
    migrated_state = {
        "schema_version": 1,
        "map_id": "bich_province",
        "dirty_chunks": sorted(buckets),
        "operations_by_chunk": buckets,
    }
    return manifest, migrated_state, operation_count


def main() -> None:
    document = read_json(DOCUMENT_PATH)
    current_size = [int(value) for value in document["design"]["design_size"]]
    if current_size not in (OLD_SIZE, NEW_SIZE):
        raise SystemExit(f"unexpected Bich size: {current_size}")
    amount = SHIFT if current_size == OLD_SIZE else 0
    if amount and not BACKUP.exists():
        BACKUP.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(WORKSPACE, BACKUP)

    state = read_json(STATE_PATH)
    migrate_document(document, amount)
    manifest, migrated_state, operation_count = migrate_ground(state, amount)
    write_json(DOCUMENT_PATH, document)
    write_json(MANIFEST_PATH, manifest)
    write_json(STATE_PATH, migrated_state)

    ready = read_json(READY_PATH)
    ready["status"] = "user_confirmed_ready_80x80"
    ready["content"]["design_size"] = NEW_SIZE.copy()
    ready["content"]["centered_from_size"] = OLD_SIZE.copy()
    ready["content"]["tile_shift"] = [SHIFT, SHIFT]
    write_json(READY_PATH, ready)
    print(f"BICH_RESIZE_80_PASS shift={amount} operations={operation_count} chunks={len(manifest['chunks'])}")


if __name__ == "__main__":
    main()
