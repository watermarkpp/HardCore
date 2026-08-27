from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

TOOL_PATH = TOOLS / "verify_source_priority_policy.py"
SPEC = importlib.util.spec_from_file_location("source_priority_policy_verifier", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class SourcePriorityPolicyVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = load_json(ROOT / "assets/data/source_priority_policy.json")

    def test_eighth_lane_is_required_and_drop_only_contract_passes(self) -> None:
        self.assertEqual(set(self.policy["lanes"]), verifier.EXPECTED_LANES)

        checks: dict[str, bool] = {}
        verifier._check_monster_drop_lane(self.policy, checks)

        self.assertEqual(
            checks,
            {
                "monsterDropProbabilityRouting": True,
                "monsterDropProbabilityPrimaryIsProjectMaster": True,
                "monsterDropProbabilityScopeIsDropOnly": True,
            },
        )

    def test_drop_only_scope_rejects_missing_or_extra_exclusions(self) -> None:
        for mutation in ("missing", "extra"):
            policy = copy.deepcopy(self.policy)
            exclusions = policy["lanes"]["monster_drop_probability"][
                "scopeExclusions"
            ]["server_data"]
            if mutation == "missing":
                exclusions.remove("item_attributes")
            else:
                exclusions.append("unrelated_scope")

            checks: dict[str, bool] = {}
            verifier._check_monster_drop_lane(policy, checks)

            self.assertFalse(
                checks["monsterDropProbabilityScopeIsDropOnly"],
                mutation,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
