"""Lock the R2/R3 runtime-closure regression contract."""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
BASELINE_PATH = ROOT / "tests/fixtures/monster_runtime_baseline_120_v1.json"


def main() -> None:
    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    baseline_ids = set(int(x) for x in baseline["runtime_ready_ids"])
    assert len(baseline_ids) == 120, f"baseline drifted: {len(baseline_ids)}"

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    by_id = {int(e["monster_id"]): e for e in catalog["entries"]}
    ready = {
        int(e["monster_id"]) for e in catalog["entries"] if bool(e.get("runtime_allowed", False))
    }
    assert ready, "no runtime_allowed monsters"

    # 1. The pre-R2/R3 approved 120 must all remain ready (no regression).
    regressed = sorted(baseline_ids - ready)
    assert not regressed, f"RUNTIME_REGRESSION_REQUIRES_REVIEW ids={regressed}"

    # 2. Every runtime_allowed monster must satisfy the full closure contract.
    for mid in sorted(ready):
        entry = by_id[mid]
        label = f"monster_id={mid}"
        status = entry.get("source_evidence", {}).get("status", {})
        assert bool(status.get("combat_identity_ok", False)), f"{label} no combat identity"
        assert bool(status.get("combat_stats_ok", False)), f"{label} combat stats incomplete"
        assert bool(status.get("ai_ok", False)), f"{label} AI unresolved"
        assert bool(status.get("timing_ok", False)), f"{label} timing incomplete"
        assert status.get("art_status") == "formal", f"{label} art not formal"
        assert bool(status.get("runtime_semantics_ok", False)), f"{label} runtime semantics not ok"
        assert bool(entry.get("editor_placement", {}).get("allowed", False)), f"{label} not placeable"

    # 3. version_difference monsters remain runtime-disabled.
    version_ids = [int(e["monster_id"]) for e in catalog["entries"] if e.get("classification") == "version_difference"]
    assert len(version_ids) == 12, f"version_difference drifted: {len(version_ids)}"
    for mid in version_ids:
        assert not bool(by_id[mid].get("runtime_allowed", False)), f"version_difference {mid} became runtime_allowed"

    print(
        "CANONICAL_MONSTER_RUNTIME_R2R3_REGRESSION_PASS: baseline=120 runtime_allowed=%d "
        "baseline_preserved=yes" % len(ready)
    )


if __name__ == "__main__":
    main()
