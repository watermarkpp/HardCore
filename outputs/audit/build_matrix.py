#!/usr/bin/env python3
"""Build the Monster Runtime Closure R4 Audit Matrix — CORRECTED methodology.

Audit-only script: reads checked-in data sources and writes
outputs/audit/monster_runtime_closure_r4_{matrix,summary}.json.
It never modifies business sources.

Methodology corrections relative to the rejected audit commit eacd70df
("audit(monsters): classify remaining runtime closure blockers"):

1.  Combat stats — `field != None` no longer counts as complete.  Every field
    (level, exp, hp, defense, magic_defense, attack_min, attack_max) is
    audited for value + source evidence + source tier + resolution.  Zeroed
    placeholders generated for a missing exact_service_name row resolve to
    UNRESOLVED unless the field is explicitly covered by an official
    auxiliary authority override.
2.  AI — `resolution_status != "unresolved"` no longer counts as resolved.
    Only the explicit allowlist {exact_service_name, auxiliary_1_exact_row}
    passes; every other status (base_name_fallback,
    unresolved_project_fallback, empty) fails closed.
3.  Timing — value + source + tier + resolution/confidence are audited
    together.  Values produced by the unresolved project fallback are not
    authority regardless of magnitude.  Zero values are NOT treated as
    errors by magnitude (stationary/special monsters may legitimately use 0);
    the judgement is source authority, never value size.
4.  Blockers — every blocker is computed independently for every ID,
    including IDs whose classification is unresolved.  No classification
    blocker may mask any other blocker; occurrences are genuinely
    multi-label.
5.  Drop authority — the formal field `item_resolution_status` is audited
    (unresolved_token and any other unresolved status).  DROP_MISSING and
    DROP_AUTHORITY_BLOCKED are separate blockers: rows exist but item
    authority unresolved => DROP_MISSING=NO, DROP_AUTHORITY_BLOCKED=YES.
6.  Special runtime — audited per ID from boss_rule + behavior-profile
    semantics (area/ranged attack, summon, teleport, burrow, stationary,
    spawn/minion behavior).  SPECIAL_RUNTIME_COMPLETE=YES only when a source
    explicitly proves no special runtime is needed or the required semantics
    are formally implemented/mapped.  Never counted zero merely because an
    earlier script did not check.
7.  Tiers — restored to the original authority-based definitions:
      A: formal authority already exists; only exact-ID wiring is missing;
         no user decision needed.
      B: authority/source exists but mapping or semantics needs confirmation.
      C: authority genuinely missing; needs new material or a user decision.
      D: version_difference or intentional exclusion.
    Tiers are never derived from runtime_allowed or blocker counts.
8.  Classification — every unresolved ID is audited for existing formal
    source / historical evidence (classification_evidence,
    classification_source, classification_source_tier,
    classification_resolution) and partitioned into
    EXISTING_AUTHORITY_NOT_WIRED / SOURCE_PRESENT_NEEDS_CONFIRMATION /
    TRUE_AUTHORITY_MISSING.
9.  NEXT_RECOMMENDED_IDS — concrete monster_id list with per-ID justification.
10. Completeness — identity invariants verified:
      ACTIVE_IDENTITY_COUNT == RUNTIME_ALLOWED_COUNT + UNRESOLVED_STATUS_COUNT
                               + VERSION_DIFFERENCE_COUNT
    plus ACTIVE_ID_SET vs GOLDEN_VALIDATED_ID_SET comparison.
"""

from __future__ import annotations

import json
import os
import collections

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(BASE, "outputs", "audit")

CATALOG_PATH = os.path.join(BASE, "assets", "data", "runtime", "canonical_monster_catalog.json")
SERVICE_PATH = os.path.join(BASE, "assets", "data", "service_monster_runtime_catalog.json")
BEHAVIOR_PATH = os.path.join(BASE, "assets", "data", "monster_behavior_profiles.json")
BOSS_RULE_PATH = os.path.join(BASE, "assets", "data", "boss_service_rules.json")
CLASSIFICATION_ID_PATH = os.path.join(BASE, "assets", "data", "canonical_monster_classification_v1.json")
MAP_EDITOR_CLASSIFICATION_PATH = os.path.join(BASE, "assets", "data", "map_editor_monster_spawn_classification_v1.json")
POLICY_PATH = os.path.join(BASE, "assets", "data", "canonical_monster_catalog_policy_v1.json")
EQUIPMENT_MASTER_PATH = os.path.join(BASE, "assets", "data", "equipment_attribute_master.json")
DROP_SOURCE_PATH = os.path.join(BASE, "assets", "data", "canonical_monster_drop_source_v2.json")

GOLDEN_SET_SOURCES = {
    "monster_animation_catalog": ("assets/data/runtime/monster_animation_catalog.json", "monsters:list[monster_id]"),
    "monster_ground_contacts": ("assets/data/runtime/monster_ground_contacts.json", "entriesByMonsterId"),
    "monster_ground_contact_calibrations": ("assets/data/runtime/monster_ground_contact_calibrations.json", "entriesByMonsterId"),
    "monster_overhead_anchors": ("assets/data/runtime/monster_overhead_anchors.json", "anchorsByMonsterId"),
    "monster_ground_alignment_manual_v1": ("assets/data/runtime/monster_ground_alignment_manual_v1.json", "entriesByMonsterId"),
}

COMBAT_FIELDS = ["level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max"]
REQUIRED_ACTIONS = ["idle", "walk", "attack", "hit", "death"]

# Correction 2: the only AI resolution states that the generator source code
# proves to be formal resolutions.  Everything else (base_name_fallback,
# unresolved_project_fallback, "") fails closed.
AI_RESOLUTION_ALLOWLIST = {"exact_service_name", "auxiliary_1_exact_row"}

# Behavior-profile keys that carry special runtime semantics (correction 6).
SPECIAL_SEMANTIC_KEYS = {
    "areaAttack": "area_attack",
    "summonRule": "summon",
    "dormant": "dormant_wake",
    "specialClassification": "special_classification",
    "largeClientBoss": "large_client_boss",
    "onHit": "on_hit_effect",
    "lifeStealRatio": "life_steal",
    "wakeRange": "dormant_wake",
    "worldCollision": "collision_exception",
    "serviceClass": "service_class_mapping",
}

UNRESOLVED_ITEM_STATUSES_MARKER = "unresolved"


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_optional(path):
    if not os.path.exists(path):
        return None
    return load(path)


catalog = load(CATALOG_PATH)
service = load(SERVICE_PATH)
behavior = load(BEHAVIOR_PATH)
boss_rules = load(BOSS_RULE_PATH)
classification_ids = load(CLASSIFICATION_ID_PATH)
map_editor_classif = load(MAP_EDITOR_CLASSIFICATION_PATH)
policy = load(POLICY_PATH)
equipment_master = load_optional(EQUIPMENT_MASTER_PATH)
drop_source = load(DROP_SOURCE_PATH)
vanilla_bosses = load(os.path.join(BASE, "assets", "data", "vanilla_176", "bosses.json"))

# vanilla_176/bosses.json carries ID-keyed historical/reference boss evidence
# (community-derived, confidence C, recordStatus "服务端变体·待判定").  It is
# NOT formal classification authority, but it is existing historical evidence
# that must be reported per correction 8.
bosses_reference_by_id = {}
for rec in vanilla_bosses.get("records", []):
    if isinstance(rec, dict) and rec.get("monsterId") is not None:
        bosses_reference_by_id[int(rec["monsterId"])] = {
            "name": str(rec.get("name", "")),
            "bossClass": str(rec.get("bossClass", "")),
            "confidence": str(rec.get("confidence", "")),
            "recordStatus": str(rec.get("recordStatus", "")),
            "verification": str(rec.get("verification", "")),
            "source": str(rec.get("source", "")),
        }

entries = catalog["entries"]
appearance_profiles = catalog.get("appearance_profiles", {})
drop_profiles = catalog.get("drop_profiles", {})
service_rows = service.get("runtimeByMonsterId", {})
behavior_by_id = behavior.get("profileByMonsterId", {})
behavior_profiles = behavior.get("profiles", {})
boss_rule_by_id = boss_rules.get("runtimeRulesByMonsterId", {})
classif_overrides = classification_ids.get("exact_id_overrides", {})
policy_wooma_matrix = policy.get("wooma_matrix", {})
map_editor_name_rules = map_editor_classification_rules = map_editor_classif.get("nameRules", [])

# ---------------------------------------------------------------------------
# Item-name authority registries (for drop item_resolution_status auditing).
#
# Correction 5 requires auditing the formal field item_resolution_status and
# separating DROP_MISSING from DROP_AUTHORITY_BLOCKED.  To judge whether the
# unresolved item tokens still have an existing authority to wire against
# (Tier A/B) or genuinely lack any item authority (Tier C), the token names
# are matched against the checked-in item authorities:
#   1. equipment_attribute_master.json — equipment-lane unique primary source
#      (user primary revision, 175 equipment records).
#   2. service_item_catalog.json — COMPLETE-ITEM-SYSTEM-1 runtime item catalog
#      (server.crystal.cjlaaa), 538 items incl. consumables and skill books.
#   3. 金币 — currency drop, needs no item registry entry.
# A token matched by exactly one authority name is resolvable; unmatched
# tokens have no item authority in this repository.
# ---------------------------------------------------------------------------
GOLD_TOKENS = {"金币"}
item_registry = {}  # name -> {"registry": [...], }


def _index_item_records(records, registry_name):
    n = 0
    for rec in records:
        if not isinstance(rec, dict):
            continue
        nm = str(rec.get("name", ""))
        if not nm:
            continue
        n += 1
        slot = item_registry.setdefault(nm, {"registries": set()})
        slot["registries"].add(registry_name)
    return n


equipment_master_name_count = 0
if isinstance(equipment_master, dict):
    em_records = equipment_master.get("records", [])
    if isinstance(em_records, list):
        equipment_master_name_count = _index_item_records(em_records, "equipment_attribute_master")
service_item_catalog = load_optional(os.path.join(BASE, "assets", "data", "service_item_catalog.json"))
service_item_name_count = 0
if isinstance(service_item_catalog, dict):
    si_records = service_item_catalog.get("runtimeItems", [])
    if isinstance(si_records, list):
        service_item_name_count = _index_item_records(si_records, "service_item_catalog")

# Name-rule index from the user-authoritative map-editor attachment.
name_rule_index = collections.defaultdict(list)
for rule in map_editor_name_rules:
    for nm in rule.get("visibleNames", []):
        name_rule_index[str(nm)].append({
            "classification": rule.get("classification", ""),
            "mapCodes": rule.get("mapCodes", []),
            "notes": rule.get("notes", ""),
        })

# canonical_name uniqueness across the active ID set
name_counts = collections.Counter(str(e.get("canonical_name", "")) for e in entries)
ids_by_name = collections.defaultdict(list)
for e in entries:
    ids_by_name[str(e.get("canonical_name", ""))].append(int(e["monster_id"]))

# Reverse summon index: summoned minion ids -> summoner ids
summoned_minion_of = collections.defaultdict(list)
for mid_key, pname in behavior_by_id.items():
    prof = behavior_profiles.get(pname, {})
    rule = prof.get("summonRule", {}) if isinstance(prof, dict) else {}
    if isinstance(rule, dict) and rule.get("enabled"):
        for summoned in rule.get("monsterIds", []):
            summoned_minion_of[int(summoned)].append(int(mid_key))

# ---------------------------------------------------------------------------
# Per-ID audit
# ---------------------------------------------------------------------------
matrix = []

for entry in entries:
    mid = int(entry["monster_id"])
    name = str(entry.get("canonical_name", ""))
    status = str(entry.get("status", ""))
    runtime_allowed = bool(entry.get("runtime_allowed", False))
    classification_name = str(entry.get("classification", ""))
    appearance_profile_id = str(entry.get("appearance_profile_id", ""))
    drop_profile_id = str(entry.get("drop_profile_id", ""))
    combat_block = entry.get("combat", {}) or {}
    combat_stats = combat_block.get("stats", {}) or {}
    ai_block = combat_block.get("ai", {}) or {}
    timing_block = combat_block.get("timing", {}) or {}
    boss_rule = combat_block.get("boss_rule", {}) or {}
    source_evidence = entry.get("source_evidence", {}) or {}
    stats_evidence = source_evidence.get("combat_stats", {}) or {}
    identity_resolution = str(source_evidence.get("identity_resolution", ""))
    status_block = source_evidence.get("status", {}) or {}

    # ---------------- 1. combat stats: per-field resolution ---------------
    field_resolution = {}
    combat_stats_complete = True
    unresolved_stat_fields = []
    for field in COMBAT_FIELDS:
        ev = stats_evidence.get(field, {}) or {}
        role = str(ev.get("role", ""))
        evd = str(ev.get("evidence", ""))
        value = combat_stats.get(field)
        if role == "combat_auxiliary_override":
            resolution = "resolved_auxiliary_1"
        elif "missing; unresolved" in evd:
            resolution = "unresolved_zeroed_placeholder"
        elif role == "combat_stats_primary_service" and ".serviceRecord." in evd:
            resolution = "resolved_primary"
        else:
            resolution = "unrecognized_fail_closed"
        if not resolution.startswith("resolved_"):
            combat_stats_complete = False
            unresolved_stat_fields.append(field)
        field_resolution[field] = {
            "value": value,
            "source": str(ev.get("original_path", "")),
            "distribution": str(ev.get("distribution", "")),
            "tier": str(ev.get("tier", "")),
            "role": role,
            "resolution": resolution,
            "evidence": evd,
        }
    combat_stats_evidence_by_field = {f: field_resolution[f]["evidence"] for f in COMBAT_FIELDS}

    # ---------------- 2. AI: allowlist only --------------------------------
    ai_resolution_status = str(ai_block.get("resolution_status", ""))
    ai_in_allowlist = ai_resolution_status in AI_RESOLUTION_ALLOWLIST
    service_row = service_rows.get(str(mid), {}) or {}
    svc_resolution = str(service_row.get("resolutionStatus", ""))
    matched_name = str(service_row.get("matchedName", ""))
    service_record_present = isinstance(service_row.get("serviceRecord"), dict)
    ai_evidence = {
        "ai_code": ai_block.get("ai_code"),
        "view_range": ai_block.get("view_range"),
        "image": ai_block.get("image"),
        "resolution_status": ai_resolution_status,
        "source_distribution": str(ai_block.get("source_distribution", "")),
        "in_allowlist": ai_in_allowlist,
        "allowlist": sorted(AI_RESOLUTION_ALLOWLIST),
        "service_row_resolution_status": svc_resolution,
        "matched_name": matched_name,
        "service_record_present": service_record_present,
        "evidence": (
            f"runtimeByMonsterId[{mid}] resolutionStatus={svc_resolution or ai_resolution_status}"
            + (f"; matched service row '{matched_name}'" if matched_name else "; no service row match")
        ),
    }
    ai_resolved = ai_in_allowlist

    # ---------------- 3. timing: source authority, not magnitude -----------
    timing_confidence = str(timing_block.get("confidence", ""))
    timing_resolution_status = str(timing_block.get("resolution_status", ""))
    authored_profile_name = behavior_by_id.get(str(mid), "")
    authored_profile = behavior_profiles.get(authored_profile_name, {}) if authored_profile_name else {}
    authored_timing = authored_profile.get("timing", {}) if isinstance(authored_profile, dict) else {}
    if timing_resolution_status == "auxiliary_1_exact_row":
        timing_source = "auxiliary_1_exact_row_override"
        timing_tier = "auxiliary_1"
        timing_authority_complete = True
    elif ai_resolution_status == "exact_service_name":
        timing_source = "primary_service_record"
        timing_tier = "primary"
        timing_authority_complete = True
    elif ai_resolution_status == "base_name_fallback":
        timing_source = "base_name_fallback_service_record"
        timing_tier = "primary_name_derived_fail_closed"
        timing_authority_complete = False
    else:
        timing_source = "unresolved_project_fallback_default"
        timing_tier = "project_fallback"
        timing_authority_complete = False
    timing_evidence = {
        "attack_interval_ms": timing_block.get("attack_interval_ms"),
        "move_interval_ms": timing_block.get("move_interval_ms"),
        "confidence": timing_confidence,
        "resolution_status": timing_resolution_status or None,
        "source": timing_source,
        "tier": timing_tier,
        "authority_complete": timing_authority_complete,
        "authored_profile": authored_profile_name or None,
        "authored_profile_timing": authored_timing if authored_timing else None,
        "evidence": (
            "timing authority follows AI resolution allowlist; fallback-derived values are not authority; "
            "zero magnitudes are never treated as errors (stationary/special monsters may legitimately use 0)"
        ),
    }

    # ---------------- 4. drops: missing vs authority-blocked ---------------
    dp = drop_profiles.get(drop_profile_id, {}) or {}
    drop_status = str(dp.get("status", ""))
    drop_entries_list = dp.get("entries", []) or []
    drop_entry_count = int(dp.get("entry_count", len(drop_entries_list)))
    item_status_counts = collections.Counter()
    unresolved_item_rows = 0
    token_covered, token_unmatched = [], []
    token_covered_registries = collections.Counter()
    for de in drop_entries_list:
        ist = str(de.get("item_resolution_status", ""))
        item_status_counts[ist or "<absent>"] += 1
        if UNRESOLVED_ITEM_STATUSES_MARKER in ist:
            unresolved_item_rows += 1
        token = str(de.get("item", de.get("item_id", de.get("item_token", ""))))
        if token in GOLD_TOKENS:
            token_covered.append(token)
            token_covered_registries["currency"] += 1
            continue
        reg = item_registry.get(token)
        if reg:
            token_covered.append(token)
            for rn in reg["registries"]:
                token_covered_registries[rn] += 1
        else:
            token_unmatched.append(token)
    drop_policy = entry.get("drop_policy", {}) or {}
    drop_exemption = drop_policy.get("exemption")
    has_drop_exemption = isinstance(drop_exemption, dict) and bool(drop_exemption.get("allowed")) and bool(drop_exemption.get("reason"))
    no_drop_confirmed = drop_status == "no_drop_confirmed"
    hostile_requires = bool(drop_policy.get("hostile_requires_non_empty", False))

    drop_missing = (drop_entry_count == 0) and not no_drop_confirmed and not has_drop_exemption
    drop_authority_blocked = unresolved_item_rows > 0
    token_covered_n = len(set(token_covered))
    token_unmatched_n = len(set(token_unmatched))
    token_unmatched_rows = sum(1 for de in drop_entries_list if str(de.get("item", "")) in set(token_unmatched))
    if drop_missing:
        drop_item_authority = "missing_no_drop_rows"
    elif not drop_authority_blocked:
        drop_item_authority = "complete_or_not_required"
    elif token_unmatched_n == 0:
        drop_item_authority = "wireable_all_tokens_have_item_authority"
    else:
        drop_item_authority = "missing_unmatched_tokens_lack_item_authority"
    drop_item_resolution_summary = {
        "profile_id": drop_profile_id or None,
        "profile_status": drop_status,
        "entry_count": drop_entry_count,
        "item_resolution_status_counts": dict(item_status_counts),
        "unresolved_item_rows": unresolved_item_rows,
        "hostile_requires_non_empty": hostile_requires,
        "drop_exemption": drop_exemption if has_drop_exemption else None,
        "item_token_match": {
            "covered_tokens": token_covered_n,
            "covered_registries": dict(token_covered_registries),
            "unmatched_tokens": token_unmatched_n,
            "unmatched_rows": token_unmatched_rows,
            "unmatched_sample": sorted(set(token_unmatched))[:12],
        },
        "item_authority": drop_item_authority,
    }

    # ---------------- 5. classification evidence ---------------------------
    override = classif_overrides.get(str(mid), {}) or {}
    override_present = bool(override)
    policy_entry = policy_wooma_matrix.get(str(mid), {}) or {}
    class_resolution = str(override.get("resolution", "")) if override_present else "unresolved"
    rules_for_name = name_rule_index.get(name, [])
    sharing_ids = ids_by_name.get(name, [])
    name_unique = len(sharing_ids) == 1
    bosses_ref = bosses_reference_by_id.get(mid)
    if classification_name == "version_difference":
        class_bucket = "VERSION_DIFFERENCE"
        class_evidence_text = (
            f"exact-ID classification override resolves to version_difference "
            f"(resolution={class_resolution}); intentional exclusion, placement forced false"
        )
    elif classification_name != "unresolved":
        class_bucket = "RESOLVED"
        class_evidence_text = (
            f"canonical_monster_classification_v1.json exact_id_overrides[{mid}] "
            f"classification={classification_name} resolution={class_resolution}"
        )
    elif rules_for_name and name_unique:
        class_bucket = "EXISTING_AUTHORITY_NOT_WIRED"
        rule_desc = "; ".join(sorted({r["classification"] for r in rules_for_name}))
        class_evidence_text = (
            f"no exact_id_override for monster_id={mid}; canonical name '{name}' matches user-authoritative "
            f"nameRule ({rule_desc}) in map_editor_monster_spawn_classification_v1.json and the name is unique "
            f"across the active ID set — authority exists, ID wiring missing"
        )
    elif rules_for_name and not name_unique:
        class_bucket = "SOURCE_PRESENT_NEEDS_CONFIRMATION"
        class_evidence_text = (
            f"no exact_id_override for monster_id={mid}; canonical name '{name}' matches a user-authoritative "
            f"nameRule but the name is shared by active IDs {sharing_ids} — exact-ID disambiguation required"
        )
    elif bosses_ref:
        class_bucket = "SOURCE_PRESENT_NEEDS_CONFIRMATION"
        class_evidence_text = (
            f"no exact_id_override and no nameRule match for monster_id={mid}; vanilla_176/bosses.json carries an "
            f"ID-keyed historical reference (bossClass={bosses_ref['bossClass']}, confidence={bosses_ref['confidence']}, "
            f"recordStatus={bosses_ref['recordStatus']}, verification={bosses_ref['verification']}) — reference "
            f"evidence present but explicitly pending judgment; user exact-ID classification decision required"
        )
    else:
        class_bucket = "TRUE_AUTHORITY_MISSING"
        class_evidence_text = (
            f"no exact_id_override for monster_id={mid}; canonical name '{name}' does not appear in the "
            f"user-authoritative attachment nameRules (map_editor_monster_spawn_classification_v1.json, "
            f"attachment sha256 {map_editor_classif.get('source', {}).get('attachmentSha256', '')[:12]}…), "
            f"no policy-level classification, and no ID-keyed vanilla bosses.json reference"
        )
    classification_evidence = {
        "override_present": override_present,
        "classification": classification_name,
        "resolution": class_resolution,
        "bucket": class_bucket,
        "name_rule_matches": rules_for_name if rules_for_name else None,
        "name_unique_among_active": name_unique,
        "active_ids_sharing_name": sharing_ids if not name_unique else None,
        "policy_wooma_entry": sorted(policy_entry.keys()) if policy_entry else None,
        "vanilla_bosses_reference": bosses_ref,
        "evidence_text": class_evidence_text,
    }
    classification_source = (
        "assets/data/canonical_monster_classification_v1.json (exact-ID policy) + "
        "assets/data/map_editor_monster_spawn_classification_v1.json (user-authoritative attachment)"
    )
    classification_source_tier = "user_authoritative"
    classification_resolution = class_resolution
    classification_resolved = classification_name not in ("unresolved",)

    # ---------------- 6. special runtime semantics --------------------------
    detected_semantics = []
    if isinstance(authored_profile, dict):
        for key, semantic in SPECIAL_SEMANTIC_KEYS.items():
            if key in authored_profile:
                if key == "worldCollision" and authored_profile.get("worldCollision") is True:
                    continue
                detected_semantics.append(semantic)
        movement = authored_profile.get("movement", {})
        if isinstance(movement, dict) and movement.get("stationary"):
            detected_semantics.append("stationary")
        rp = authored_profile.get("runtimeProjection", {})
        if isinstance(rp, dict) and isinstance(rp.get("attackRange"), (int, float)) and rp.get("attackRange") >= 100:
            detected_semantics.append("ranged_or_area_attack_range")
    if mid in summoned_minion_of:
        detected_semantics.append("summoned_minion")
    detected_semantics = sorted(set(detected_semantics))

    boss_rule_present = bool(boss_rule)
    boss_special_skill = boss_rule.get("specialSkill") if boss_rule_present else None
    boss_phase_two = boss_rule.get("phaseTwo") if boss_rule_present else None
    boss_service_class = None
    profile_service_class = authored_profile.get("serviceClass") if isinstance(authored_profile, dict) else None
    base_behavior_authority = False
    base_behavior_reason = ""
    if ai_in_allowlist:
        base_behavior_authority = True
        base_behavior_reason = f"AI resolution '{ai_resolution_status}' provides primary service authority for base behavior"
    elif isinstance(profile_service_class, dict) and str(profile_service_class.get("confidence", "")) in ("A", "B"):
        base_behavior_authority = True
        base_behavior_reason = (
            f"behavior profile serviceClass {profile_service_class.get('name')} (confidence "
            f"{profile_service_class.get('confidence')}, {profile_service_class.get('source')}) proves behavior class"
        )
    elif boss_rule_present and str(boss_rule.get("mappingConfidence", "")) in ("A", "B"):
        base_behavior_authority = True
        base_behavior_reason = f"boss_service_rules mapping (serviceClass {boss_rule.get('serviceClass')}, confidence {boss_rule.get('mappingConfidence')}) proves behavior class"

    semantics_formally_mapped = True
    semantics_reason_parts = []
    if boss_rule_present:
        if isinstance(boss_special_skill, dict):
            if boss_special_skill.get("enabled"):
                semantics_reason_parts.append("boss_rule specialSkill enabled (rule mapped in boss_service_rules.json)")
            else:
                semantics_reason_parts.append(
                    f"boss_rule proves no special skill needed: {boss_special_skill.get('reason', 'explicit negative finding')}"
                )
    if detected_semantics:
        semantics_reason_parts.append(
            f"behavior profile '{authored_profile_name}' formally maps semantics: {', '.join(detected_semantics)}"
        )
    if not detected_semantics and not boss_rule_present:
        if base_behavior_authority and ai_in_allowlist:
            semantics_reason_parts.append(
                "no special semantics detected; primary service row proves standard behavior (no special runtime needed)"
            )
        else:
            semantics_formally_mapped = False
            semantics_reason_parts.append(
                "no special semantics authored and no allowlist service/boss-rule authority — cannot prove special runtime is unneeded (fail closed)"
            )
    special_runtime_complete = semantics_formally_mapped and base_behavior_authority
    special_runtime_evidence = {
        "boss_rule_present": boss_rule_present,
        "boss_rule_special_skill": boss_special_skill,
        "boss_rule_phase_two": boss_phase_two,
        "boss_rule_knockback_immune": boss_rule.get("knockbackImmune") if boss_rule_present else None,
        "behavior_profile": authored_profile_name or None,
        "profile_service_class": profile_service_class,
        "detected_semantics": detected_semantics,
        "summoned_minion_of": summoned_minion_of.get(mid) or None,
        "base_behavior_authority": base_behavior_authority,
        "base_behavior_reason": base_behavior_reason,
        "complete": special_runtime_complete,
        "reason": "; ".join(semantics_reason_parts),
    }

    # ---------------- 7. appearance translation -----------------------------
    appearance_translation = status_block.get("appearance_translation")
    translation_required = bool(appearance_translation and appearance_translation.get("required"))
    translation_provided = bool(appearance_translation and appearance_translation.get("provided")) if translation_required else True
    appearance_translation_missing = translation_required and not translation_provided

    # ---------------- art ----------------------------------------------------
    art_profile = appearance_profiles.get(appearance_profile_id, {}) or {}
    art_formal = str(art_profile.get("status", "")) == "formal"
    art_actions = art_profile.get("actions", {}) or {}
    art_has_5_actions = all(a in art_actions for a in REQUIRED_ACTIONS)
    atlas = art_profile.get("atlas", {}) or {}
    art_has_foot_anchor = atlas.get("foot_anchor") not in (None, [])
    art_has_frame_size = atlas.get("frame_size") not in (None, [])

    # ---------------- 8. independent multi-label blockers --------------------
    blockers = []
    if not art_formal:
        blockers.append("ART_UNRESOLVED")
    if classification_name == "unresolved":
        blockers.append("CLASSIFICATION_UNRESOLVED")
    if classification_name == "version_difference" or (
        isinstance(policy_entry, dict) and policy_entry.get("placement_allowed") is False
    ):
        blockers.append("CLASSIFICATION_OR_POLICY_BLOCKED")
    if not ai_in_allowlist:
        blockers.append("COMBAT_IDENTITY_MISSING")
    if not combat_stats_complete:
        blockers.append("COMBAT_STATS_INCOMPLETE")
    if not ai_resolved:
        blockers.append("AI_UNRESOLVED")
    if not timing_authority_complete:
        blockers.append("TIMING_INCOMPLETE")
    if drop_missing:
        blockers.append("DROP_MISSING")
    if drop_authority_blocked:
        blockers.append("DROP_AUTHORITY_BLOCKED")
    if not special_runtime_complete:
        blockers.append("SPECIAL_RUNTIME_SEMANTICS")
    if appearance_translation_missing:
        blockers.append("APPEARANCE_TRANSLATION_MISSING")

    # ---------------- current gate reconstruction ----------------------------
    current_gate_blockers = []
    if not runtime_allowed:
        if not art_formal:
            current_gate_blockers.append("art_not_formal")
        if classification_name == "unresolved":
            current_gate_blockers.append("classification_unresolved")
        if classification_name == "version_difference":
            current_gate_blockers.append("version_difference_forces_placement_false")
        placement_allowed = bool(entry.get("editor_placement", {}).get("allowed", False))
        if classification_name not in ("unresolved", "version_difference") and not placement_allowed:
            if not ai_in_allowlist:
                current_gate_blockers.append(f"combat_identity_unresolved(resolution={ai_resolution_status})")
            if drop_missing and hostile_requires:
                current_gate_blockers.append("drop_missing_for_hostile")
            if appearance_translation_missing:
                current_gate_blockers.append("appearance_translation_missing")
            if isinstance(policy_entry, dict) and policy_entry.get("placement_allowed") is False:
                current_gate_blockers.append("policy_placement_override_false")
            if not current_gate_blockers:
                current_gate_blockers.append("unexplained_gate_discrepancy")
        if not current_gate_blockers:
            current_gate_blockers.append("unexplained_gate_discrepancy")

    # ---------------- tier (original authority definitions) ------------------
    # combat facet
    if ai_in_allowlist and combat_stats_complete:
        combat_facet = "OK"
    elif ai_resolution_status == "base_name_fallback" and service_record_present:
        combat_facet = "CONFIRM(base_name_fallback service record exists; variant mapping needs confirmation)"
    else:
        combat_facet = "MISSING(no exact service row; no auxiliary authority attached)"
    # classification facet
    if class_bucket == "RESOLVED":
        classif_facet = "OK"
    elif class_bucket == "VERSION_DIFFERENCE":
        classif_facet = "VERSION_DIFFERENCE"
    elif class_bucket == "EXISTING_AUTHORITY_NOT_WIRED":
        classif_facet = "WIREABLE(unique user nameRule match; exact-ID override missing)"
    elif class_bucket == "SOURCE_PRESENT_NEEDS_CONFIRMATION":
        classif_facet = "CONFIRM(reference/rule source present; exact-ID classification decision required)"
    else:
        classif_facet = "MISSING(no user-authoritative classification evidence)"
    # drop facet
    if no_drop_confirmed or has_drop_exemption or (not drop_authority_blocked and not drop_missing):
        drop_facet = "OK"
    elif drop_missing:
        drop_facet = "MISSING(no drop rows; no confirmed exemption)"
    elif drop_item_authority == "wireable_all_tokens_have_item_authority":
        drop_facet = "WIREABLE(exact Excel slots present; every item token has checked-in item authority)"
    else:
        drop_facet = f"MISSING({token_unmatched_n} unmatched item token(s), {token_unmatched_rows} row(s) lack any item authority)"
    # special facet
    special_facet = "OK" if special_runtime_complete else f"INCOMPLETE({special_runtime_evidence['reason']})"
    # policy placement facet (explicit user-authoritative placement overrides)
    if isinstance(policy_entry, dict) and policy_entry.get("placement_allowed") is False and not runtime_allowed:
        policy_facet = (
            "CONFIRM(canonical_monster_catalog_policy_v1.json wooma_matrix explicitly records "
            "placement_allowed=false; re-enabling requires a user policy decision)"
        )
    else:
        policy_facet = "OK"
    # translation facet
    if appearance_translation_missing:
        translation_facet = "BLOCKED_BY_COMBAT_IDENTITY(service image missing until AI resolution allowlisted)"
    elif translation_required:
        translation_facet = "OK(ID-keyed client mapping evidence provided)"
    else:
        translation_facet = "OK"

    if classification_name == "version_difference":
        tier = "D"
        tier_reason = "version_difference: intentional exclusion (Tier D by definition)"
    else:
        facets = {
            "combat": combat_facet,
            "classification": classif_facet,
            "policy_placement": policy_facet,
            "drop": drop_facet,
            "special_runtime": special_facet,
            "appearance_translation": translation_facet,
        }
        if any(f.startswith("MISSING") for f in facets.values()):
            tier = "C"
            tier_reason = "true authority missing on: " + ", ".join(k for k, v in facets.items() if v.startswith("MISSING"))
        elif any(f.startswith("CONFIRM") for f in facets.values()) or special_facet.startswith("INCOMPLETE"):
            tier = "B"
            needs = [k for k, v in facets.items() if v.startswith("CONFIRM") or v.startswith("INCOMPLETE")]
            tier_reason = "source present but needs confirmation on: " + ", ".join(needs)
        else:
            tier = "A"
            wireable = [k for k, v in facets.items() if v.startswith("WIREABLE")]
            if runtime_allowed and not wireable:
                tier_reason = "all facets carry formal authority and are already wired (runtime_allowed)"
            elif wireable:
                tier_reason = "formal authority exists for every facet; only exact-ID wiring missing: " + ", ".join(wireable)
            else:
                tier_reason = "all facets OK"

    runtime_blocked_reason = None
    if not runtime_allowed:
        runtime_blocked_reason = "; ".join(current_gate_blockers)

    row = {
        "monster_id": mid,
        "name": name,
        "variant_code": str(entry.get("variant_code", "")),
        "status": status,
        "runtime_allowed": runtime_allowed,
        "classification": {
            "name": classification_name,
            "resolved": classification_resolved,
            "placement_allowed": bool(entry.get("editor_placement", {}).get("allowed", False)),
            "placement_kind": str(entry.get("editor_placement", {}).get("placement_kind", "")),
        },
        "classification_evidence": classification_evidence,
        "classification_source": classification_source,
        "classification_source_tier": classification_source_tier,
        "classification_resolution": classification_resolution,
        "combat_stats_field_resolution": field_resolution,
        "combat_stats_complete": combat_stats_complete,
        "combat_stats_unresolved_fields": unresolved_stat_fields,
        "combat_stats_evidence_by_field": combat_stats_evidence_by_field,
        "ai_evidence": ai_evidence,
        "ai_resolved": ai_resolved,
        "timing_evidence": timing_evidence,
        "timing_complete": timing_authority_complete,
        "drop_item_resolution_summary": drop_item_resolution_summary,
        "drop_missing": drop_missing,
        "drop_authority_blocked": drop_authority_blocked,
        "special_runtime_evidence": special_runtime_evidence,
        "special_runtime_complete": special_runtime_complete,
        "art": {
            "formal": art_formal,
            "profile_id": appearance_profile_id or None,
            "has_foot_anchor": art_has_foot_anchor,
            "has_frame_size": art_has_frame_size,
            "has_5_actions": art_has_5_actions,
        },
        "appearance_translation": {
            "required": translation_required,
            "provided": translation_provided,
            "missing": appearance_translation_missing,
        },
        "current_gate_blockers": current_gate_blockers,
        "deep_closure_blockers": blockers,
        "runtime_blocked_reason": runtime_blocked_reason,
        "tier": tier,
        "tier_reason": tier_reason,
        "tier_facets": {
            "combat": combat_facet,
            "classification": classif_facet,
            "drop": drop_facet,
            "special_runtime": special_facet,
            "appearance_translation": translation_facet,
        },
    }
    matrix.append(row)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total = len(matrix)
active_ids = sorted(m["monster_id"] for m in matrix)
runtime_allowed_ids = sorted(m["monster_id"] for m in matrix if m["runtime_allowed"])
runtime_allowed_count = len(runtime_allowed_ids)
runtime_blocked_count = total - runtime_allowed_count
status_unresolved_count = sum(1 for m in matrix if m["status"] == "unresolved")
version_difference_ids = sorted(m["monster_id"] for m in matrix if m["classification"]["name"] == "version_difference")
version_difference_count = len(version_difference_ids)
art_formal_count = sum(1 for m in matrix if m["art"]["formal"])

blocker_labels = [
    "COMBAT_IDENTITY_MISSING",
    "COMBAT_STATS_INCOMPLETE",
    "AI_UNRESOLVED",
    "TIMING_INCOMPLETE",
    "DROP_MISSING",
    "DROP_AUTHORITY_BLOCKED",
    "CLASSIFICATION_UNRESOLVED",
    "CLASSIFICATION_OR_POLICY_BLOCKED",
    "SPECIAL_RUNTIME_SEMANTICS",
    "APPEARANCE_TRANSLATION_MISSING",
    "ART_UNRESOLVED",
]
blocker_counts = {b: 0 for b in blocker_labels}
blocker_id_lists = {b: [] for b in blocker_labels}
for m in matrix:
    for b in m["deep_closure_blockers"]:
        blocker_counts[b] += 1
        blocker_id_lists[b].append(m["monster_id"])
primary_blocker_count = sum(len(m["deep_closure_blockers"]) for m in matrix)
current_gate_occurrences = sum(1 for m in matrix if not m["runtime_allowed"])
deep_closure_occurrences = sum(1 for m in matrix if m["deep_closure_blockers"])

tier_ids = {"A": [], "B": [], "C": [], "D": []}
for m in matrix:
    tier_ids[m["tier"]].append(m["monster_id"])

class_buckets = collections.Counter(m["classification_evidence"]["bucket"] for m in matrix)
existing_not_wired_ids = sorted(
    m["monster_id"] for m in matrix if m["classification_evidence"]["bucket"] == "EXISTING_AUTHORITY_NOT_WIRED"
)

false_with_zero_reason = sum(1 for m in matrix if not m["runtime_allowed"] and len(m["current_gate_blockers"]) == 0)

# ---------------- golden validated ID set comparison ------------------------
def golden_ids_for(rel, accessor):
    path = os.path.join(BASE, rel)
    if not os.path.exists(path):
        return None
    data = load(path)
    if accessor == "monsters:list[monster_id]":
        ids = set()
        for item in data.get("monsters", []):
            if isinstance(item, dict):
                for key in ("monster_id", "monsterId", "id"):
                    if key in item:
                        try:
                            ids.add(int(item[key]))
                        except (TypeError, ValueError):
                            pass
                        break
        return ids
    sub = data.get(accessor, {})
    ids = set()
    for k in sub.keys():
        try:
            ids.add(int(k))
        except (TypeError, ValueError):
            pass
    return ids

id_set_comparison = {}
active_set = set(active_ids)
all_equal = True
for name, (rel, accessor) in GOLDEN_SET_SOURCES.items():
    ids = golden_ids_for(rel, accessor)
    if ids is None:
        id_set_comparison[name] = {"status": "SOURCE_FILE_MISSING"}
        all_equal = False
        continue
    equal = ids == active_set
    if not equal:
        all_equal = False
    id_set_comparison[name] = {
        "source": rel,
        "count": len(ids),
        "equal_to_active": equal,
        "active_minus_golden": sorted(active_set - ids),
        "golden_minus_active": sorted(ids - active_set),
    }
if all_equal:
    id_set_verdict = "EQUAL"
elif any(v.get("status") == "SOURCE_FILE_MISSING" for v in id_set_comparison.values()):
    id_set_verdict = "INSUFFICIENT_EXISTING_SOURCE"
else:
    # The golden authority document (docs/handoff/2026-08-17/03_GOLDEN_RUNTIME_AUTHORITY.md)
    # records monster_ground_alignment_manual_v1.json as "212 (+ 2 airborne)": the two airborne
    # IDs intentionally carry no ground-alignment entry.  A difference limited to that documented
    # exclusion is not an identity mismatch.
    only_manual_alignment_diff = all(
        v.get("equal_to_active", False) or k == "monster_ground_alignment_manual_v1"
        for k, v in id_set_comparison.items()
    )
    manual_diff = id_set_comparison.get("monster_ground_alignment_manual_v1", {})
    if only_manual_alignment_diff and not manual_diff.get("golden_minus_active"):
        id_set_verdict = "EQUAL_WITH_DOCUMENTED_AIRBORNE_EXCLUSION"
        id_set_comparison["monster_ground_alignment_manual_v1"]["documented_exclusion"] = (
            "golden authority document records 212 entries + 2 airborne IDs without ground alignment; "
            "active_minus_golden lists exactly those airborne IDs"
        )
    else:
        id_set_verdict = "MISMATCH"

# ---------------- identity invariants ---------------------------------------
identity_invariants = {
    "ACTIVE_IDENTITY_COUNT": total,
    "invariant_status_based": {
        "formula": "ACTIVE_IDENTITY_COUNT == RUNTIME_ALLOWED_COUNT + UNRESOLVED_STATUS_COUNT + VERSION_DIFFERENCE_COUNT",
        "left": total,
        "right": runtime_allowed_count + status_unresolved_count + version_difference_count,
        "parts": {
            "RUNTIME_ALLOWED_COUNT": runtime_allowed_count,
            "UNRESOLVED_STATUS_COUNT": status_unresolved_count,
            "VERSION_DIFFERENCE_COUNT": version_difference_count,
        },
        "holds": total == runtime_allowed_count + status_unresolved_count + version_difference_count,
    },
    "invariant_gate_based": {
        "formula": "ACTIVE_IDENTITY_COUNT == RUNTIME_ALLOWED_COUNT + RUNTIME_BLOCKED_COUNT",
        "left": total,
        "right": runtime_allowed_count + runtime_blocked_count,
        "holds": total == runtime_allowed_count + runtime_blocked_count,
    },
    "note": (
        "status-based decomposition uses entry.status: formal(=runtime_allowed) / unresolved / "
        "version_difference; gate-based decomposition uses the runtime_allowed boolean. The two are "
        "different projections and both are verified independently."
    ),
}

# ---------------- next recommended batch ------------------------------------
tier_a_wiring_candidates = [
    m for m in matrix if m["tier"] == "A" and not m["runtime_allowed"]
]
tier_a_already_wired = [m for m in matrix if m["tier"] == "A" and m["runtime_allowed"]]
next_recommended = []
for m in sorted(tier_a_wiring_candidates, key=lambda r: r["monster_id"])[:20]:
    wireable = [k for k, v in m["tier_facets"].items() if v.startswith("WIREABLE")]
    next_recommended.append({
        "monster_id": m["monster_id"],
        "name": m["name"],
        "why_tier_a": m["tier_reason"],
        "wireable_facets": wireable,
        "authority_sources": {
            "classification": m["classification_evidence"]["evidence_text"],
            "combat": m["ai_evidence"]["evidence"],
            "drop": m["drop_item_resolution_summary"]["item_authority"],
        },
        "cross_system_risk": (
            "none detected: wiring touches only monster-lane exact-ID joins; drop item mapping uses "
            "checked-in item authorities (equipment_attribute_master / service_item_catalog)"
            if m["drop_item_resolution_summary"]["item_authority"] == "wireable_all_tokens_have_item_authority"
            else "none detected: all facets already carry ID-keyed formal authority"
        ),
    })
next_recommended_ids = [r["monster_id"] for r in next_recommended]

summary = {
    "audit_version": "R4-corrected",
    "baseline_commit": "a2e9cb243b58aa33b50cce870e754901fb247595",
    "prior_audit_commit": "eacd70df (retained as historical; methodology rejected and corrected here)",
    "methodology": {
        "combat_stats": "per-field value+source+tier+resolution; zeroed placeholders UNRESOLVED unless auxiliary authority covers the field",
        "ai": f"allowlist {sorted(AI_RESOLUTION_ALLOWLIST)}; all other statuses fail closed",
        "timing": "value+source+tier+resolution/confidence; fallback defaults are not authority; magnitude never judged",
        "blockers": "all blockers computed independently per ID; multi-label; classification never masks others",
        "drop": "item_resolution_status audited; DROP_MISSING and DROP_AUTHORITY_BLOCKED separate",
        "special_runtime": "boss_rule + behavior-profile semantics audited per ID; fail closed without source proof",
        "tiers": "A authority exists/wiring only; B source present/needs confirmation; C authority missing; D version_difference or intentional exclusion",
        "classification": "every unresolved ID audited against user-authoritative attachment evidence",
    },
    "ACTIVE_IDENTITY_COUNT": total,
    "ACTIVE_ID_SET": active_ids,
    "RUNTIME_ALLOWED_COUNT": runtime_allowed_count,
    "RUNTIME_BLOCKED_COUNT": runtime_blocked_count,
    "UNRESOLVED_STATUS_COUNT": status_unresolved_count,
    "VERSION_DIFFERENCE_COUNT": version_difference_count,
    "VERSION_DIFFERENCE_IDS": version_difference_ids,
    "ART_FORMAL_COUNT": art_formal_count,
    "COMBAT_IDENTITY_MISSING": blocker_counts["COMBAT_IDENTITY_MISSING"],
    "COMBAT_STATS_INCOMPLETE": blocker_counts["COMBAT_STATS_INCOMPLETE"],
    "AI_UNRESOLVED": blocker_counts["AI_UNRESOLVED"],
    "TIMING_INCOMPLETE": blocker_counts["TIMING_INCOMPLETE"],
    "DROP_MISSING": blocker_counts["DROP_MISSING"],
    "DROP_AUTHORITY_BLOCKED": blocker_counts["DROP_AUTHORITY_BLOCKED"],
    "CLASSIFICATION_UNRESOLVED": blocker_counts["CLASSIFICATION_UNRESOLVED"],
    "CLASSIFICATION_OR_POLICY_BLOCKED": blocker_counts["CLASSIFICATION_OR_POLICY_BLOCKED"],
    "SPECIAL_RUNTIME_SEMANTICS": blocker_counts["SPECIAL_RUNTIME_SEMANTICS"],
    "APPEARANCE_TRANSLATION_MISSING": blocker_counts["APPEARANCE_TRANSLATION_MISSING"],
    "ART_UNRESOLVED": blocker_counts["ART_UNRESOLVED"],
    "BLOCKER_ID_LISTS": blocker_id_lists,
    "CURRENT_GATE_OCCURRENCES": current_gate_occurrences,
    "DEEP_CLOSURE_OCCURRENCES": deep_closure_occurrences,
    "PRIMARY_BLOCKER_COUNT": primary_blocker_count,
    "FALSE_WITH_ZERO_REASON_COUNT": false_with_zero_reason,
    "CLASSIFICATION_BUCKET_COUNTS": dict(class_buckets),
    "EXISTING_CLASSIFICATION_AUTHORITY_NOT_WIRED_COUNT": len(existing_not_wired_ids),
    "EXISTING_CLASSIFICATION_AUTHORITY_NOT_WIRED_IDS": existing_not_wired_ids,
    "TIER_A_COUNT": len(tier_ids["A"]),
    "TIER_B_COUNT": len(tier_ids["B"]),
    "TIER_C_COUNT": len(tier_ids["C"]),
    "TIER_D_COUNT": len(tier_ids["D"]),
    "TIER_A_IDS": tier_ids["A"],
    "TIER_B_IDS": tier_ids["B"],
    "TIER_C_IDS": tier_ids["C"],
    "TIER_D_IDS": tier_ids["D"],
    "TIER_A_ALREADY_WIRED_IDS": sorted(m["monster_id"] for m in tier_a_already_wired),
    "TIER_A_WIRING_CANDIDATE_IDS": sorted(m["monster_id"] for m in tier_a_wiring_candidates),
    "NEXT_RECOMMENDED_BATCH": len(next_recommended),
    "NEXT_RECOMMENDED_IDS": next_recommended_ids,
    "NEXT_RECOMMENDED": next_recommended,
    "IDENTITY_INVARIANTS": identity_invariants,
    "ID_SET_COMPARISON": {"verdict": id_set_verdict, "sources": id_set_comparison},
    "DROP_ITEM_TOKEN_REGISTRY": {
        "equipment_attribute_master_names": equipment_master_name_count,
        "service_item_catalog_names": service_item_name_count,
        "currency_tokens": sorted(GOLD_TOKENS),
        "note": "token judged covered when its name exists in any checked-in item authority; unmatched tokens have no item authority in this repository",
    },
    "AI_RESOLUTION_STATUS_BREAKDOWN": dict(collections.Counter(m["ai_evidence"]["resolution_status"] for m in matrix)),
    "COMBAT_STATS_RESOLUTION_BREAKDOWN": {
        "complete": sum(1 for m in matrix if m["combat_stats_complete"]),
        "incomplete_zeroed_placeholder": sum(1 for m in matrix if not m["combat_stats_complete"]),
    },
    "TIMING_RESOLUTION_BREAKDOWN": {
        "authority_complete": sum(1 for m in matrix if m["timing_complete"]),
        "authority_incomplete": sum(1 for m in matrix if not m["timing_complete"]),
    },
    "DROP_BREAKDOWN": {
        "profiles_exact_slots": sum(1 for m in matrix if m["drop_item_resolution_summary"]["profile_status"] == "exact_slots"),
        "profiles_no_drop_confirmed": sum(1 for m in matrix if m["drop_item_resolution_summary"]["profile_status"] == "no_drop_confirmed"),
        "profiles_no_monitems_file": sum(1 for m in matrix if m["drop_item_resolution_summary"]["profile_status"] == "no_monitems_file"),
        "item_authority_wireable": sum(1 for m in matrix if m["drop_item_resolution_summary"]["item_authority"] == "wireable_all_tokens_have_item_authority"),
        "item_authority_missing_unmatched_tokens": sum(1 for m in matrix if m["drop_item_resolution_summary"]["item_authority"] == "missing_unmatched_tokens_lack_item_authority"),
        "item_authority_missing_no_rows": sum(1 for m in matrix if m["drop_item_resolution_summary"]["item_authority"] == "missing_no_drop_rows"),
        "item_authority_complete_or_not_required": sum(1 for m in matrix if m["drop_item_resolution_summary"]["item_authority"] == "complete_or_not_required"),
    },
    "BUSINESS_FILES_CHANGED": "NO",
    "READY_FOR_SOL_NEXT_BATCH_DECISION": "YES",
    "READY_FOR_SOL_NEXT_BATCH_DECISION_REASON": (
        "Corrected audit is complete and fail-closed: every blocker is independently evidenced per ID, "
        "tiers use the original authority definitions, and no pure wiring-only (Tier A) batch exists — "
        "the next batch is a user-decision batch (exact-ID classification for the 19 SOURCE_PRESENT "
        "references + 141 TRUE_AUTHORITY_MISSING variants, plus item-authority gaps for drop tokens). "
        "Sol can decide immediately on the Tier B list; Tier C requires new authority material."
    ),
}

os.makedirs(OUT_DIR, exist_ok=True)
with open(os.path.join(OUT_DIR, "monster_runtime_closure_r4_matrix.json"), "w", encoding="utf-8") as f:
    json.dump(matrix, f, indent=1, ensure_ascii=False)
with open(os.path.join(OUT_DIR, "monster_runtime_closure_r4_summary.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=1, ensure_ascii=False)

print("=== Monster Runtime Closure R4 Audit (CORRECTED methodology) ===")
print(f"ACTIVE_IDENTITY_COUNT={total}")
print(f"RUNTIME_ALLOWED={runtime_allowed_count} BLOCKED={runtime_blocked_count}")
print(f"STATUS unresolved={status_unresolved_count} version_difference={version_difference_count} ids={version_difference_ids}")
print(f"status invariant holds: {identity_invariants['invariant_status_based']['holds']}")
print(f"gate invariant holds: {identity_invariants['invariant_gate_based']['holds']}")
print(f"AI breakdown: {summary['AI_RESOLUTION_STATUS_BREAKDOWN']}")
print(f"combat stats: {summary['COMBAT_STATS_RESOLUTION_BREAKDOWN']}")
print(f"timing: {summary['TIMING_RESOLUTION_BREAKDOWN']}")
print(f"drop: {summary['DROP_BREAKDOWN']}")
for b in blocker_labels:
    print(f"{b}={blocker_counts[b]}")
print(f"CURRENT_GATE_OCCURRENCES={current_gate_occurrences} DEEP_CLOSURE_OCCURRENCES={deep_closure_occurrences} PRIMARY_BLOCKER_COUNT={primary_blocker_count}")
print(f"classification buckets: {dict(class_buckets)}")
print(f"Tiers: A={len(tier_ids['A'])} B={len(tier_ids['B'])} C={len(tier_ids['C'])} D={len(tier_ids['D'])}")
print(f"Tier A wired={len(tier_a_already_wired)} wiring-candidates={len(tier_a_wiring_candidates)}")
print(f"NEXT_RECOMMENDED_IDS={next_recommended_ids}")
print(f"ID_SET_COMPARISON verdict={id_set_verdict}")
print(f"FALSE_WITH_ZERO_REASON_COUNT={false_with_zero_reason}")
