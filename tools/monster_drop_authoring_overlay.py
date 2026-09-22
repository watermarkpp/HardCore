#!/usr/bin/env python3
"""Strict user-authoring overlay for canonical monster drop profiles."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


OVERLAY_SCHEMA = "canonical_monster_drop_authoring_overlay_v1"
OVERLAY_AUTHORITY = "user_editable"
MAX_RUNTIME_INTEGER = 2_147_483_647

TOP_LEVEL_FIELDS = frozenset({
    "schema",
    "authority",
    "global_additions",
    "monster_additions",
})
GLOBAL_FIELDS = frozenset({
    "entry_key",
    "enabled",
    "chance",
    "item",
    "gold",
    "note",
})
MONSTER_FIELDS = GLOBAL_FIELDS | {"monster_id"}

ENTRY_KEY_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
CHANCE_RE = re.compile(r"^1/([1-9][0-9]*)$")


class OverlayValidationError(ValueError):
    """Raised when the authoring overlay violates its strict contract."""


def _fail(path: str, reason: str) -> None:
    raise OverlayValidationError(
        f"MONSTER_DROP_AUTHORING_OVERLAY_INVALID: path={path} reason={reason}"
    )


def _plain_string(
    value: Any,
    path: str,
    *,
    allow_empty: bool = False,
) -> str:
    if not isinstance(value, str):
        _fail(path, "expected_string")
    if value != value.strip():
        _fail(path, "surrounding_whitespace_forbidden")
    if not allow_empty and value == "":
        _fail(path, "empty_string")
    for character in value:
        codepoint = ord(character)
        if codepoint < 32 or codepoint in (0x7F, 0xFFFD):
            _fail(path, "control_or_replacement_character")
    return value


def _validate_entry(
    raw: Any,
    *,
    path: str,
    scope: str,
    valid_monster_ids: set[int],
    seen_entry_keys: set[str],
) -> dict[str, Any]:
    if not isinstance(raw, dict):
        _fail(path, "expected_object")

    allowed_fields = MONSTER_FIELDS if scope == "monster" else GLOBAL_FIELDS
    unknown_fields = sorted(set(raw) - allowed_fields)
    if unknown_fields:
        _fail(path, f"unknown_fields={','.join(unknown_fields)}")

    required_fields = {"entry_key", "enabled", "chance", "item"}
    if scope == "monster":
        required_fields.add("monster_id")
    missing_fields = sorted(required_fields - set(raw))
    if missing_fields:
        _fail(path, f"missing_fields={','.join(missing_fields)}")

    entry_key = _plain_string(raw["entry_key"], f"{path}.entry_key")
    if len(entry_key) > 128:
        _fail(f"{path}.entry_key", "length_exceeds_128")
    if ENTRY_KEY_RE.fullmatch(entry_key) is None:
        _fail(
            f"{path}.entry_key",
            "must_match_[a-z0-9][a-z0-9._-]*",
        )
    if entry_key in seen_entry_keys:
        _fail(
            f"{path}.entry_key",
            f"duplicate_entry_key={entry_key}",
        )
    seen_entry_keys.add(entry_key)

    enabled = raw["enabled"]
    if type(enabled) is not bool:
        _fail(f"{path}.enabled", "expected_boolean")

    chance = _plain_string(raw["chance"], f"{path}.chance")
    chance_match = CHANCE_RE.fullmatch(chance)
    if chance_match is None:
        _fail(
            f"{path}.chance",
            "expected_1_over_positive_integer",
        )
    denominator = int(chance_match.group(1))
    if denominator > MAX_RUNTIME_INTEGER:
        _fail(
            f"{path}.chance",
            f"denominator_exceeds_{MAX_RUNTIME_INTEGER}",
        )

    item = _plain_string(raw["item"], f"{path}.item")
    note = _plain_string(
        raw.get("note", ""),
        f"{path}.note",
        allow_empty=True,
    )

    gold: int | None = None
    if "gold" in raw:
        raw_gold = raw["gold"]
        if (
            type(raw_gold) is not int
            or raw_gold <= 0
            or raw_gold > MAX_RUNTIME_INTEGER
        ):
            _fail(
                f"{path}.gold",
                "expected_positive_runtime_integer",
            )
        if item != "金币":
            _fail(
                f"{path}.gold",
                "gold_field_requires_item_金币",
            )
        gold = raw_gold
    elif item == "金币":
        _fail(
            path,
            "item_金币_requires_positive_gold_field",
        )

    monster_id: int | None = None
    if scope == "monster":
        raw_monster_id = raw["monster_id"]
        if type(raw_monster_id) is not int or raw_monster_id <= 0:
            _fail(
                f"{path}.monster_id",
                "expected_positive_integer",
            )
        if raw_monster_id not in valid_monster_ids:
            _fail(
                f"{path}.monster_id",
                f"unknown_active_monster_id={raw_monster_id}",
            )
        monster_id = raw_monster_id

    normalized: dict[str, Any] = {
        "entry_key": entry_key,
        "enabled": enabled,
        "chance": chance,
        "denominator": denominator,
        "item": item,
        "note": note,
    }
    if gold is not None:
        normalized["gold"] = gold
    if monster_id is not None:
        normalized["monster_id"] = monster_id
    return normalized


def validate_overlay(
    raw: Any,
    valid_monster_ids: set[int],
    source_label: str,
) -> dict[str, Any]:
    if not isinstance(raw, dict):
        _fail("$", "expected_object")

    unknown_fields = sorted(set(raw) - TOP_LEVEL_FIELDS)
    if unknown_fields:
        _fail("$", f"unknown_fields={','.join(unknown_fields)}")

    missing_fields = sorted(TOP_LEVEL_FIELDS - set(raw))
    if missing_fields:
        _fail("$", f"missing_fields={','.join(missing_fields)}")

    if raw["schema"] != OVERLAY_SCHEMA:
        _fail("$.schema", f"expected={OVERLAY_SCHEMA}")
    if raw["authority"] != OVERLAY_AUTHORITY:
        _fail("$.authority", f"expected={OVERLAY_AUTHORITY}")

    global_raw = raw["global_additions"]
    monster_raw = raw["monster_additions"]
    if not isinstance(global_raw, list):
        _fail("$.global_additions", "expected_array")
    if not isinstance(monster_raw, list):
        _fail("$.monster_additions", "expected_array")

    seen_entry_keys: set[str] = set()
    global_entries = [
        _validate_entry(
            entry,
            path=f"$.global_additions[{index}]",
            scope="global",
            valid_monster_ids=valid_monster_ids,
            seen_entry_keys=seen_entry_keys,
        )
        for index, entry in enumerate(global_raw)
    ]
    monster_entries = [
        _validate_entry(
            entry,
            path=f"$.monster_additions[{index}]",
            scope="monster",
            valid_monster_ids=valid_monster_ids,
            seen_entry_keys=seen_entry_keys,
        )
        for index, entry in enumerate(monster_raw)
    ]

    enabled_global_entries = [
        entry for entry in global_entries
        if entry["enabled"]
    ]
    enabled_monster_entries_by_id: dict[int, list[dict[str, Any]]] = {}
    for entry in monster_entries:
        if entry["enabled"]:
            enabled_monster_entries_by_id.setdefault(
                int(entry["monster_id"]),
                [],
            ).append(entry)

    return {
        "schema": OVERLAY_SCHEMA,
        "source_label": source_label,
        "global_additions": global_entries,
        "monster_additions": monster_entries,
        "enabled_global_additions": enabled_global_entries,
        "enabled_monster_additions_by_id": enabled_monster_entries_by_id,
        "enabled_monster_addition_count": sum(
            len(entries)
            for entries in enabled_monster_entries_by_id.values()
        ),
    }


def load_overlay(
    path: Path,
    valid_monster_ids: set[int],
    source_label: str,
) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise OverlayValidationError(
            "MONSTER_DROP_AUTHORING_OVERLAY_INVALID: "
            f"path=$ reason=cannot_parse:{exc}"
        ) from exc
    return validate_overlay(raw, valid_monster_ids, source_label)


def _runtime_row(
    entry: dict[str, Any],
    *,
    scope: str,
    source_label: str,
) -> dict[str, Any]:
    entry_key = str(entry["entry_key"])
    raw_text = f'{entry["chance"]} {entry["item"]}'
    if "gold" in entry:
        raw_text += f' {entry["gold"]}'

    row: dict[str, Any] = {
        "line_number": 0,
        "raw_text": raw_text,
        "chance": str(entry["chance"]),
        "item": str(entry["item"]),
        "slot_index": f"authoring_{scope}_{entry_key}",
        "excel_monster_id": "",
        "source_note": str(entry["note"]),
        "source_quantity_or_gold": str(entry.get("gold", "")),
        "same_item_slot_ordinal": "",
        "same_item_slot_total": "",
        "source_rate": str(entry["chance"]),
        "source_denom": str(entry["denominator"]),
        "rate_policy": "USER_AUTHORING_EXACT",
        "slot_status": "AUTHORING_ENABLED",
        "source_kind": (
            "USER_GLOBAL_ADDITION"
            if scope == "global"
            else "USER_MONSTER_ADDITION"
        ),
        "source_ref": f"{source_label}::{entry_key}",
        "db_record_name": "",
        "display_name": "",
        "authoring_entry_key": entry_key,
        "authoring_scope": scope,
    }
    if "gold" in entry:
        row["gold"] = int(entry["gold"])
    return row


def runtime_rows_for_monster(
    monster_id: int,
    overlay: dict[str, Any],
) -> list[dict[str, Any]]:
    source_label = str(overlay["source_label"])
    rows = [
        _runtime_row(
            entry,
            scope="global",
            source_label=source_label,
        )
        for entry in overlay["enabled_global_additions"]
    ]
    rows.extend(
        _runtime_row(
            entry,
            scope="monster",
            source_label=source_label,
        )
        for entry in overlay[
            "enabled_monster_additions_by_id"
        ].get(monster_id, [])
    )
    return rows
