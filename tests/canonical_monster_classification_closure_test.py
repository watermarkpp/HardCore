from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
SOURCE = ROOT / "assets/data/canonical_monster_classification_v1.json"

def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    source = json.loads(SOURCE.read_text(encoding="utf-8"))

    entries = catalog["entries"]
    assert len(entries) == 214

    ids = [int(e["monster_id"]) for e in entries]
    assert len(set(ids)) == 214
    assert 14 not in ids
    assert 16 not in ids
    assert 17 not in ids

    counts = Counter(str(e["classification"]) for e in entries)

    assert counts["ordinary"] == 133, counts
    assert counts["elite"] == 30, counts
    assert counts["boss"] == 20, counts
    assert counts["special"] == 18, counts
    assert counts["version_difference"] == 12, counts
    assert counts["non_hostile"] == 1, counts
    assert counts["unresolved"] == 0, counts

    assert catalog["summary"]["runtime_allowed_count"] == 39

    by_id = {int(e["monster_id"]): e for e in entries}

    assert by_id[41]["classification"] == "elite"
    assert by_id[41]["editor_placement"]["allowed"] is False

    assert by_id[239]["classification"] == "boss"
    assert by_id[239]["editor_placement"]["allowed"] is False

    assert by_id[240]["classification"] == "boss"
    assert by_id[240]["editor_placement"]["allowed"] is False

    assert by_id[241]["classification"] == "special"
    assert by_id[241]["editor_placement"]["allowed"] is False

    assert "239" not in source["exact_id_overrides"]
    assert len(source["exact_id_overrides"]) == 216

    print(
        "CANONICAL_MONSTER_CLASSIFICATION_CLOSURE_PASS "
        "total=214 unresolved=0 ordinary=133 elite=30 boss=20 "
        "special=18 version_difference=12 non_hostile=1 runtime_allowed=39"
    )

if __name__ == "__main__":
    main()
