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
