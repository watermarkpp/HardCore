"""Lock the 217-identity classification closure contract.

After Phase B, every stable monster_id must carry one of the six canonical
classifications (unresolved == 0), without expanding runtime enablement
(runtime_allowed stays 37) and without touching the 9590 drop slots.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
DROP_SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
EXPECTED_DROP_SHA256 = "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"

# The exact monster_id set that was placeable at the classification baseline
# (parent 8808ebe3). Phase B must not move any identity across the placement
# boundary: the same 37 IDs stay placeable, and none more.
EXPECTED_PLACEMENT_ALLOWED_IDS = {
    18, 19, 21, 24, 26, 28, 30, 34, 38, 39,
    64, 65, 66, 67, 68, 69, 70, 71, 73, 74,
    75, 76, 120, 124, 135, 136, 137, 141, 156, 157,
    158, 159, 160, 180, 188, 191, 194,
}


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entries = catalog.get("entries", [])
    assert len(entries) == 217, len(entries)

    ids = [int(e.get("monster_id", -1)) for e in entries]
    assert len(set(ids)) == 217, "duplicate or missing monster_id"

    counts = Counter(str(e.get("classification", "")) for e in entries)
    assert counts.get("unresolved", 0) == 0, dict(counts)
    assert counts.get("ordinary", 0) == 135, dict(counts)
    assert counts.get("elite", 0) == 30, dict(counts)
    assert counts.get("boss", 0) == 20, dict(counts)
    assert counts.get("special", 0) == 19, dict(counts)
    assert counts.get("version_difference", 0) == 12, dict(counts)
    assert counts.get("non_hostile", 0) == 1, dict(counts)

    assert int(catalog.get("summary", {}).get("runtime_allowed_count", -1)) == 37

    placement_allowed_ids = {
        int(e["monster_id"])
        for e in entries
        if bool(e.get("editor_placement", {}).get("allowed", False))
    }
    assert len(placement_allowed_ids) == 37, sorted(placement_allowed_ids)
    assert placement_allowed_ids == EXPECTED_PLACEMENT_ALLOWED_IDS, sorted(placement_allowed_ids)

    by_id = {int(e.get("monster_id", -1)): e for e in entries}

    anchor_41 = by_id.get(41, {})
    assert anchor_41.get("classification") == "elite", anchor_41.get("classification")
    assert not bool(anchor_41.get("editor_placement", {}).get("allowed", True)), "ID41 must not be placeable"

    assert by_id.get(103, {}).get("classification") == "ordinary"

    anchor_240 = by_id.get(240, {})
    assert anchor_240.get("classification") == "boss", anchor_240.get("classification")
    assert not bool(anchor_240.get("editor_placement", {}).get("allowed", True)), "ID240 must not be placeable"
    assert int(anchor_240.get("drop_policy", {}).get("entry_count", 0)) == 54

    assert by_id.get(241, {}).get("classification") == "special"

    # 9590 drop source unchanged.
    import hashlib
    sha = hashlib.sha256(DROP_SOURCE_PATH.read_bytes()).hexdigest().upper()
    assert sha == EXPECTED_DROP_SHA256, sha

    print(
        "CANONICAL_MONSTER_CLASSIFICATION_CLOSURE_PASS: "
        "total=217 unresolved=0 ordinary=135 elite=30 boss=20 special=19 "
        "version_difference=12 non_hostile=1 runtime_allowed=37 placement_allowed=37"
    )


if __name__ == "__main__":
    main()
