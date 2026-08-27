#!/usr/bin/env python3
"""Focused tests for the non-runtime DPV2 A0.7 item Tier authority."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "tools" / "validate_dpv2_a07_item_tier_authority.py"
AUTHORITY_PATH = ROOT / "assets" / "data" / "drop" / "dpv2_item_tier_authority_v1.json"
A05_PATH = ROOT / "outputs" / "drop" / "dpv2_item_tier_seed_candidate.json"
A06_PATH = ROOT / "assets" / "data" / "drop" / "dpv2_item_identity_authority_v1.json"
DECISION_PATH = ROOT / "docs" / "drop" / "DPV2_A07_HUMAN_AUTHORITY_DECISION.md"

_SPEC = importlib.util.spec_from_file_location(
    "validate_dpv2_a07_item_tier_authority", VALIDATOR_PATH
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError(f"cannot load validator: {VALIDATOR_PATH}")
_VALIDATOR = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_VALIDATOR)


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class Dpv2A07ItemTierAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.authority = _load(AUTHORITY_PATH)
        self.a05 = _load(A05_PATH)
        self.a06 = _load(A06_PATH)

    def _validate(self, authority: dict | None = None) -> dict:
        return _VALIDATOR.validate_authority_documents(
            authority or self.authority,
            self.a05,
            self.a06,
            repo_root=ROOT,
            authority_path=AUTHORITY_PATH,
            a05_seed_path=A05_PATH,
            a06_identity_path=A06_PATH,
            decision_document_path=DECISION_PATH,
        )

    def test_full_closure_is_233_resolved_and_unique(self) -> None:
        result = self._validate()
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["authority_records"], 233)
        self.assertEqual(result["unique_canonical_ids"], 233)
        self.assertEqual(result["unique_canonical_names"], 233)
        self.assertEqual(result["resolved_items"], 233)
        self.assertEqual(result["unresolved_items"], 0)
        self.assertEqual(result["a05_accepted_tiers"], 225)
        self.assertEqual(result["a07_human_decisions"], 8)
        self.assertEqual(result["tier_status_counts"], {"RESOLVED": 233})

    def test_taxonomy_and_exact_eight_decisions(self) -> None:
        result = self._validate()
        self.assertEqual(result["tier_counts"]["BOSS_KEY_ITEM"], 2)
        self.assertEqual(result["tier_counts"]["MONSTER_MATERIAL"], 6)
        by_id = {int(row["canonical_item_id"]): row for row in self.authority["records"]}
        expected = {
            920023: ("沃玛号角", "BOSS_KEY_ITEM", True, 200),
            920032: ("祖玛头像", "BOSS_KEY_ITEM", True, 200),
            920037: ("肉", "MONSTER_MATERIAL", False, 100),
            920038: ("蛆卵", "MONSTER_MATERIAL", False, 100),
            920039: ("蜘蛛牙", "MONSTER_MATERIAL", False, 100),
            920040: ("蝎尾", "MONSTER_MATERIAL", False, 100),
            920049: ("食人花叶", "MONSTER_MATERIAL", False, 100),
            920050: ("食人花果", "MONSTER_MATERIAL", False, 100),
        }
        self.assertEqual(set(expected), set(by_id) & set(expected))
        for canonical_id, (name, tier, protected, priority) in expected.items():
            row = by_id[canonical_id]
            self.assertEqual(row["canonical_name"], name)
            self.assertEqual(row["tier"], tier)
            self.assertEqual(row["base_denominator"], 32)
            self.assertIsNone(row["denominator_override"])
            self.assertIs(row["protected_drop"], protected)
            self.assertEqual(row["overflow_priority"], priority)
            self.assertNotIn(row["tier"], {"FUNCTIONAL_SPECIAL", "COLLECTOR_LOW"})
            self.assertEqual(row["authority_basis"], "A0_7_HUMAN_AUTHORITY_DECISION")

    def test_non_runtime_and_source_rate_is_provenance_only(self) -> None:
        self.assertEqual(
            self.authority["activation"],
            {
                "production_active": False,
                "phase1_allowed": False,
                "runtime_consumer": None,
                "persistence_consumer": None,
            },
        )
        self.assertEqual(self._validate()["source_rate_role"], "provenance_only")
        for row in self.authority["records"]:
            self.assertEqual(row["source_rate_provenance"]["role"], "provenance_only")
            self.assertFalse(row["source_rate_provenance"]["used_for_tier"])
            self.assertFalse(row["source_rate_provenance"]["used_for_denominator"])

    def test_duplicate_id_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.authority)
        mutated["records"][1]["canonical_item_id"] = mutated["records"][0]["canonical_item_id"]
        with self.assertRaises(_VALIDATOR.AuthorityValidationError):
            self._validate(mutated)

    def test_stale_status_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.authority)
        mutated["records"][0]["tier_status"] = "WAITING_HUMAN_AUTHORITY"
        with self.assertRaises(_VALIDATOR.AuthorityValidationError):
            self._validate(mutated)

    def test_a06_identity_parity_is_rejected_on_id_drift(self) -> None:
        mutated = copy.deepcopy(self.authority)
        row = next(row for row in mutated["records"] if row["identity_source"] == "A0_6_ITEM_IDENTITY_AUTHORITY")
        row["canonical_item_id"] += 1
        with self.assertRaises(_VALIDATOR.AuthorityValidationError):
            self._validate(mutated)

    def test_per_item_denominator_override_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.authority)
        mutated["records"][0]["denominator_override"] = 99
        with self.assertRaises(_VALIDATOR.AuthorityValidationError):
            self._validate(mutated)


if __name__ == "__main__":
    unittest.main()
