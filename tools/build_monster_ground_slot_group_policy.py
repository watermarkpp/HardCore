#!/usr/bin/env python3
"""Build the canonical-classification keyed monster ground-slot policy."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/drop/monster_ground_slot_group_policy.source.json"
CLASSIFICATION = ROOT / "assets/data/canonical_monster_classification_v1.json"
RUNTIME = ROOT / "assets/data/drop/monster_ground_slot_group_policy.runtime.json"
EXPECTED = {"ordinary": 6, "elite": 9, "boss": 12}


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected object")
    return value


def build() -> dict[str, Any]:
    source = load(SOURCE)
    if source.get("schema") != "hardcore.monster_ground_slot_group_policy.source.v1":
        raise ValueError("invalid source schema")
    groups = source.get("groups")
    if not isinstance(groups, dict):
        raise ValueError("groups must be an object")
    actual: dict[str, int] = {}
    for name in EXPECTED:
        group = groups.get(name)
        value = group.get("ground_slot_limit") if isinstance(group, dict) else None
        if type(value) is not int:
            raise ValueError(f"{name}.ground_slot_limit must be an integer")
        actual[name] = value
    if actual != EXPECTED or set(groups) != set(EXPECTED):
        raise ValueError(f"group limits/classes must be exactly {EXPECTED}")
    contract = source.get("selection_contract")
    if contract != {
        "stage": "AFTER_ALL_SLOT_RNG",
        "probability_influence_forbidden": True,
        "protected_priority_order_unchanged": True,
        "gold_aggregation_unchanged": True,
    }:
        raise ValueError("selection_contract is not the frozen post-RNG contract")
    classification = load(CLASSIFICATION)
    records = [dict(row, canonical_monster_id=int(monster_id)) for monster_id, row in (classification.get("exact_id_overrides") or {}).items()]
    if not records:
        raise ValueError("canonical classification records missing")
    seen_ids: set[int] = set()
    seen_classes: set[str] = set()
    for row in records:
        if not isinstance(row, dict):
            raise ValueError("classification record must be object")
        monster_id = int(row.get("canonical_monster_id", -1))
        cls = str(row.get("classification", ""))
        if monster_id <= 0 or monster_id in seen_ids:
            raise ValueError(f"invalid/duplicate canonical monster ID: {monster_id}")
        seen_ids.add(monster_id)
        seen_classes.add(cls)
    if not set(EXPECTED).issubset(seen_classes):
        raise ValueError(f"classification source missing policy classes: {set(EXPECTED) - seen_classes}")
    source_bytes = SOURCE.read_bytes().replace(b"\r\n", b"\n")
    source_sha = hashlib.sha256(source_bytes).hexdigest().upper()
    return {
        "schema": "hardcore.monster_ground_slot_group_policy.runtime.v1",
        "authority_id": "monster.ground_slot_groups.runtime.v1",
        "status": "PRODUCTION_ACTIVE",
        "production_active": True,
        "identity_key": "canonical_monster_classification",
        "source_authority": {
            "path": "assets/data/drop/monster_ground_slot_group_policy.source.json",
            "schema": source["schema"],
            "sha256_lf": source_sha,
        },
        "classification_source": {
            "path": "assets/data/canonical_monster_classification_v1.json",
            "classification_count": len(records),
        },
        "groups": {name: {"ground_slot_limit": limit} for name, limit in EXPECTED.items()},
        "unsupported_classifications": ["special"],
        "selection_contract": source["selection_contract"],
        "generator": "tools/build_monster_ground_slot_group_policy.py",
    }


def render(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.write == args.check:
        parser.error("choose exactly one of --write or --check")
    rendered = render(build())
    if args.write:
        RUNTIME.write_text(rendered, encoding="utf-8", newline="\n")
    elif RUNTIME.read_text(encoding="utf-8") != rendered:
        raise SystemExit("generated runtime policy differs; run --write")
    print("MONSTER_GROUND_SLOT_GROUP_POLICY_BUILD_PASS classes=3 ordinary=6 elite=9 boss=12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
