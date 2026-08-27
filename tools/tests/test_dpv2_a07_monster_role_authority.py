#!/usr/bin/env python3
"""Focused tests for the DPV2 A0.7 monster-role authority contract."""

from __future__ import annotations

import copy
import json
import sys
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import validate_dpv2_a07_monster_role_authority as validator  # noqa: E402


class Dpv2A07MonsterRoleAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.authority = json.loads(validator.AUTHORITY_PATH.read_text(encoding="utf-8"))
        cls.by_id = {row["canonical_monster_id"]: row for row in cls.authority["monsters"]}

    def test_formal_authority_passes_complete_contract(self) -> None:
        result = validator.validate_authority(copy.deepcopy(self.authority), repo_root=ROOT)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["canonical_monsters"], 156)
        self.assertEqual(result["enabled"], 131)
        self.assertEqual(result["disabled_non_loot"], 25)
        self.assertEqual(result["conflicts_finalized"], 32)
        self.assertEqual(result["human_frozen_overrides"], 3)

    def test_every_current_canonical_row_has_exactly_one_a_or_b_state(self) -> None:
        catalog = json.loads(validator.CATALOG_PATH.read_text(encoding="utf-8"))
        catalog_by_id = {row["monster_id"]: row for row in catalog["entries"]}
        self.assertEqual(set(self.by_id), set(catalog_by_id))
        self.assertEqual(len(self.by_id), 156)

        enabled = 0
        disabled = 0
        for monster_id, row in self.by_id.items():
            self.assertEqual(row["canonical_name"], catalog_by_id[monster_id]["canonical_name"])
            self.assertIs(row["runtime_allowed"], catalog_by_id[monster_id]["runtime_allowed"])
            state_a = (
                row["drop_enabled"] is True
                and row["drop_role"] in validator.LEGAL_ROLE_FACTORS
                and row["role_factor"] == validator.LEGAL_ROLE_FACTORS.get(row["drop_role"])
                and row["reporting_label"] is None
            )
            state_b = (
                row["drop_enabled"] is False
                and row["drop_role"] is None
                and row["role_factor"] is None
                and row["reporting_label"] == "NON_LOOT"
            )
            self.assertNotEqual(state_a, state_b, f"monster {monster_id} is not in exactly one state")
            self.assertNotEqual(row["role_factor"], 0)
            enabled += int(state_a)
            disabled += int(state_b)
        self.assertEqual((enabled, disabled), (131, 25))

    def test_all_32_conflicts_have_exact_finals_and_authority(self) -> None:
        conflict_rows = {
            monster_id: row
            for monster_id, row in self.by_id.items()
            if row["a06_source_recommendation"]["conflict"] is True
        }
        self.assertEqual(set(conflict_rows), set(validator.EXPECTED_A06_CONFLICT_RECOMMENDATIONS))
        self.assertEqual(len(conflict_rows), 32)

        for monster_id, row in conflict_rows.items():
            source = row["a06_source_recommendation"]
            self.assertEqual(
                (source["role"], source["factor"]),
                validator.EXPECTED_A06_CONFLICT_RECOMMENDATIONS[monster_id],
            )
            if monster_id in validator.HUMAN_FROZEN_OVERRIDES:
                self.assertEqual(row["assignment_authority"], "HUMAN_FROZEN")
                self.assertEqual(
                    (row["drop_role"], row["role_factor"]),
                    validator.HUMAN_FROZEN_OVERRIDES[monster_id],
                )
            else:
                self.assertEqual(
                    row["assignment_authority"],
                    "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION",
                )

        authority_counts = Counter(row["assignment_authority"] for row in self.authority["monsters"])
        self.assertEqual(
            authority_counts,
            Counter(
                {
                    "A0_6_DETERMINISTIC_ACCEPTED": 124,
                    "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION": 29,
                    "HUMAN_FROZEN": 3,
                }
            ),
        )

    def test_non_loot_is_reporting_only_and_invalid_probability_states_fail(self) -> None:
        self.assertNotIn("NON_LOOT", {row["role"] for row in self.authority["formal_probability_roles"]})
        disabled = [row for row in self.authority["monsters"] if row["drop_enabled"] is False]
        self.assertEqual(len(disabled), 25)
        self.assertTrue(
            all(
                row["drop_role"] is None
                and row["role_factor"] is None
                and row["reporting_label"] == "NON_LOOT"
                for row in disabled
            )
        )

        factor_zero = copy.deepcopy(self.authority)
        factor_zero["monsters"][0]["role_factor"] = 0
        with self.assertRaisesRegex(validator.AuthorityValidationError, "A/B state partition|factor zero"):
            validator.validate_authority(factor_zero, repo_root=ROOT)

        probability_non_loot = copy.deepcopy(self.authority)
        disabled_row = next(row for row in probability_non_loot["monsters"] if row["drop_enabled"] is False)
        disabled_row["drop_role"] = "NON_LOOT"
        disabled_row["role_factor"] = 0
        with self.assertRaisesRegex(validator.AuthorityValidationError, "A/B state partition|factor zero"):
            validator.validate_authority(probability_non_loot, repo_root=ROOT)

    def test_human_evidence_clothes_dark_cow_and_activation_are_frozen(self) -> None:
        self.assertEqual(validator._sha256(validator.DECISION_PATH), validator.DECISION_SHA256)
        self.assertEqual(
            self.authority["authority"]["decision_document_sha256"],
            validator.DECISION_SHA256,
        )
        self.assertEqual(
            {row["canonical_monster_id"]: row["canonical_item_id"] for row in self.authority["new_clothes_boss_authority"]["mappings"]},
            validator.NEW_CLOTHES_BIJECTION,
        )
        self.assertEqual(sum(row["new_clothes_eligible"] for row in self.authority["monsters"]), 6)
        dark_cow = self.by_id[225]
        self.assertEqual((dark_cow["drop_role"], dark_cow["role_factor"]), ("ENDGAME_BOSS", 16))
        self.assertIs(dark_cow["new_clothes_eligible"], False)
        self.assertEqual(
            self.authority["activation"],
            {"production_active": False, "runtime_consumer": None, "phase_1_allowed": False},
        )
        self.assertEqual(self.authority["summary"]["veteran_formal_definitions"], 0)
        self.assertEqual(self.authority["summary"]["veteran_assignments"], 0)

        wrong_override = copy.deepcopy(self.authority)
        wrong_override_by_id = {row["canonical_monster_id"]: row for row in wrong_override["monsters"]}
        wrong_override_by_id[77]["assignment_authority"] = "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION"
        with self.assertRaisesRegex(validator.AuthorityValidationError, "override 77 is not HUMAN_FROZEN|distribution"):
            validator.validate_authority(wrong_override, repo_root=ROOT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
