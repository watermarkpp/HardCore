#!/usr/bin/env python3
"""R1: enable placement_allowed for POLICY_ONLY_BLOCKED monsters.

A monster is policy-only blocked when its exact-ID combat/AI/timing, formal
appearance, and drop profile are all already complete and the only remaining
blocker is the legacy frozen placement_allowed=false in the classification
authority.  Flipping that single flag (and re-generating the catalog) lets
runtime_allowed become true without hand-editing runtime_allowed.

SPECIAL_RUNTIME_SEMANTICS is a review flag, not a data blocker, so a special
monster that is otherwise fully complete is also policy-only enableable here.
"""

from __future__ import annotations

import json
from pathlib import Path

from audit_monster_runtime_readiness import build_audit

ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_PATH = ROOT / "assets" / "data" / "canonical_monster_classification_v1.json"
ENABLE_NOTE = "R1 runtime closure: policy-only unblock (exact-ID combat/AI/timing/art/drop formal)"

REVIEW_ONLY = {"SPECIAL_RUNTIME_SEMANTICS"}


def _policy_only_ids(audit: dict) -> list[int]:
    ids: list[int] = []
    for record in audit["records"]:
        blockers = set(record["runtime_blockers"]) - REVIEW_ONLY
        if record["authoring_candidate"] and blockers == {"PLACEMENT_POLICY_BLOCKED"}:
            ids.append(record["monster_id"])
    return sorted(ids)


def main() -> None:
    audit = build_audit()
    ids = _policy_only_ids(audit)
    authority = json.loads(AUTHORITY_PATH.read_text(encoding="utf-8"))
    overrides = authority["exact_id_overrides"]
    changed = []
    for mid in ids:
        override = overrides.get(str(mid))
        if not isinstance(override, dict):
            raise SystemExit(f"missing override for {mid}")
        if bool(override.get("placement_allowed", False)):
            continue
        override["placement_allowed"] = True
        notes = str(override.get("notes", "")).strip()
        override["notes"] = f"{notes}；{ENABLE_NOTE}" if notes else ENABLE_NOTE
        changed.append(mid)
    AUTHORITY_PATH.write_text(
        json.dumps(authority, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"POLICY_ONLY_ENABLEMENT_PASS changed={len(changed)}")
    print(f"ids={changed}")


if __name__ == "__main__":
    main()
