"""Lock the runtime-closure contract for every runtime_allowed monster.

A monster may only carry runtime_allowed == true when its classification,
editor placement, exact-ID combat identity, combat stats, AI/timing, formal
appearance (idle/walk/attack/hit/death), and (for hostile classes) a non-empty
drop profile or formal drop exemption are all satisfied.  Any violation fails
this test.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"

REQUIRED_ACTIONS = ("idle", "walk", "attack", "hit", "death")
HOSTILE_CLASSES = {"ordinary", "elite", "boss", "special"}
STAT_FIELDS = ("level", "hp", "attack_min", "attack_max", "defense", "magic_defense")


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

        stats = entry.get("combat", {}).get("stats", {})
        assert any(int(stats.get(field, 0)) != 0 for field in STAT_FIELDS), f"{label} missing combat stats"

        ai = entry.get("combat", {}).get("ai", {})
        assert int(ai.get("ai_code", -1)) >= 0, f"{label} missing AI code"
        timing = entry.get("combat", {}).get("timing", {})
        assert int(timing.get("attack_interval_ms", 0)) > 0 or int(timing.get("move_interval_ms", 0)) > 0, f"{label} missing timing"

        profile = profiles.get(str(entry.get("appearance_profile_id", "")), {})
        assert profile.get("status") == "formal", f"{label} appearance not formal"
        for action in REQUIRED_ACTIONS:
            action_evidence = profile.get("actions", {}).get(action, {})
            assert bool(action_evidence.get("source_path_exists", False)), f"{label} missing {action} action"

        drop_policy = entry.get("drop_policy", {})
        drop_count = int(drop_policy.get("entry_count", 0))
        if classification in HOSTILE_CLASSES:
            assert drop_count > 0 or _drop_exempt(drop_policy), f"{label} hostile with no drop/exemption"

    print("CANONICAL_MONSTER_RUNTIME_CLOSURE_PASS: runtime_allowed=%d" % len(ready))


if __name__ == "__main__":
    main()
