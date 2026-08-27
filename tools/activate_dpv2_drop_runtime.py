#!/usr/bin/env python3
"""Build/check the production DPV2 probability and nine-slot authorities.

The 7,032 canonical source rows are deliberately outside this builder's write
set.  It only activates the frozen A0.7 role/tier decisions and adds explicit
overflow policy to every canonical item plus the synthetic gold reward kind.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TIER_PATH = ROOT / "assets/data/drop/dpv2_item_tier_authority_v1.json"
ROLE_PATH = ROOT / "assets/data/drop/dpv2_monster_role_authority_v1.json"
SPECIAL_NORMAL_PATH = ROOT / "assets/data/special_normal_monster_spawn_authority_v1.json"
RUNTIME_AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_drop_runtime_authority_v1.json"
GLOBAL_AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
RUNTIME_CONSUMER = "scripts/layers/runtime/loot_runtime_service.gd"

EQUIPMENT_ITEM_TYPES = {
    "武器",
    "盔甲",
    "头盔",
    "项链",
    "手镯",
    "戒指",
    "腰带",
    "鞋",
    "圣物",
    "徽章",
    "特殊装备",
}
PROTECTED_NON_EQUIPMENT_TIERS = {
    "BOOK_HIGH",
    "BOOK_35",
    "BOSS_KEY_ITEM",
    "RARE_CONSUMABLE",
    "FUNCTIONAL_SPECIAL",
}


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"{path} is not a JSON object")
    return value


def compact(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n"


def pretty(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def classify_overflow(record: dict[str, Any]) -> tuple[str, bool, int]:
    item_type = str(record.get("item_type", ""))
    tier = str(record.get("tier", ""))
    if item_type in EQUIPMENT_ITEM_TYPES:
        return "EQUIPMENT", True, 300
    if tier in PROTECTED_NON_EQUIPMENT_TIERS:
        return "PROTECTED_HIGH_VALUE", True, 200
    return "ORDINARY_CONSUMABLE", False, 100


def build_tier(source: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(source)
    if result.get("schema") != "hardcore.dpv2.item_tier_authority.v1":
        raise RuntimeError("item Tier authority schema mismatch")
    records = result.get("records")
    if not isinstance(records, list) or len(records) != 233:
        raise RuntimeError("item Tier authority must contain 233 records")

    result["status"] = "A0_7_COMPLETE_ITEM_TIER_AUTHORITY"
    authority = result.setdefault("authority", {})
    authority["runtime_consumer"] = None
    authority["persistence_consumer"] = None
    result["activation"] = {
        "production_active": False,
        "phase1_allowed": False,
        "runtime_consumer": None,
        "persistence_consumer": None,
    }
    result.setdefault("tier_denominators", {}).pop("GOLD_COMMON", None)
    policies = result.setdefault("tier_policies", {})
    policies.pop("GOLD_COMMON", None)
    policies["per_item_denominator_override_allowed"] = False
    result.pop("gold_policy", None)
    result.pop("overflow_policy", None)

    seen_ids: set[int] = set()
    seen_names: set[str] = set()
    class_counts: dict[str, int] = {}
    for raw in records:
        if not isinstance(raw, dict):
            raise RuntimeError("invalid item Tier record")
        item_id = int(raw.get("canonical_item_id", -1))
        name = str(raw.get("canonical_name", ""))
        if (
            item_id <= 0
            or not name
            or item_id in seen_ids
            or name in seen_names
            or raw.get("tier_status") != "RESOLVED"
            or raw.get("denominator_override") is not None
            or int(raw.get("base_denominator", 0)) <= 0
        ):
            raise RuntimeError(f"invalid canonical item Tier identity: {name!r}/{item_id}")
        seen_ids.add(item_id)
        seen_names.add(name)
        overflow_class, protected, priority = classify_overflow(raw)
        if str(raw.get("tier", "")) in {"BOSS_KEY_ITEM", "MONSTER_MATERIAL"}:
            raw["protected_drop"] = protected
            raw["overflow_priority"] = priority
        else:
            raw.pop("protected_drop", None)
            raw.pop("overflow_priority", None)
        raw.pop("overflow_class", None)
        raw.pop("overflow_authority", None)
        class_counts[overflow_class] = class_counts.get(overflow_class, 0) + 1

    result.setdefault("summary", {}).pop("overflow_class_counts", None)
    result["summary"].pop("overflow_policy_records", None)
    return result


def build_role(source: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(source)
    if result.get("schema") != "hardcore.dpv2.monster_role_authority.v1":
        raise RuntimeError("monster role authority schema mismatch")
    monsters = result.get("monsters")
    if not isinstance(monsters, list) or len(monsters) != 156:
        raise RuntimeError("monster role authority must contain 156 records")
    result["status"] = "A0_7_FORMAL_AUTHORITY_COMPLETE_PHASE_1_FORBIDDEN"
    result["activation"] = {
        "production_active": False,
        "runtime_consumer": None,
        "phase_1_allowed": False,
    }
    for row in monsters:
        if not isinstance(row, dict):
            raise RuntimeError("invalid monster role record")
        enabled = bool(row.get("drop_enabled", False))
        role = row.get("drop_role")
        factor = row.get("role_factor")
        if enabled and (not isinstance(role, str) or not role or factor is None):
            raise RuntimeError(f"enabled monster has invalid role: {row}")
        if not enabled and (role is not None or factor is not None):
            raise RuntimeError(f"NON_LOOT monster entered probability roles: {row}")
    return result


def build_special_normal(source: dict[str, Any], tier_sha: str) -> dict[str, Any]:
    result = copy.deepcopy(source)
    binding = result.get("drop_binding")
    if not isinstance(binding, dict):
        raise RuntimeError("special_normal drop binding missing")
    binding["production_active"] = True
    binding["phase_1_allowed"] = True
    binding["runtime_consumer"] = RUNTIME_CONSUMER
    binding["persistence_consumer"] = None
    sources = result.get("authority", {}).get("sources", [])
    for row in sources:
        if (
            isinstance(row, dict)
            and row.get("path")
            == "assets/data/drop/dpv2_item_tier_authority_v1.json"
        ):
            row["sha256"] = tier_sha
            break
    else:
        raise RuntimeError("special_normal item Tier source evidence missing")
    return result


def build_runtime_authority(
    tier: dict[str, Any],
    role: dict[str, Any],
    global_authority: dict[str, Any],
    tier_sha: str,
    role_sha: str,
    global_sha: str,
) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    class_counts: dict[str, int] = {}
    for row in tier["records"]:
        overflow_class, protected, priority = classify_overflow(row)
        records.append({
            "canonical_item_id": int(row["canonical_item_id"]),
            "canonical_name": str(row["canonical_name"]),
            "overflow_class": overflow_class,
            "protected_drop": protected,
            "overflow_priority": priority,
        })
        class_counts[overflow_class] = class_counts.get(overflow_class, 0) + 1
    return {
        "schema": "hardcore.dpv2.drop_runtime_authority.v1",
        "authority_id": "dpv2.drop_runtime.v1",
        "status": "PRODUCTION_ACTIVE",
        "activation": {
            "production_active": True,
            "runtime_consumer": RUNTIME_CONSUMER,
            "historical_a07_activation_boundaries_preserved": True,
        },
        "source_authorities": {
            "item_tier": {
                "path": TIER_PATH.relative_to(ROOT).as_posix(),
                "schema": tier["schema"],
                "sha256": tier_sha,
            },
            "monster_role": {
                "path": ROLE_PATH.relative_to(ROOT).as_posix(),
                "schema": role["schema"],
                "sha256": role_sha,
            },
            "global_scale": {
                "path": GLOBAL_AUTHORITY_PATH.relative_to(ROOT).as_posix(),
                "schema": global_authority["schema"],
                "sha256": global_sha,
            },
        },
        "source_slot_contract": {
            "canonical_source_slot_count": 7032,
            "source_slot_mutated": False,
            "source_chance_role": "provenance_only",
            "all_resolved_slots_rng_before_overflow": True,
        },
        "ground_overflow_policy": {
            "maximum_ground_slots": 9,
            "selection_stage": "after_all_probability_rolls",
            "priority_order": [
                {"class": "EQUIPMENT", "priority": 300},
                {"class": "PROTECTED_HIGH_VALUE", "priority": 200},
                {"class": "ORDINARY_CONSUMABLE", "priority": 100},
            ],
            "same_priority_selection": "uniform_random_without_replacement",
            "protected_over_capacity": "uniform_random_keep_n_with_telemetry",
            "source_array_order_priority_forbidden": True,
        },
        "gold_policy": {
            "reward_kind": "gold",
            "tier": "GOLD_COMMON",
            "base_denominator": 32,
            "amount_role": "resolved_quantity_provenance",
            "overflow_class": "ORDINARY_CONSUMABLE",
            "protected_drop": False,
            "overflow_priority": 100,
        },
        "summary": {
            "canonical_item_policy_count": len(records),
            "overflow_class_counts": dict(sorted(class_counts.items())),
        },
        "item_overflow_records": records,
    }


def desired_outputs() -> dict[Path, str]:
    tier = build_tier(load(TIER_PATH))
    tier_text = compact(tier)
    role = build_role(load(ROLE_PATH))
    role_text = pretty(role)
    global_text = GLOBAL_AUTHORITY_PATH.read_text(encoding="utf-8")
    global_authority = json.loads(global_text)
    special = build_special_normal(load(SPECIAL_NORMAL_PATH), sha256_text(tier_text))
    runtime = build_runtime_authority(
        tier,
        role,
        global_authority,
        sha256_text(tier_text),
        sha256_text(role_text),
        sha256_text(global_text),
    )
    return {
        TIER_PATH: tier_text,
        ROLE_PATH: role_text,
        SPECIAL_NORMAL_PATH: pretty(special),
        RUNTIME_AUTHORITY_PATH: pretty(runtime),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    outputs = desired_outputs()
    if args.write:
        for path, rendered in outputs.items():
            path.write_text(rendered, encoding="utf-8", newline="\n")
        print("DPV2_DROP_RUNTIME_AUTHORITY_BUILD_PASS: items=233 monsters=156 ground_slots=9")
        return 0
    mismatches = [path for path, rendered in outputs.items() if path.read_text(encoding="utf-8") != rendered]
    if mismatches:
        for path in mismatches:
            print(f"ERROR: {path.relative_to(ROOT)} differs from generated authority")
        return 1
    print("DPV2_DROP_RUNTIME_AUTHORITY_CHECK_PASS: items=233 monsters=156 ground_slots=9")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
