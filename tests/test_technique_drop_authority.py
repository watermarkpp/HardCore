"""RED contract tests for technique-necklace instance rolls and item 251 removal.

These tests exercise the public authority boundaries after the production
rule/compiler change. They compare the current loot authority to a compact
freeze manifest captured immediately before the exact item-251 deletion.
"""

import json
import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"
TARGET_UID = "dpv2.direct.m160.slot_070"


def _read_json_bytes(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _frozen_before_authority() -> dict:
    return _read_json_bytes(ROOT / "tests/fixtures/technique_drop_authority_before.json")


def _slot_index(doc: dict) -> dict[str, tuple[int, dict]]:
    result = {}
    for monster in doc.get("monsters", []):
        monster_id = int(monster["monster_id"])
        for slot in monster.get("slots", []):
            result[str(slot["slot_uid"])] = (monster_id, slot)
    return result


def _ordered_non_target_sha(doc: dict, target_uid: str) -> str:
    records = []
    for monster in doc.get("monsters", []):
        monster_id = int(monster["monster_id"])
        for slot in monster.get("slots", []):
            if str(slot["slot_uid"]) != target_uid:
                records.append([monster_id, slot])
    encoded = "\n".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        for record in records
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


class TechniqueDropAuthorityRedTest(unittest.TestCase):
    def test_item_251_target_uid_is_removed_and_every_other_slot_is_unchanged(self):
        before = _frozen_before_authority()
        after = _read_json_bytes(AUTHORITY)
        expected = before["target_slot"]
        after_slots = _slot_index(after)

        self.assertEqual(before["target_uid"], TARGET_UID)
        self.assertEqual(before["pre_change_total_slots"], len(after_slots) + 1)
        self.assertEqual(expected["canonical_item_id"], 251)
        self.assertNotIn(TARGET_UID, after_slots, "item 251 target UID is still present")
        self.assertEqual(_ordered_non_target_sha(after, TARGET_UID), before["non_target_ordered_sha256"])

    def test_no_item_251_drop_identity_remains(self):
        after = _read_json_bytes(AUTHORITY)
        remaining = [
            slot
            for monster in after.get("monsters", [])
            for slot in monster.get("slots", [])
            if int(slot.get("canonical_item_id", -1)) == 251
        ]
        self.assertEqual(remaining, [])

    def test_technique_rule_script_exposes_the_six_api_contracts(self):
        source = ROOT / "scripts/equipment_random_special_instance_rules.gd"
        self.assertTrue(source.exists(), "RED: dedicated rules script is missing")
        text = source.read_text(encoding="utf-8")
        required = (
            "is_technique_necklace",
            "allowed_technique_skill_ids",
            "create_technique_instance",
            "validate_technique_instance",
            "technique_skill_level_modifiers",
        )
        for symbol in required:
            self.assertIn(symbol, text, f"RED: missing public API {symbol}")


if __name__ == "__main__":
    unittest.main()
