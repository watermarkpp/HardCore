"""Lock the runtime-closure contract for every runtime_allowed monster.

A monster may only carry runtime_allowed == true when the full closure gate
holds: classification, editor placement, exact-ID combat identity, complete
combat stats with valid domains, formal AI resolution, formal timing, formal
appearance (idle/walk/attack/hit/death), drop profile/exemption, and (for
special monsters) an approved runtime semantics.  The assertions mirror the
generator's own closure logic via the shared ``_combat_stats_ok`` helper.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
GENERATOR_PATH = ROOT / "tools" / "build_canonical_monster_catalog.py"

SPEC = importlib.util.spec_from_file_location("canonical_monster_catalog_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)

REQUIRED_ACTIONS = ("idle", "walk", "attack", "hit", "death")
HOSTILE_CLASSES = {"ordinary", "elite", "boss", "special"}
FORBIDDEN_AI_RESOLUTION = ("", "unresolved", "unresolved_project_fallback")


def _drop_exempt(drop_policy: dict) -> bool:
    exemption = drop_policy.get("exemption")
    return isinstance(exemption, dict) and bool(exemption.get("allowed")) and bool(exemption.get("reason"))


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entries = catalog.get("entries", [])
    profiles = catalog.get("appearance_profiles", {})

    ready = [e for e in entries if bool(e.get("runtime_allowed", False))]
    assert ready, "no runtime_allowed monsters"

    for entry in ready:
        mid = int(entry["monster_id"])
        label = f"monster_id={mid}"
        classification = str(entry.get("classification", ""))
        assert classification not in ("unresolved", "version_difference"), f"{label} bad classification {classification}"
        assert bool(entry.get("editor_placement", {}).get("allowed", False)), f"{label} not editor-placeable"

        status = entry.get("source_evidence", {}).get("status", {})
        assert bool(status.get("combat_identity_ok", False)), f"{label} no combat identity"

        # Complete combat stats with valid domains (shared generator helper).
        stats = entry.get("combat", {}).get("stats", {})
        hostile = classification in HOSTILE_CLASSES
        runtime_semantics = str(status.get("runtime_semantics", ""))
        standard_combat = classification in ("ordinary", "elite", "boss") or runtime_semantics in GEN.APPROVED_COMBAT_SEMANTICS
        assert GEN._combat_stats_ok(stats, hostile and standard_combat), f"{label} combat stats incomplete/invalid"

        # Formal AI resolution.
        ai = entry.get("combat", {}).get("ai", {})
        assert int(ai.get("ai_code", -1)) >= 0, f"{label} missing AI code"
        assert str(ai.get("resolution_status", "")) not in FORBIDDEN_AI_RESOLUTION, f"{label} AI resolution unresolved"

        # Formal timing (standard combat only).
        timing = entry.get("combat", {}).get("timing", {})
        if standard_combat:
            assert int(timing.get("attack_interval_ms", 0)) > 0, f"{label} missing attack interval"
            assert int(timing.get("move_interval_ms", 0)) > 0, f"{label} missing move interval"
            assert bool(str(timing.get("confidence", "")).strip()), f"{label} timing confidence missing"

        # Formal appearance with all five actions.
        profile = profiles.get(str(entry.get("appearance_profile_id", "")), {})
        assert profile.get("status") == "formal", f"{label} appearance not formal"
        for action in REQUIRED_ACTIONS:
            action_evidence = profile.get("actions", {}).get(action, {})
            assert bool(action_evidence.get("source_path_exists", False)), f"{label} missing {action} action"

        # Drop profile or formal exemption.
        drop_policy = entry.get("drop_policy", {})
        if classification in HOSTILE_CLASSES:
            assert int(drop_policy.get("entry_count", 0)) > 0 or _drop_exempt(drop_policy), f"{label} hostile with no drop/exemption"

        # Special monsters must have an approved runtime semantics.
        if classification == "special":
            assert runtime_semantics in GEN.APPROVED_COMBAT_SEMANTICS, f"{label} special missing approved runtime_semantics"

    print("CANONICAL_MONSTER_RUNTIME_CLOSURE_PASS: runtime_allowed=%d" % len(ready))


if __name__ == "__main__":
    main()
