from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER_PATH = ROOT / "tools/build_canonical_monster_catalog.py"
sys.path.insert(0, str(ROOT / "tools"))
SPEC = importlib.util.spec_from_file_location("special_normal_catalog_builder", BUILDER_PATH)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class SpecialNormalMonsterSpawnAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.authority = builder.load_json(builder.SPECIAL_NORMAL_AUTHORITY_PATH)
        self.vanilla = builder.load_json(builder.VANILLA_PATH)

    def validate(self, authority):
        return builder.validate_special_normal_authority(authority, self.vanilla)

    def test_exact_eight_and_spawn_only_contract(self) -> None:
        rows = self.validate(copy.deepcopy(self.authority))
        self.assertEqual(set(rows), {39, 57, 74, 77, 90, 121, 137, 142})
        self.assertEqual(rows[74]["combat_classification"], "elite")
        self.assertEqual(rows[74]["spawn"], builder.SPECIAL_NORMAL_DEFAULTS)
        self.assertEqual(
            self.authority["drop_probability"],
            builder.SPECIAL_NORMAL_DROP_PROBABILITY_POLICY,
        )
        self.assertNotIn(
            "assets/data/drop/dpv2_monster_role_authority_v1.json",
            {source["path"] for source in self.authority["authority"]["sources"]},
        )
        for row in self.authority["records"]:
            self.assertEqual(
                set(row), {"monster_id", "canonical_name", "combat_classification", "spawn"}
            )

    def test_name_widening_and_spawn_drift_fail_closed(self) -> None:
        widened = copy.deepcopy(self.authority)
        widened["scope"]["selection"] = "name_suffix"
        with self.assertRaisesRegex(RuntimeError, "selection is not exact-ID"):
            self.validate(widened)
        drifted = copy.deepcopy(self.authority)
        drifted["records"][0]["spawn"]["respawn_seconds"] = 480
        with self.assertRaisesRegex(RuntimeError, "spawn policy drift"):
            self.validate(drifted)


if __name__ == "__main__":
    unittest.main()
