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
    # P3C active runtime universe = 156.
    assert len(entries) == 156

    ids = [int(e["monster_id"]) for e in entries]
    assert len(set(ids)) == 156, "duplicate monster_id in active catalog"
    # Retired IDs 14/16/17 must not enter the active catalog.
    assert 14 not in ids
    assert 16 not in ids
    assert 17 not in ids

    counts = Counter(str(e["classification"]) for e in entries)

    assert counts["ordinary"] == 75, counts
    assert counts["elite"] == 29, counts
    assert counts["boss"] == 20, counts
    assert counts["special"] == 25, counts
    assert counts["version_difference"] == 6, counts
    assert counts["non_hostile"] == 1, counts
    assert counts["unresolved"] == 0, counts

    assert catalog["summary"]["runtime_allowed_count"] == 153

    by_id = {int(e["monster_id"]): e for e in entries}

    assert by_id[41]["classification"] == "elite"
    assert by_id[41]["editor_placement"]["allowed"] is True

    assert by_id[239]["classification"] == "boss"
    assert by_id[239]["editor_placement"]["allowed"] is True

    assert by_id[240]["classification"] == "boss"
    assert by_id[240]["editor_placement"]["allowed"] is True

    assert by_id[241]["classification"] == "special"
    assert by_id[241]["editor_placement"]["allowed"] is True

    # Explicit current dispositions are the narrow placement policy.  The
    # historical placement_allowed=false values on other exact-ID rows are
    # retained as audit input and must not re-close the active editor pool.
    for monster_id in (59, 78, 161):
        source_row = source["exact_id_overrides"][str(monster_id)]
        entry = by_id[monster_id]
        assert source_row["disposition"] == "quarantine"
        assert isinstance(source_row.get("evidence"), dict) and source_row["evidence"]
        assert entry["disposition"] == "quarantine"
        assert entry["editor_placement"]["allowed"] is False
        assert entry["runtime_allowed"] is True
        assert entry["disposition_evidence"] == source_row["evidence"]

    source_157 = source["exact_id_overrides"]["157"]
    entry_157 = by_id[157]
    assert source_157["classification"] == "ordinary"
    assert source_157["disposition"] == "internal_subtype"
    assert isinstance(source_157.get("evidence"), dict) and source_157["evidence"]
    assert source_157["evidence"]["elite"] is False
    assert source_157["evidence"]["independent_map_monster"] is False
    assert entry_157["classification"] == "ordinary"
    assert entry_157["disposition"] == "internal_subtype"
    assert entry_157["editor_placement"]["allowed"] is False
    assert entry_157["runtime_allowed"] is True

    # The two neighboring Zuma Guard elite variants retain their elite
    # identity and remain in the formal editor pool.
    for monster_id in (158, 159):
        assert by_id[monster_id]["classification"] == "elite"
        assert by_id[monster_id]["editor_placement"]["allowed"] is True
        assert by_id[monster_id]["runtime_allowed"] is True

    assert "239" not in source["exact_id_overrides"]
    # Source classification attachment retains its own record count; this is
    # the persisted user-adjudicated policy table, not the active runtime.
    assert len(source["exact_id_overrides"]) == 216

    print(
        "CANONICAL_MONSTER_CLASSIFICATION_CLOSURE_PASS "
        "total=156 unresolved=0 ordinary=75 elite=29 boss=20 "
        "special=25 version_difference=6 non_hostile=1 runtime_allowed=153"
    )

if __name__ == "__main__":
    main()
