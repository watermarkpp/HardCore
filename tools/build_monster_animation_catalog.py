#!/usr/bin/env python3
"""Build the authoritative monster-animation coverage catalog."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / "assets/data/legend176_data.json").read_text(encoding="utf-8"))
COMMON = json.loads((ROOT / "assets/data/bich_common_client_art_sources.json").read_text(encoding="utf-8"))
UNDEAD = json.loads((ROOT / "assets/data/bich_undead_client_art_sources.json").read_text(encoding="utf-8"))
BOSSES = json.loads((ROOT / "assets/data/classic_boss_client_art_sources.json").read_text(encoding="utf-8"))
SKIN = json.loads((ROOT / "assets/presentation/skins/classic_client/skin_manifest.json").read_text(encoding="utf-8"))
OUT = ROOT / "assets/data/runtime/monster_animation_catalog.json"

client = {**COMMON.get("runtimeMappings", {}), **UNDEAD.get("runtimeMappings", {}), **BOSSES.get("runtimeMappings", {})}
client_by_id = BOSSES.get("runtimeMappingsByMonsterId", {})
authored = SKIN.get("runtimeAssets", {}).get("fallbackMonsters", {})
rows = []
for monster in DATA.get("monsters", []):
    name = str(monster.get("name", ""))
    base = str(monster.get("baseName", name)) or name
    # Exact variant names must win.  The old base-only lookup collapsed
    # 僵尸1..5 to 僵尸 and incorrectly marked five complete client mappings as
    # missing.  A trailing-zero alias is kept only for duplicated server rows.
    candidates = []
    for candidate in [name, base, name.rstrip("0"), base.rstrip("0")]:
        if candidate and candidate not in candidates:
            candidates.append(candidate)
    stable_id = str(int(monster.get("monsterId", -1)))
    id_profile = client_by_id.get(stable_id, {})
    lookup = str(id_profile.get("name", "")) if id_profile else next((candidate for candidate in candidates if candidate in client), "")
    authored_lookup = next((candidate for candidate in candidates if candidate in authored), "")
    row = {"monster_id": int(monster.get("monsterId", -1)), "name": name, "base_name": base}
    if lookup:
        profile = id_profile or client[lookup]
        row.update({
            "status": "formal", "source_type": "classic_client_wil", "source_confidence": profile.get("mappingConfidence", "A"),
            "resource_lookup": lookup,
            "direction_mode": "mir2_north_first", "frame_size": profile["frameSize"],
            "foot_anchor": profile["footAnchor"], "actions": {k: v["framesPerDirection"] for k, v in profile["actions"].items()},
            "runtime_allowed": True,
        })
    elif authored_lookup:
        profile = authored[authored_lookup]
        row.update({
            "status": "provisional", "source_type": profile.get("animationSource", "authored_turnaround"),
            "source_confidence": "C", "direction_mode": profile.get("directionMode", "logical_south_first"),
            "frame_size": profile["frameSize"], "foot_anchor": profile["footAnchor"],
            "actions": {"idle":4, "walk":8, "attack":6, "hit":3, "death":6},
            "runtime_allowed": True, "formal_release_allowed": False,
            "reason": "turnaround-derived animation; replace with verified action frames",
        })
    else:
        row.update({"status":"missing", "runtime_allowed":False, "formal_release_allowed":False, "reason":"five-action visual profile missing"})
    rows.append(row)

payload = {
    "schema_version": 2,
    "identity_key": "monsterId",
    "compatibility_key": "name/baseName",
    "policy": {
        "required_actions": ["idle", "walk", "attack", "hit", "death"],
        "required_directions": 8,
        "root_motion_in_atlas": False,
        "frame_isolation_required": True,
        "version_bound_action_tables": True,
        "missing_profile_blocks_map_release": True,
    },
    "summary": {
        "total": len(rows),
        "formal": sum(r["status"] == "formal" for r in rows),
        "provisional": sum(r["status"] == "provisional" for r in rows),
        "missing": sum(r["status"] == "missing" for r in rows),
    },
    "monsters": rows,
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("MONSTER_ANIMATION_CATALOG", payload["summary"])
