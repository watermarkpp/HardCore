"""HC-MONSTER-COMPAT-R2 T2: semantic diff between the R1 stamped catalog and
the formal generator rebuild. Allowed differences are enumerated; anything
else fails the build-swap gate. Usage: python tools/verify_catalog_reswap.py
<old> <new>

HC-MONSTER-COMBAT-R3 W4 (R3-05): the three audited blind spots are closed.
- BOTH views are gated: the entries array is not a free mirror of
  entries_by_id; every row must equal its twin in BOTH files and a change to
  either view fails the swap (entries_only_combat_tamper).
- The source-binding table is part of the gate: dropping or rewriting a
  provenance binding fails the swap; an empty table never passes
  (remove_all_source_bindings).
- The exempt-id carve-out is precise: only the drop_policy of an exempt id
  may legitimately change in a formal rebuild. Combat stats and their source
  evidence are never exempt, not on an exempt id
  (exempt_id_unrelated_combat_evidence_tamper).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")


def normalize(value):
    if isinstance(value, str) and HEX64.match(value):
        return value.lower()
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()}
    return value


def load(path: str) -> dict:
    return normalize(json.loads(Path(path).read_text(encoding="utf-8")))


def check_view_consistency(label: str, doc: dict, unexpected: list) -> None:
    """R3 W4: in each file, entries rows and entries_by_id must agree."""
    rows = doc.get("entries", [])
    by_id = doc.get("entries_by_id", {})
    row_keys = []
    for index, row in enumerate(rows):
        key = str(row.get("monster_id"))
        row_keys.append(key)
        if by_id.get(key) != row:
            unexpected.append(f"{label}: entries[{index}] != entries_by_id[{key}]")
    if set(by_id) != set(row_keys):
        unexpected.append(f"{label}: entries/entries_by_id key sets differ")


def main() -> int:
    old, new = load(sys.argv[1]), load(sys.argv[2])
    unexpected: list[str] = []
    exempt_ids = {"33", "183", "241"}

    # Top-level keys other than entries/entries_by_id/sources must match.
    for key in sorted(set(old) | set(new)):
        if key in ("entries", "entries_by_id", "sources"):
            continue
        if old.get(key) != new.get(key):
            unexpected.append(f"top-level {key}")

    # R3 W4: the source-binding table is part of the gate.
    old_sources, new_sources = old.get("sources", {}), new.get("sources", {})
    if not new_sources:
        unexpected.append("sources table missing or empty")
    for path in sorted(set(old_sources) | set(new_sources)):
        a, b = old_sources.get(path), new_sources.get(path)
        if a != b:
            unexpected.append(f"sources[{path}]")

    check_view_consistency("old", old, unexpected)
    check_view_consistency("new", new, unexpected)

    old_by_id, new_by_id = old.get("entries_by_id", {}), new.get("entries_by_id", {})
    if set(old_by_id) != set(new_by_id):
        unexpected.append("entries_by_id key set differs")
    for key in sorted(set(old_by_id) & set(new_by_id)):
        a, b = old_by_id[key], new_by_id[key]
        for field in sorted(set(a) | set(b)):
            if a.get(field) == b.get(field):
                continue
            # R3 W4: the exemption is precise - only the drop_policy of an
            # exempt id may legitimately change in a formal rebuild. Combat
            # stats and their source evidence are never exempt, not even on
            # an exempt id.
            if field == "drop_policy" and key in exempt_ids:
                continue
            unexpected.append(f"entries_by_id[{key}].{field}")

    for diff in unexpected:
        print("UNEXPECTED:", diff)
    print("unexpected diff count:", len(unexpected))
    return 0 if not unexpected else 1


if __name__ == "__main__":
    sys.exit(main())
