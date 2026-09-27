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

HC-MONSTER-COMBAT-R4 T4: the last structural holes are closed.
- Duplicate identity rows are rejected: the same monster_id may not appear
  twice in one view, and an entry id must be a strict positive integer
  (bool is not an integer) whose by_id key is its exact decimal form.
- An empty identity view is rejected: a file with neither rows nor ids can
  never "diff clean" against another empty view
  (both_inputs_empty_identity_views).
- Deleting a whole required drop_policy block on an exempt id is rejected:
  the R3 carve-out only tolerates FIELD-LEVEL drop_policy changes, never
  the removal of the block itself (exempt_id_drop_policy_deleted).
- Non-standard JSON numeric constants (NaN/Infinity) are rejected at parse
  time, before any comparison can silently accept them.
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
    def reject_constant(name: str) -> float:
        raise ValueError(f"non-standard JSON numeric constant: {name}")

    return normalize(
        json.loads(
            Path(path).read_text(encoding="utf-8"),
            parse_constant=reject_constant,
        )
    )


def _is_strict_positive_int(value) -> bool:
    # bool is a subclass of int in Python; the contract excludes it.
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def check_view_consistency(label: str, doc: dict, unexpected: list) -> None:
    """R3 W4: in each file, entries rows and entries_by_id must agree.
    R4 T4: duplicate identity rows, empty identity views and non-positive or
    non-integer identities are structural failures."""
    rows = doc.get("entries", [])
    by_id = doc.get("entries_by_id", {})
    if not isinstance(rows, list) or not isinstance(by_id, dict):
        unexpected.append(f"{label}: entries/entries_by_id missing or wrong type")
        return
    if not rows and not by_id:
        unexpected.append(f"{label}: empty identity view (no entries, no entries_by_id)")
        return
    row_keys = []
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            unexpected.append(f"{label}: entries[{index}] is not an object")
            continue
        monster_id = row.get("monster_id")
        if not _is_strict_positive_int(monster_id):
            unexpected.append(
                f"{label}: entries[{index}] monster_id is not a strict positive integer"
            )
        key = str(row.get("monster_id"))
        if key in seen:
            unexpected.append(
                f"{label}: duplicate identity row entries[{index}] monster_id={key}"
            )
        seen.add(key)
        row_keys.append(key)
        if by_id.get(key) != row:
            unexpected.append(f"{label}: entries[{index}] != entries_by_id[{key}]")
    for key in by_id:
        key_text = str(key)
        if not (
            key_text.isdigit()
            and _is_strict_positive_int(int(key_text))
            and key_text == str(int(key_text))
        ):
            unexpected.append(
                f"{label}: entries_by_id[{key}] is not a strict positive integer id"
            )
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
                # R4 T4: the carve-out covers FIELD-LEVEL policy changes only.
                # Deleting the whole required drop_policy block (or emptying
                # it) can never pass as a "harmless exemption"
                # (exempt_id_drop_policy_deleted).
                replacement = b.get("drop_policy")
                if not isinstance(replacement, dict) or not replacement:
                    unexpected.append(
                        f"entries_by_id[{key}].drop_policy block deleted or emptied on exempt id"
                    )
                continue
            unexpected.append(f"entries_by_id[{key}].{field}")

    for diff in unexpected:
        print("UNEXPECTED:", diff)
    print("unexpected diff count:", len(unexpected))
    return 0 if not unexpected else 1


if __name__ == "__main__":
    sys.exit(main())
