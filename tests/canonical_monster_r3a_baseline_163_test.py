"""Lock the R3A runtime baseline (163) as a non-regressible subset.

The R3A 163 subset is derived from the frozen R3A commit 22d87986 catalog
(159 R2 baseline + 4 R3A additions: ID14 鸡, ID16 鹿, ID56 骷髅精灵, ID89 尸王).
R3B added ID45 蝎子 via exact drop alias closure (runtime_allowed=164); ID45 is
asserted present but is not part of the frozen 163 list. Every runtime_allowed
monster must also satisfy the full closure contract.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"

# Exact R3A-closed baseline: 163 runtime_allowed ids after R3A, locked from the
# R3A commit 22d87986 catalog (159 + ID14/16/56/89). Do not hand-edit; derive
# from the R3A commit catalog if a new R3B/R3C round changes readiness.
R3A_BASELINE_163 = {
    14, 16, 18, 19, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37,
    38, 39, 42, 43, 44, 46, 56, 60, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 73,
    74, 75, 76, 89, 92, 93, 94, 95, 96, 97, 98, 100, 101, 102, 103, 104, 105,
    106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
    122, 124, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
    140, 141, 142, 143, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158,
    159, 160, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174,
    175, 176, 177, 178, 179, 185, 188, 189, 191, 192, 193, 194, 196, 197, 198,
    199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213,
    214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 234, 235, 236, 237,
    238, 239, 240,
}
assert len(R3A_BASELINE_163) == 163, f"R3A baseline set must be 163, got {len(R3A_BASELINE_163)}"


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    by_id = {int(e["monster_id"]): e for e in catalog["entries"]}
    ready = {int(e["monster_id"]) for e in catalog["entries"] if bool(e.get("runtime_allowed", False))}

    regressed = sorted(R3A_BASELINE_163 - ready)
    assert not regressed, f"R3A_BASELINE_163_REGRESSED ids={regressed}"

    # R3A additions must be present. ID45 belongs to the R3B 164 baseline and is
    # locked by canonical_monster_r3b_baseline_164_test.py, not here.
    for mid in (14, 16, 56, 89):
        assert mid in ready, f"R3A addition {mid} not runtime_allowed"

    # Full closure contract for every ready monster.
    for mid in sorted(ready):
        entry = by_id[mid]
        status = entry.get("source_evidence", {}).get("status", {})
        label = f"monster_id={mid}"
        assert bool(status.get("combat_identity_ok", False)), f"{label} no combat identity"
        assert bool(status.get("combat_stats_ok", False)), f"{label} combat stats incomplete"
        assert bool(status.get("ai_ok", False)), f"{label} AI unresolved"
        assert bool(status.get("timing_ok", False)), f"{label} timing incomplete"
        assert status.get("art_status") == "formal", f"{label} art not formal"
        assert bool(status.get("runtime_semantics_ok", False)), f"{label} runtime semantics not ok"
        assert bool(entry.get("editor_placement", {}).get("allowed", False)), f"{label} not placeable"

    print(
        "CANONICAL_MONSTER_R3A_BASELINE_163_PASS: baseline_163=%d runtime_allowed=%d "
        "baseline_163_preserved=yes" % (len(R3A_BASELINE_163), len(ready))
    )


if __name__ == "__main__":
    main()
