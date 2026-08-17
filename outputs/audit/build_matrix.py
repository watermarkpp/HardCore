#!/usr/bin/env python3
"""Build the Monster Runtime Closure R4 Audit Matrix. READ-ONLY analysis."""
import json
import os

BASE = r"C:\Users\Administrator\Documents\HardCore-worktrees\r4-audit"
CATALOG_PATH = os.path.join(BASE, "assets", "data", "runtime", "canonical_monster_catalog.json")
BEHAVIOR_PATH = os.path.join(BASE, "assets", "data", "monster_behavior_profiles.json")
CLASSIFICATION_PATH = os.path.join(BASE, "assets", "data", "canonical_monster_classification_v1.json")
OUT_DIR = os.path.join(BASE, "outputs", "audit")

def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

catalog = load(CATALOG_PATH)
behavior = load(BEHAVIOR_PATH)
classification_data = load(CLASSIFICATION_PATH)

entries = catalog["entries"]
appearance_profiles = catalog.get("appearance_profiles", {})
drop_profiles = catalog.get("drop_profiles", {})

# Build behavior lookup: profileByMonsterId maps id -> profile_name
behavior_profile_by_id = behavior.get("profileByMonsterId", {})
behavior_profiles_data = behavior.get("profiles", {})
# Count how many monster IDs have a behavior profile mapping
behavior_ids_set = set()
for k, v in behavior_profile_by_id.items():
    try:
        behavior_ids_set.add(int(k))
    except (ValueError, TypeError):
        pass

# Classification exact_id_overrides
classif_overrides = classification_data.get("exact_id_overrides", {})
classif_override_ids = set()
for k in classif_overrides:
    try:
        classif_override_ids.add(int(k))
    except (ValueError, TypeError):
        pass

REQUIRED_COMBAT_FIELDS = ["hp", "attack_min", "attack_max", "defense", "magic_defense", "level", "exp"]
REQUIRED_ACTIONS = ["idle", "walk", "attack", "hit", "death"]

matrix = []

for entry in entries:
    mid = int(entry["monster_id"])
    name = entry.get("canonical_name", "")
    variant = entry.get("variant_code", "")
    status = entry.get("status", "")
    runtime_allowed = bool(entry.get("runtime_allowed", False))
    appearance_profile_id = entry.get("appearance_profile_id", "")
    drop_profile_id = entry.get("drop_profile_id", "")
    classification_name = entry.get("classification", "")

    # Combat stats - nested under combat.stats
    combat_block = entry.get("combat", {})
    combat_stats = combat_block.get("stats", {})
    combat_missing = []
    for f in REQUIRED_COMBAT_FIELDS:
        v = combat_stats.get(f)
        if v is None:
            combat_missing.append(f)
    combat_complete = len(combat_missing) == 0

    # Source evidence for combat
    source_evidence = entry.get("source_evidence", {})
    has_combat_stats_evidence = bool(source_evidence.get("combat_stats"))
    has_combat_ai_evidence = bool(source_evidence.get("combat_ai_timing"))
    has_combat_aux_evidence = bool(source_evidence.get("combat_auxiliary"))

    # AI data - nested under combat.ai
    ai_block = combat_block.get("ai", {})
    ai_code = ai_block.get("ai_code")
    ai_resolution = ai_block.get("resolution_status", "")
    ai_resolved = ai_code is not None and ai_resolution not in ("unresolved", "", None)
    # Combat identity OK requires exact_service_name resolution OR auxiliary evidence
    combat_identity_exact = ai_resolution == "exact_service_name"
    combat_identity_ok = combat_identity_exact or has_combat_aux_evidence
    view_range = ai_block.get("view_range")
    ai_source = ai_block.get("source_distribution", "")

    # Timing - nested under combat.timing
    timing_block = combat_block.get("timing", {})
    timing_attack = timing_block.get("attack_interval_ms")
    timing_move = timing_block.get("move_interval_ms")
    timing_confidence = timing_block.get("confidence", "")
    timing_complete = timing_attack is not None and timing_move is not None

    # Behavior profile from separate file
    has_behavior_profile = mid in behavior_ids_set
    behavior_profile_name = behavior_profile_by_id.get(str(mid), "")

    # Appearance profile check
    art_formal = False
    art_profile_data = appearance_profiles.get(appearance_profile_id, {}) if appearance_profile_id else {}
    if art_profile_data:
        art_formal = art_profile_data.get("status", "") == "formal"

    atlas = art_profile_data.get("atlas", {}) if art_profile_data else {}
    art_has_foot_anchor = "foot_anchor" in atlas and atlas["foot_anchor"] is not None
    art_has_frame_size = "frame_size" in atlas and atlas["frame_size"] is not None
    art_actions = art_profile_data.get("actions", {}) if art_profile_data else {}
    art_has_5_actions = all(a in art_actions for a in REQUIRED_ACTIONS) if isinstance(art_actions, dict) else False

    # Drop profile
    dp = drop_profiles.get(drop_profile_id, {}) if drop_profile_id else {}
    drop_status = dp.get("status", "") if dp else ""
    drop_entry_count = dp.get("entry_count", 0) if dp else 0
    drop_complete = drop_entry_count > 0 or drop_status in ("no_drop_confirmed", "exempt", "no_drop_policy")

    # Check for unresolved item tokens in drop entries
    drop_unresolved = False
    drop_entries_list = dp.get("entries", []) if dp else []
    for de in drop_entries_list:
        item = de.get("item", de.get("item_id", de.get("item_token", "")))
        slot_status = de.get("slot_status", "")
        if not item or item == "unresolved" or "UNRESOLVED" in slot_status:
            drop_unresolved = True
            break

    # Drop policy from entry
    drop_policy = entry.get("drop_policy", {})
    drop_policy_entry_count = drop_policy.get("entry_count", 0)
    drop_policy_hostile = drop_policy.get("hostile_requires_non_empty", False)

    # Classification
    classification_resolved = classification_name not in ("unresolved", "", None)
    placement_allowed = entry.get("editor_placement", {}).get("allowed", False)
    placement_kind = entry.get("editor_placement", {}).get("placement_kind", "")

    # Appearance translation
    appearance_translation = entry.get("appearance_translation")
    translation_required = False
    translation_provided = True
    if appearance_translation:
        translation_required = appearance_translation.get("required", False)
        translation_provided = appearance_translation.get("provided", True)

    # Determine current gate blockers (why runtime_allowed=false)
    current_blockers = []
    if not runtime_allowed:
        # Art gate
        if not appearance_profile_id:
            current_blockers.append("no_appearance_profile")
        elif not art_formal:
            current_blockers.append("art_not_formal")

        # Classification gate
        if not classification_resolved:
            current_blockers.append("classification_unresolved")
        elif classification_name == "version_difference":
            current_blockers.append("version_difference_forces_placement_false")

        # Placement gate (placement_allowed requires drop_ok AND combat_identity_ok)
        if not placement_allowed and classification_resolved and classification_name != "version_difference":
            # Sub-reasons for placement failure
            if not combat_identity_ok:
                current_blockers.append(f"combat_identity_unresolved(resolution={ai_resolution})")
            if classification_name in ("ordinary", "elite", "boss", "special"):
                if drop_entry_count == 0 and not drop_policy.get("exemption"):
                    current_blockers.append("drop_incomplete_for_hostile")
            # If placement is still False but we haven't identified why, it might be a policy override
            if not current_blockers or (len(current_blockers) == 1 and "version_difference" in current_blockers[0]):
                # Check if this is a Wooma ID with policy override
                if mid in (64, 65, 66, 67, 68, 69, 70, 71, 73, 74, 75, 76, 77, 78, 239):
                    current_blockers.append("wooma_matrix_policy_override")

        # Appearance translation gate
        if translation_required and not translation_provided:
            current_blockers.append("appearance_translation_missing")

        if not current_blockers:
            current_blockers.append("unknown_blocker")

    # Deep closure blockers (stricter - what prevents full closure)
    deep_blockers = []
    if not art_has_foot_anchor:
        deep_blockers.append("art_missing_foot_anchor")
    if not art_has_frame_size:
        deep_blockers.append("art_missing_frame_size")
    if not art_has_5_actions and art_profile_data:
        deep_blockers.append("art_missing_actions")
    if not ai_resolved:
        deep_blockers.append("ai_unresolved")
    if not timing_complete:
        deep_blockers.append("timing_incomplete")
    if drop_unresolved:
        deep_blockers.append("drop_unresolved_tokens")
    if not combat_complete:
        deep_blockers.append(f"combat_missing:{','.join(combat_missing)}")
    if not has_behavior_profile:
        deep_blockers.append("no_behavior_profile_mapping")

    # Tier assignment
    if runtime_allowed and len(deep_blockers) == 0:
        tier = "A"
    elif runtime_allowed:
        tier = "B"
    elif len(current_blockers) <= 2:
        tier = "C"
    else:
        tier = "D"

    row = {
        "monster_id": mid,
        "name": name,
        "variant_code": variant,
        "status": status,
        "runtime_allowed": runtime_allowed,
        "art": {
            "formal": art_formal,
            "profile_id": appearance_profile_id or None,
            "has_foot_anchor": art_has_foot_anchor if art_profile_data else None,
            "has_frame_size": art_has_frame_size if art_profile_data else None,
            "has_5_actions": art_has_5_actions if art_profile_data else None,
        },
        "combat": {
            "complete": combat_complete,
            "missing_fields": combat_missing,
            "level": combat_stats.get("level"),
            "hp": combat_stats.get("hp"),
            "attack_min": combat_stats.get("attack_min"),
            "attack_max": combat_stats.get("attack_max"),
            "defense": combat_stats.get("defense"),
            "magic_defense": combat_stats.get("magic_defense"),
            "exp": combat_stats.get("exp"),
            "has_stats_evidence": has_combat_stats_evidence,
            "has_aux_evidence": has_combat_aux_evidence,
        },
        "ai": {
            "resolved": ai_resolved,
            "ai_code": ai_code,
            "view_range": view_range,
            "resolution_status": ai_resolution,
            "combat_identity_ok": combat_identity_ok,
            "source": ai_source,
            "has_behavior_profile": has_behavior_profile,
            "behavior_profile_name": behavior_profile_name if behavior_profile_name else None,
        },
        "timing": {
            "complete": timing_complete,
            "attack_interval_ms": timing_attack,
            "move_interval_ms": timing_move,
            "confidence": timing_confidence,
        },
        "drop": {
            "profile_id": drop_profile_id or None,
            "status": drop_status,
            "entry_count": drop_entry_count,
            "complete": drop_complete,
            "has_unresolved_tokens": drop_unresolved,
        },
        "classification": {
            "resolved": classification_resolved,
            "name": classification_name,
            "placement_allowed": placement_allowed,
            "placement_kind": placement_kind,
        },
        "appearance_translation": {
            "required": translation_required,
            "provided": translation_provided,
        } if appearance_translation else None,
        "current_gate_blockers": current_blockers,
        "deep_closure_blockers": deep_blockers,
        "tier": tier,
    }
    matrix.append(row)

# Summary statistics
total = len(matrix)
runtime_allowed_count = sum(1 for m in matrix if m["runtime_allowed"])
runtime_blocked_count = total - runtime_allowed_count
art_formal_count = sum(1 for m in matrix if m["art"]["formal"])
art_unresolved_count = total - art_formal_count
combat_incomplete_count = sum(1 for m in matrix if not m["combat"]["complete"])
ai_unresolved_count = sum(1 for m in matrix if not m["ai"]["resolved"])
drop_missing_count = sum(1 for m in matrix if not m["drop"]["complete"])
timing_incomplete_count = sum(1 for m in matrix if not m["timing"]["complete"])
classification_unresolved_count = sum(1 for m in matrix if not m["classification"]["resolved"])
false_with_zero_reason = sum(
    1 for m in matrix
    if not m["runtime_allowed"] and len(m["current_gate_blockers"]) == 0
)

tier_a = [m["monster_id"] for m in matrix if m["tier"] == "A"]
tier_b = [m["monster_id"] for m in matrix if m["tier"] == "B"]
tier_c = [m["monster_id"] for m in matrix if m["tier"] == "C"]
tier_d = [m["monster_id"] for m in matrix if m["tier"] == "D"]

# Appearance profiles stats
profiles_total = len(appearance_profiles)
profiles_formal = sum(1 for p in appearance_profiles.values() if p.get("status") == "formal")
profiles_unresolved = profiles_total - profiles_formal
profiles_missing_foot = sum(1 for p in appearance_profiles.values()
    if "foot_anchor" not in p.get("atlas", {}))
profiles_missing_frame = sum(1 for p in appearance_profiles.values()
    if "frame_size" not in p.get("atlas", {}))
profiles_missing_actions = 0
for p in appearance_profiles.values():
    acts = p.get("actions", {})
    if not all(a in acts for a in REQUIRED_ACTIONS):
        profiles_missing_actions += 1

monsters_no_appearance = sum(1 for m in matrix if m["art"]["profile_id"] is None)

# Drop status breakdown
drop_status_counts = {}
for m in matrix:
    s = m["drop"]["status"] or "none"
    drop_status_counts[s] = drop_status_counts.get(s, 0) + 1

# Classification breakdown
classif_counts = {}
for m in matrix:
    c = m["classification"]["name"] or "none"
    classif_counts[c] = classif_counts.get(c, 0) + 1

# Blocker frequency analysis
blocker_freq = {}
for m in matrix:
    for b in m["current_gate_blockers"]:
        blocker_freq[b] = blocker_freq.get(b, 0) + 1

summary = {
    "audit_version": "R4",
    "total_monsters": total,
    "RUNTIME_ALLOWED_COUNT": runtime_allowed_count,
    "RUNTIME_BLOCKED_COUNT": runtime_blocked_count,
    "ART_FORMAL_COUNT": art_formal_count,
    "ART_UNRESOLVED_COUNT": art_unresolved_count,
    "ART_PROFILES_TOTAL": profiles_total,
    "ART_PROFILES_FORMAL": profiles_formal,
    "ART_PROFILES_UNRESOLVED": profiles_unresolved,
    "ART_PROFILES_MISSING_FOOT_ANCHOR": profiles_missing_foot,
    "ART_PROFILES_MISSING_FRAME_SIZE": profiles_missing_frame,
    "ART_PROFILES_MISSING_ACTIONS": profiles_missing_actions,
    "MONSTERS_WITHOUT_APPEARANCE_PROFILE": monsters_no_appearance,
    "COMBAT_STATS_INCOMPLETE": combat_incomplete_count,
    "AI_UNRESOLVED": ai_unresolved_count,
    "DROP_MISSING": drop_missing_count,
    "TIMING_INCOMPLETE": timing_incomplete_count,
    "CLASSIFICATION_UNRESOLVED": classification_unresolved_count,
    "FALSE_WITH_ZERO_REASON_COUNT": false_with_zero_reason,
    "TIER_A_COUNT": len(tier_a),
    "TIER_B_COUNT": len(tier_b),
    "TIER_C_COUNT": len(tier_c),
    "TIER_D_COUNT": len(tier_d),
    "TIER_A_IDS": tier_a,
    "TIER_B_IDS": tier_b,
    "TIER_C_IDS": tier_c,
    "TIER_D_IDS": tier_d,
    "DROP_STATUS_BREAKDOWN": drop_status_counts,
    "CLASSIFICATION_BREAKDOWN": classif_counts,
    "BLOCKER_FREQUENCY": blocker_freq,
    "BEHAVIOR_PROFILE_COVERAGE": len(behavior_ids_set),
    "CLASSIFICATION_OVERRIDE_IDS": len(classif_override_ids),
    "runtime_allowed_logic": {
        "formula": "runtime_allowed = art_ok AND classification_ok AND drop_ok AND combat_identity_ok",
        "art_ok": "appearance_profile status == 'formal'",
        "classification_ok": "classification != 'unresolved' AND placement_allowed",
        "placement_allowed": "base_placement_allowed AND drop_ok AND combat_identity_ok",
        "drop_ok": "drop entry_count > 0 OR has_drop_exemption OR not hostile_classification",
        "combat_identity_ok": "service_exact_for_identity OR auxiliary_combat_evidence",
        "appearance_translation_gate": "if service image != art appearance and translation not provided -> false",
    },
}

# Write outputs
os.makedirs(OUT_DIR, exist_ok=True)

with open(os.path.join(OUT_DIR, "monster_runtime_closure_r4_matrix.json"), "w", encoding="utf-8") as f:
    json.dump(matrix, f, indent=2, ensure_ascii=False)

with open(os.path.join(OUT_DIR, "monster_runtime_closure_r4_summary.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)

print(f"=== Monster Runtime Closure R4 Audit ===")
print(f"Total monsters: {total}")
print(f"Runtime allowed: {runtime_allowed_count}")
print(f"Runtime blocked: {runtime_blocked_count}")
print(f"")
print(f"Art formal: {art_formal_count}, unresolved: {art_unresolved_count}")
print(f"  Profiles: {profiles_total} total, {profiles_formal} formal, {profiles_unresolved} unresolved")
print(f"  Missing foot_anchor: {profiles_missing_foot}, frame_size: {profiles_missing_frame}, actions: {profiles_missing_actions}")
print(f"  Monsters without profile: {monsters_no_appearance}")
print(f"")
print(f"Combat complete: {total - combat_incomplete_count}, incomplete: {combat_incomplete_count}")
print(f"AI resolved: {total - ai_unresolved_count}, unresolved: {ai_unresolved_count}")
print(f"  Behavior profile coverage: {len(behavior_ids_set)} / {total}")
print(f"Timing complete: {total - timing_incomplete_count}, incomplete: {timing_incomplete_count}")
print(f"")
print(f"Drop complete: {total - drop_missing_count}, missing: {drop_missing_count}")
print(f"  Status breakdown: {drop_status_counts}")
print(f"")
print(f"Classification resolved: {total - classification_unresolved_count}, unresolved: {classification_unresolved_count}")
print(f"  Breakdown: {classif_counts}")
print(f"")
print(f"False with zero reason: {false_with_zero_reason}")
print(f"Blocker frequency: {blocker_freq}")
print(f"")
print(f"Tier A (full closure): {len(tier_a)}")
print(f"Tier B (runtime ok, deep blockers): {len(tier_b)}")
print(f"Tier C (blocked, <=2 blockers): {len(tier_c)}")
print(f"Tier D (blocked, 3+ blockers): {len(tier_d)}")
print(f"")
print(f"Files written to {OUT_DIR}")
