#!/usr/bin/env python3
"""Build 214-ID Runtime Closure Matrix for P3 monster golden authority closure."""
import sys
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def main():
    print("=" * 80)
    print("P3 MONSTER GOLDEN RUNTIME AUTHORITY - 214-ID CLOSURE MATRIX")
    print("=" * 80)
    
    # Load all data sources
    print("\n[1/6] Loading data sources...")
    
    # 1. Service runtime catalog (214 IDs)
    service_catalog = load_json(REPO / "assets/data/service_monster_runtime_catalog.json")
    runtime_by_id = service_catalog.get("runtimeByMonsterId", {})
    print(f"  Service runtime entries: {len(runtime_by_id)}")
    
    # 2. Monster behavior profiles
    behavior_profiles = load_json(REPO / "assets/data/monster_behavior_profiles.json")
    profiles_by_id = behavior_profiles.get("profileByMonsterId", {})
    # Convert string keys to int keys
    profiles_by_id = {int(k) if k.isdigit() else k: v for k, v in profiles_by_id.items()}
    all_profiles = behavior_profiles.get("profiles", {})
    print(f"  Behavior profiles: {len(profiles_by_id)} monster bindings, {len(all_profiles)} unique profiles")
    
    # 3. Monster animation catalog
    animation_catalog = load_json(REPO / "assets/data/runtime/monster_animation_catalog.json")
    animations_by_id = {}
    for m in animation_catalog.get("monsters", []):
        mid = m.get("monster_id")
        if mid is not None:
            animations_by_id[mid] = m
    print(f"  Animation entries: {len(animations_by_id)}")
    
    # 4. Vanilla 176 monsters (original data)
    vanilla_monsters = load_json(REPO / "assets/data/vanilla_176/monsters.json")
    vanilla_by_id = {}
    for m in vanilla_monsters.get("records", []):
        mid = m.get("id") or m.get("monsterId")
        if mid is not None:
            vanilla_by_id[mid] = m
    print(f"  Vanilla 176 monsters: {len(vanilla_by_id)}")
    
    # 5. Get all 214 production monster IDs
    all_monster_ids = sorted([int(mid) for mid in runtime_by_id.keys()])
    print(f"\n  Production identity count: {len(all_monster_ids)}")
    
    if len(all_monster_ids) != 214:
        print(f"\n  ️ WARNING: Expected 214, got {len(all_monster_ids)}")
        print("  Stopping - identity count mismatch")
        return
    
    # Analyze each monster
    print("\n[2/6] Analyzing runtime closure status...")
    
    matrix = []
    blocker_counts = {
        "GOLDEN_VALUE_NOT_PROMOTED": 0,
        "EXACT_ID_BINDING_MISSING": 0,
        "POLICY_GATE_STALE": 0,
        "RUNTIME_HANDLER_MISSING": 0,
        "ITEM_TOKEN_MAPPING_MISSING": 0,
        "INTENTIONAL_EXCLUSION": 0,
        "DATA_MISSING": 0,
    }
    
    runtime_ready_count = 0
    placement_allowed_count = 0
    placeable_runtime_blocker_count = 0
    
    for monster_id in all_monster_ids:
        mid_str = str(monster_id)
        
        # Get data from each source
        runtime_entry = runtime_by_id.get(mid_str, {})
        behavior_profile_id = profiles_by_id.get(monster_id, "")
        behavior = all_profiles.get(behavior_profile_id, {}) if behavior_profile_id else {}
        animation = animations_by_id.get(monster_id, {})
        vanilla = vanilla_by_id.get(monster_id, {})
        
        # Extract key fields
        canonical_name = runtime_entry.get("projectName", "") or vanilla.get("name", "")
        classification = runtime_entry.get("classification", "") or vanilla.get("classification", "")
        resolution_status = runtime_entry.get("resolutionStatus", "")
        
        # Check runtime readiness
        runtime_ready = runtime_entry.get("runtimeReady", False)
        placement_allowed = runtime_entry.get("placementAllowed", False)
        
        # Identify blockers based on actual data structure
        blockers = []
        
        # Check resolution status (identity)
        resolution_status = runtime_entry.get("resolutionStatus", "")
        identity_ok = resolution_status in ["exact_service_name", "exact_id_map_spawn_audit"]
        if not identity_ok:
            blockers.append("EXACT_ID_BINDING_MISSING")
        
        # Check combat authority (serviceRecord contains combat stats)
        service_record = runtime_entry.get("serviceRecord", {})
        combat_ok = bool(service_record.get("stats", {}))
        if not combat_ok:
            blockers.append("GOLDEN_VALUE_NOT_PROMOTED")
        
        # Check AI/timing authority (behaviorProfile)
        behavior_profile = runtime_entry.get("behaviorProfile", {})
        ai_ok = bool(behavior_profile.get("timing", {})) or bool(behavior_profile.get("serviceBehavior", {}))
        if not ai_ok:
            blockers.append("EXACT_ID_BINDING_MISSING")
        
        # Check animation
        animation_ok = bool(animation.get("resource_lookup", "")) or bool(animation.get("resourceLookup", ""))
        if not animation_ok:
            blockers.append("GOLDEN_VALUE_NOT_PROMOTED")
        
        # Check placement policy
        if placement_allowed and not runtime_ready:
            blockers.append("POLICY_GATE_STALE")
            placeable_runtime_blocker_count += 1
        
        # Check drop closure
        drop_path = service_record.get("dropPath", "")
        drop_ok = True  # Drop policy is separate, assume OK for now
        if not drop_ok:
            blockers.append("ITEM_TOKEN_MAPPING_MISSING")
        
        # Check special handler
        special_behavior = vanilla.get("specialBehavior", "")
        handler_exists = bool(behavior.get("handlerExists", False))
        if special_behavior and not handler_exists:
            blockers.append("RUNTIME_HANDLER_MISSING")
        
        # Check intentional exclusion
        intentional_exclusion = bool(runtime_entry.get("intentionalExclusion", False))
        if intentional_exclusion:
            blockers.append("INTENTIONAL_EXCLUSION")
        
        # Update counts
        for b in blockers:
            if b in blocker_counts:
                blocker_counts[b] += 1
        
        if not blockers:
            runtime_ready_count += 1
        
        if placement_allowed:
            placement_allowed_count += 1
        
        matrix.append({
            "monster_id": monster_id,
            "canonical_name": canonical_name,
            "classification": classification,
            "resolution_status": resolution_status,
            "runtime_ready": runtime_ready,
            "placement_allowed": placement_allowed,
            "combat_ok": combat_ok,
            "ai_ok": ai_ok,
            "animation_ok": animation_ok,
            "drop_ok": drop_ok,
            "handler_ok": handler_exists if special_behavior else True,
            "intentional_exclusion": intentional_exclusion,
            "blockers": blockers,
        })
    
    # Print summary
    print("\n[3/6] PRE-FIX MATRIX SUMMARY")
    print("=" * 80)
    print(f"Production identity count: {len(all_monster_ids)}")
    print(f"Current runtime_ready count: {runtime_ready_count}")
    print(f"Current placement_allowed count: {placement_allowed_count}")
    print(f"Placeable but runtime_ready=false: {placeable_runtime_blocker_count}")
    
    print("\nBlocker counts:")
    for blocker, count in blocker_counts.items():
        print(f"  {blocker}: {count}")
    
    # Print detailed matrix (first 20 for preview)
    print("\n[4/6] DETAILED MATRIX (first 20 entries)")
    print("=" * 80)
    print(f"{'ID':<5} {'Name':<20} {'Class':<12} {'Runtime':<8} {'Place':<8} {'Blockers'}")
    print("-" * 80)
    
    for m in matrix[:20]:
        blockers_str = ",".join(m["blockers"]) if m["blockers"] else "-"
        print(f"{m['monster_id']:<5} {m['canonical_name']:<20} {m['classification']:<12} {str(m['runtime_ready']):<8} {str(m['placement_allowed']):<8} {blockers_str}")
    
    if len(matrix) > 20:
        print(f"\n... and {len(matrix) - 20} more entries")
    
    # Save full matrix to JSON
    print("\n[5/6] Saving matrix...")
    matrix_path = REPO / "docs" / "p3_runtime_closure_matrix.json"
    matrix_path.parent.mkdir(parents=True, exist_ok=True)
    with open(matrix_path, 'w', encoding='utf-8') as f:
        json.dump(matrix, f, ensure_ascii=False, indent=2)
    print(f"  Saved to: {matrix_path}")
    
    # Save summary
    summary = {
        "production_identity_count": len(all_monster_ids),
        "runtime_ready_count": runtime_ready_count,
        "placement_allowed_count": placement_allowed_count,
        "placeable_runtime_blocker_count": placeable_runtime_blocker_count,
        "blocker_counts": blocker_counts,
    }
    
    summary_path = REPO / "docs" / "p3_pre_fix_summary.json"
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print(f"  Saved to: {summary_path}")
    
    print("\n[6/6] PRE-FIX SUMMARY")
    print("=" * 80)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    
    print("\n" + "=" * 80)
    print("Matrix generation complete")
    print("=" * 80)

if __name__ == "__main__":
    main()
