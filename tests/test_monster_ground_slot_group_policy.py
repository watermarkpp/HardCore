import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/drop/monster_ground_slot_group_policy.source.json"
RUNTIME = ROOT / "assets/data/drop/monster_ground_slot_group_policy.runtime.json"
CLASSIFICATION = ROOT / "assets/data/canonical_monster_classification_v1.json"

spec = importlib.util.spec_from_file_location(
    "build_monster_ground_slot_group_policy",
    ROOT / "tools/build_monster_ground_slot_group_policy.py",
)
assert spec and spec.loader
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class MonsterGroundSlotGroupPolicyTest(unittest.TestCase):
    def test_generated_policy_matches_authoring_and_canonical_classes(self):
        expected = builder.render(builder.build())
        self.assertEqual(RUNTIME.read_text(encoding="utf-8"), expected)
        source = json.loads(SOURCE.read_text(encoding="utf-8"))
        runtime = json.loads(RUNTIME.read_text(encoding="utf-8"))
        self.assertEqual(
            {name: row["ground_slot_limit"] for name, row in source["groups"].items()},
            {"ordinary": 6, "elite": 9, "boss": 12},
        )
        self.assertEqual(runtime["source_authority"]["schema"], source["schema"])
        classes = {
            row["classification"]
            for row in json.loads(CLASSIFICATION.read_text(encoding="utf-8"))["exact_id_overrides"].values()
        }
        self.assertTrue({"ordinary", "elite", "boss"}.issubset(classes))

    def test_builder_rejects_unknown_policy_class(self):
        original_path = builder.SOURCE
        original = json.loads(SOURCE.read_text(encoding="utf-8"))
        invalid_sources = []
        unknown = json.loads(json.dumps(original))
        unknown["groups"]["special"] = {"ground_slot_limit": 12}
        invalid_sources.append(unknown)
        decimal = json.loads(json.dumps(original))
        decimal["groups"]["ordinary"]["ground_slot_limit"] = 6.5
        invalid_sources.append(decimal)
        boolean = json.loads(json.dumps(original))
        boolean["groups"]["elite"]["ground_slot_limit"] = True
        invalid_sources.append(boolean)
        contract = json.loads(json.dumps(original))
        contract["selection_contract"]["stage"] = "BEFORE_RNG"
        invalid_sources.append(contract)
        with tempfile.TemporaryDirectory() as temp_dir:
            try:
                for index, invalid in enumerate(invalid_sources):
                    path = Path(temp_dir) / f"invalid_{index}.json"
                    path.write_text(json.dumps(invalid), encoding="utf-8")
                    builder.SOURCE = path
                    with self.assertRaises(ValueError):
                        builder.build()
            finally:
                builder.SOURCE = original_path
        self.assertEqual(json.loads(SOURCE.read_text(encoding="utf-8")), original)
        self.assertEqual(json.loads(RUNTIME.read_text(encoding="utf-8"))["groups"]["ordinary"]["ground_slot_limit"], 6)


if __name__ == "__main__":
    unittest.main()
