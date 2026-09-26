"""HC-MONSTER-COMPAT-R2 T2: semantic diff between the R1 stamped catalog and
the formal generator rebuild. Allowed differences are enumerated; anything
else fails the build-swap gate. Usage: python tools/verify_catalog_reswap.py
<old> <new>
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

    old_sources, new_sources = old.get("sources", {}), new.get("sources", {})
    for path in sorted(set(old_sources) | set(new_sources)):
        a, b = old_sources.get(path), new_sources.get(path)
        if a != b:
            print(f"sources diff: {path}\n  old={a}\n  new={b}")

    old_by_id, new_by_id = old["entries_by_id"], new["entries_by_id"]
    if set(old_by_id) != set(new_by_id):
        unexpected.append("entries_by_id key set differs")
    for key in sorted(set(old_by_id) & set(new_by_id)):
        a, b = old_by_id[key], new_by_id[key]
        for field in sorted(set(a) | set(b)):
            if a.get(field) == b.get(field):
                continue
            if field == "drop_policy" and key in exempt_ids:
                continue
            if field == "source_evidence" and key in exempt_ids:
                continue
            unexpected.append(f"entries_by_id[{key}].{field}")
    for key in sorted(set(old_by_id) & set(new_by_id)):
        a, b = old_by_id[key], new_by_id[key]
        for field in ("drop_policy", "source_evidence"):
            if a.get(field) != b.get(field) and key not in exempt_ids:
                unexpected.append(f"UNEXPECTED {field} change on {key}")

    for diff in unexpected:
        print("UNEXPECTED:", diff)
    print("unexpected diff count:", len(unexpected))
    return 0 if not unexpected else 1


if __name__ == "__main__":
    sys.exit(main())
