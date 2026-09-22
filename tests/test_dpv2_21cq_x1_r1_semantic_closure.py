from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json"
TOOL_PATH = ROOT / "tools/validate_dpv2_21cq_x1_r1_semantic_closure.py"
SPEC = importlib.util.spec_from_file_location(
    "dpv2_21cq_x1_r1_semantic_validator", TOOL_PATH
)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class SemanticClosureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.authority = load_json(AUTHORITY_PATH)

    def test_validator_closes_all_authorities(self) -> None:
        result = validator.validate_authority()
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["canonical_monsters"], 156)
        self.assertEqual(result["runtime_allowed"], 153)
        self.assertEqual(result["drop_enabled"], 144)
        self.assertEqual(result["explicit_non_loot"], 9)
        self.assertEqual(result["runtime_disabled"], 3)
        self.assertEqual(result["production_slots"], 6809)
        self.assertEqual(result["restored_slots"], 814)
        self.assertEqual(result["existing_slot_drift"], 0)
        self.assertEqual(result["x1_probability_mismatch"], 0)
        self.assertEqual(result["duplicate_slot_collapse"], 0)

    def test_frozen_semantic_partition_and_direct_counts(self) -> None:
        expected_direct = {
            79: 59,
            81: 60,
            83: 59,
            85: 59,
            87: 59,
            226: 1,
            227: 36,
            228: 51,
            229: 36,
            230: 64,
            231: 57,
            232: 95,
            233: 96,
            234: 82,
        }
        frozen = self.authority["frozen_decisions"]
        direct = {
            int(row["canonical_monster_id"]): int(row["source_row_count"])
            for row in frozen["direct_21cq"]
        }
        self.assertEqual(direct, expected_direct)
        self.assertEqual(set(frozen["runtime_disabled"]), {33, 183, 241})
        self.assertEqual(
            frozen["project_extension"],
            {"canonical_monster_id": 225, "source_row_count": 69},
        )

        records = {
            int(row["canonical_monster_id"]): row
            for row in self.authority["records"]
        }
        explicit = {59, 78, 145, 146, 147, 161, 186, 187, 194}
        self.assertEqual(
            {monster_id for monster_id, row in records.items()
             if row["semantic_status"] == "EXPLICIT_NON_LOOT"},
            explicit,
        )
        self.assertEqual(
            {monster_id: records[monster_id]["source_row_count"]
             for monster_id in (145, 146, 147)},
            {145: 74, 146: 78, 147: 71},
        )
        self.assertTrue(
            all(
                row["exemption"]["required"] is True
                and row["exemption"]["kind"] == "EXPLICIT_NON_LOOT"
                for monster_id, row in records.items()
                if monster_id in explicit
            )
        )

    def test_semantic_rows_have_formal_state_reason_evidence_and_freeze_flag(self) -> None:
        records = {
            int(row["canonical_monster_id"]): row
            for row in self.authority["records"]
        }
        expected_reasons = {
            145: "SUMMON_OR_EVENT_COMBAT_ENTITY",
            146: "SUMMON_OR_EVENT_COMBAT_ENTITY",
            147: "SUMMON_OR_EVENT_COMBAT_ENTITY",
            59: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
            78: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
            161: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
            186: "TAMEABLE_CURRENT_EXEMPTION",
            187: "TAMEABLE_CURRENT_EXEMPTION",
            194: "GUARD_SCRIPT_CURRENT_EXEMPTION",
            225: "PROJECT_EXTENSION",
            33: "RUNTIME_DISABLED",
            183: "RUNTIME_DISABLED",
            241: "RUNTIME_DISABLED",
        }
        for monster_id, row in records.items():
            self.assertEqual(row["drop_semantic_state"], row["semantic_status"])
            self.assertIsInstance(row["reason_code"], str)
            self.assertTrue(row["reason_code"])
            self.assertIsInstance(row["evidence"], dict)
            self.assertTrue(row["evidence"])
            self.assertIs(type(row["human_frozen"]), bool)
            self.assertEqual(
                row["evidence"]["source_row"]["count"],
                row["source_row_count"],
            )
            self.assertIn("classification_path", row["evidence"])
        for monster_id, reason in expected_reasons.items():
            self.assertEqual(records[monster_id]["reason_code"], reason)
            self.assertTrue(records[monster_id]["human_frozen"])
        self.assertTrue(
            all(
                row["human_frozen"] is True
                for monster_id, row in records.items()
                if monster_id in {79, 81, 83, 85, 87, 226, 227, 228, 229, 230, 231, 232, 233, 234}
            )
        )
        self.assertTrue(
            all(
                row["human_frozen"] is False
                and row["reason_code"] == "DIRECT_CATALOG_SOURCE_EXACT"
                for monster_id, row in records.items()
                if row["semantic_status"] == "DIRECT_21CQ"
                and monster_id not in {79, 81, 83, 85, 87, 226, 227, 228, 229, 230, 231, 232, 233, 234}
            )
        )
        for monster_id in (33, 183, 241):
            runtime_evidence = records[monster_id]["evidence"]["runtime_evidence"]
            self.assertIs(runtime_evidence["runtime_allowed"], False)
            self.assertTrue(runtime_evidence["script_path"])
            self.assertTrue(runtime_evidence["effect_path"])
            self.assertTrue(runtime_evidence["runtime_path"])

    def test_semantic_authority_has_no_legacy_probability_axes(self) -> None:
        text = json.dumps(self.authority, ensure_ascii=False).lower()
        for forbidden in ("tier", "role", "factor"):
            self.assertNotIn(forbidden, text)

    def test_missing_explicit_exemption_fails_closed(self) -> None:
        tampered = copy.deepcopy(self.authority)
        record = next(
            row
            for row in tampered["records"]
            if row["canonical_monster_id"] == 145
        )
        record["exemption"] = None
        with self.assertRaises(validator.SemanticClosureValidationError):
            validator.validate_authority(tampered)


if __name__ == "__main__":
    unittest.main()
