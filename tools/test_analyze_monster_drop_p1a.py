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


def compiled_row() -> dict:
    runtime_slot = {
        "slot_uid": "dpv2.direct.m18.slot_001",
        "base_numerator": 1,
        "base_denominator": 3,
        "overflow_priority": 200,
        "protected_drop": False,
        "baseline_origin": "LEGACY_21CQ_MONITEMS",
        "source_provenance_id": "dpv2.source.m18.slot_001",
        "canonical_item_id": 920039,
    }
    return {
        "source_profile_id": "drop.18",
        "runtime_profile_id": "dpv2.direct.18",
        "canonical_monster_id": 18,
        "source_entry_ordinal_zero_based": 0,
        "source_entry_ordinal_one_based": 1,
        "source_line_number": 1,
        "source_slot_index": "slot_001",
        "source_item_label": "测试物品",
        "source_raw_text": "1/3 测试物品",
        "source_chance": "1/3",
        "source_chance_denominator": 3,
        "source_chance_valid": True,
        "source_rate_policy": "AUDIT_ONLY",
        "source_slot_status": "CONFIRMED_SOURCE_SLOT",
        "source_kind": "EXISTING_AUDITED_SLOTS",
        "source_ref": "fixture",
        "source_entry": {
            "chance": "1/3",
            "rate_policy": "AUDIT_ONLY",
            "slot_status": "CONFIRMED_SOURCE_SLOT",
        },
        "runtime_compiled": True,
        "runtime_reward_resolved": True,
        "runtime_probability_resolved": True,
        "runtime_rng_eligible": True,
        "runtime_rng_eligible_before_overflow": True,
        "runtime_rejection_reason": "",
        "runtime_slot": runtime_slot,
        "slot_uid": runtime_slot["slot_uid"],
        "source_provenance_id": runtime_slot["source_provenance_id"],
        "canonical_item_id": 920039,
        "gold_amount": None,
        "reward_kind": "item",
        "item_name": "测试物品",
        "baseline_origin": "LEGACY_21CQ_MONITEMS",
        "base_numerator": 1,
        "base_denominator": 3,
        "base_probability": 1 / 3,
        "global_preset": "1x",
        "global_scale_numerator": 1,
        "global_scale_denominator": 1,
        "global_scale": 1.0,
        "final_numerator": 1,
        "final_denominator": 3,
        "final_probability": 1 / 3,
        "overflow_priority": 200,
        "protected_drop": False,
    }


def disabled_row() -> dict:
    row = compiled_row()
    row.update({
        "source_profile_id": "drop.226",
        "runtime_profile_id": "",
        "canonical_monster_id": 226,
        "source_item_label": "金币",
        "source_raw_text": "1/2 金币 3000",
        "source_chance": "1/2",
        "source_chance_denominator": 2,
        "source_slot_index": "slot_001",
        "source_entry": {
            "chance": "1/2",
            "rate_policy": "AUDIT_ONLY",
            "slot_status": "CONFIRMED_SOURCE_SLOT",
        },
        "runtime_compiled": False,
        "runtime_reward_resolved": False,
        "runtime_probability_resolved": False,
        "runtime_rng_eligible": False,
        "runtime_rng_eligible_before_overflow": False,
        "runtime_rejection_reason": "non_loot_profile",
        "runtime_slot": None,
        "slot_uid": "",
        "source_provenance_id": "",
        "canonical_item_id": None,
        "gold_amount": None,
        "reward_kind": "",
        "item_name": "",
        "baseline_origin": "",
        "base_numerator": None,
        "base_denominator": None,
        "base_probability": None,
        "global_preset": "",
        "global_scale_numerator": None,
        "global_scale_denominator": None,
        "global_scale": None,
        "final_numerator": None,
        "final_denominator": None,
        "final_probability": None,
        "overflow_priority": None,
        "protected_drop": None,
    })
    return row


def minimal_snapshot(rows: list[dict]) -> dict:
    profiles = [{
        "source_profile_id": "drop.18",
        "canonical_monster_id": 18,
    }]
    compiled_profiles = [{
        "runtime_profile_id": "dpv2.direct.18",
        "canonical_monster_id": 18,
        "drop_enabled": True,
    }]
    compiled = [
        row for row in rows
        if bool(row.get("runtime_compiled", False))
    ]
    summary = MODULE._recompute_summary(
        rows,
        compiled,
        profiles,
        compiled_profiles,
    )
    return {
        "schema": MODULE.SNAPSHOT_SCHEMA,
        "authority": {
            "catalog_sha256_before": "same",
            "catalog_sha256_after": "same",
            "runtime_authority": {
                "authority_id": "dpv2.direct_baseline.v2",
                "schema": "hardcore.dpv2.direct_monster_drop_baseline.v2",
                "production_runtime": "V2_DIRECT_BASELINE",
                "identity_key": "canonical_monster_id",
                "direct_profile_join": "canonical_monster_id_exact",
                "source_profile_id_is_audit_only": True,
                "fallback_forbidden": True,
            },
            "source_corpus_is_audit_only": True,
            "compiled_runtime_is_rng_authority": True,
            "overflow_stage": "after_all_probability_rolls",
            "source_slot_gate": {
                "available": True,
                "authority": "dpv2.direct_baseline.v2",
                "compiled_slots": len(compiled),
                "maximum_ground_slots": 9,
            },
        },
        "direct_baseline_summary": {},
        "source_summary": summary["source_corpus"],
        "compiled_runtime_summary": summary["compiled_runtime"],
        "summary": summary,
        "correction_provenance": {},
        "source_profiles": profiles,
        "compiled_profiles": compiled_profiles,
        "source_rows": rows,
        "compiled_slots": compiled,
    }


class P1ADirectAnalyzerContractTest(unittest.TestCase):
    def test_compiled_row_contract(self) -> None:
        self.assertEqual(MODULE.validate_source_row_contract(compiled_row()), [])

    def test_source_provenance_does_not_change_runtime_semantics(self) -> None:
        original = compiled_row()
        changed = copy.deepcopy(original)
        changed["source_chance"] = "1/00"
        changed["source_chance_valid"] = False
        changed["source_chance_denominator"] = None
        changed["source_raw_text"] = "1/00 测试物品"
        self.assertEqual(
            MODULE.runtime_semantics_key(original),
            MODULE.runtime_semantics_key(changed),
        )
        self.assertEqual(MODULE.validate_source_row_contract(changed), [])

    def test_non_loot_source_row_cannot_enter_rng(self) -> None:
        self.assertEqual(
            MODULE.validate_source_row_contract(disabled_row()),
            [],
        )
        rejected = disabled_row()
        rejected["runtime_rng_eligible"] = True
        errors = MODULE.validate_source_row_contract(rejected)
        self.assertTrue(any("NON_LOOT" in error for error in errors), errors)

    def test_invalid_direct_identity_is_rejected(self) -> None:
        row = compiled_row()
        row["canonical_item_id"] = None
        errors = MODULE.validate_source_row_contract(row)
        self.assertTrue(any("canonical ID" in error for error in errors), errors)

    def test_source_and_compiled_summary_closes(self) -> None:
        snapshot = minimal_snapshot([compiled_row(), disabled_row()])
        errors = MODULE.validate_snapshot(
            snapshot,
            enforce_current_corpus=False,
        )
        self.assertEqual(errors, [], errors)

    def test_summary_tamper_is_rejected(self) -> None:
        snapshot = minimal_snapshot([compiled_row()])
        snapshot["summary"]["source_corpus"]["row_count"] = 99
        errors = MODULE.validate_snapshot(
            snapshot,
            enforce_current_corpus=False,
        )
        self.assertTrue(any("summary does not equal" in error for error in errors))

    def test_duplicate_compiled_slot_is_rejected(self) -> None:
        snapshot = minimal_snapshot([compiled_row()])
        snapshot["compiled_slots"].append(copy.deepcopy(compiled_row()))
        errors = MODULE.validate_snapshot(
            snapshot,
            enforce_current_corpus=False,
        )
        self.assertTrue(any("collision" in error for error in errors), errors)

    def test_malformed_correction_fixture(self) -> None:
        row = compiled_row()
        row.update({
            "source_profile_id": "drop.168",
            "canonical_monster_id": 168,
            "source_line_number": 20,
            "source_entry_ordinal_zero_based": 19,
            "source_entry_ordinal_one_based": 20,
            "source_slot_index": "slot_020",
            "source_chance": "1/00",
            "source_chance_denominator": None,
            "source_chance_valid": False,
            "source_raw_text": "1/00 灵魂战衣(男)",
            "runtime_profile_id": "dpv2.direct.168",
            "runtime_slot": {
                **row["runtime_slot"],
                "slot_uid": "dpv2.direct.m168.slot_020",
                "source_provenance_id": "dpv2.source.m168.slot_020",
                "base_denominator": 2800,
            },
            "slot_uid": "dpv2.direct.m168.slot_020",
            "source_provenance_id": "dpv2.source.m168.slot_020",
            "base_denominator": 2800,
            "final_denominator": 2800,
            "final_probability": 1 / 2800,
            "source_entry": {
                "chance": "1/00",
                "rate_policy": "AUDIT_ONLY",
                "slot_status": "CONFIRMED_SOURCE_SLOT",
            },
        })
        snapshot = minimal_snapshot([row])
        snapshot["correction_provenance"] = {
            **MODULE.EXPECTED_ANOMALY,
            "path": "assets/data/drop/dpv2_21cq_source_corrections_v1.json",
        }
        errors = MODULE.validate_snapshot(
            snapshot,
            enforce_current_corpus=False,
        )
        self.assertEqual(errors, [], errors)


if __name__ == "__main__":
    unittest.main(verbosity=2)
