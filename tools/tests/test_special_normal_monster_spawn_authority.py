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
        self.roles = builder.load_json(builder.DPV2_ROLE_AUTHORITY_PATH)
        self.tiers = builder.load_json(builder.DPV2_ITEM_TIER_AUTHORITY_PATH)

    def validate(self, authority):
        return builder.validate_special_normal_authority(
            authority, self.vanilla, self.roles, self.tiers
        )

    def test_exact_eight_and_global_drop_binding(self) -> None:
        rows = self.validate(copy.deepcopy(self.authority))
        self.assertEqual(set(rows), {39, 57, 74, 77, 90, 121, 137, 142})
        self.assertEqual(rows[74]["combat_classification"], "elite")
        self.assertEqual(rows[74]["drop_role"], "ELITE")
        self.assertEqual(rows[74]["role_factor"], 3)
        self.assertIsNone(rows[74]["additional_multiplier"])

    def test_name_widening_and_custom_multiplier_fail_closed(self) -> None:
        widened = copy.deepcopy(self.authority)
        widened["scope"]["selection"] = "name_suffix"
        with self.assertRaisesRegex(RuntimeError, "selection is not exact-ID"):
            self.validate(widened)
        multiplied = copy.deepcopy(self.authority)
        multiplied["records"][0]["additional_multiplier"] = 2
        with self.assertRaisesRegex(RuntimeError, "adds a drop multiplier"):
            self.validate(multiplied)


if __name__ == "__main__":
    unittest.main()
