"""Migrate the currently known map-editor spawn identity defects.

This is an exact, allow-listed migration.  It only rewrites ``semantic_id``
and ``spawn_group_id`` in the five documents that were found by the complete
workspace audit.  Counts, ordering, placement data and all spawn properties
are checked before a write and compared again after the identity-only
transformation.

Formal runtime maps must be published one at a time with
``publish_single_formal_map_release.gd`` after this source migration.  The
sandbox document has no formal runtime release and is intentionally editor
only.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
from typing import Any


ROOT = Path("map_editor_workspace")
FORMAL_SEMANTIC_PREFIX = "mse.placement.v1."
FORMAL_GROUP_PREFIX = "mse.group.v1."
IDENTITY_KEYS = {"semantic_id", "spawn_group_id"}

# These counts are the read-only audit contract.  Refuse to touch a document
# if an author changed its placement population while this migration was
# being prepared.
TARGET_SPECS: dict[str, tuple[int, int]] = {
    "world_bich_province": (82, 0),
    "world_cangyue_island": (37, 0),
    "world_wooma_forest": (50, 4),
    "bich_orc_tomb_f1": (40, 0),
    "sandbox_64": (45, 0),
}


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise RuntimeError(f"expected object: {path}")
    return value


def non_identity(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: non_identity(item)
            for key, item in value.items()
            if key not in IDENTITY_KEYS
        }
    if isinstance(value, list):
        return [non_identity(item) for item in value]
    return value


def parse_formal(value: Any, prefix: str, map_id: str, kind: str) -> int | None:
    text = str(value or "")
    expected_prefix = f"{prefix}{map_id}.{kind}."
    if not text.startswith(expected_prefix):
        return None
    serial_text = text[len(expected_prefix) :]
    if len(serial_text) != 6 or not serial_text.isdecimal():
        return None
    serial = int(serial_text)
    return serial if serial > 0 else None


def formal_id(prefix: str, map_id: str, kind: str, serial: int) -> str:
    return f"{prefix}{map_id}.{kind}.{serial:06d}"


def _entries(document: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    layers = document.get("layers")
    if not isinstance(layers, dict):
        raise RuntimeError("layers must be an object")
    entries = layers.get(kind)
    if not isinstance(entries, list) or not all(isinstance(item, dict) for item in entries):
        raise RuntimeError(f"{kind} must be an array of objects")
    return entries


def transform(document: dict[str, Any], map_id: str) -> tuple[dict[str, Any], int]:
    if map_id not in TARGET_SPECS:
        raise RuntimeError(f"map is not allow-listed: {map_id!r}")
    if document.get("map_id") != map_id:
        raise RuntimeError(f"map mismatch: {document.get('map_id')!r}")
    expected_monsters, expected_bosses = TARGET_SPECS[map_id]
    monsters = _entries(document, "monster_spawn")
    bosses = _entries(document, "boss_spawn")
    if len(monsters) != expected_monsters or len(bosses) != expected_bosses:
        raise RuntimeError(
            f"unexpected placement counts for {map_id}: "
            f"monster_spawn={len(monsters)} boss_spawn={len(bosses)}"
        )

    migrated = copy.deepcopy(document)
    all_entries: list[tuple[str, dict[str, Any]]] = []
    for kind in ("monster_spawn", "boss_spawn"):
        all_entries.extend((kind, entry) for entry in _entries(migrated, kind))

    # Preserve every already-correct formal pair.  Any legacy, malformed, or
    # colliding pair gets a new serial after the highest preserved serial.  In
    # particular, this keeps the first forty Bich identities byte-for-byte
    # identical while assigning rows 41..82 fresh IDs.
    preserved_semantics: set[str] = set()
    preserved_groups: set[str] = set()
    next_serial: dict[str, int] = {"monster_spawn": 1, "boss_spawn": 1}
    preserve: set[int] = set()
    for index, (kind, entry) in enumerate(all_entries):
        serial = parse_formal(entry.get("semantic_id"), FORMAL_SEMANTIC_PREFIX, map_id, kind)
        expected_group = (
            formal_id(FORMAL_GROUP_PREFIX, map_id, kind, serial)
            if serial is not None
            else ""
        )
        if (
            serial is not None
            and entry.get("spawn_group_id") == expected_group
            and entry.get("semantic_id") not in preserved_semantics
            and expected_group not in preserved_groups
        ):
            preserve.add(index)
            preserved_semantics.add(str(entry.get("semantic_id")))
            preserved_groups.add(expected_group)
            next_serial[kind] = max(next_serial[kind], serial + 1)

    changed = 0
    for index, (kind, entry) in enumerate(all_entries):
        if index in preserve:
            continue
        while (
            formal_id(FORMAL_SEMANTIC_PREFIX, map_id, kind, next_serial[kind])
            in preserved_semantics
            or formal_id(FORMAL_GROUP_PREFIX, map_id, kind, next_serial[kind])
            in preserved_groups
        ):
            next_serial[kind] += 1
        semantic = formal_id(FORMAL_SEMANTIC_PREFIX, map_id, kind, next_serial[kind])
        group = formal_id(FORMAL_GROUP_PREFIX, map_id, kind, next_serial[kind])
        if entry.get("semantic_id") != semantic:
            entry["semantic_id"] = semantic
            changed += 1
        if entry.get("spawn_group_id") != group:
            entry["spawn_group_id"] = group
            changed += 1
        preserved_semantics.add(semantic)
        preserved_groups.add(group)
        next_serial[kind] += 1

    if non_identity(document) != non_identity(migrated):
        raise RuntimeError("non-identity fields changed during migration")
    return migrated, changed


def write_json(path: Path, document: dict[str, Any]) -> None:
    payload = (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
            separators=(",", ": "),
        )
        + "\n"
    )
    temporary = path.with_name(path.name + ".spawn_identity.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", choices=[*TARGET_SPECS, "all"], default="all")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    map_ids = list(TARGET_SPECS) if args.map == "all" else [args.map]
    results: list[tuple[str, int]] = []
    for map_id in map_ids:
        path = ROOT / map_id / f"{map_id}.editor.json"
        before = read_json(path)
        after, changed = transform(before, map_id)
        results.append((map_id, changed))
        if args.write:
            write_json(path, after)
            if read_json(path) != after:
                raise RuntimeError(f"written editor document did not round-trip: {path}")
    verb = "REPAIR" if args.write else "CHECK"
    for map_id, changed in results:
        monsters, bosses = TARGET_SPECS[map_id]
        print(
            f"MAP_SPAWN_IDENTITY_{verb}_PASS map={map_id} "
            f"monster_spawn={monsters} boss_spawn={bosses} "
            f"identity_fields_{'changed' if args.write else 'to_change'}={changed}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
