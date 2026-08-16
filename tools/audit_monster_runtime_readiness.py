#!/usr/bin/env python3
"""Machine-classified runtime-readiness audit for all 217 canonical monsters.

Reads the same exact-ID inputs as ``build_canonical_monster_catalog.py`` and
emits one record per monster_id plus a machine summary.  This tool never
mutates data: it only classifies the *reason* each monster is not runtime
ready so the closure work can be prioritised by blocker class.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "tools" / "build_canonical_monster_catalog.py"
SPEC = importlib.util.spec_from_file_location("canonical_monster_catalog_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)

OUTPUT_PATH = ROOT / "outputs" / "monster_runtime_readiness_audit_217.json"

AUTHORING_CLASSES = {"ordinary", "elite", "boss", "special", "non_hostile"}
HOSTILE_CLASSES = {"ordinary", "elite", "boss", "special"}

STAT_FIELDS = ("level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max")


def _has_any_stat(stats: dict[str, Any]) -> bool:
    return any(int(stats.get(field, 0)) != 0 for field in STAT_FIELDS)


def _drop_exempt(entry: dict[str, Any], drop_exception: Any) -> bool:
    if isinstance(drop_exception, dict) and drop_exception.get("allowed") and drop_exception.get("reason"):
        return True
    return False


def _ai_status(ai: dict[str, Any]) -> str:
    code = int(ai.get("ai_code", -1))
    resolution = str(ai.get("resolution_status", ""))
    if code < 0:
        return "missing"
    if resolution in ("", "unresolved", "unresolved_project_fallback"):
        return "unresolved"
    return "formal"


def _timing_status(timing: dict[str, Any]) -> str:
    attack = int(timing.get("attack_interval_ms", 0))
    move = int(timing.get("move_interval_ms", 0))
    confidence = str(timing.get("confidence", ""))
    if attack <= 0 and move <= 0:
        return "missing"
    if not confidence:
        return "unresolved"
    return "formal"


def _stats_status(stats: dict[str, Any]) -> str:
    return "formal" if _has_any_stat(stats) else "missing"


def build_audit() -> dict[str, Any]:
    catalog = GEN.build_catalog()
    classification_ids = GEN.load_json(GEN.CLASSIFICATION_ID_PATH)
    overrides = classification_ids.get("exact_id_overrides", {})
    service = GEN.load_json(GEN.SERVICE_PATH)
    id_to_art, _profiles, _art_evidence = GEN.art_profiles()

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

        combat = entry.get("combat", {})
        stats = combat.get("stats", {})
        ai = combat.get("ai", {})
        timing = combat.get("timing", {})
        status_block = entry.get("source_evidence", {}).get("status", {})
        combat_identity_ok = bool(status_block.get("combat_identity_ok", False))
        art_status = str(status_block.get("art_status", ""))
        drop_status = str(status_block.get("drop_status", ""))
        drop_count = int(entry.get("drop_policy", {}).get("entry_count", 0))
        drop_exception = entry.get("drop_policy", {}).get("exemption")
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
        if _stats_status(stats) == "missing":
            blockers.append("COMBAT_STATS_MISSING")
        ai_stat = _ai_status(ai)
        if ai_stat != "formal":
            blockers.append("AI_MISSING")
        timing_stat = _timing_status(timing)
        if timing_stat != "formal":
            blockers.append("TIMING_MISSING")
        if mid not in id_to_art:
            blockers.append("ART_MAPPING_MISSING")
        elif art_status != "formal":
            blockers.append("ART_ACTION_INCOMPLETE")
        if classification in HOSTILE_CLASSES and drop_count <= 0 and not _drop_exempt(entry, drop_exception):
            blockers.append("DROP_MISSING")
        if classification == "special":
            blockers.append("SPECIAL_RUNTIME_SEMANTICS")

        records.append({
            "monster_id": mid,
            "name": str(entry.get("canonical_name", "")),
            "classification": classification,
            "authoring_candidate": classification in AUTHORING_CLASSES,
            "classification_placement_allowed": classification_placement,
            "runtime_allowed": runtime_allowed,
            "combat_identity_status": "exact" if combat_identity_ok else "missing",
            "combat_stats_status": _stats_status(stats),
            "ai_status": ai_stat,
            "timing_status": timing_stat,
            "appearance_profile_id": appearance_profile_id,
            "appearance_status": art_status,
            "drop_entry_count": drop_count,
            "drop_status": drop_status,
            "canonical_status": str(entry.get("status", "")),
            "runtime_blockers": blockers,
            "source_evidence": {
                "service_resolution": str(service.get("runtimeByMonsterId", {}).get(str(mid), {}).get("resolutionStatus", "")) if isinstance(service.get("runtimeByMonsterId", {}).get(str(mid)), dict) else "",
                "has_exact_art_mapping": mid in id_to_art,
            },
        })
        if runtime_allowed:
            ready.append(mid)

    summary = {
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
        and "PLACEMENT_POLICY_BLOCKED" in r["runtime_blockers"]
        and not (set(r["runtime_blockers"]) - {"PLACEMENT_POLICY_BLOCKED"})
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
