#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("analyze_monster_drop_p1a.py")
SPEC = importlib.util.spec_from_file_location(
    "analyze_monster_drop_p1a",
    MODULE_PATH,
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def base_slot() -> dict:
    return {
        "drop_profile_id": "drop.18",
        "monster_id": 18,
        "profile_entry_ordinal_zero_based": 0,
        "profile_entry_ordinal_one_based": 1,
        "line_number": 1,
        "slot_index": "slot_001",
        "raw_text": "1/3 测试物品",
        "chance_raw": "1/3",
        "chance_denominator": 3,
        "chance_valid": True,
        "item_resolution_status": "unresolved_token",
        "reward_probe_performed": True,
        "reward_resolution_status": "resolved",
        "reward_resolvable": True,
        "reward_resolution_reason": None,
        "reward_probe": {
            "ok": True,
            "kind": "item",
            "item_name": "测试物品",
            "item_id": 1,
        },
        "runtime_reward_attempted": True,
        "probability_authority_resolvable": True,
        "probability_policy": {
            "ok": True,
            "probability_numerator": 1,
            "probability_denominator": 32,
        },
        "slot_runtime_rollable": True,
        "runtime_rollable": True,
        "non_rollable_reason": None,
        "runtime_rejection_reason": None,
        "monster_runtime_allowed": True,
        "monster_runtime_reason": "",
        "monster_runtime_closure": {
            "allowed": True,
            "reason": "",
            "resolved_reward_count": 1,
        },
        "runtime_reachable": True,
        "source_entry": {
            "chance": "1/3",
            "rate_policy": "AUDIT_ONLY",
            "slot_status": "CONFIRMED_SOURCE_SLOT",
            "item_resolution_status": "unresolved_token",
        },
    }


def minimal_snapshot(slot: dict) -> dict:
    summary = MODULE._recompute_summary([slot])
    summary["monster_runtime_gate_counts"] = {"allowed": 1}
    return {
        "schema": MODULE.SNAPSHOT_SCHEMA,
        "authority": {
            "catalog_sha256_before": "same",
            "catalog_sha256_after": "same",
        },
        "summary": summary,
        "slots": [slot],
        "catalog_summary": {},
    }


class P1AAnalyzerContractTest(unittest.TestCase):
    def test_audit_only_is_provenance_only(self) -> None:
        original = base_slot()
        changed = copy.deepcopy(original)
        changed["source_entry"]["rate_policy"] = (
            "SYNTHETIC_PROVENANCE_ONLY"
        )
        self.assertEqual(
            MODULE.runtime_semantics_key(original),
            MODULE.runtime_semantics_key(changed),
        )
        self.assertEqual(
            MODULE.validate_slot_contract(original),
            [],
        )
        self.assertEqual(
            MODULE.validate_slot_contract(changed),
            [],
        )

    def test_invalid_1_00_contract(self) -> None:
        slot = base_slot()
        slot.update({
            "drop_profile_id": "drop.168",
            "monster_id": 168,
            "profile_entry_ordinal_zero_based": 19,
            "profile_entry_ordinal_one_based": 20,
            "line_number": 20,
            "slot_index": "slot_020",
            "raw_text": "1/00 灵魂战衣(男)",
            "chance_raw": "1/00",
            "chance_denominator": None,
            "chance_valid": False,
            # Source chance is provenance-only in production DPV2.
            "reward_resolution_status": "resolved",
            "reward_resolvable": True,
            "reward_resolution_reason": None,
            "runtime_reward_attempted": True,
            "slot_runtime_rollable": True,
            "runtime_rollable": True,
            "non_rollable_reason": None,
            "runtime_rejection_reason": None,
            "runtime_reachable": True,
        })
        slot["source_entry"]["chance"] = "1/00"
        self.assertEqual(MODULE.validate_slot_contract(slot), [])

    def test_valid_chance_unresolved_reward_contract(self) -> None:
        slot = base_slot()
        slot.update({
            "reward_resolution_status": "unresolved",
            "reward_resolvable": False,
            "reward_resolution_reason": "item_authority_unresolved",
            "reward_probe": {
                "ok": False,
                "reason": "item_authority_unresolved",
            },
            "probability_authority_resolvable": False,
            "probability_policy": {},
            "slot_runtime_rollable": False,
            "runtime_rollable": False,
            "non_rollable_reason": "unresolved_reward",
            "runtime_rejection_reason": "item_authority_unresolved",
            "runtime_reachable": False,
        })
        self.assertEqual(MODULE.validate_slot_contract(slot), [])

    def test_invalid_source_chance_does_not_mask_unresolved_reward(self) -> None:
        slot = base_slot()
        slot.update({
            "chance_denominator": None,
            "chance_valid": False,
            "reward_resolution_status": "unresolved",
            "reward_resolvable": False,
            "reward_resolution_reason": "item_authority_unresolved",
            "runtime_reward_attempted": True,
            "probability_authority_resolvable": False,
            "probability_policy": {},
            "slot_runtime_rollable": False,
            "runtime_rollable": False,
            "non_rollable_reason": "unresolved_reward",
            "runtime_rejection_reason": "item_authority_unresolved",
            "runtime_reachable": False,
        })
        self.assertEqual(MODULE.validate_slot_contract(slot), [])

    def test_inconsistent_rollable_state_is_rejected(self) -> None:
        slot = base_slot()
        slot["chance_valid"] = False
        slot["chance_denominator"] = None
        slot["probability_authority_resolvable"] = False
        slot["probability_policy"] = {
            "ok": False,
            "reason": "drop_probability_authority_invalid",
        }
        errors = MODULE.validate_slot_contract(slot)
        self.assertTrue(
            any("slot_runtime_rollable" in error for error in errors),
            errors,
        )

    def test_catalog_hash_drift_is_rejected(self) -> None:
        snapshot = minimal_snapshot(base_slot())
        snapshot["authority"]["catalog_sha256_after"] = "changed"
        errors = MODULE.validate_snapshot(
            snapshot,
            enforce_current_corpus=False,
        )
        self.assertTrue(
            any("changed during export" in error for error in errors),
            errors,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
