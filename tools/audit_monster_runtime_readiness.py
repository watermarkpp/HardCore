#!/usr/bin/env python3
"""Machine-classified runtime-readiness audit for all 217 canonical monsters.

Reads the generated canonical catalog (which already carries the full
runtime-closure gate status: combat identity / complete stats / formal AI /
formal timing / runtime semantics / formal art / drop) and emits one record
per monster_id plus a machine summary.  This tool never mutates data.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets" / "data" / "runtime" / "canonical_monster_catalog.json"
CLASSIFICATION_PATH = ROOT / "assets" / "data" / "canonical_monster_classification_v1.json"
OUTPUT_PATH = ROOT / "outputs" / "monster_runtime_readiness_audit_217.json"

AUTHORING_CLASSES = {"ordinary", "elite", "boss", "special", "non_hostile"}
HOSTILE_CLASSES = {"ordinary", "elite", "boss", "special"}


def _drop_exempt(drop_policy: dict[str, Any]) -> bool:
    exemption = drop_policy.get("exemption")
    return isinstance(exemption, dict) and bool(exemption.get("allowed")) and bool(exemption.get("reason"))


def build_audit() -> dict[str, Any]:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    classification_ids = json.loads(CLASSIFICATION_PATH.read_text(encoding="utf-8"))
    overrides = classification_ids.get("exact_id_overrides", {})

    records: list[dict[str, Any]] = []
    ready: list[int] = []
    for entry in sorted(catalog["entries"], key=lambda item: int(item["monster_id"])):
        mid = int(entry["monster_id"])
        classification = str(entry.get("classification", ""))
        runtime_allowed = bool(entry.get("runtime_allowed", False))
        editor_allowed = bool(entry.get("editor_placement", {}).get("allowed", False))
        override = overrides.get(str(mid), {})
        if not isinstance(override, dict):
            override = {}
        classification_placement = bool(override.get("placement_allowed", True))
        if classification in ("unresolved", "version_difference"):
            classification_placement = False

        status = entry.get("source_evidence", {}).get("status", {})
        combat_identity_ok = bool(status.get("combat_identity_ok", False))
        combat_stats_ok = bool(status.get("combat_stats_ok", False))
        ai_ok = bool(status.get("ai_ok", False))
        ai_resolution = str(status.get("ai_resolution_status", ""))
        timing_ok = bool(status.get("timing_ok", False))
        runtime_semantics = str(status.get("runtime_semantics", ""))
        runtime_semantics_ok = bool(status.get("runtime_semantics_ok", False))
        art_status = str(status.get("art_status", ""))
        drop_status = str(status.get("drop_status", ""))
        drop_count = int(entry.get("drop_policy", {}).get("entry_count", 0))
        drop_policy = entry.get("drop_policy", {})
        appearance_profile_id = str(entry.get("appearance_profile_id", ""))

        blockers: list[str] = []
        if classification == "unresolved":
            blockers.append("UNRESOLVED_CLASSIFICATION")
        if classification == "version_difference":
            blockers.append("VERSION_DIFFERENCE")
        if classification in AUTHORING_CLASSES and not classification_placement:
            blockers.append("PLACEMENT_POLICY_BLOCKED")
        if not combat_identity_ok:
            blockers.append("COMBAT_IDENTITY_MISSING")
        if not combat_stats_ok:
            blockers.append("COMBAT_STATS_INCOMPLETE")
        if not ai_ok:
            blockers.append("AI_UNRESOLVED")
        if not timing_ok:
            blockers.append("TIMING_INCOMPLETE")
        if appearance_profile_id.startswith("appearance.unresolved"):
            blockers.append("ART_MAPPING_MISSING")
        elif art_status != "formal":
            blockers.append("ART_ACTION_INCOMPLETE")
        if classification in HOSTILE_CLASSES and drop_count <= 0 and not _drop_exempt(drop_policy):
            blockers.append("DROP_MISSING")
        if classification == "special" and not runtime_semantics_ok:
            blockers.append("SPECIAL_RUNTIME_SEMANTICS")

        records.append({
            "monster_id": mid,
            "name": str(entry.get("canonical_name", "")),
            "classification": classification,
            "authoring_candidate": classification in AUTHORING_CLASSES,
            "classification_placement_allowed": classification_placement,
            "runtime_allowed": runtime_allowed,
            "combat_identity_status": "exact" if combat_identity_ok else "missing",
            "combat_stats_status": "formal" if combat_stats_ok else "incomplete",
            "ai_status": ai_resolution if ai_ok else ("unresolved" if ai_resolution else "missing"),
            "timing_status": "formal" if timing_ok else "incomplete",
            "runtime_semantics": runtime_semantics,
            "appearance_profile_id": appearance_profile_id,
            "appearance_status": art_status,
            "drop_entry_count": drop_count,
            "drop_status": drop_status,
            "canonical_status": str(entry.get("status", "")),
            "runtime_blockers": blockers,
            "source_evidence": {
                "ai_resolution_status": ai_resolution,
                "runtime_semantics_ok": runtime_semantics_ok,
                "combat_stats_ok": combat_stats_ok,
                "timing_ok": timing_ok,
                "ai_ok": ai_ok,
            },
        })
        if runtime_allowed:
            ready.append(mid)

    summary: dict[str, Any] = {
        "identity_count": len(records),
        "RUNTIME_READY_BEFORE": len(ready),
        "runtime_ready_ids": ready,
        "not_ready_count": len(records) - len(ready),
        "blocker_counts": {},
        "blocker_ids": {},
    }
    for record in records:
        for blocker in record["runtime_blockers"]:
            summary["blocker_counts"][blocker] = summary["blocker_counts"].get(blocker, 0) + 1
            summary["blocker_ids"].setdefault(blocker, []).append(record["monster_id"])

    placement_only = [
        r["monster_id"] for r in records
        if r["authoring_candidate"]
        and set(r["runtime_blockers"]) == {"PLACEMENT_POLICY_BLOCKED"}
    ]
    summary["placement_policy_only_blocked_ids"] = sorted(placement_only)
    summary["placement_policy_only_blocked_count"] = len(placement_only)

    return {
        "generated_by": "tools/audit_monster_runtime_readiness.py",
        "summary": summary,
        "records": records,
    }


def main() -> None:
    audit = build_audit()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = audit["summary"]
    print("MONSTER_RUNTIME_READINESS_AUDIT_PASS")
    print(f"identity_count={summary['identity_count']}")
    print(f"RUNTIME_READY_BEFORE={summary['RUNTIME_READY_BEFORE']}")
    print(f"not_ready_count={summary['not_ready_count']}")
    print(f"placement_policy_only_blocked={summary['placement_policy_only_blocked_count']}")
    for blocker, count in sorted(summary["blocker_counts"].items()):
        print(f"{blocker}={count}")
    print(f"output={OUTPUT_PATH}")


if __name__ == "__main__":
    main()
