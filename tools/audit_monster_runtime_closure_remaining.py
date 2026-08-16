#!/usr/bin/env python3
"""Emit the remaining runtime-closure blockers for every runtime_allowed=false ID.

The reason mapping is machine-derived from the audit blocker classes and gives
a concrete, reviewable reason (never a bare "runtime not ready").
"""

from __future__ import annotations

import json
from pathlib import Path

from audit_monster_runtime_readiness import build_audit

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "outputs" / "monster_runtime_closure_remaining.json"

REASON_BY_BLOCKER = {
    "VERSION_DIFFERENCE": "VERSION_DIFFERENCE_EXCLUDED",
    "COMBAT_IDENTITY_MISSING": "MISSING_COMBAT_SOURCE",
    "COMBAT_STATS_INCOMPLETE": "MISSING_COMBAT_STATS",
    "AI_UNRESOLVED": "MISSING_AI_SOURCE",
    "TIMING_INCOMPLETE": "MISSING_TIMING_SOURCE",
    "ART_MAPPING_MISSING": "MISSING_ART_SOURCE",
    "ART_ACTION_INCOMPLETE": "INCOMPLETE_ART_ACTIONS",
    "DROP_MISSING": "DROP_EXEMPTION_REQUIRED",
    "SPECIAL_RUNTIME_SEMANTICS": "SPECIAL_RUNTIME_SEMANTICS",
    "PLACEMENT_POLICY_BLOCKED": "PLACEMENT_POLICY_BLOCKED",
    "UNRESOLVED_CLASSIFICATION": "UNRESOLVED_CLASSIFICATION",
}

PRIMARY_PRIORITY = (
    "VERSION_DIFFERENCE",
    "COMBAT_IDENTITY_MISSING",
    "ART_MAPPING_MISSING",
    "ART_ACTION_INCOMPLETE",
    "DROP_MISSING",
    "AI_UNRESOLVED",
    "TIMING_INCOMPLETE",
    "SPECIAL_RUNTIME_SEMANTICS",
    "PLACEMENT_POLICY_BLOCKED",
    "COMBAT_STATS_MISSING",
    "UNRESOLVED_CLASSIFICATION",
)


def main() -> None:
    audit = build_audit()
    remaining = [r for r in audit["records"] if not r["runtime_allowed"]]
    summary: dict = {"remaining_count": len(remaining), "reason_counts": {}, "reason_ids": {}}
    remaining_out = []
    for record in sorted(remaining, key=lambda r: int(r["monster_id"])):
        blockers = record["runtime_blockers"]
        primary = next((b for b in PRIMARY_PRIORITY if b in blockers), blockers[0] if blockers else "UNKNOWN")
        reasons = [REASON_BY_BLOCKER.get(b, b) for b in blockers]
        remaining_out.append({
            "monster_id": record["monster_id"],
            "name": record["name"],
            "classification": record["classification"],
            "blockers": blockers,
            "reasons": reasons,
            "primary_reason": REASON_BY_BLOCKER.get(primary, primary),
        })
        for reason in reasons:
            summary["reason_counts"][reason] = summary["reason_counts"].get(reason, 0) + 1
            summary["reason_ids"].setdefault(reason, []).append(record["monster_id"])
    for reason in summary["reason_ids"]:
        summary["reason_ids"][reason].sort()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {"generated_by": "tools/audit_monster_runtime_closure_remaining.py", "summary": summary, "remaining": remaining_out}
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"MONSTER_RUNTIME_CLOSURE_REMAINING_PASS remaining={len(remaining)}")
    for reason, count in sorted(summary["reason_counts"].items()):
        print(f"{reason}={count}")
    print(f"output={OUTPUT_PATH}")


if __name__ == "__main__":
    main()
