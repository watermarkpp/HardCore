#!/usr/bin/env python3
"""Build and validate the ID-only canonical monster catalog.

The input files are deliberately treated as source evidence, not as runtime
registries.  The emitted catalog is the only runtime join surface: every
lookup is by ``monster_id`` and every uncertain appearance/placement is
explicitly marked unresolved instead of receiving a name-derived fallback.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
VANILLA_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
SERVICE_PATH = ROOT / "assets/data/service_monster_runtime_catalog.json"
BEHAVIOR_PATH = ROOT / "assets/data/monster_behavior_profiles.json"
BOSS_RULE_PATH = ROOT / "assets/data/boss_service_rules.json"
ANIMATION_PATH = ROOT / "assets/data/runtime/monster_animation_catalog.json"
CLASSIFICATION_PATH = ROOT / "assets/data/map_editor_monster_spawn_classification_v1.json"
CLASSIFICATION_ID_PATH = ROOT / "assets/data/canonical_monster_classification_v1.json"
POLICY_PATH = ROOT / "assets/data/canonical_monster_catalog_policy_v1.json"
DROP_SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
# Retired: canonical_monster_drop_overrides_v1.json (Crystal Wooma equivalence)
# is no longer read by the generator and is intentionally absent from
# source_files/generator_input below.
DROP_OVERRIDE_PATH = ROOT / "assets/data/canonical_monster_drop_overrides_v1.json"
ART_PATHS = [
    ROOT / "assets/data/bich_common_client_art_sources.json",
    ROOT / "assets/data/complete_monster_client_art_sources.json",
    ROOT / "assets/data/classic_boss_client_art_sources.json",
]
COMPLETE_MONSTER_ART_SOURCES_PATH = (
    ROOT / "assets/data/complete_monster_client_art_sources.json"
)

REQUIRED_ACTIONS = ("idle", "walk", "attack", "hit", "death")
TEXT_HASH_SUFFIXES = {".json"}
WOOMA_EQUIVALENCE_IDS = {68, 69}
EXCLUDED_PRIVATE_DROP_TOKENS = {"LongBow", "SilverBow"}
WOOma_IDS = (64, 65, 66, 67, 68, 69, 70, 71, 73, 74, 75, 76, 77, 78, 239)
WOOma_SLUG_BY_ID = {
    64: "wooma_soldier",
    65: "wooma_soldier",
    66: "wooma_fighter",
    67: "wooma_fighter",
    68: "wooma_warrior",
    69: "wooma_warrior",
    70: "flaming_wooma",
    71: "flaming_wooma",
    73: "wooma_guardian",
    74: "wooma_guardian",
    75: "wooma_guardian",
    76: "wooma_taurus",
    239: "dark_wooma_taurus",
}

# The old runtime payload sometimes carried agility/anti-poison fields, but
# those values have no authoritative monster-service evidence in this lane.
# Keep the projection explicit and fail-safe: consumers receive the project
# combat defaults, never caller-provided legacy payload values.
RUNTIME_PROJECTION_DEFAULTS = {
    "agility": 15,
    "anti_poison": 0,
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def hash_normalization_for(path: Path) -> str:
    """Return the stable hash contract for a checked-in source file.

    Git may materialize JSON as LF or CRLF depending on the checkout. JSON
    source evidence is therefore hashed from UTF-8 text with all line endings
    normalized to LF. Binary assets (including PNG atlases) retain raw bytes.
    """
    return "lf_text" if path.suffix.lower() in TEXT_HASH_SUFFIXES else "raw_bytes"


def normalized_hash_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if hash_normalization_for(path) != "lf_text":
        return data
    text = data.decode("utf-8")
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def sha256_file(path: Path) -> str:
    return sha256_bytes(normalized_hash_bytes(path))


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - error is reported by caller
        raise RuntimeError(f"cannot parse {path}: {exc}") from exc


def to_int_flag(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on", "y"}:
            return 1
        if normalized in {"0", "false", "no", "off", "n"}:
            return 0
    return default


def source_ref(
    path: Path,
    *,
    role: str,
    distribution: str,
    tier: str,
    field: str | None = None,
    evidence: str | None = None,
) -> dict[str, Any]:
    item: dict[str, Any] = {
        "distribution": distribution,
        "tier": tier,
        "original_path": path.relative_to(ROOT).as_posix(),
        "sha256": sha256_file(path),
        "hash_normalization": hash_normalization_for(path),
        "role": role,
    }
    if field:
        item["field"] = field
    if evidence:
        item["evidence"] = evidence
    return item


def monster_db_binding_evidence(row: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(row, dict):
        return {}
    evidence: dict[str, Any] = {}
    for key in (
        "binding_status",
        "bindingStatus",
        "binding_candidate_count",
        "bindingCandidateCount",
        "source_name",
        "sourceName",
        "source_row_index",
        "sourceRowIndex",
        "source_record_ordinal",
        "sourceRecordOrdinal",
        "source_distribution",
        "sourceDistribution",
        "source_tier",
        "sourceTier",
        "source_path",
        "sourcePath",
        "source_sha256",
        "sourceSha256",
        "provenanceEvidenceSha256",
        "serviceRace",
        "service_race",
        "serviceCoolEye",
        "service_cool_eye",
        "combatAttackSpd",
        "combat_attack_spd",
        "combatWalkSpd",
        "combat_walk_spd",
    ):
        value = row.get(key)
        if value is not None and value != "":
            evidence[key] = value
    if "source_path" in row and "original_path" not in evidence:
        evidence["original_path"] = str(row.get("source_path"))
    elif "sourcePath" in row and "original_path" not in evidence:
        evidence["original_path"] = str(row.get("sourcePath"))
    return evidence


def monster_db_combat_evidence(row: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(row, dict):
        return {}
    evidence: dict[str, Any] = {}
    for key in (
        "sourceDistribution",
        "source_distribution",
        "sourcePath",
        "source_path",
        "sourceSha256",
        "source_sha256",
        "provenanceEvidenceSha256",
        "source_tier",
        "sourceTier",
        "serviceCoolEye",
        "service_cool_eye",
        "combatAttackSpd",
        "combat_attack_spd",
        "combatWalkSpd",
        "combat_walk_spd",
        "serviceRace",
        "service_race",
        "raceImg",
        "appearance",
        "binding_status",
        "binding_status_code",
        "bindingStatus",
        "bindingType",
        "binding_type",
        "sourceRowIndex",
        "source_row_index",
        "sourceRecordOrdinal",
        "source_record_ordinal",
    ):
        value = row.get(key)
        if value is not None and value != "":
            evidence[key] = value
    if "source_path" in row and "original_path" not in evidence:
        evidence["original_path"] = str(row.get("source_path"))
    elif "sourcePath" in row and "original_path" not in evidence:
        evidence["original_path"] = str(row.get("sourcePath"))
    return evidence


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def local_from_res(path_value: str) -> Path:
    return ROOT / path_value.removeprefix("res://").lstrip("/")


def normalize_action(action: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(action)
    path_value = str(result.get("path", ""))
    local_path = local_from_res(path_value) if path_value else None
    result["path"] = path_value
    result["path_sha256"] = (
        sha256_file(local_path) if local_path is not None and local_path.is_file() else ""
    )
    result["source_path_exists"] = bool(local_path is not None and local_path.is_file())
    return result


def mapping_signature(mapping: dict[str, Any]) -> str:
    actions = mapping.get("actions", {})
    value = {
        "appearance": mapping.get("appearance"),
        "raceImg": mapping.get("raceImg"),
        "actionTable": mapping.get("actionTable"),
        "clientLibrary": mapping.get("clientLibrary"),
        "blockBase": mapping.get("blockBase"),
        "frameSize": mapping.get("frameSize"),
        "footAnchor": mapping.get("footAnchor"),
        "actions": {name: actions.get(name, {}).get("path", "") for name in REQUIRED_ACTIONS},
    }
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False).encode("utf-8")
    ).hexdigest()[:16]


def art_profiles() -> tuple[dict[int, str], dict[str, dict[str, Any]], dict[int, dict[str, Any]]]:
    """Return ID -> profile id, profiles, and per-ID art evidence.

    The first matching source is intentional: the Wooma common-client
    manifest is the explicit source for 64..75, then complete client art, and
    finally the classic boss manifest.  No names or suffixes participate.
    """

    id_to_mapping: dict[int, tuple[str, dict[str, Any], Path]] = {}
    for manifest_path in ART_PATHS:
        manifest = load_json(manifest_path)
        by_id = manifest.get("runtimeMappingsByMonsterId", {})
        if isinstance(by_id, dict):
            for raw_id, value in by_id.items():
                monster_id = int(raw_id)
                if monster_id in id_to_mapping:
                    continue
                mapping: dict[str, Any]
                if isinstance(value, str):
                    candidate = manifest.get("runtimeMappings", {}).get(value, {})
                    mapping = candidate if isinstance(candidate, dict) else {}
                elif isinstance(value, dict):
                    mapping = value
                else:
                    mapping = {}
                if mapping:
                    id_to_mapping[monster_id] = (manifest_path.name, mapping, manifest_path)

    profile_by_signature: dict[str, str] = {}
    profiles: dict[str, dict[str, Any]] = {}
    id_to_profile: dict[int, str] = {}
    id_evidence: dict[int, dict[str, Any]] = {}
    for monster_id, (manifest_name, mapping, manifest_path) in sorted(id_to_mapping.items()):
        signature = mapping_signature(mapping)
        profile_id = profile_by_signature.get(signature)
        if profile_id is None:
            slug = str(mapping.get("name", "")).strip().lower().replace(" ", "_")
            if monster_id in WOOma_SLUG_BY_ID:
                slug = WOOma_SLUG_BY_ID[monster_id]
            slug = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in slug).strip("_")
            profile_id = f"appearance.{slug or 'profile'}_{signature}"
            profile_by_signature[signature] = profile_id
            actions = mapping.get("actions", {})
            normalized_actions = {
                action: normalize_action(actions.get(action, {}))
                for action in REQUIRED_ACTIONS
            }
            all_paths_valid = all(
                bool(normalized_actions[action].get("path_sha256"))
                and bool(normalized_actions[action].get("source_path_exists"))
                for action in REQUIRED_ACTIONS
            )
            profiles[profile_id] = {
                "appearance_profile_id": profile_id,
                "status": "formal" if all_paths_valid else "unresolved",
                "atlas": {
                    "appearance": mapping.get("appearance", 0),
                    "race_img": mapping.get("raceImg", 0),
                    "action_table": mapping.get("actionTable", ""),
                    "frame_size": mapping.get("frameSize", []),
                    "foot_anchor": mapping.get("footAnchor", []),
                    "directions": mapping.get("directions", 0),
                    "block_base": mapping.get("blockBase", 0),
                    "client_library": mapping.get("clientLibrary", ""),
                    "client_library_sha256": mapping.get("clientLibrarySha256", ""),
                },
                "actions": normalized_actions,
                "shared_by_ids": [],
                "source_evidence": {
                    "manifest": source_ref(
                        manifest_path,
                        role="explicit_client_art_mapping",
                        distribution=(
                            "source.original_gameofmir.client_wil"
                            if "boss" in manifest_name or "complete" in manifest_name
                            else "source.original_gameofmir.client_wil"
                        ),
                        tier="primary",
                        evidence="ID-keyed client mapping; no name or suffix inference",
                    ),
                    "mapping": {
                        "mapping_confidence": mapping.get("mappingConfidence", ""),
                        "pixel_confidence": mapping.get("pixelConfidence", ""),
                        "mapping_source": mapping.get("mappingSource", ""),
                        "resolution_status": mapping.get("resolutionStatus", ""),
                    },
                },
            }
        profiles[profile_id]["shared_by_ids"].append(monster_id)
        id_to_profile[monster_id] = profile_id
        id_evidence[monster_id] = {
            "status": profiles[profile_id]["status"],
            "manifest": manifest_name,
            "manifest_sha256": sha256_file(manifest_path),
            "manifest_hash_normalization": hash_normalization_for(manifest_path),
            "mapping_source": mapping.get("mappingSource", ""),
            "mapping_confidence": mapping.get("mappingConfidence", ""),
        }
    return id_to_profile, profiles, id_evidence


def classification_for(
    monster_id: int,
    classification_ids: dict[str, Any],
    policy: dict[str, Any],
) -> tuple[str, bool, str, list[str], dict[str, Any]]:
    overrides = classification_ids.get("exact_id_overrides", {})
    override = overrides.get(str(monster_id), {})
    policy_override = policy.get("wooma_matrix", {}).get(str(monster_id), {})
    if not isinstance(override, dict):
        override = {}
    if not isinstance(policy_override, dict):
        policy_override = {}
    classification_name = str(
        policy_override.get("classification", override.get("classification", ""))
    )
    # The build input is already an offline-compiled ID policy.  Name rules
    # from the user attachment are intentionally not read here: production
    # catalog generation must never re-run a name/base-name/alias join.
    unresolved = not classification_name
    if unresolved:
        classification_name = "unresolved"
    policy_table = {}
    placement_allowed = bool(override.get("placement_allowed", True))
    if "placement_allowed" in policy_override:
        placement_allowed = bool(policy_override["placement_allowed"])
    if classification_name in ("unresolved", "version_difference"):
        placement_allowed = False
    placement_kind = str(override.get("placement_kind", ""))
    if placement_kind == "":
        placement_kind = (
            "monster_spawn"
            if classification_name in ("ordinary", "special", "non_hostile", "version_difference")
            else policy_table.get("placement_kind", "")
        )
    if policy_override.get("placement_semantics") == "ordinary_spawn":
        placement_kind = "monster_spawn"
    map_codes: list[str] = []
    for code in policy_override.get("map_codes", override.get("map_codes", [])):
        if str(code) not in map_codes:
            map_codes.append(str(code))
    evidence = {
        "source": source_ref(
            CLASSIFICATION_ID_PATH,
            role="classification_and_editor_placement",
            distribution="source.user_authoritative_attachment",
            tier="user_authoritative",
            evidence="Persisted exact monster_id policy; runtime generator performs no name join",
        ),
        "attachment_source": {
            "path": str(classification_ids.get("source_path", "")),
            "sha256": str(classification_ids.get("source_attachment_sha256", "")),
            "resolution_policy": str(classification_ids.get("resolution_policy", "")),
        },
        "matched_exact_id": bool(override),
        "resolution": str(override.get("resolution", "unresolved")),
        "unresolved": unresolved,
    }
    exemption = override.get("drop_exemption", {})
    if isinstance(exemption, dict) and exemption.get("allowed") and exemption.get("reason"):
        evidence["drop_exemption"] = {
            "allowed": True,
            "reason": str(exemption.get("reason")),
        }
    return classification_name, placement_allowed, placement_kind, map_codes, evidence


def behavior_for(
    monster_id: int,
    service: dict[str, Any],
    behavior: dict[str, Any],
    boss_rules: dict[str, Any],
    combat_binding: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    service_row = service.get("runtimeByMonsterId", {}).get(str(monster_id), {})
    service_behavior = service_row.get("behaviorProfile", {}) if isinstance(service_row, dict) else {}
    profile_id = behavior.get("profileByMonsterId", {}).get(str(monster_id), "")
    authored = behavior.get("profiles", {}).get(profile_id, {})
    merged_profile = deep_merge(authored if isinstance(authored, dict) else {}, service_behavior if isinstance(service_behavior, dict) else {})
    timing = copy.deepcopy(merged_profile.get("timing", {}))
    service_behavior_value = copy.deepcopy(merged_profile.get("serviceBehavior", {}))
    if not timing and isinstance(service_row, dict):
        row = service_row.get("serviceRecord", {})
        timing = {
            "attackIntervalMs": row.get("attackIntervalMs", 0),
            "moveIntervalMs": row.get("moveIntervalMs", 0),
            "confidence": "service_record",
        }
    if not service_behavior_value and isinstance(service_row, dict):
        row = service_row.get("serviceRecord", {})
        service_behavior_value = {
            "aiCode": row.get("aiCode", -1),
            "image": row.get("image", -1),
            "viewRange": row.get("viewRange", 0),
            "resolutionStatus": service_row.get("resolutionStatus", ""),
        }
    boss_rule = boss_rules.get("runtimeRulesByMonsterId", {}).get(str(monster_id), {})
    if not isinstance(boss_rule, dict):
        boss_rule = {}
    ai = {
        "ai_code": int(service_behavior_value.get("aiCode", -1)),
        "view_range": int(service_behavior_value.get("viewRange", 0)),
        "image": int(service_behavior_value.get("image", -1)),
        "resolution_status": str(
            service_behavior_value.get(
                "resolutionStatus", service_row.get("resolutionStatus", "") if isinstance(service_row, dict) else ""
            )
        ),
        "source_distribution": service_behavior_value.get("sourceDistribution", ""),
    }
    timing_out = {
        "attack_interval_ms": int(timing.get("attackIntervalMs", timing.get("attack_interval_ms", 0))),
        "move_interval_ms": int(timing.get("moveIntervalMs", timing.get("move_interval_ms", 0))),
        "confidence": str(timing.get("confidence", "")),
    }
    evidence = {
        "service": source_ref(
            SERVICE_PATH,
            role="service_ai_and_timing",
            distribution="source.original_gameofmir.server_suite",
            tier="primary",
            evidence="Direct monster_id row; unresolved source status is retained, never name-resolved",
        ),
        "behavior": source_ref(
            BEHAVIOR_PATH,
            role="behavior_profile",
            distribution="project.monster_behavior_profiles",
            tier="primary",
            evidence=f"profileByMonsterId[{monster_id}]={profile_id or 'none'}",
        ),
    }
    combat_db_evidence = monster_db_combat_evidence(
        combat_binding if isinstance(combat_binding, dict) else {}
    )
    if combat_db_evidence:
        evidence["combat_monster_db"] = combat_db_evidence
    return merged_profile, ai, timing_out, {"boss_rule": boss_rule, "evidence": evidence}


def _drop_source_evidence(record: dict[str, Any], *, role: str, tier: str | None = None) -> dict[str, Any]:
    """Convert an ID-keyed drop source record into auditable evidence.

    ``canonical_monster_drop_source_v2.json`` is the user-locked Excel drop
    authority (217 MonsterDB records / 9590 independent drop slots), built
    deterministically by tools/import_canonical_monster_drop_excel.py and
    pinned to the workbook SHA256.  Its rows retain the source path and
    workbook hash even when the workbook is not present in this worktree, so
    the drop authority is always an explicit, reviewable source result.
    """
    return {
        "distribution": str(record.get("source_distribution", "")),
        "tier": tier or ("primary" if record.get("status") in ("available", "empty") else "primary"),
        "original_path": str(record.get("source_path", "")),
        "sha256": str(record.get("source_sha256", "")),
        "role": role,
        "row_count": int(record.get("line_count", len(record.get("rows", [])))),
        "resolution": str(record.get("primary_resolution", record.get("status", ""))),
    }


def _filter_wooma_equivalence_rows(monster_id: int, rows: list[Any]) -> tuple[list[Any], list[str]]:
    """Filter only the audited private tokens for the 68/69 equivalence path."""
    filtered: list[Any] = []
    removed: list[str] = []
    for row in rows:
        item = str(row.get("item", "")) if isinstance(row, dict) else ""
        if monster_id in WOOMA_EQUIVALENCE_IDS and item in EXCLUDED_PRIVATE_DROP_TOKENS:
            removed.append(item)
            continue
        filtered.append(copy.deepcopy(row))
    return filtered, sorted(set(removed))


def validate_drop_equivalence_inputs(
    policy: dict[str, Any],
    drop_overrides: dict[str, Any],
    drop_source_by_id: dict[str, Any],
) -> list[str]:
    """Ensure the Wooma cross-distribution decision is explicit and aligned."""
    errors: list[str] = []
    expected_ids = {"68": 66, "69": 67}
    for raw_id, canonical_id in expected_ids.items():
        policy_entry = policy.get("wooma_matrix", {}).get(raw_id, {})
        policy_equivalence = policy_entry.get("drop_equivalence_override", {}) if isinstance(policy_entry, dict) else {}
        override = drop_overrides.get(raw_id, {})
        override_equivalence = override.get("auxiliary_2_equivalence", {}) if isinstance(override, dict) else {}
        selected_source = override.get("selected_source", {}) if isinstance(override, dict) else {}
        if policy_equivalence.get("strategy") != "cross_distribution_equivalence" or policy_equivalence.get("equivalence_status") != "byte_exact_cross_distribution":
            errors.append(f"Wooma monster_id={raw_id} policy lacks explicit cross-distribution equivalence")
        if override_equivalence.get("strategy") != policy_equivalence.get("strategy") or override_equivalence.get("status") != policy_equivalence.get("equivalence_status"):
            errors.append(f"Wooma monster_id={raw_id} override/policy equivalence strategy mismatch")
        if int(override_equivalence.get("canonical_source_monster_id", -1)) != canonical_id:
            errors.append(f"Wooma monster_id={raw_id} override canonical source mismatch")
        policy_pairs = policy_equivalence.get("auxiliary_2_pairs", [])
        override_pairs = override_equivalence.get("pairs", [])
        if policy_pairs != override_pairs:
            errors.append(f"Wooma monster_id={raw_id} policy/override equality evidence mismatch")
        source_record = drop_source_by_id.get(str(canonical_id), {})
        expected_count = 58 if canonical_id == 66 else 62
        if not isinstance(source_record, dict) or int(source_record.get("line_count", 0)) != expected_count:
            errors.append(f"Wooma monster_id={raw_id} canonical source {canonical_id} row count mismatch")
        if int(selected_source.get("canonical_source_monster_id", -1)) != canonical_id:
            errors.append(f"Wooma monster_id={raw_id} selected source canonical ID mismatch")
        if str(selected_source.get("sha256", "")).upper() != str(source_record.get("source_sha256", "")).upper():
            errors.append(f"Wooma monster_id={raw_id} selected source hash mismatch")
        if int(selected_source.get("row_count", 0)) != expected_count:
            errors.append(f"Wooma monster_id={raw_id} selected source row count mismatch")
    return errors


def drop_for(
    monster_id: int,
    drop_source_by_id: dict[str, Any],
    drop_overrides: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    """Build a complete drop profile from ID-keyed inputs only.

    Empty primary tables are retained as evidence and may descend through an
    explicit ID override.  For Wooma 68/69, the override records the
    auxiliary-1 empty file and the byte-exact auxiliary-2 equivalence, then
    copies the ID-keyed primary rows for stable 66/67.  No source name,
    base-name, suffix, alias, or community runtime map participates.
    """
    profile_id = f"drop.{monster_id}"
    source_record = drop_source_by_id.get(str(monster_id), {})
    if not isinstance(source_record, dict):
        source_record = {}
    primary_rows = source_record.get("rows", [])
    if not isinstance(primary_rows, list):
        primary_rows = []
    evidence: list[dict[str, Any]] = [_drop_source_evidence(source_record, role="drop_profile_primary")]
    override = drop_overrides.get(str(monster_id), {})
    if not isinstance(override, dict):
        override = {}
    primary_exact = override.get("primary_exact_evidence", {})
    if isinstance(primary_exact, dict) and primary_exact:
        evidence[0] = {
            "distribution": str(primary_exact.get("distribution", "")),
            "tier": str(primary_exact.get("tier", "primary")),
            "original_path": str(primary_exact.get("original_path", "")),
            "sha256": str(primary_exact.get("sha256", "")),
            "role": "drop_profile_primary_exact_missing",
            "row_count": int(primary_exact.get("row_count", 0)),
            "resolution": str(primary_exact.get("resolution", "")),
        }
    selected_source = override.get("selected_source", {})
    selected_rows = override.get("rows", [])
    equivalence = override.get("auxiliary_2_equivalence", {})
    canonical_source_id = (
        selected_source.get("canonical_source_monster_id")
        if isinstance(selected_source, dict)
        else None
    )
    if canonical_source_id is None and isinstance(equivalence, dict):
        canonical_source_id = equivalence.get("canonical_source_monster_id")
    if canonical_source_id is not None:
        canonical_record = drop_source_by_id.get(str(int(canonical_source_id)), {})
        canonical_rows = canonical_record.get("rows", []) if isinstance(canonical_record, dict) else []
        if not isinstance(canonical_rows, list):
            canonical_rows = []
        if canonical_rows:
            upstream_empty = override.get("primary_empty_evidence", {})
            if isinstance(upstream_empty, dict):
                evidence.append(
                    {
                        "distribution": str(upstream_empty.get("distribution", "")),
                        "tier": str(upstream_empty.get("tier", "")),
                        "original_path": str(upstream_empty.get("original_path", "")),
                        "sha256": str(upstream_empty.get("sha256", "")),
                        "role": "drop_profile_auxiliary_empty",
                        "row_count": int(upstream_empty.get("row_count", 0)),
                        "resolution": str(upstream_empty.get("resolution", "")),
                    }
                )
            if isinstance(equivalence, dict) and equivalence:
                pairs = equivalence.get("pairs", [])
                first_pair = pairs[0] if isinstance(pairs, list) and pairs and isinstance(pairs[0], dict) else {}
                evidence.append(
                    {
                        "distribution": str(first_pair.get("distribution", "")),
                        "tier": "auxiliary_2",
                        "original_path": str(first_pair.get("warrior_path", "")),
                        "sha256": str(first_pair.get("warrior_sha256", "")),
                        "role": "drop_profile_auxiliary_2_equivalence",
                        "row_count": len(canonical_rows),
                        "resolution": str(equivalence.get("status", "")),
                        "strategy": str(equivalence.get("strategy", "")),
                        "canonical_source_monster_id": int(canonical_source_id),
                        "pairs": copy.deepcopy(pairs),
                    }
                )
            selected_evidence = {
                "distribution": str(selected_source.get("distribution", "")),
                "tier": str(selected_source.get("tier", "primary")),
                "original_path": str(selected_source.get("original_path", "")),
                "sha256": str(selected_source.get("sha256", "")),
                "role": "drop_profile_selected_canonical_source",
                "row_count": int(selected_source.get("row_count", len(canonical_rows))),
                "resolution": str(selected_source.get("resolution", "")),
                "canonical_source_monster_id": int(canonical_source_id),
            }
            evidence.append(selected_evidence)
            rows, filtered_tokens = _filter_wooma_equivalence_rows(monster_id, canonical_rows)
            for row in rows:
                if isinstance(row, dict):
                    row.setdefault("item_resolution_status", "unresolved_token")
            if filtered_tokens:
                selected_evidence["filtered_audited_private_token_count"] = len(filtered_tokens)
            profile = {
                "drop_profile_id": profile_id,
                "status": "formal_id_keyed_cross_distribution_equivalence",
                "entries": rows,
                "entry_count": len(rows),
                "source_evidence": {"sources": evidence},
            }
            if filtered_tokens:
                profile["filtered_audited_private_token_count"] = len(filtered_tokens)
            return profile_id, profile
    if isinstance(selected_source, dict) and isinstance(selected_rows, list) and selected_rows:
        upstream_empty = override.get("primary_empty_evidence", {})
        if isinstance(upstream_empty, dict):
            evidence.append(
                {
                    "distribution": str(upstream_empty.get("distribution", "")),
                    "tier": str(upstream_empty.get("tier", "")),
                    "original_path": str(upstream_empty.get("original_path", "")),
                    "sha256": str(upstream_empty.get("sha256", "")),
                    "role": "drop_profile_auxiliary_empty",
                    "row_count": int(upstream_empty.get("row_count", 0)),
                    "resolution": str(upstream_empty.get("resolution", "")),
                }
            )
        evidence.append(
            {
                "distribution": str(selected_source.get("distribution", "")),
                "tier": str(selected_source.get("tier", "")),
                "original_path": str(selected_source.get("original_path", "")),
                "sha256": str(selected_source.get("sha256", "")),
                "role": "drop_profile_selected_id_override",
                "row_count": int(selected_source.get("row_count", len(selected_rows))),
                "resolution": str(selected_source.get("resolution", "")),
            }
        )
        rows = copy.deepcopy(selected_rows)
        return profile_id, {
            "drop_profile_id": profile_id,
            "status": "formal_id_keyed_auxiliary",
            "entries": rows,
            "entry_count": len(rows),
            "source_evidence": {"sources": evidence},
        }
    if primary_rows:
        # Preserve every parsed row, including duplicate item/chance rows.
        rows = copy.deepcopy(primary_rows)
        for row in rows:
            if isinstance(row, dict):
                row.setdefault("item_resolution_status", "unresolved_token")
        evidence[0]["row_count"] = len(rows)
        return profile_id, {
            "drop_profile_id": profile_id,
            "status": "exact_slots",
            "entries": rows,
            "entry_count": len(rows),
            "source_evidence": {"sources": evidence},
        }
    source_status = str(source_record.get("status", ""))
    empty_status = source_status if source_status in ("no_drop_confirmed", "no_monitems_file") else "missing_for_hostile"
    return profile_id, {
        "drop_profile_id": profile_id,
        "status": empty_status,
        "entries": [],
        "entry_count": 0,
        "source_evidence": {"sources": evidence},
    }


def build_catalog() -> dict[str, Any]:
    vanilla = load_json(VANILLA_PATH)
    service = load_json(SERVICE_PATH)
    behavior = load_json(BEHAVIOR_PATH)
    boss_rules = load_json(BOSS_RULE_PATH)
    complete_art_source = load_json(COMPLETE_MONSTER_ART_SOURCES_PATH)
    classification_ids = load_json(CLASSIFICATION_ID_PATH)
    policy = load_json(POLICY_PATH)
    drop_source = load_json(DROP_SOURCE_PATH)
    drop_source_by_id = {
        str(item.get("stable_monster_id")): item
        for item in drop_source.get("records", [])
        if isinstance(item, dict) and item.get("stable_monster_id") is not None
    }
    # The Excel 217-record drop source is the canonical authority and already
    # carries direct 68/69 rows, so the Crystal cross-distribution Wooma
    # equivalence override is retired (no longer primary).
    drop_overrides: dict[str, Any] = {}
    id_to_art, appearance_profiles, art_evidence = art_profiles()
    records = vanilla.get("records", [])
    complete_art_by_id = (
        complete_art_source.get("runtimeMappingsByMonsterId", {})
        if isinstance(complete_art_source, dict)
        else {}
    )
    entries: list[dict[str, Any]] = []
    drop_profiles: dict[str, dict[str, Any]] = {}
    entries_by_id: dict[str, dict[str, Any]] = {}
    for record in sorted(records, key=lambda item: int(item.get("monsterId", -1))):
        monster_id = int(record.get("monsterId", -1))
        policy_wooma = policy.get("wooma_matrix", {}).get(str(monster_id), {})
        if not isinstance(policy_wooma, dict):
            policy_wooma = {}
        service_row_for_identity = service.get("runtimeByMonsterId", {}).get(str(monster_id), {})
        service_record_for_identity = (
            service_row_for_identity.get("serviceRecord", {})
            if isinstance(service_row_for_identity, dict)
            else {}
        )
        art_binding = monster_db_binding_evidence(
            complete_art_by_id.get(str(monster_id), {})
        )
        service_exact_for_identity = (
            isinstance(service_row_for_identity, dict)
            and service_row_for_identity.get("resolutionStatus") == "exact_service_name"
            and isinstance(service_record_for_identity, dict)
        )
        canonical_name_override = policy_wooma.get("canonical_name_override", {})
        if service_exact_for_identity:
            canonical_name = str(service_record_for_identity.get("serviceName", ""))
            canonical_name_evidence = source_ref(
                SERVICE_PATH,
                role="canonical_name_primary_service",
                distribution="server.crystal.cjlaaa",
                tier="primary",
                field="serviceRecord.serviceName",
                evidence=f"runtimeByMonsterId[{monster_id}].serviceRecord.serviceName",
            )
            canonical_name_evidence.update(art_binding)
            identity_resolution = "exact_service_name"
        elif isinstance(canonical_name_override, dict) and canonical_name_override.get("value"):
            canonical_name = str(canonical_name_override.get("value"))
            aux = policy_wooma.get("auxiliary_source", {})
            canonical_name_evidence = {
                "distribution": str(aux.get("distribution", "")),
                "tier": str(aux.get("tier", "auxiliary_1")),
                "original_path": str(aux.get("original_path", "")),
                "sha256": str(aux.get("sha256", "")),
                "role": "canonical_name_auxiliary_override",
                "field": str(canonical_name_override.get("field", "MonsterName")),
                "evidence": f"primary exact missing; explicit auxiliary name row for monster_id={monster_id}",
            }
            identity_resolution = "auxiliary_1_exact_name"
        else:
            canonical_name = str(record.get("name", ""))
            canonical_name_evidence = source_ref(
                VANILLA_PATH,
                role="stable_identity_namespace_display_name",
                distribution="source.vanilla_176",
                tier="identity_namespace",
                field="canonical_name",
                evidence=f"records[{monster_id}].name; no exact service name, display only",
            )
            identity_resolution = "unresolved_service_name"
        classification_name, placement_allowed, placement_kind, map_codes, class_evidence = classification_for(
            monster_id, classification_ids, policy
        )
        art_profile_id = id_to_art.get(monster_id, f"appearance.unresolved.{monster_id}")
        if monster_id not in id_to_art:
            appearance_profiles.setdefault(
                art_profile_id,
                {
                    "appearance_profile_id": art_profile_id,
                    "status": "unresolved",
                    "atlas": {"appearance": 0, "race_img": 0, "action_table": "", "frame_size": [], "foot_anchor": [], "directions": 0, "block_base": 0, "client_library": "", "client_library_sha256": ""},
                    "actions": {action: {"path": "", "path_sha256": "", "source_path_exists": False} for action in REQUIRED_ACTIONS},
                    "shared_by_ids": [monster_id],
                    "source_evidence": {"missing": "No ID-keyed explicit client art mapping in current manifests"},
                },
            )
            art_evidence[monster_id] = {"status": "unresolved", "manifest": "", "manifest_sha256": "", "mapping_source": "", "mapping_confidence": ""}
        service_row = service.get("runtimeByMonsterId", {}).get(str(monster_id), {})
        service_record = service_row.get("serviceRecord", {}) if isinstance(service_row, dict) else {}
        service_exact = (
            isinstance(service_row, dict)
            and service_row.get("resolutionStatus") == "exact_service_name"
            and isinstance(service_record, dict)
        )
        if service_exact:
            service_stats = service_record.get("stats", {})
            stats = {
                "level": int(service_record.get("level", 0)),
                "exp": int(service_record.get("experience", 0)),
                "hp": int(service_stats.get("12", 0)),
                "defense": int(service_stats.get("0", 0)),
                "magic_defense": int(service_stats.get("2", 0)),
                "attack_min": int(service_stats.get("4", 0)),
                "attack_max": int(service_stats.get("5", 0)),
            }
            service_field_paths = {
                "level": "level",
                "exp": "experience",
                "hp": "stats.12",
                "defense": "stats.0",
                "magic_defense": "stats.2",
                "attack_min": "stats.4",
                "attack_max": "stats.5",
            }
            stats_source = {
                field: source_ref(
                    SERVICE_PATH,
                    role="combat_stats_primary_service",
                    distribution="server.crystal.cjlaaa",
                    tier="primary",
                    field=field,
                    evidence=f"runtimeByMonsterId[{monster_id}].serviceRecord.{service_field_paths[field]}",
                )
                for field in stats
            }
            for field in stats_source.values():
                if isinstance(field, dict):
                    field.update(art_binding)
        else:
            # The vanilla project table is an identity namespace only.  A
            # missing/non-exact service row cannot silently supply combat
            # numbers; unresolved records carry zeroed values and remain
            # fail-closed until a tiered stat source is attached.
            stats = {field: 0 for field in ("level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max")}
            stats_source = {
                field: source_ref(
                    SERVICE_PATH,
                    role="combat_stats_primary_service",
                    distribution="server.crystal.cjlaaa",
                    tier="primary",
                    field=field,
                    evidence=f"runtimeByMonsterId[{monster_id}] exact_service_name row missing; unresolved",
                )
                for field in stats
            }
        auxiliary_combat_evidence: dict[str, Any] = {}
        if isinstance(service_row, dict):
            cross_verified_21cq = to_int_flag(
                service_row.get("cross_verified_21cq", 0)
            )
        elif isinstance(service_record, dict):
            cross_verified_21cq = to_int_flag(
                service_record.get("cross_verified_21cq", 0)
            )
        else:
            cross_verified_21cq = 0
        stats["cross_verified_21cq"] = cross_verified_21cq
        if "cross_verified_21cq" not in stats_source:
            stats_source["cross_verified_21cq"] = source_ref(
                SERVICE_PATH,
                role="combat_stats_primary_service",
                distribution="server.crystal.cjlaaa",
                tier="primary",
                field="cross_verified_21cq",
                evidence=f"runtimeByMonsterId[{monster_id}] cross_verified_21cq",
            )
        if isinstance(policy_wooma, dict) and isinstance(policy_wooma.get("combat_override"), dict):
            override = policy_wooma["combat_override"]
            for field, value in override.items():
                if field in stats:
                    stats[field] = int(value)
            aux = policy_wooma.get("auxiliary_source", {})
            for field in aux.get("fields", []):
                evidence = {
                    "distribution": aux.get("distribution", ""),
                    "tier": aux.get("tier", "auxiliary_1"),
                    "original_path": aux.get("original_path", ""),
                    "sha256": aux.get("sha256", ""),
                    "role": "combat_auxiliary_override",
                    "field": field,
                    "evidence": f"primary exact missing; auxiliary field override for monster_id={monster_id}",
                }
                auxiliary_combat_evidence[field] = evidence
                if field in stats:
                    stats_source[field] = evidence
        merged_behavior, ai, timing, behavior_extra = behavior_for(
            monster_id,
            service,
            behavior,
            boss_rules,
            art_binding,
        )
        runtime_projection = {
            "agility": int(RUNTIME_PROJECTION_DEFAULTS["agility"]),
            "anti_poison": int(RUNTIME_PROJECTION_DEFAULTS["anti_poison"]),
            "source_evidence": {
                field: source_ref(
                    POLICY_PATH,
                    role="runtime_projection_safe_default",
                    distribution="project.monster_runtime_contract",
                    tier="project_rule",
                    field=field,
                    evidence=(
                        "No authoritative monster-service field; canonical runtime uses the safe project default "
                        "and ignores legacy caller payload values"
                    ),
                )
                for field in RUNTIME_PROJECTION_DEFAULTS
            },
        }
        # The phase-1 Wooma matrix supplies a complete auxiliary row for 68/69.
        # Do not copy serviceIndex or label a service fallback as auxiliary
        # evidence: every overridden field carries the candidate CSV hash.
        if isinstance(policy_wooma, dict) and isinstance(policy_wooma.get("combat_override"), dict):
            override = policy_wooma["combat_override"]
            if "ai_code" in override:
                ai["ai_code"] = int(override["ai_code"])
            if "view_range" in override:
                ai["view_range"] = int(override["view_range"])
            if "image" in override:
                ai["image"] = int(override["image"])
            if "attack_interval_ms" in override:
                timing["attack_interval_ms"] = int(override["attack_interval_ms"])
            if "move_interval_ms" in override:
                timing["move_interval_ms"] = int(override["move_interval_ms"])
            if auxiliary_combat_evidence:
                ai["source"] = "auxiliary_1"
                ai["resolution_status"] = "auxiliary_1_exact_row"
                ai["source_distribution"] = "source.angelk727.mir2_server_databases"
                timing["source"] = "auxiliary_1"
                timing["confidence"] = "auxiliary_1"
                timing["resolution_status"] = "auxiliary_1_exact_row"
                # Ensure EnemyActor and any other canonical consumer sees the
                # same authoritative timing/AI, without consulting the old
                # service catalog's fallback row.
                merged_behavior["timing"] = {
                    "attackIntervalMs": timing.get("attack_interval_ms", timing.get("attackIntervalMs", 0)),
                    "moveIntervalMs": timing.get("move_interval_ms", timing.get("moveIntervalMs", 0)),
                    "confidence": "auxiliary_1",
                    "resolutionStatus": "auxiliary_1_exact_row",
                }
                merged_behavior["serviceBehavior"] = {
                    "aiCode": ai.get("ai_code", -1),
                    "image": ai.get("image", -1),
                    "viewRange": ai.get("view_range", 0),
                    "resolutionStatus": "auxiliary_1_exact_row",
                    "sourceDistribution": "source.angelk727.mir2_server_databases",
                }
        drop_profile_id, drop_profile = drop_for(monster_id, drop_source_by_id, drop_overrides)
        drop_profiles[drop_profile_id] = drop_profile
        appearance = appearance_profiles[art_profile_id]
        art_ok = appearance.get("status") == "formal"
        classification_ok = classification_name != "unresolved" and placement_allowed
        class_id_override = classification_ids.get("exact_id_overrides", {}).get(str(monster_id), {})
        drop_exception = (
            policy_wooma.get("drop_exemption", {})
            if isinstance(policy_wooma, dict)
            else {}
        )
        if not drop_exception and isinstance(class_id_override, dict):
            drop_exception = class_id_override.get("drop_exemption", {})
        has_drop_exemption = (
            isinstance(drop_exception, dict)
            and bool(drop_exception.get("allowed"))
            and bool(drop_exception.get("reason"))
        )
        hostile_classification = classification_name in ("ordinary", "elite", "boss", "special")
        drop_ok = bool(drop_profile.get("entry_count", 0)) or has_drop_exemption or not hostile_classification
        # A hostile spawn cannot be placed or run without a non-empty,
        # source-evidenced drop table.  The drop profile itself remains in the
        # catalog as missing_for_hostile for later source-priority repair.
        combat_identity_ok = bool(service_exact_for_identity or auxiliary_combat_evidence)
        combat_stats_ok = bool(service_exact_for_identity or bool(auxiliary_combat_evidence))
        ai_ok = (
            int(ai.get("ai_code", -1)) >= 0
            and int(ai.get("image", -1)) >= 0
            and int(ai.get("view_range", 0)) >= 0
        )
        timing_ok = (
            int(timing["attack_interval_ms"]) > 0
            and int(timing["move_interval_ms"]) > 0
        )
        placement_allowed = bool(placement_allowed and drop_ok and combat_identity_ok)
        classification_ok = classification_name != "unresolved" and placement_allowed
        runtime_allowed = bool(
            art_ok
            and classification_ok
            and drop_ok
            and combat_identity_ok
            and combat_stats_ok
            and ai_ok
            and timing_ok
        )
        runtime_semantics_ok = bool(
            runtime_allowed and art_ok and combat_identity_ok and combat_stats_ok and ai_ok and timing_ok
        )
        service_image = ai.get("image", -1)
        art_appearance = appearance.get("atlas", {}).get("appearance", 0)
        appearance_translation = None
        if art_appearance and service_image != art_appearance:
            appearance_translation = {
                "required": True,
                "provided": service_image >= 0,
                "reason": (
                    "service image and client appearance differ; ID-keyed client mapping evidence is explicit"
                    if service_image >= 0
                    else "service image evidence is missing; client appearance cannot be translated safely"
                ),
                "source": art_evidence[monster_id],
            }
        if appearance_translation is not None and not appearance_translation["provided"]:
            placement_allowed = False
            runtime_allowed = False
        if not art_ok:
            placement_allowed = False
        status = "formal" if runtime_allowed else (
            "version_difference" if classification_name == "version_difference" else "unresolved"
        )
        entry = {
            "monster_id": monster_id,
            "canonical_name": canonical_name,
            "variant_code": str(record.get("variantCode", "")),
            "classification": classification_name,
            "editor_placement": {
                "allowed": placement_allowed,
                "placement_kind": placement_kind,
                "map_codes": map_codes,
                "source_scope": "classification_and_drop_closure",
            },
            "runtime_allowed": runtime_allowed,
            "status": status,
            "drop_policy": {
                "hostile_requires_non_empty": hostile_classification,
                "entry_count": int(drop_profile.get("entry_count", 0)),
                "exemption": drop_exception if has_drop_exemption else None,
            },
            "combat": {
                "stats": stats,
                "ai": ai,
                "timing": timing,
                "runtime_projection": runtime_projection,
                "behavior_profile": merged_behavior,
                "boss_rule": behavior_extra["boss_rule"],
            },
            "appearance_profile_id": art_profile_id,
            "drop_profile_id": drop_profile_id,
            "spawn_contexts": [
                {
                    "map_code": code,
                    "classification": classification_name,
                    "placement_kind": placement_kind,
                    "allowed": placement_allowed,
                }
                for code in map_codes
            ],
            "source_evidence": {
                "canonical_name": canonical_name_evidence,
                "identity_resolution": identity_resolution,
                "classification": class_evidence,
                "combat_stats": stats_source,
                "combat_ai_timing": behavior_extra["evidence"],
                "combat_auxiliary": auxiliary_combat_evidence,
                "appearance": art_evidence[monster_id],
                    "drops": drop_profile["source_evidence"],
                "status": {
                    "runtime_allowed": runtime_allowed,
                    "art_status": appearance.get("status", ""),
                    "classification_status": classification_name,
                    "identity_resolution": identity_resolution,
                "combat_identity_ok": combat_identity_ok,
                "combat_stats_ok": combat_stats_ok,
                "ai_ok": ai_ok,
                "timing_ok": timing_ok,
                "runtime_semantics_ok": runtime_semantics_ok,
                "drop_status": drop_profile.get("status", ""),
                "drop_entry_count": int(drop_profile.get("entry_count", 0)),
                "drop_exemption": drop_exception if has_drop_exemption else None,
                "appearance_translation": appearance_translation,
            },
            },
        }
        entries.append(entry)
        entries_by_id[str(monster_id)] = entry
    source_files = [
        VANILLA_PATH,
        SERVICE_PATH,
        BEHAVIOR_PATH,
        BOSS_RULE_PATH,
        ANIMATION_PATH,
        CLASSIFICATION_PATH,
        CLASSIFICATION_ID_PATH,
        POLICY_PATH,
        DROP_SOURCE_PATH,
        *ART_PATHS,
    ]
    catalog: dict[str, Any] = {
        "schema_version": 1,
        "catalog_id": "canonical_monster_catalog",
        "identity_key": "monster_id",
        "runtime_policy": policy.get("runtime_policy", {}),
        "source_policy": {
            "source_priority_policy": "assets/data/source_priority_policy.json",
            "production_resolution": "id_only_fail_closed",
            "name_fallback": False,
            "trim_suffix_fallback": False,
            "alias_fallback": False,
        },
        "sources": {
            path.relative_to(ROOT).as_posix(): {
                "sha256": sha256_file(path),
                "hash_normalization": hash_normalization_for(path),
                "role": "generator_input",
            }
            for path in source_files
            if path.is_file()
        },
        "summary": {
            "identity_count": len(entries),
            "runtime_allowed_count": sum(bool(x["runtime_allowed"]) for x in entries),
            "unresolved_count": sum(x["status"] == "unresolved" for x in entries),
            "version_difference_count": sum(x["status"] == "version_difference" for x in entries),
            "appearance_profile_count": len(appearance_profiles),
            "drop_profile_count": len(drop_profiles),
        },
        "appearance_profiles": appearance_profiles,
        "drop_profiles": drop_profiles,
        "entries": entries,
        "entries_by_id": entries_by_id,
    }
    return catalog


def validate_catalog(catalog: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    def reject_replacement_paths(value: Any, context: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in ("original_path", "source_path") and isinstance(child, str):
                    if "\ufffd" in child or "??" in child:
                        errors.append(f"{context}.{key} contains replacement characters")
                reject_replacement_paths(child, f"{context}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                reject_replacement_paths(child, f"{context}[{index}]")

    reject_replacement_paths(catalog.get("sources", {}), "sources")
    reject_replacement_paths(catalog.get("drop_profiles", {}), "drop_profiles")
    reject_replacement_paths(catalog.get("entries", []), "entries")
    entries = catalog.get("entries", [])
    if len(entries) != 217:
        errors.append(f"identity_count={len(entries)} expected 217")
    source_index = catalog.get("sources", {})
    if not isinstance(source_index, dict):
        errors.append("sources index is not a dictionary")
        source_index = {}
    for source_path, source_evidence in source_index.items():
        if not isinstance(source_evidence, dict):
            errors.append(f"source {source_path} evidence is not a dictionary")
            continue
        expected_hash_mode = (
            "lf_text" if str(source_path).lower().endswith(".json") else "raw_bytes"
        )
        if source_evidence.get("hash_normalization") != expected_hash_mode:
            errors.append(
                f"source {source_path} hash_normalization={source_evidence.get('hash_normalization')} expected {expected_hash_mode}"
            )
    ids = [entry.get("monster_id") for entry in entries if isinstance(entry, dict)]
    if len(ids) != len(set(ids)):
        errors.append("duplicate monster_id")
    by_id = catalog.get("entries_by_id", {})
    profiles = catalog.get("appearance_profiles", {})
    drops = catalog.get("drop_profiles", {})
    for entry in entries:
        if not isinstance(entry, dict):
            errors.append("non-dictionary entry")
            continue
        monster_id = int(entry.get("monster_id", -1))
        required = ("canonical_name", "classification", "editor_placement", "runtime_allowed", "status", "drop_policy", "combat", "appearance_profile_id", "drop_profile_id", "spawn_contexts", "source_evidence")
        for field in required:
            if field not in entry:
                errors.append(f"monster_id={monster_id} missing {field}")
        combat_value = entry.get("combat", {})
        projection = combat_value.get("runtime_projection", {}) if isinstance(combat_value, dict) else {}
        if not isinstance(projection, dict):
            errors.append(f"monster_id={monster_id} runtime_projection missing")
        else:
            if int(projection.get("agility", -1)) != int(RUNTIME_PROJECTION_DEFAULTS["agility"]):
                errors.append(f"monster_id={monster_id} unsafe agility projection")
            if int(projection.get("anti_poison", -1)) != int(RUNTIME_PROJECTION_DEFAULTS["anti_poison"]):
                errors.append(f"monster_id={monster_id} unsafe anti_poison projection")
            projection_evidence = projection.get("source_evidence", {})
            for projection_field in RUNTIME_PROJECTION_DEFAULTS:
                evidence = projection_evidence.get(projection_field, {}) if isinstance(projection_evidence, dict) else {}
                if not isinstance(evidence, dict) or evidence.get("tier") != "project_rule":
                    errors.append(f"monster_id={monster_id} {projection_field} missing project_rule evidence")
        if by_id.get(str(monster_id)) != entry:
            errors.append(f"monster_id={monster_id} entries_by_id closure")
        appearance_id = str(entry.get("appearance_profile_id", ""))
        profile = profiles.get(appearance_id)
        if not isinstance(profile, dict):
            errors.append(f"monster_id={monster_id} missing appearance profile {appearance_id}")
        elif entry.get("runtime_allowed") or entry.get("editor_placement", {}).get("allowed"):
            if profile.get("status") != "formal":
                errors.append(f"monster_id={monster_id} allowed with non-formal appearance")
            for action in REQUIRED_ACTIONS:
                action_data = profile.get("actions", {}).get(action, {})
                if not action_data.get("path") or not action_data.get("path_sha256") or not action_data.get("source_path_exists"):
                    errors.append(f"monster_id={monster_id} allowed with incomplete appearance action {action}")
        drop_id = str(entry.get("drop_profile_id", ""))
        drop_profile = drops.get(drop_id)
        if drop_id not in drops or not isinstance(drop_profile, dict):
            errors.append(f"monster_id={monster_id} missing drop profile {drop_id}")
        else:
            entry_count = int(drop_profile.get("entry_count", len(drop_profile.get("entries", []))))
            hostile = str(entry.get("classification", "")) in ("ordinary", "elite", "boss", "special")
            if (entry.get("runtime_allowed") or entry.get("editor_placement", {}).get("allowed")) and hostile and entry_count <= 0:
                errors.append(f"monster_id={monster_id} hostile allowed without non-empty drop profile")
            sources = drop_profile.get("source_evidence", {}).get("sources", [])
            if not isinstance(sources, list) or not sources:
                errors.append(f"monster_id={monster_id} drop profile lacks source evidence")
            if drop_profile.get("status") == "missing_for_hostile" and hostile and (
                entry.get("runtime_allowed") or entry.get("editor_placement", {}).get("allowed")
            ):
                errors.append(f"monster_id={monster_id} missing hostile drop marked allowed")
        if entry.get("classification") == "non_hostile":
            exemption = entry.get("drop_policy", {}).get("exemption")
            if not isinstance(exemption, dict) or not exemption.get("allowed") or not exemption.get("reason"):
                errors.append(f"monster_id={monster_id} non_hostile missing explicit drop exemption reason")
        evidence = entry.get("source_evidence", {})
        for field in ("canonical_name", "classification", "combat_stats", "combat_ai_timing", "appearance", "drops", "status"):
            if field not in evidence:
                errors.append(f"monster_id={monster_id} missing source evidence {field}")
    matrix = catalog.get("entries_by_id", {})
    for monster_id in WOOma_IDS:
        entry = matrix.get(str(monster_id))
        if not isinstance(entry, dict):
            errors.append(f"Wooma monster_id={monster_id} missing")
            continue
        expected = {
            64: "ordinary", 65: "ordinary", 66: "ordinary", 67: "ordinary", 68: "ordinary", 69: "ordinary", 70: "ordinary", 71: "ordinary", 73: "elite", 74: "elite", 75: "elite", 76: "boss", 77: "special", 78: "version_difference", 239: "boss",
        }[monster_id]
        if entry.get("classification") != expected:
            errors.append(f"Wooma monster_id={monster_id} classification={entry.get('classification')} expected {expected}")
        if monster_id in WOOma_SLUG_BY_ID:
            if WOOma_SLUG_BY_ID[monster_id] not in str(entry.get("appearance_profile_id", "")):
                errors.append(f"Wooma monster_id={monster_id} appearance profile is not explicit {WOOma_SLUG_BY_ID[monster_id]}")
        elif entry.get("runtime_allowed") or entry.get("editor_placement", {}).get("allowed"):
            errors.append(f"Wooma monster_id={monster_id} unresolved art/placement unexpectedly allowed")
    for monster_id in (68, 69):
        stats = matrix[str(monster_id)]["combat"]["stats"]
        if stats.get("attack_min") != 16 or stats.get("attack_max") != 28 or stats.get("exp") != 310:
            errors.append(f"Wooma monster_id={monster_id} aux1 stats override missing")
        evidence = matrix[str(monster_id)].get("source_evidence", {}).get("combat_auxiliary", {})
        if not all(field in evidence for field in ("level", "hp", "defense", "magic_defense", "attack_min", "attack_max", "exp", "ai_code", "attack_interval_ms", "move_interval_ms", "view_range", "image")):
            errors.append(f"Wooma monster_id={monster_id} auxiliary fields lack per-field evidence")
        expected_drop_count = 58 if monster_id == 68 else 62
        drop = catalog.get("drop_profiles", {}).get(str(matrix[str(monster_id)].get("drop_profile_id", "")), {})
        # The Excel source is now the canonical drop authority, so the Wooma
        # cross-distribution equivalence is retired; only require a non-empty
        # audited table for these hostile ordinary variants.
        if int(drop.get("entry_count", 0)) <= 0:
            errors.append(f"Wooma monster_id={monster_id} canonical drop table is empty")
    exact_service_expectations = {
        64: {"level": 30, "exp": 340, "hp": 285, "defense": 3, "magic_defense": 2, "attack_min": 16, "attack_max": 28},
        66: {"level": 30, "exp": 340, "hp": 285, "defense": 3, "magic_defense": 2, "attack_min": 15, "attack_max": 28},
        73: {"level": 50, "exp": 2400, "hp": 1000, "defense": 8, "magic_defense": 8, "attack_min": 22, "attack_max": 42},
        76: {"level": 60, "exp": 6000, "hp": 3000, "defense": 25, "magic_defense": 40, "attack_min": 35, "attack_max": 90},
    }
    for monster_id, expected_stats in exact_service_expectations.items():
        actual_stats = matrix[str(monster_id)].get("combat", {}).get("stats", {})
        for field, expected in expected_stats.items():
            if actual_stats.get(field) != expected:
                errors.append(
                    f"monster_id={monster_id} primary service {field}={actual_stats.get(field)} expected {expected}"
                )
        service_record = load_json(SERVICE_PATH).get("runtimeByMonsterId", {}).get(str(monster_id), {}).get("serviceRecord", {})
        if matrix[str(monster_id)].get("canonical_name") != service_record.get("serviceName"):
            errors.append(f"monster_id={monster_id} canonical_name is not exact service name")
        name_evidence = matrix[str(monster_id)].get("source_evidence", {}).get("canonical_name", {})
        if name_evidence.get("tier") != "primary" or name_evidence.get("distribution") != "server.crystal.cjlaaa":
            errors.append(f"monster_id={monster_id} canonical_name source is not primary service")
    for monster_id in (68, 69):
        if matrix[str(monster_id)].get("source_evidence", {}).get("identity_resolution") != "auxiliary_1_exact_name":
            errors.append(f"Wooma monster_id={monster_id} canonical_name auxiliary resolution missing")
    if matrix["239"].get("monster_id") == matrix["76"].get("monster_id"):
        errors.append("Wooma 239 identity collapsed into 76")
    return errors


def validate_generator_contract() -> list[str]:
    """Guard the production builder against accidental legacy joins."""
    source = Path(__file__).read_text(encoding="utf-8")
    drop_start = source.index("def drop_for(")
    drop_end = source.index("def build_catalog(", drop_start)
    drop_section = source[drop_start:drop_end]
    class_start = source.index("def classification_for(")
    class_end = source.index("def behavior_for(", class_start)
    class_section = source[class_start:class_end]
    errors: list[str] = []
    for token in ("baseName", "runtimeDrops", "record.get(\"name\")", "trim_suffix"):
        if token in drop_section:
            errors.append(f"drop_for contains forbidden legacy join token {token}")
    for token in ("baseName", "nameRules", "visibleNames", "trim_suffix"):
        if token in class_section:
            errors.append(f"classification_for contains forbidden legacy join token {token}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate generated output without writing")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        catalog = build_catalog()
        errors = validate_catalog(catalog) + validate_generator_contract()
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
        if args.check:
            if not args.output.is_file():
                print(f"ERROR: missing output {args.output}", file=sys.stderr)
                return 1
            current = args.output.read_text(encoding="utf-8")
            if current != rendered:
                print(f"ERROR: {args.output} differs from generated catalog", file=sys.stderr)
                return 1
            print(f"CANONICAL_MONSTER_CATALOG_CHECK_PASS: identities={len(catalog['entries'])} runtime_allowed={catalog['summary']['runtime_allowed_count']}")
            return 0
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8", newline="\n")
        print(f"CANONICAL_MONSTER_CATALOG_BUILD_PASS: identities={len(catalog['entries'])} runtime_allowed={catalog['summary']['runtime_allowed_count']}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
