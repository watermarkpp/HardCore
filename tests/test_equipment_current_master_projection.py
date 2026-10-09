import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "equipment_master_builder", ROOT / "tools/build_equipment_attribute_master.py"
)
BUILDER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILDER)


def record(item_id: int, metadata: dict) -> dict:
    return {
        "itemId": item_id,
        "weight": 1,
        "durability": 5,
        "jobAffinity": "general",
        "jobAffinityLabel": "通用",
        "jobLock": None,
        "requirementType": "level",
        "requirementValue": 18,
        "legacyNeed": 0,
        "legacyNeedLevel": 18,
        "genderRestriction": None,
        "weightRequirementType": "wear",
        "weightRequirementValue": 1,
        "rollPolicy": "legacy_clamp_negative_span",
        "setId": "mystery_set",
        "specialEffectId": "mystery_random_stats",
        "specialEffectDescription": "random",
        **metadata,
        "stats": {},
        "warnings": [],
        "source": {"tier": "primary"},
    }


class CurrentMasterProjectionTests(unittest.TestCase):
    def test_check_only_projects_exact_targets_and_preserves_non_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            master_path = root / "master.json"
            items_path = root / "items.json"
            master = {"records": [record(218, {"randomInstanceRule": {"family": "helmet"}}), record(221, {})]}
            catalog = {"records": [record(218, {}), record(221, {})]}
            master_path.write_text(json.dumps(master), encoding="utf-8")
            items_path.write_text(json.dumps(catalog), encoding="utf-8")
            old_master, old_items = BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH
            try:
                BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH = master_path, items_path
                before = items_path.read_bytes()
                audit = BUILDER.project_current_master_items([218], write_outputs=False, audit_output=None)
                self.assertEqual(audit["itemIds"], [218])
                self.assertEqual(items_path.read_bytes(), before)
            finally:
                BUILDER.MASTER_PATH, BUILDER.ITEMS_PATH = old_master, old_items

    def test_unknown_or_duplicate_ids_fail_closed(self):
        with self.assertRaises(RuntimeError):
            BUILDER.project_current_master_items([218, 218], write_outputs=False, audit_output=None)


if __name__ == "__main__":
    unittest.main()
