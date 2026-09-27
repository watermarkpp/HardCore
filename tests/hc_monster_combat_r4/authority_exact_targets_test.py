import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "authority_builder", ROOT / "tools/build_monster_runtime_authority.py"
)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class ExactTargetGenerationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.actual = builder.read_json(builder.OUTPUT)
        cls.expected = builder.build_payload()

    def test_three_targets_follow_present_primary_intervals(self):
        stale = copy.deepcopy(self.actual)
        for row in stale["records"]:
            if row["monster_id"] in (33, 183, 241):
                row["runtime_allowed"] = False
                row["movement"]["base_move_speed_gu_per_sec"] = 0.0
                row["movement"]["current_runtime_move_speed_gu_per_sec"] = 0.0
        result = builder.select_exact_targets(self.expected, stale, [33, 183, 241])
        before = {r["monster_id"]: r for r in stale["records"]}
        after = {r["monster_id"]: r for r in result["records"]}
        for mid, speed in {33: 0.4, 183: 2.0, 241: 2.5}.items():
            self.assertTrue(after[mid]["runtime_allowed"])
            self.assertEqual(after[mid]["movement"]["base_move_speed_gu_per_sec"], speed)
        for mid in set(after) - {33, 183, 241}:
            self.assertEqual(after[mid], before[mid], f"unselected monster {mid} changed")
        # A precise update must preserve unrelated stale rows as well; it
        # cannot silently repair nine older classification projections.
        remaining_errors = [error for error in builder.validate(stale)
                            if not any(error.startswith(f"monster_id={mid} ")
                                       for mid in (33, 183, 241))]
        self.assertEqual(builder.validate(result), remaining_errors)
        self.assertEqual(result["summary"], builder.summarize_records(result["records"]))

    def test_explicit_current_stale_set_closes_source_consistency(self):
        before = {r["monster_id"]: r for r in self.actual["records"]}
        after = {r["monster_id"]: r for r in self.expected["records"]}
        targets = [mid for mid in after if before[mid] != after[mid]]
        if not targets:
            self.assertEqual(builder.validate(self.actual), [])
            return
        result = builder.select_exact_targets(self.expected, self.actual, targets)
        self.assertEqual(builder.validate(result), [])
        for row in result["records"]:
            if row["monster_id"] not in targets:
                self.assertEqual(row, before[row["monster_id"]])

    def test_inputs_are_not_mutated(self):
        saved = copy.deepcopy(self.actual)
        builder.select_exact_targets(self.expected, self.actual, [33])
        self.assertEqual(self.actual, saved)

    def test_unknown_duplicate_and_missing_ids_fail(self):
        for ids in ([999999], [33, 33], []):
            with self.assertRaises(ValueError):
                builder.select_exact_targets(self.expected, self.actual, ids)


if __name__ == "__main__":
    unittest.main()
