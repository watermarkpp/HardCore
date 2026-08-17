"""Lock the R3B runtime baseline (164) as a non-regressible subset.

The 164 subset is the current full runtime_allowed set (R3A 163 + R3B ID45).
Anchors: ID14 鸡, ID16 鹿, ID45 蝎子, ID56 骷髅精灵, ID89 尸王 (R3A/R3B
additions), ID239 暗之沃玛教主, ID240 (frozen drop anchors). Every
runtime_allowed monster must also satisfy the full closure contract.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"

# Exact R3B-closed baseline: 164 runtime_allowed ids after R3B (R3A 163 + ID45),
# derived from the R3B commit b707dfb3 catalog.
R3B_BASELINE_164 = {
    14, 16, 18, 19, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37,
    38, 39, 42, 43, 44, 45, 46, 56, 60, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71,
    73, 74, 75, 76, 89, 92, 93, 94, 95, 96, 97, 98, 100, 101, 102, 103, 104,
    105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120,
    121, 122, 124, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138,
    139, 140, 141, 142, 143, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
    158, 159, 160, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    174, 175, 176, 177, 178, 179, 185, 188, 189, 191, 192, 193, 194, 196, 197,
    198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212,
    213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 234, 235, 236,
    237, 238, 239, 240,
}
assert len(R3B_BASELINE_164) == 164, f"R3B baseline set must be 164, got {len(R3B_BASELINE_164)}"

ANCHOR_IDS = (14, 16, 45, 56, 89, 239, 240)


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    by_id = {int(e["monster_id"]): e for e in catalog["entries"]}
    ready = {int(e["monster_id"]) for e in catalog["entries"] if bool(e.get("runtime_allowed", False))}

    regressed = sorted(R3B_BASELINE_164 - ready)
    assert not regressed, f"R3B_BASELINE_164_REGRESSED ids={regressed}"

    # Anchors must be present and runtime_allowed.
    for mid in ANCHOR_IDS:
        assert mid in ready, f"anchor {mid} not runtime_allowed"

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
        "CANONICAL_MONSTER_R3B_BASELINE_164_PASS: baseline_164=%d runtime_allowed=%d "
        "baseline_164_preserved=yes anchors=%s" % (len(R3B_BASELINE_164), len(ready), list(ANCHOR_IDS))
    )


if __name__ == "__main__":
    main()
