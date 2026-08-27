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

from monster_drop_authoring_overlay import (
    load_overlay as load_drop_authoring_overlay,
    runtime_rows_for_monster,
)


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
SPECIAL_NORMAL_AUTHORITY_PATH = ROOT / "assets/data/special_normal_monster_spawn_authority_v1.json"
DPV2_ROLE_AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_monster_role_authority_v1.json"
DPV2_ITEM_TIER_AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_item_tier_authority_v1.json"
DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
DROP_SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
DROP_AUTHORING_OVERLAY_PATH = (
    ROOT
    / "assets/data/canonical_monster_drop_authoring_overrides_v1.json"
)
COMBAT_SOURCE_PATH = ROOT / "assets/data/canonical_monster_combat_source_v1.json"
DETAIL_SOURCE_PATH = ROOT / "assets/data/monster_21cq_detail_source_v1.json"
# Retired: canonical_monster_drop_overrides_v1.json (Crystal Wooma equivalence)
# is no longer read by the generator and is intentionally absent from
# source_files/generator_input below.
DROP_OVERRIDE_PATH = ROOT / "assets/data/canonical_monster_drop_overrides_v1.json"
ART_PATHS = [
    ROOT / "assets/data/bich_common_client_art_sources.json",
    ROOT / "assets/data/bich_undead_client_art_sources.json",
    ROOT / "assets/data/complete_monster_client_art_sources.json",
    ROOT / "assets/data/classic_boss_client_art_sources.json",
]

REQUIRED_ACTIONS = ("idle", "walk", "attack", "hit", "death")
RUNTIME_CAPABLE_CLASSIFICATIONS = frozenset({
    "ordinary",
    "elite",
    "boss",
    "special",
    "non_hostile",
    "version_difference",
})

# P3C keeps the historical placement fields in the exact-ID attachment for
# auditability, but those fields are not themselves a current editor gate.
# Only an explicit disposition is allowed to narrow the formal editor pool;
# this prevents re-opening the old broad placement=false defaults by accident.
EDITOR_PLACEMENT_DISPOSITIONS = frozenset({
    "quarantine",
    "internal_subtype",
})

# P3B: version_difference 只是 classification/metadata 提醒，不再自动
# 排除 runtime。排除集合保持为空结构，等待未来明确的排除裁决。
INTENTIONAL_EXCLUSION_CLASSIFICATIONS = frozenset()

# R4C: Monster.DB exact-ID core combat authority. Only these 6 IDs may be
# overridden with the SHA-verified Monster.DB core stats. All other IDs keep
# the P3C vanilla exact-ID read. Special/event entities and the 12 IDs without
# a Monster.DB exact binding are explicitly excluded from override.
MONSTER_DB_CORE_OVERRIDE_IDS = frozenset({
    39,
    107,
    162,
    163,
    168,
    193,
})
MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS = frozenset({
    146,
    226,
    234,
})
MONSTER_DB_CORE_STATS_FIELDS = ("level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max")
# Race 200 is the primary-source identity bridge for the active cow mage and
# priest. Their Crystal service rows are explicitly unresolved fallbacks, while
# the SHA-pinned Monster.DB rows bind exact IDs 220/222 to ai_code=200 and the
# original server maps Race 200 to TElectronicScolpionMon.
MONSTER_DB_RACE_200_RUNTIME_IDS = frozenset({220, 222})
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

SPECIAL_NORMAL_IDS = frozenset({39, 57, 74, 77, 90, 121, 137, 142})
SPECIAL_NORMAL_AUTHORITY_SCHEMA = "hardcore.monster_special_normal_spawn_authority.v1"
SPECIAL_NORMAL_AUTHORITY_STATUS = "FORMAL_SPAWN_AUTHORITY_ACTIVE"
SPECIAL_NORMAL_DEFAULTS = {
    "spawn_classification": "special_normal",
    "placement_kind": "monster_spawn",
    "respawn_policy_id": "special_normal",
    "respawn_seconds": 900,
    "random_seconds": 0,
    "count": 1,
    "max_alive": 1,
}
SPECIAL_NORMAL_SOURCE_RATE_POLICY = {
    "source_path": "outputs/monster_drop_p1a/monster_drop_p1a_slots.csv",
    "field": "source_rate",
    "role": "provenance_only",
    "used_for_tier": False,
    "used_for_denominator": False,
}

# The old runtime payload sometimes carried agility/anti-poison fields, but
# those values have no authoritative monster-service evidence in this lane.
# Keep the projection explicit and fail-safe: consumers receive the project
# combat defaults, never caller-provided legacy payload values.
RUNTIME_PROJECTION_DEFAULTS = {
    "agility": 15,
    "anti_poison": 0,
}

DETAIL_REQUIRED_FIELDS = (
    "level",
    "exp",
    "hp",
    "defense",
    "magic_defense",
    "attack_min",
    "attack_max",
    "agility",
    "accuracy",
    "attack_interval_ms",
    "move_interval_ms",
    "life_type",
    "undead",
    "anti_stealth",
)
DETAIL_CORE_FIELD_MAP = {
    "level": "level",
    "exp": "exp",
    "hp": "hp",
    "defense": "defense",
    "magic_defense": "magic_defense",
    "attack_min": "attack_min",
    "attack_max": "attack_max",
}
DETAIL_TIMING_FIELD_MAP = {
    "attack_interval_ms": "attack_interval_ms",
    "move_interval_ms": "move_interval_ms",
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


def validate_21cq_detail_source(payload: dict[str, Any]) -> dict[int, dict[str, Any]]:
    """Validate the complete user-authoritative 21CQ detail snapshot.

    The snapshot is intentionally separate from the Crystal ``server_data``
    lane.  It contains only attribute/timing/life-flag fields; spawn and drop
    tables are excluded by the fetch/parser contract and are rejected here if
    they appear as record keys.
    """
    if payload.get("authority") != "user_authoritative_override":
        raise RuntimeError("21CQ detail source authority mismatch")
    if payload.get("authority_scope") != [
        "monster_attributes",
        "monster_timing",
        "monster_life_flags",
    ]:
        raise RuntimeError("21CQ detail source authority scope mismatch")
    if payload.get("distribution") != "user.21cq.com.mir.monster_detail":
        raise RuntimeError("21CQ detail source distribution mismatch")
    records = payload.get("records")
    if not isinstance(records, list) or len(records) != 217:
        raise RuntimeError("21CQ detail source must contain exactly 217 records")
    by_id: dict[int, dict[str, Any]] = {}
    excluded_keys = {
        "spawn",
        "spawn_table",
        "spawn_quantity",
        "respawn",
        "respawn_time",
        "drop",
        "drop_tables",
        "drop_probability",
        "map",
    }
    for row in records:
        if not isinstance(row, dict):
            raise RuntimeError("21CQ detail source record is not an object")
        monster_id = row.get("monster_id")
        if isinstance(monster_id, bool) or not isinstance(monster_id, int) or monster_id <= 0:
            raise RuntimeError(f"21CQ detail source invalid monster_id={monster_id!r}")
        if monster_id in by_id:
            raise RuntimeError(f"21CQ detail source duplicate monster_id={monster_id}")
        missing = [field for field in DETAIL_REQUIRED_FIELDS if field not in row]
        if missing:
            raise RuntimeError(f"21CQ monster_id={monster_id} missing detail fields {missing}")
        if any(str(key).lower() in excluded_keys for key in row):
            raise RuntimeError(f"21CQ monster_id={monster_id} contains excluded spawn/drop field")
        for field in (
            "level",
            "exp",
            "hp",
            "defense",
            "magic_defense",
            "attack_min",
            "attack_max",
            "agility",
            "accuracy",
            "attack_interval_ms",
            "move_interval_ms",
        ):
            value = row[field]
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise RuntimeError(f"21CQ monster_id={monster_id} invalid {field}={value!r}")
        if row["life_type"] not in ("生物系", "不死系"):
            raise RuntimeError(f"21CQ monster_id={monster_id} invalid life_type={row['life_type']!r}")
        if row["undead"] != (row["life_type"] == "不死系"):
            raise RuntimeError(f"21CQ monster_id={monster_id} undead/life_type mismatch")
        if row.get("http_status") != 200 or not str(row.get("source_url", "")).endswith(
            f"Mob.Aspx?ID={monster_id}"
        ):
            raise RuntimeError(f"21CQ monster_id={monster_id} URL/HTTP evidence invalid")
        raw_hash = str(row.get("raw_html_sha256", ""))
        if len(raw_hash) != 64 or any(char not in "0123456789ABCDEF" for char in raw_hash):
            raise RuntimeError(f"21CQ monster_id={monster_id} raw HTML hash invalid")
        by_id[monster_id] = row
    vanilla_payload = load_json(VANILLA_PATH)
    expected_ids = sorted(
        int(record["monsterId"])
        for record in vanilla_payload.get("records", [])
        if isinstance(record, dict) and int(record.get("monsterId", -1)) > 0
    )
    if sorted(by_id) != expected_ids or len(by_id) != 217:
        raise RuntimeError("21CQ detail source IDs are not complete")
    return by_id


def validate_special_normal_authority(
    authority: dict[str, Any],
    vanilla: dict[str, Any],
    role_authority: dict[str, Any],
    item_tier_authority: dict[str, Any],
    global_drop_rate_authority: dict[str, Any],
) -> dict[int, dict[str, Any]]:
    """Validate the exact-ID special_normal overlay before catalog generation.

    ``special_normal`` is a spawn classification overlay, not a replacement
    for the combat classification or the DPV2 role.  Keeping this contract in
    the ID-keyed catalog builder makes it impossible for a name/suffix join or
    a map-specific fallback to silently widen the category.
    """

    def require(condition: bool, message: str) -> None:
        if not condition:
            raise RuntimeError(f"special_normal authority: {message}")

    require(authority.get("schema") == SPECIAL_NORMAL_AUTHORITY_SCHEMA, "schema mismatch")
    require(authority.get("status") == SPECIAL_NORMAL_AUTHORITY_STATUS, "status mismatch")
    scope = authority.get("scope", {})
    require(isinstance(scope, dict), "scope must be a dictionary")
    require(scope.get("identity_key") == "monster_id", "identity key must be monster_id")
    require(scope.get("selection") == "explicit_exact_monster_id_set", "selection is not exact-ID")
    require(scope.get("classification_field") == "spawn_classification", "spawn classification field drift")
    require(scope.get("combat_classification_is_independent") is True, "combat classification is not independent")
    require(scope.get("name_or_suffix_resolution_forbidden") is True, "name/suffix resolution guard missing")
    expected_ids = sorted(SPECIAL_NORMAL_IDS)
    actual_scope_ids = sorted(int(value) for value in scope.get("canonical_monster_ids", []))
    require(actual_scope_ids == expected_ids, f"scope IDs={actual_scope_ids} expected {expected_ids}")

    defaults = authority.get("defaults", {})
    require(defaults == SPECIAL_NORMAL_DEFAULTS, f"defaults={defaults!r} expected {SPECIAL_NORMAL_DEFAULTS!r}")

    drop_binding = authority.get("drop_binding", {})
    require(isinstance(drop_binding, dict), "drop_binding must be a dictionary")
    require(drop_binding.get("rule") == "reuse_global_dpv2_role_and_item_tier_authority", "DPV2 reuse rule missing")
    require(drop_binding.get("additional_multiplier") is None, "special_normal adds a drop multiplier")
    require(drop_binding.get("per_item_denominator_override_allowed") is False, "per-item denominator override enabled")
    require(drop_binding.get("role_authority_path") == DPV2_ROLE_AUTHORITY_PATH.relative_to(ROOT).as_posix(), "role authority path drift")
    require(drop_binding.get("item_tier_authority_path") == DPV2_ITEM_TIER_AUTHORITY_PATH.relative_to(ROOT).as_posix(), "Tier authority path drift")
    require(drop_binding.get("source_rate_policy") == SPECIAL_NORMAL_SOURCE_RATE_POLICY, "source_rate policy drift")
    require(drop_binding.get("production_active") is True, "special_normal production binding is inactive")
    require(drop_binding.get("phase_1_allowed") is True, "special_normal phase 1 binding is blocked")
    require(drop_binding.get("runtime_consumer") == "scripts/layers/runtime/loot_runtime_service.gd", "special_normal runtime consumer drift")
    require(drop_binding.get("persistence_consumer") is None, "special_normal has a persistence consumer")
    require(
        authority.get("spawn_activation")
        == {
            "production_active": True,
            "runtime_consumers": [
                "scripts/layers/runtime/map_editor_runtime_bridge.gd",
                "scripts/monster_respawn_policy.gd",
                "scripts/game_root.gd",
            ],
            "map_data_mutated": False,
        },
        "spawn activation contract drift",
    )

    expected_sources = {
        "assets/data/vanilla_176/monsters.json": "C3CD33787BF537C648B456D99B933FAE8CCBD336AD07D55BB14BC393D2E614C0",
        "assets/data/canonical_monster_classification_v1.json": "0A6DB865644E2B91D972B438B14D51974A32524080A62ED5D30C620421F4B377",
        "assets/data/drop/dpv2_item_tier_authority_v1.json": "8F7AD07FADE03033C336BDD32633670E5F3224A4A4BE109C41D71ED794235B7A",
        "assets/data/drop/dpv2_monster_role_authority_v1.json": sha256_file(DPV2_ROLE_AUTHORITY_PATH),
        "assets/data/drop/dpv2_global_drop_rate_authority_v1.json": sha256_file(DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH),
    }
    source_rows = authority.get("authority", {}).get("sources", [])
    source_by_path = {
        str(row.get("path")): row
        for row in source_rows
        if isinstance(row, dict)
    }
    for relative_path, expected_hash in expected_sources.items():
        source = source_by_path.get(relative_path, {})
        require(source.get("sha256", "").upper() == expected_hash, f"source hash mismatch for {relative_path}")
        source_path = ROOT / relative_path
        require(source_path.is_file(), f"missing source {relative_path}")
        require(sha256_file(source_path) == expected_hash, f"checked-in source drift for {relative_path}")
    role_source = source_by_path.get(
        DPV2_ROLE_AUTHORITY_PATH.relative_to(ROOT).as_posix(), {}
    )
    require(
        role_source.get("role") == "A0.7 monster drop role and factor authority",
        "role source evidence drift",
    )

    global_source = source_by_path.get(
        DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH.relative_to(ROOT).as_posix(), {}
    )
    require(
        global_source.get("role") == "A0.7 global drop-rate scale authority",
        "global scale source evidence drift",
    )

    require(role_authority.get("schema") == "hardcore.dpv2.monster_role_authority.v1", "A0.7 role authority schema mismatch")
    require(role_authority.get("activation") == {"production_active": False, "runtime_consumer": None, "phase_1_allowed": False}, "A0.7 role authority must remain inactive")
    role_rows = {
        int(row.get("canonical_monster_id", -1)): row
        for row in role_authority.get("monsters", [])
        if isinstance(row, dict)
    }
    require(len(role_rows) == 156, "A0.7 role authority is not the 156-monster closure")

    require(item_tier_authority.get("schema") == "hardcore.dpv2.item_tier_authority.v1", "A0.7 Tier authority schema mismatch")
    require(item_tier_authority.get("activation") == {"production_active": False, "phase1_allowed": False, "runtime_consumer": None, "persistence_consumer": None}, "A0.7 Tier authority must remain inactive")
    require(item_tier_authority.get("source_rate_policy") == SPECIAL_NORMAL_SOURCE_RATE_POLICY, "A0.7 source_rate is not provenance-only")
    tier_rows = item_tier_authority.get("records", [])
    require(len(tier_rows) == 233, "A0.7 Tier authority is not the 233-item closure")
    require(all(isinstance(row, dict) and row.get("tier_status") == "RESOLVED" for row in tier_rows), "A0.7 Tier authority has unresolved records")
    require(
        global_drop_rate_authority.get("schema")
        == "hardcore.dpv2.global_drop_rate_authority.v1",
        "A0.7 global scale authority schema mismatch",
    )
    require(
        global_drop_rate_authority.get("active_preset") == "1x",
        "A0.7 global scale active preset drift",
    )

    provenance = drop_binding.get("authority_provenance", {})
    require(isinstance(provenance, dict), "special_normal DPV2 provenance missing")
    expected_provenance = {
        "item_tier_sha": expected_sources[
            "assets/data/drop/dpv2_item_tier_authority_v1.json"
        ],
        "monster_role_sha": expected_sources[
            "assets/data/drop/dpv2_monster_role_authority_v1.json"
        ],
        "global_scale_sha": expected_sources[
            "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
        ],
        "hash_normalization": "lf_text",
    }
    require(provenance == expected_provenance, "special_normal DPV2 provenance drift")
    for key, expected in expected_provenance.items():
        if key == "hash_normalization":
            continue
        require(drop_binding.get(key) == expected, f"special_normal drop_binding.{key} drift")

    vanilla_by_id = {
        int(record.get("monsterId", -1)): record
        for record in vanilla.get("records", [])
        if isinstance(record, dict) and record.get("recordStatus") != "retired"
    }
    records = authority.get("records", [])
    require(isinstance(records, list) and len(records) == len(expected_ids), "record count is not eight")
    by_id: dict[int, dict[str, Any]] = {}
    for row in records:
        require(isinstance(row, dict), "record is not a dictionary")
        monster_id = row.get("monster_id")
        require(isinstance(monster_id, int) and not isinstance(monster_id, bool), f"invalid monster_id={monster_id!r}")
        require(monster_id in SPECIAL_NORMAL_IDS, f"unexpected monster_id={monster_id}")
        require(monster_id not in by_id, f"duplicate monster_id={monster_id}")
        by_id[monster_id] = row
        canonical = vanilla_by_id.get(monster_id)
        require(isinstance(canonical, dict), f"monster_id={monster_id} is not an active canonical identity")
        require(row.get("canonical_name") == canonical.get("name"), f"monster_id={monster_id} canonical name drift")
        spawn = row.get("spawn")
        require(spawn == SPECIAL_NORMAL_DEFAULTS, f"monster_id={monster_id} spawn policy drift")
        role = role_rows.get(monster_id)
        require(isinstance(role, dict), f"monster_id={monster_id} missing A0.7 role row")
        require(row.get("drop_enabled") is True, f"monster_id={monster_id} must remain drop-enabled")
        require(row.get("drop_role") == role.get("drop_role"), f"monster_id={monster_id} role drift")
        require(row.get("role_factor") == role.get("role_factor"), f"monster_id={monster_id} factor drift")
        require(row.get("role_assignment_authority") == role.get("assignment_authority"), f"monster_id={monster_id} role authority drift")
        require(row.get("item_tier_resolution") == "A0_7_ITEM_TIER_AUTHORITY_V1", f"monster_id={monster_id} Tier authority drift")
        require(row.get("additional_multiplier") is None, f"monster_id={monster_id} adds a drop multiplier")
        require(row.get("source_rate_role") == "provenance_only", f"monster_id={monster_id} source_rate role drift")
    require(sorted(by_id) == expected_ids, f"records IDs={sorted(by_id)} expected {expected_ids}")
    return by_id


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


def detail_source_ref(
    detail_source: dict[str, Any],
    detail_row: dict[str, Any],
    *,
    field: str,
    superseded_conflicts: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build a compact field-level reference to the full 21CQ snapshot.

    The complete URL/status/raw-page evidence lives once per ID in
    ``monster_21cq_detail_source_v1.json``.  Canonical entries retain only
    the stable snapshot hash, exact page hash/URL, authority and compact old
    candidate conflict values so the runtime catalog remains reviewable.
    """
    item: dict[str, Any] = {
        "source": DETAIL_SOURCE_PATH.relative_to(ROOT).as_posix(),
        "sha256": sha256_file(DETAIL_SOURCE_PATH),
        "authority": "user_authoritative_override",
        "role": "monster_21cq_detail_user_authoritative_override",
        "field": field,
        "raw_html_sha256": str(detail_row.get("raw_html_sha256", "")),
    }
    if superseded_conflicts:
        item["superseded_conflicts"] = superseded_conflicts
    return item


def superseded_candidate(
    *,
    distribution: str,
    tier: str,
    original_path: str,
    sha256_value: str,
    field: str,
    value: Any,
    detail_value: Any,
    role: str,
    evidence: str,
) -> dict[str, Any]:
    return {
        "source": distribution,
        "distribution": distribution,
        "tier": tier,
        "original_path": original_path,
        "sha256": sha256_value,
        "field": field,
        "role": role,
        "value": value,
        "evidence": evidence,
        "resolution": "corroborating_non_authoritative" if value == detail_value else "superseded_by_21cq_user_override",
    }


def detail_conflicts_for_field(
    monster_id: int,
    field: str,
    detail_value: Any,
    vanilla_record: dict[str, Any],
    combat_source: dict[str, Any],
    combat_entry: dict[str, Any],
    service_row: dict[str, Any],
    policy_wooma: dict[str, Any],
) -> list[dict[str, Any]]:
    """Preserve the old candidate values without allowing them to win."""
    conflicts: list[dict[str, Any]] = []
    vanilla_key = VANILLA_COMBAT_FIELD_MAP.get(field)
    if vanilla_key is not None and vanilla_key in vanilla_record:
        conflicts.append(
            superseded_candidate(
                distribution="source.vanilla_176",
                tier="primary",
                original_path=VANILLA_PATH.relative_to(ROOT).as_posix(),
                sha256_value=sha256_file(VANILLA_PATH),
                field=field,
                value=vanilla_record[vanilla_key],
                detail_value=detail_value,
                role="superseded_vanilla_exact_id_candidate",
                evidence=f"vanilla_176 exact monster_id={monster_id} record.{vanilla_key}",
            )
        )
    if field in combat_entry:
        conflicts.append(
            superseded_candidate(
                distribution=str(combat_source.get("distribution", "source.original_gameofmir.monster_db_176")),
                tier=str(combat_source.get("tier", "primary")),
                original_path=str(combat_source.get("source", COMBAT_SOURCE_PATH.relative_to(ROOT).as_posix())),
                sha256_value=str(combat_source.get("source_sha256", sha256_file(COMBAT_SOURCE_PATH))),
                field=field,
                value=combat_entry[field],
                detail_value=detail_value,
                role="superseded_monster_db_exact_id_candidate",
                evidence=f"canonical_monster_combat_source_v1 records_by_monster_id[{monster_id}].{field}",
            )
        )
    if field == "accuracy" and "hit" in combat_entry:
        conflicts.append(
            superseded_candidate(
                distribution=str(combat_source.get("distribution", "source.original_gameofmir.monster_db_176")),
                tier=str(combat_source.get("tier", "primary")),
                original_path=str(combat_source.get("source", COMBAT_SOURCE_PATH.relative_to(ROOT).as_posix())),
                sha256_value=str(combat_source.get("source_sha256", sha256_file(COMBAT_SOURCE_PATH))),
                field=field,
                value=combat_entry["hit"],
                detail_value=detail_value,
                role="superseded_monster_db_hit_candidate",
                evidence=f"Monster.DB HIT field mapped as an old accuracy candidate for monster_id={monster_id}",
            )
        )
    if field in DETAIL_TIMING_FIELD_MAP:
        behavior = service_row.get("behaviorProfile", {}) if isinstance(service_row, dict) else {}
        timing = behavior.get("timing", {}) if isinstance(behavior, dict) else {}
        service_key = "attackIntervalMs" if field == "attack_interval_ms" else "moveIntervalMs"
        if service_key in timing:
            conflicts.append(
                superseded_candidate(
                    distribution="server.crystal.cjlaaa",
                    tier="primary",
                    original_path=SERVICE_PATH.relative_to(ROOT).as_posix(),
                    sha256_value=sha256_file(SERVICE_PATH),
                    field=field,
                    value=timing[service_key],
                    detail_value=detail_value,
                    role="superseded_crystal_timing_candidate",
                    evidence=f"service_monster_runtime_catalog runtimeByMonsterId[{monster_id}].behaviorProfile.timing.{service_key}",
                )
            )
    if field in ("undead", "life_type", "anti_stealth"):
        behavior = service_row.get("behaviorProfile", {}) if isinstance(service_row, dict) else {}
        service_behavior = behavior.get("serviceBehavior", {}) if isinstance(behavior, dict) else {}
        if field == "undead" and "undead" in service_behavior:
            value = bool(service_behavior["undead"])
            conflicts.append(
                superseded_candidate(
                    distribution="server.crystal.cjlaaa",
                    tier="primary",
                    original_path=SERVICE_PATH.relative_to(ROOT).as_posix(),
                    sha256_value=sha256_file(SERVICE_PATH),
                    field=field,
                    value=value,
                    detail_value=detail_value,
                    role="superseded_crystal_life_flag_candidate",
                    evidence=f"service_monster_runtime_catalog runtimeByMonsterId[{monster_id}].behaviorProfile.serviceBehavior.undead",
                )
            )
    if isinstance(policy_wooma, dict) and isinstance(policy_wooma.get("combat_override"), dict):
        override = policy_wooma["combat_override"]
        if field in override:
            aux = policy_wooma.get("auxiliary_source", {})
            conflicts.append(
                superseded_candidate(
                    distribution=str(aux.get("distribution", "source.angelk727.mir2_server_databases")),
                    tier=str(aux.get("tier", "auxiliary_1")),
                    original_path=str(aux.get("original_path", "")),
                    sha256_value=str(aux.get("sha256", "")),
                    field=field,
                    value=override[field],
                    detail_value=detail_value,
                    role="superseded_wooma_auxiliary_candidate",
                    evidence=f"canonical policy Wooma combat_override for monster_id={monster_id}",
                )
            )
    # Canonical needs only the actual losing values; equal candidates remain
    # available in their original source snapshots and would otherwise bloat
    # every entry without adding conflict evidence.
    return [
        candidate
        for candidate in conflicts
        if candidate.get("resolution") == "superseded_by_21cq_user_override"
    ]


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

    Only ``runtimeMappingsByMonsterId`` (exact-ID authority) is consumed.
    Name-keyed ``runtimeMappings`` entries are resolved when an ID-keyed
    value is a string reference, but no automatic name-based fallback is
    performed — every monster must have an explicit ID entry.
    """

    id_to_mapping: dict[int, tuple[str, dict[str, Any], Path]] = {}
    for manifest_path in ART_PATHS:
        manifest = load_json(manifest_path)
        by_id = manifest.get("runtimeMappingsByMonsterId", {})
        if isinstance(by_id, dict) and by_id:
            by_name = manifest.get("runtimeMappings", {})
            for raw_id, value in by_id.items():
                monster_id = int(raw_id)
                if monster_id in id_to_mapping:
                    continue
                mapping: dict[str, Any]
                if isinstance(value, str):
                    candidate = by_name.get(value, {})
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
    disposition_value = override.get(
        "disposition",
        policy_override.get("disposition", ""),
    )
    disposition = str(disposition_value).strip()
    disposition_evidence_value = override.get(
        "evidence",
        policy_override.get("evidence", {}),
    )
    disposition_evidence = (
        copy.deepcopy(disposition_evidence_value)
        if isinstance(disposition_evidence_value, dict)
        else {}
    )
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
    if disposition:
        # An explicit disposition is the only current placement restriction.
        # Unknown values fail closed here and are reported by validate_catalog.
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
    if disposition:
        evidence["disposition"] = disposition
        evidence["disposition_evidence"] = disposition_evidence
    return classification_name, placement_allowed, placement_kind, map_codes, evidence


def behavior_for(
    monster_id: int,
    service: dict[str, Any],
    behavior: dict[str, Any],
    boss_rules: dict[str, Any],
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


VANILLA_COMBAT_FIELD_MAP: dict[str, str] = {
    "level": "level",
    "exp": "exp",
    "hp": "hp",
    "defense": "defense",
    "magic_defense": "magicDefense",
    "attack_min": "attackMin",
    "attack_max": "attackMax",
}


def read_vanilla_core_combat_exact_id(
    record: dict[str, Any],
) -> tuple[dict[str, int], dict[str, bool], bool]:
    """Read core combat stats from a vanilla exact-ID record with strict validation.

    Returns (stats, field_validity, all_fields_valid).
    - stats: parsed int values (0 for invalid/missing fields)
    - field_validity: per-field bool indicating legal value
    - all_fields_valid: True only if every required field is present, int, non-bool, non-negative
    """
    stats: dict[str, int] = {}
    field_validity: dict[str, bool] = {}
    for stat_field, vanilla_key in VANILLA_COMBAT_FIELD_MAP.items():
        if vanilla_key not in record:
            stats[stat_field] = 0
            field_validity[stat_field] = False
            continue
        raw = record[vanilla_key]
        if isinstance(raw, bool):
            stats[stat_field] = 0
            field_validity[stat_field] = False
            continue
        if not isinstance(raw, int):
            stats[stat_field] = 0
            field_validity[stat_field] = False
            continue
        if raw < 0:
            stats[stat_field] = 0
            field_validity[stat_field] = False
            continue
        stats[stat_field] = raw
        field_validity[stat_field] = True
    all_fields_valid = all(field_validity.values())
    return stats, field_validity, all_fields_valid


def build_catalog() -> dict[str, Any]:
    vanilla = load_json(VANILLA_PATH)
    service = load_json(SERVICE_PATH)
    behavior = load_json(BEHAVIOR_PATH)
    boss_rules = load_json(BOSS_RULE_PATH)
    detail_source = load_json(DETAIL_SOURCE_PATH)
    detail_by_id = validate_21cq_detail_source(detail_source)
    classification_ids = load_json(CLASSIFICATION_ID_PATH)
    policy = load_json(POLICY_PATH)
    special_normal_authority = load_json(SPECIAL_NORMAL_AUTHORITY_PATH)
    dpv2_role_authority = load_json(DPV2_ROLE_AUTHORITY_PATH)
    dpv2_item_tier_authority = load_json(DPV2_ITEM_TIER_AUTHORITY_PATH)
    dpv2_global_drop_rate_authority = load_json(
        DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH
    )
    special_normal_by_id = validate_special_normal_authority(
        special_normal_authority,
        vanilla,
        dpv2_role_authority,
        dpv2_item_tier_authority,
        dpv2_global_drop_rate_authority,
    )
    drop_source = load_json(DROP_SOURCE_PATH)
    combat_source = load_json(COMBAT_SOURCE_PATH)
    combat_source_by_id = combat_source.get("records_by_monster_id", {})
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
    if not isinstance(records, list):
        raise RuntimeError("vanilla records must be a list")

    active_monster_ids = {
        int(record.get("monsterId", -1))
        for record in records
        if (
            isinstance(record, dict)
            and record.get("recordStatus") != "retired"
            and int(record.get("monsterId", -1)) > 0
        )
    }
    drop_authoring_source_label = (
        DROP_AUTHORING_OVERLAY_PATH.relative_to(ROOT).as_posix()
    )
    drop_authoring_overlay = load_drop_authoring_overlay(
        DROP_AUTHORING_OVERLAY_PATH,
        active_monster_ids,
        drop_authoring_source_label,
    )
    drop_authoring_source_evidence = source_ref(
        DROP_AUTHORING_OVERLAY_PATH,
        role="drop_profile_authoring_overlay",
        distribution="source.user_drop_authoring_overlay",
        tier="user_authoritative",
        evidence=(
            "Exact entry_key authoring rows; global rows project to every "
            "active canonical profile, monster rows join by monster_id only"
        ),
    )

    entries: list[dict[str, Any]] = []
    drop_profiles: dict[str, dict[str, Any]] = {}
    entries_by_id: dict[str, dict[str, Any]] = {}
    base_drop_row_count = 0
    global_authoring_expanded_row_count = 0
    monster_authoring_added_row_count = 0
    for record in sorted(records, key=lambda item: int(item.get("monsterId", -1))):
        monster_id = int(record.get("monsterId", -1))
        if record.get("recordStatus") == "retired":
            continue
        policy_wooma = policy.get("wooma_matrix", {}).get(str(monster_id), {})
        if not isinstance(policy_wooma, dict):
            policy_wooma = {}
        service_row_for_identity = service.get("runtimeByMonsterId", {}).get(str(monster_id), {})
        service_record_for_identity = (
            service_row_for_identity.get("serviceRecord", {})
            if isinstance(service_row_for_identity, dict)
            else {}
        )
        service_exact_for_identity = (
            isinstance(service_row_for_identity, dict)
            and service_row_for_identity.get("resolutionStatus") == "exact_service_name"
            and isinstance(service_record_for_identity, dict)
        )
        # canonical_name: always vanilla exact-ID record.name.
        # policy canonical_name_override is no longer consumed for production identity.
        canonical_name = str(record.get("name", ""))
        canonical_name_evidence = source_ref(
            VANILLA_PATH,
            role="canonical_name_vanilla_exact_id",
            distribution="source.vanilla_176",
            tier="primary",
            field="canonical_name",
            evidence=f"vanilla_176/monsters.json exact monster_id={monster_id} record.name",
        )
        identity_resolution = "vanilla_exact_id"
        classification_name, placement_allowed, placement_kind, map_codes, class_evidence = classification_for(
            monster_id, classification_ids, policy
        )
        classification_disposition = str(
            class_evidence.get("disposition", "")
        ).strip()
        disposition_evidence = class_evidence.get(
            "disposition_evidence",
            {},
        )
        special_normal_row = special_normal_by_id.get(monster_id)
        spawn_classification: str | None = None
        spawn_authority: dict[str, Any] | None = None
        placement_source_scope = "classification_and_drop_closure"
        if special_normal_row is not None:
            if classification_name != str(special_normal_row.get("combat_classification", "")):
                raise RuntimeError(
                    f"special_normal authority combat classification mismatch for monster_id={monster_id}: "
                    f"catalog={classification_name!r} authority={special_normal_row.get('combat_classification')!r}"
                )
            spawn = copy.deepcopy(special_normal_row["spawn"])
            spawn_classification = str(spawn["spawn_classification"])
            placement_kind = str(spawn["placement_kind"])
            placement_allowed = True
            placement_source_scope = "special_normal_spawn_authority_v1"
            spawn_authority = {
                "authority_id": str(special_normal_authority["authority_id"]),
                "authority_path": SPECIAL_NORMAL_AUTHORITY_PATH.relative_to(ROOT).as_posix(),
                "record_key": f"monster_id={monster_id}",
                **spawn,
                "drop_binding": {
                    "drop_enabled": bool(special_normal_row["drop_enabled"]),
                    "drop_role": special_normal_row["drop_role"],
                    "role_factor": special_normal_row["role_factor"],
                    "role_assignment_authority": special_normal_row["role_assignment_authority"],
                    "item_tier_resolution": special_normal_row["item_tier_resolution"],
                    "additional_multiplier": special_normal_row["additional_multiplier"],
                    "source_rate_role": special_normal_row["source_rate_role"],
                    "item_tier_sha": str(
                        special_normal_authority["drop_binding"]["item_tier_sha"]
                    ),
                    "monster_role_sha": str(
                        special_normal_authority["drop_binding"]["monster_role_sha"]
                    ),
                    "global_scale_sha": str(
                        special_normal_authority["drop_binding"]["global_scale_sha"]
                    ),
                    "authority_provenance": copy.deepcopy(
                        special_normal_authority["drop_binding"][
                            "authority_provenance"
                        ]
                    ),
                },
                "production_active": True,
                "phase_1_allowed": True,
            }
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
        # Start with the historical exact-ID candidates so their values can
        # remain visible in superseded conflict evidence.  The 21CQ user
        # override below is the final authority for all covered attributes.
        stats, field_validity, all_fields_valid = read_vanilla_core_combat_exact_id(record)
        stats_source = {
            field: source_ref(
                VANILLA_PATH,
                role="core_combat_stats_vanilla_exact_id",
                distribution="source.vanilla_176",
                tier="primary",
                field=field,
                evidence=f"vanilla_176/monsters.json exact monster_id={monster_id} record.{VANILLA_COMBAT_FIELD_MAP[field]}",
            )
            for field in stats
        }
        # Preserve the historical Monster.DB exact-ID candidate in the
        # intermediate value path.  It is intentionally superseded by the
        # user-authoritative 21CQ row below; retaining this block makes the old
        # evidence available for audit without letting it win.
        if monster_id in MONSTER_DB_CORE_OVERRIDE_IDS:
            db_entry = combat_source_by_id.get(str(monster_id))
            if not isinstance(db_entry, dict):
                raise RuntimeError(
                    f"monster_id={monster_id} is in MONSTER_DB_CORE_OVERRIDE_IDS "
                    "but has no records_by_monster_id entry; fail closed"
                )
            missing_fields = [f for f in MONSTER_DB_CORE_STATS_FIELDS if f not in db_entry]
            if missing_fields:
                raise RuntimeError(
                    f"monster_id={monster_id} Monster.DB entry missing fields {missing_fields}"
                )
            for field in MONSTER_DB_CORE_STATS_FIELDS:
                value = db_entry[field]
                if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                    raise RuntimeError(
                        f"monster_id={monster_id} Monster.DB field {field}={value!r} invalid"
                    )
                stats[field] = value
                stats_source[field] = {
                    "distribution": str(combat_source.get("distribution", "")),
                    "tier": str(combat_source.get("tier", "")),
                    "original_path": str(combat_source.get("source", "")),
                    "sha256": str(combat_source.get("source_sha256", "")),
                    "hash_normalization": "raw_bytes",
                    "role": "combat_stats_monster_db_exact_id",
                    "field": field,
                    "evidence": (
                        f"canonical_monster_combat_source_v1.json "
                        f"records_by_monster_id[{monster_id}].{field} "
                        f"binding={db_entry.get('binding', '')} "
                        f"cross_verified_21cq={db_entry.get('cross_verified_21cq', False)}"
                    ),
                }
        auxiliary_combat_evidence: dict[str, Any] = {}
        override_invalid_field = False
        if isinstance(policy_wooma, dict) and isinstance(policy_wooma.get("combat_override"), dict):
            override = policy_wooma["combat_override"]
            for field, value in override.items():
                if field not in stats:
                    continue
                # Strict validation: must be int, not bool, not float, >= 0
                if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                    override_invalid_field = True
                    continue
                stats[field] = value
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
        detail_row = detail_by_id.get(monster_id)
        if not isinstance(detail_row, dict):
            raise RuntimeError(f"21CQ detail source missing active monster_id={monster_id}")
        detail_combat_entry = combat_source_by_id.get(str(monster_id), {})
        if not isinstance(detail_combat_entry, dict):
            detail_combat_entry = {}
        for field, detail_key in DETAIL_CORE_FIELD_MAP.items():
            detail_value = detail_row[detail_key]
            stats[field] = int(detail_value)
            stats_source[field] = detail_source_ref(
                detail_source,
                detail_row,
                field=field,
                superseded_conflicts=detail_conflicts_for_field(
                    monster_id,
                    field,
                    detail_value,
                    record,
                    combat_source,
                    detail_combat_entry,
                    service_row_for_identity,
                    policy_wooma,
                ),
            )
        # The complete 21CQ row is validated above, so the final core stats
        # validity is independent of any malformed historical candidate.
        all_fields_valid = all(
            isinstance(stats[field], int) and not isinstance(stats[field], bool) and stats[field] >= 0
            for field in MONSTER_DB_CORE_STATS_FIELDS
        )
        merged_behavior, ai, timing, behavior_extra = behavior_for(monster_id, service, behavior, boss_rules)
        if monster_id in MONSTER_DB_RACE_200_RUNTIME_IDS:
            db_entry = combat_source_by_id.get(str(monster_id))
            if not isinstance(db_entry, dict) or int(db_entry.get("ai_code", -1)) != 200:
                raise RuntimeError(
                    f"monster_id={monster_id} Race 200 primary binding missing or invalid"
                )
            ai = {
                "ai_code": 200,
                "view_range": int(db_entry.get("view_range", 0)),
                "image": int(db_entry.get("image", -1)),
                "resolution_status": "primary_monster_db_exact_id",
                "source_distribution": str(combat_source.get("distribution", "")),
            }
            timing = {
                "attack_interval_ms": int(db_entry.get("attack_interval_ms", 0)),
                "move_interval_ms": int(db_entry.get("move_interval_ms", 0)),
                "confidence": "A",
                "resolution_status": "primary_monster_db_exact_id",
            }
            merged_behavior["serviceBehavior"] = {
                "aiCode": 200,
                "image": ai["image"],
                "viewRange": ai["view_range"],
                "confidence": "A",
                "resolutionStatus": "primary_monster_db_exact_id",
                "sourceDistribution": ai["source_distribution"],
            }
            merged_behavior["timing"] = {
                "attackIntervalMs": timing["attack_interval_ms"],
                "moveIntervalMs": timing["move_interval_ms"],
                "confidence": "A",
                "resolutionStatus": "primary_monster_db_exact_id",
            }
            behavior_extra["evidence"]["service"] = {
                "distribution": str(combat_source.get("distribution", "")),
                "tier": str(combat_source.get("tier", "primary")),
                "original_path": str(combat_source.get("source", "")),
                "sha256": str(combat_source.get("source_sha256", "")),
                "hash_normalization": "raw_bytes",
                "role": "race_200_ai_timing_monster_db_exact_id",
                "evidence": (
                    f"records_by_monster_id[{monster_id}] exact binding "
                    "ai_code=200; original UsrEngn.pas Race 200 class mapping"
                ),
            }
        runtime_projection = {
            "agility": int(detail_row["agility"]),
            "accuracy": int(detail_row["accuracy"]),
            "life_type": str(detail_row["life_type"]),
            "undead": bool(detail_row["undead"]),
            "anti_stealth": bool(detail_row["anti_stealth"]),
            "anti_poison": int(RUNTIME_PROJECTION_DEFAULTS["anti_poison"]),
            "source_evidence": {
                field: detail_source_ref(
                    detail_source,
                    detail_row,
                    field=field,
                    superseded_conflicts=detail_conflicts_for_field(
                        monster_id,
                        field,
                        detail_row[field],
                        record,
                        combat_source,
                        detail_combat_entry,
                        service_row_for_identity,
                        policy_wooma,
                    ),
                )
                for field in ("agility", "accuracy", "life_type", "undead", "anti_stealth")
            },
        }
        runtime_projection["source_evidence"]["anti_poison"] = source_ref(
            POLICY_PATH,
            role="runtime_projection_safe_default",
            distribution="project.monster_runtime_contract",
            tier="project_rule",
            field="anti_poison",
            evidence=(
                "No authoritative 21CQ anti-poison field; canonical runtime keeps the safe project default"
            ),
        )
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
        # 21CQ owns the detail timing and life flags for every active exact ID.
        # Keep the existing service AI code/image/range and Boss rule intact;
        # only the requested attack/move cadence and life flags are replaced.
        timing["attack_interval_ms"] = int(detail_row["attack_interval_ms"])
        timing["move_interval_ms"] = int(detail_row["move_interval_ms"])
        timing["confidence"] = "user_authoritative_21cq"
        timing["resolution_status"] = "user_authoritative_21cq"
        merged_behavior["timing"] = {
            "attackIntervalMs": timing["attack_interval_ms"],
            "moveIntervalMs": timing["move_interval_ms"],
            "confidence": "user_authoritative_21cq",
            "resolutionStatus": "user_authoritative_21cq",
        }
        service_behavior = merged_behavior.setdefault("serviceBehavior", {})
        if not isinstance(service_behavior, dict):
            service_behavior = {}
            merged_behavior["serviceBehavior"] = service_behavior
        service_behavior["undead"] = bool(detail_row["undead"])
        service_behavior["lifeType"] = str(detail_row["life_type"])
        service_behavior["antiStealth"] = bool(detail_row["anti_stealth"])
        behavior_extra["evidence"]["detail"] = {
            "source": DETAIL_SOURCE_PATH.relative_to(ROOT).as_posix(),
            "source_sha256": sha256_file(DETAIL_SOURCE_PATH),
            "distribution": str(detail_source.get("distribution", "")),
            "authority": "user_authoritative_override",
            "role": "monster_21cq_detail_timing_and_life_flags",
            "field_page_sha256": {
                field: str(detail_row.get("raw_html_sha256", ""))
                for field in ("attack_interval_ms", "move_interval_ms", "life_type", "undead", "anti_stealth")
            },
        }
        drop_profile_id, drop_profile = drop_for(monster_id, drop_source_by_id, drop_overrides)

        base_entries_value = drop_profile.get("entries", [])
        if not isinstance(base_entries_value, list):
            raise RuntimeError(
                f"monster_id={monster_id} drop entries must be a list"
            )
        base_entry_count = len(base_entries_value)
        base_drop_row_count += base_entry_count

        global_entry_count = len(
            drop_authoring_overlay["enabled_global_additions"]
        )
        monster_entry_count = len(
            drop_authoring_overlay[
                "enabled_monster_additions_by_id"
            ].get(monster_id, [])
        )
        authoring_rows = runtime_rows_for_monster(
            monster_id,
            drop_authoring_overlay,
        )
        if len(authoring_rows) != (
            global_entry_count + monster_entry_count
        ):
            raise RuntimeError(
                f"monster_id={monster_id} authoring projection count mismatch"
            )

        global_authoring_expanded_row_count += global_entry_count
        monster_authoring_added_row_count += monster_entry_count

        if authoring_rows:
            final_entries = [
                *copy.deepcopy(base_entries_value),
                *authoring_rows,
            ]
            drop_profile["entries"] = final_entries
            drop_profile["entry_count"] = len(final_entries)

            if str(drop_profile.get("status", "")) == "missing_for_hostile":
                drop_profile["base_status"] = "missing_for_hostile"
                drop_profile["status"] = "authoring_overlay_only"

            entry_keys = [
                str(row.get("authoring_entry_key", ""))
                for row in authoring_rows
            ]
            drop_profile["authoring_overlay"] = {
                "entry_count": len(authoring_rows),
                "global_entry_count": global_entry_count,
                "monster_entry_count": monster_entry_count,
                "entry_keys": entry_keys,
            }

            evidence_container = drop_profile.setdefault(
                "source_evidence",
                {},
            )
            if not isinstance(evidence_container, dict):
                raise RuntimeError(
                    f"monster_id={monster_id} source_evidence must be a dictionary"
                )
            evidence_sources = evidence_container.setdefault(
                "sources",
                [],
            )
            if not isinstance(evidence_sources, list):
                raise RuntimeError(
                    f"monster_id={monster_id} source evidence sources must be a list"
                )
            authoring_evidence = copy.deepcopy(
                drop_authoring_source_evidence
            )
            authoring_evidence["row_count"] = len(authoring_rows)
            authoring_evidence["entry_keys"] = entry_keys
            evidence_sources.append(authoring_evidence)

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
        # Combat identity: proven by vanilla exact-ID record existence.
        # Service exact match is decoupled — it no longer gates identity.
        core_combat_identity_ok = True  # active vanilla record always exists
        # core_combat_stats_ok: ALL 7 required fields must be valid.
        core_combat_stats_ok = all_fields_valid and not override_invalid_field
        # AI authority: by resolution provenance, not numeric value.
        ai_resolution = str(ai.get("resolution_status", ""))
        ai_authority_ok = ai_resolution in ("exact_service_name", "auxiliary_1_exact_row")
        # Timing authority: by resolution provenance.
        timing_resolution = str(timing.get("confidence", ""))
        timing_authority_ok = (
            timing_resolution in ("auxiliary_1", "user_authoritative_21cq")
            or service_exact_for_identity
        )
        combat_identity_ok = core_combat_identity_ok and core_combat_stats_ok

        intentional_exclusion = (
            classification_name in INTENTIONAL_EXCLUSION_CLASSIFICATIONS
        )

        runtime_classification_ok = (
            classification_name in RUNTIME_CAPABLE_CLASSIFICATIONS
        )

        runtime_blockers: list[str] = []

        if not runtime_classification_ok and not intentional_exclusion:
            runtime_blockers.append("classification_not_runtime_capable")

        if not art_ok:
            runtime_blockers.append("art_not_formal")

        if not drop_ok:
            runtime_blockers.append("drop_policy_not_closed")

        if not combat_identity_ok:
            runtime_blockers.append("combat_identity_not_closed")

        # IMPORTANT:
        #
        # runtime capability 和 editor placement policy 是两个独立概念。
        #
        # 一个怪物可以：
        #   runtime_allowed=true
        #   placement_allowed=false
        #
        # 例如内部变体/不希望用户摆放的正式运行实体。
        #
        # 禁止再次让 placement_allowed 参与 runtime_allowed 的计算。

        runtime_allowed = bool(
            runtime_classification_ok
            and not intentional_exclusion
            and art_ok
            and drop_ok
            and combat_identity_ok
        )

        # P3B/P3C: historical placement_allowed=false values are retained as
        # source evidence, but do not re-close the current editor pool.  A
        # current restriction must be an explicit, machine-checkable
        # disposition so quarantine/internal-subtype decisions stay narrow.
        placement_allowed = not bool(classification_disposition)

        classification_ok = runtime_classification_ok

        service_image = ai.get("image", -1)
        art_appearance = appearance.get("atlas", {}).get("appearance", 0)

        appearance_translation = None

        if art_appearance and service_image != art_appearance:
            exact_id_art_evidence = art_evidence.get(monster_id, {})
            exact_id_art_ok = bool(
                exact_id_art_evidence
                and art_ok
            )

            appearance_translation = {
                "required": True,
                "provided": exact_id_art_ok,
                "service_image": service_image,
                "client_appearance": art_appearance,
                "reason": (
                    "exact monster_id client-art authority provides the "
                    "service-to-client appearance translation; service image "
                    "is diagnostic metadata and is not the client rendering identity"
                    if exact_id_art_ok
                    else
                    "exact monster_id client-art authority is missing"
                ),
                "source": exact_id_art_evidence,
            }

            if not exact_id_art_ok:
                if "appearance_translation_missing" not in runtime_blockers:
                    runtime_blockers.append(
                        "appearance_translation_missing"
                    )
                runtime_allowed = False

        if runtime_allowed:
            status = "formal"
        elif classification_name == "version_difference":
            status = "version_difference"
        else:
            status = "unresolved"
        editor_placement = {
            "allowed": placement_allowed,
            "placement_kind": placement_kind,
            "map_codes": map_codes,
            "source_scope": placement_source_scope,
        }
        if classification_disposition:
            editor_placement["disposition"] = classification_disposition
            editor_placement["disposition_evidence"] = copy.deepcopy(
                disposition_evidence
            )
        entry = {
            "monster_id": monster_id,
            "canonical_name": canonical_name,
            "variant_code": str(record.get("variantCode", "")),
            "classification": classification_name,
            "spawn_classification": spawn_classification,
            "editor_placement": editor_placement,
            "spawn_authority": spawn_authority,
            "runtime_allowed": runtime_allowed,
            "runtime_capability": {
                "allowed": runtime_allowed,
                "classification_ok": runtime_classification_ok,
                "art_ok": art_ok,
                "drop_ok": drop_ok,
                "combat_identity_ok": combat_identity_ok,
                "intentional_exclusion": intentional_exclusion,
                "blockers": runtime_blockers,
            },
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
                "spawn_classification": (
                    source_ref(
                        SPECIAL_NORMAL_AUTHORITY_PATH,
                        role="special_normal_spawn_classification",
                        distribution="source.user_authoritative_special_normal",
                        tier="user_authoritative",
                        field="spawn_classification",
                        evidence=(
                            f"Explicit special_normal authority record for exact monster_id={monster_id}; "
                            "combat classification and DPV2 probability role remain independent"
                        ),
                    )
                    if special_normal_row is not None
                    else None
                ),
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
                    "core_combat_identity_ok": core_combat_identity_ok,
                    "core_combat_stats_ok": core_combat_stats_ok,
                    "ai_authority_ok": ai_authority_ok,
                    "timing_authority_ok": timing_authority_ok,
                    "combat_identity_ok": combat_identity_ok,
                    "drop_status": drop_profile.get("status", ""),
                    "drop_entry_count": int(drop_profile.get("entry_count", 0)),
                    "drop_exemption": drop_exception if has_drop_exemption else None,
                    "appearance_translation": appearance_translation,
                },
            },
        }
        if classification_disposition:
            entry["disposition"] = classification_disposition
            entry["disposition_evidence"] = copy.deepcopy(
                disposition_evidence
            )
        entries.append(entry)
        entries_by_id[str(monster_id)] = entry
    expected_global_expansion = (
        len(drop_authoring_overlay["enabled_global_additions"])
        * len(entries)
    )
    if global_authoring_expanded_row_count != expected_global_expansion:
        raise RuntimeError(
            "global authoring expansion mismatch: "
            f"actual={global_authoring_expanded_row_count} "
            f"expected={expected_global_expansion}"
        )

    expected_monster_additions = int(
        drop_authoring_overlay[
            "enabled_monster_addition_count"
        ]
    )
    if monster_authoring_added_row_count != expected_monster_additions:
        raise RuntimeError(
            "monster authoring addition mismatch: "
            f"actual={monster_authoring_added_row_count} "
            f"expected={expected_monster_additions}"
        )

    final_drop_row_count = sum(
        int(profile.get("entry_count", 0))
        for profile in drop_profiles.values()
    )
    if final_drop_row_count != (
        base_drop_row_count
        + global_authoring_expanded_row_count
        + monster_authoring_added_row_count
    ):
        raise RuntimeError(
            "final drop row count invariant failed"
        )
    source_files = [
        VANILLA_PATH,
        SERVICE_PATH,
        BEHAVIOR_PATH,
        BOSS_RULE_PATH,
        ANIMATION_PATH,
        CLASSIFICATION_PATH,
        CLASSIFICATION_ID_PATH,
        POLICY_PATH,
        SPECIAL_NORMAL_AUTHORITY_PATH,
        DPV2_ITEM_TIER_AUTHORITY_PATH,
        DPV2_ROLE_AUTHORITY_PATH,
        DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH,
        DROP_SOURCE_PATH,
        DROP_AUTHORING_OVERLAY_PATH,
        COMBAT_SOURCE_PATH,
        DETAIL_SOURCE_PATH,
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
            "user_authoritative_overrides": [
                {
                    "source": DETAIL_SOURCE_PATH.relative_to(ROOT).as_posix(),
                    "authority": "user_authoritative_override",
                    "scope": ["monster_attributes", "monster_timing", "monster_life_flags"],
                    "excludes": ["drops", "drop_probability", "spawn", "respawn", "map"],
                }
            ],
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
            "drop_base_row_count": base_drop_row_count,
            "drop_authoring_enabled_global_count": len(
                drop_authoring_overlay["enabled_global_additions"]
            ),
            "drop_authoring_global_expanded_row_count": (
                global_authoring_expanded_row_count
            ),
            "drop_authoring_enabled_monster_count": (
                expected_monster_additions
            ),
            "drop_authoring_monster_added_row_count": (
                monster_authoring_added_row_count
            ),
            "drop_final_row_count": final_drop_row_count,
            "special_normal_spawn_count": sum(
                x.get("spawn_classification") == "special_normal"
                for x in entries
            ),
        },
        "special_normal_spawn_authority": {
            "schema": special_normal_authority["schema"],
            "authority_id": special_normal_authority["authority_id"],
            "path": SPECIAL_NORMAL_AUTHORITY_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256_file(SPECIAL_NORMAL_AUTHORITY_PATH),
            "canonical_monster_ids": sorted(SPECIAL_NORMAL_IDS),
            "production_active": True,
            "phase_1_allowed": True,
            "authority_provenance": copy.deepcopy(
                special_normal_authority["drop_binding"][
                    "authority_provenance"
                ]
            ),
        },
        "appearance_profiles": appearance_profiles,
        "drop_profiles": drop_profiles,
        "entries": entries,
        "entries_by_id": entries_by_id,
    }
    return catalog


def validate_catalog(catalog: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    combat_source = load_json(COMBAT_SOURCE_PATH)
    combat_source_by_id = combat_source.get("records_by_monster_id", {})
    try:
        detail_source = load_json(DETAIL_SOURCE_PATH)
        detail_by_id = validate_21cq_detail_source(detail_source)
    except (RuntimeError, ValueError, TypeError) as exc:
        errors.append(str(exc))
        detail_source = {}
        detail_by_id = {}
    special_normal_authority = load_json(SPECIAL_NORMAL_AUTHORITY_PATH)
    try:
        special_normal_by_id = validate_special_normal_authority(
            special_normal_authority,
            load_json(VANILLA_PATH),
            load_json(DPV2_ROLE_AUTHORITY_PATH),
            load_json(DPV2_ITEM_TIER_AUTHORITY_PATH),
            load_json(DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH),
        )
    except (RuntimeError, ValueError, TypeError) as exc:
        errors.append(str(exc))
        special_normal_by_id = {}

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
    if len(entries) != 156:
        errors.append(f"identity_count={len(entries)} expected 156")
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

    summary = catalog.get("summary", {})
    if not isinstance(summary, dict):
        errors.append("summary is not a dictionary")
        summary = {}

    base_rows = int(summary.get("drop_base_row_count", -1))
    global_enabled = int(
        summary.get("drop_authoring_enabled_global_count", -1)
    )
    global_expanded = int(
        summary.get("drop_authoring_global_expanded_row_count", -1)
    )
    monster_enabled = int(
        summary.get("drop_authoring_enabled_monster_count", -1)
    )
    monster_added = int(
        summary.get("drop_authoring_monster_added_row_count", -1)
    )
    final_rows = int(summary.get("drop_final_row_count", -1))

    if global_expanded != global_enabled * len(drops):
        errors.append("drop authoring global expansion invariant failed")
    if monster_added != monster_enabled:
        errors.append("drop authoring monster addition invariant failed")
    if final_rows != base_rows + global_expanded + monster_added:
        errors.append("drop authoring final row invariant failed")

    observed_final_rows = sum(
        len(profile.get("entries", []))
        for profile in drops.values()
        if isinstance(profile, dict)
    )
    if observed_final_rows != final_rows:
        errors.append(
            "drop authoring observed final row count mismatch"
        )
    for entry in entries:
        if not isinstance(entry, dict):
            errors.append("non-dictionary entry")
            continue
        monster_id = int(entry.get("monster_id", -1))
        required = ("canonical_name", "classification", "spawn_classification", "editor_placement", "spawn_authority", "runtime_allowed", "status", "drop_policy", "combat", "appearance_profile_id", "drop_profile_id", "spawn_contexts", "source_evidence")
        for field in required:
            if field not in entry:
                errors.append(f"monster_id={monster_id} missing {field}")
        special_normal_row = special_normal_by_id.get(monster_id)
        if special_normal_row is None:
            if entry.get("spawn_classification") is not None:
                errors.append(f"monster_id={monster_id} has an unexpected spawn_classification")
            if entry.get("spawn_authority") is not None:
                errors.append(f"monster_id={monster_id} has an unexpected spawn_authority")
        else:
            if entry.get("spawn_classification") != "special_normal":
                errors.append(f"monster_id={monster_id} spawn_classification is not special_normal")
            placement = entry.get("editor_placement", {})
            if placement.get("placement_kind") != "monster_spawn":
                errors.append(f"monster_id={monster_id} special_normal placement is not monster_spawn")
            if placement.get("source_scope") != "special_normal_spawn_authority_v1":
                errors.append(f"monster_id={monster_id} special_normal placement source scope drift")
            spawn_authority = entry.get("spawn_authority")
            if not isinstance(spawn_authority, dict):
                errors.append(f"monster_id={monster_id} missing special_normal spawn_authority")
            else:
                for key, expected in SPECIAL_NORMAL_DEFAULTS.items():
                    if spawn_authority.get(key) != expected:
                        errors.append(f"monster_id={monster_id} spawn_authority.{key}={spawn_authority.get(key)!r} expected {expected!r}")
                drop_binding = spawn_authority.get("drop_binding", {})
                for key in ("drop_enabled", "drop_role", "role_factor", "role_assignment_authority", "item_tier_resolution", "additional_multiplier", "source_rate_role"):
                    expected = {
                        "drop_enabled": special_normal_row["drop_enabled"],
                        "drop_role": special_normal_row["drop_role"],
                        "role_factor": special_normal_row["role_factor"],
                        "role_assignment_authority": special_normal_row["role_assignment_authority"],
                        "item_tier_resolution": special_normal_row["item_tier_resolution"],
                        "additional_multiplier": None,
                        "source_rate_role": "provenance_only",
                    }[key]
                    if not isinstance(drop_binding, dict) or drop_binding.get(key) != expected:
                        errors.append(f"monster_id={monster_id} spawn_authority.drop_binding.{key} drift")
                expected_provenance = special_normal_authority.get(
                    "drop_binding", {}
                ).get("authority_provenance", {})
                if (
                    not isinstance(drop_binding, dict)
                    or drop_binding.get("authority_provenance")
                    != expected_provenance
                    or drop_binding.get("item_tier_sha")
                    != expected_provenance.get("item_tier_sha")
                    or drop_binding.get("monster_role_sha")
                    != expected_provenance.get("monster_role_sha")
                    or drop_binding.get("global_scale_sha")
                    != expected_provenance.get("global_scale_sha")
                ):
                    errors.append(
                        f"monster_id={monster_id} special_normal DPV2 provenance drift"
                    )

        combat_value = entry.get("combat", {})
        projection = combat_value.get("runtime_projection", {}) if isinstance(combat_value, dict) else {}
        detail_row = detail_by_id.get(monster_id, {})
        if not isinstance(projection, dict):
            errors.append(f"monster_id={monster_id} runtime_projection missing")
        else:
            for field in ("agility", "accuracy", "life_type", "undead", "anti_stealth"):
                if field in detail_row and projection.get(field) != detail_row[field]:
                    errors.append(
                        f"monster_id={monster_id} runtime_projection.{field}={projection.get(field)!r} "
                        f"expected 21CQ={detail_row[field]!r}"
                    )
            if int(projection.get("anti_poison", -1)) != int(RUNTIME_PROJECTION_DEFAULTS["anti_poison"]):
                errors.append(f"monster_id={monster_id} unsafe anti_poison projection")
            projection_evidence = projection.get("source_evidence", {})
            for projection_field in ("agility", "accuracy", "life_type", "undead", "anti_stealth"):
                evidence = projection_evidence.get(projection_field, {}) if isinstance(projection_evidence, dict) else {}
                if not isinstance(evidence, dict) or evidence.get("authority") != "user_authoritative_override":
                    errors.append(f"monster_id={monster_id} {projection_field} missing 21CQ authority evidence")
            anti_poison_evidence = projection_evidence.get("anti_poison", {}) if isinstance(projection_evidence, dict) else {}
            if not isinstance(anti_poison_evidence, dict) or anti_poison_evidence.get("tier") != "project_rule":
                errors.append(f"monster_id={monster_id} anti_poison missing project_rule evidence")
        timing = combat_value.get("timing", {}) if isinstance(combat_value, dict) else {}
        if isinstance(detail_row, dict) and detail_row:
            if timing.get("attack_interval_ms") != detail_row.get("attack_interval_ms"):
                errors.append(f"monster_id={monster_id} attack timing is not 21CQ")
            if timing.get("move_interval_ms") != detail_row.get("move_interval_ms"):
                errors.append(f"monster_id={monster_id} move timing is not 21CQ")
            if timing.get("confidence") != "user_authoritative_21cq":
                errors.append(f"monster_id={monster_id} timing authority is not 21CQ")
            behavior_timing = combat_value.get("behavior_profile", {}).get("timing", {}) if isinstance(combat_value.get("behavior_profile", {}), dict) else {}
            if behavior_timing.get("attackIntervalMs") != detail_row.get("attack_interval_ms") or behavior_timing.get("moveIntervalMs") != detail_row.get("move_interval_ms"):
                errors.append(f"monster_id={monster_id} behavior_profile timing is not 21CQ")
            service_behavior = combat_value.get("behavior_profile", {}).get("serviceBehavior", {}) if isinstance(combat_value.get("behavior_profile", {}), dict) else {}
            if service_behavior.get("undead") != detail_row.get("undead") or service_behavior.get("lifeType") != detail_row.get("life_type") or service_behavior.get("antiStealth") != detail_row.get("anti_stealth"):
                errors.append(f"monster_id={monster_id} behavior_profile life flags are not 21CQ")
        if isinstance(projection, dict):
            for projection_field in ("anti_poison",):
                evidence = projection_evidence.get(projection_field, {}) if isinstance(projection_evidence, dict) else {}
                if not isinstance(evidence, dict) or evidence.get("tier") != "project_rule":
                    errors.append(f"monster_id={monster_id} {projection_field} missing project_rule evidence")
        if by_id.get(str(monster_id)) != entry:
            errors.append(f"monster_id={monster_id} entries_by_id closure")
        placement = entry.get("editor_placement", {})
        disposition = str(entry.get("disposition", "")).strip()
        placement_disposition = str(
            placement.get("disposition", "")
        ).strip() if isinstance(placement, dict) else ""
        disposition_evidence = entry.get("disposition_evidence", {})
        source_evidence = entry.get("source_evidence", {})
        classification_evidence = (
            source_evidence.get("classification", {})
            if isinstance(source_evidence, dict)
            else {}
        )
        if disposition:
            if disposition not in EDITOR_PLACEMENT_DISPOSITIONS:
                errors.append(
                    f"monster_id={monster_id} unsupported disposition={disposition}"
                )
            if not isinstance(placement, dict) or bool(placement.get("allowed", True)):
                errors.append(
                    f"monster_id={monster_id} disposition requires editor placement=false"
                )
            if placement_disposition != disposition:
                errors.append(
                    f"monster_id={monster_id} editor disposition mismatch"
                )
            if not isinstance(disposition_evidence, dict) or not disposition_evidence:
                errors.append(
                    f"monster_id={monster_id} disposition evidence missing"
                )
            if not isinstance(classification_evidence, dict) or (
                classification_evidence.get("disposition") != disposition
                or classification_evidence.get("disposition_evidence")
                != disposition_evidence
            ):
                errors.append(
                    f"monster_id={monster_id} classification disposition evidence mismatch"
                )
        elif placement_disposition:
            errors.append(
                f"monster_id={monster_id} editor disposition has no entry disposition"
            )
        appearance_id = str(entry.get("appearance_profile_id", ""))
        profile = profiles.get(appearance_id)
        if not isinstance(profile, dict):
            errors.append(f"monster_id={monster_id} missing appearance profile {appearance_id}")
        elif entry.get("runtime_allowed"):
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
            if entry.get("runtime_allowed") and hostile and entry_count <= 0:
                exemption = entry.get("drop_policy", {}).get("exemption")
                if not isinstance(exemption, dict) or not exemption.get("allowed"):
                    errors.append(f"monster_id={monster_id} hostile allowed without non-empty drop profile")
            sources = drop_profile.get("source_evidence", {}).get("sources", [])
            if not isinstance(sources, list) or not sources:
                errors.append(f"monster_id={monster_id} drop profile lacks source evidence")
            if drop_profile.get("status") == "missing_for_hostile" and hostile and entry.get("runtime_allowed"):
                errors.append(f"monster_id={monster_id} missing hostile drop marked allowed")
        if entry.get("classification") == "non_hostile":
            exemption = entry.get("drop_policy", {}).get("exemption")
            if not isinstance(exemption, dict) or not exemption.get("allowed") or not exemption.get("reason"):
                errors.append(f"monster_id={monster_id} non_hostile missing explicit drop exemption reason")
        evidence = entry.get("source_evidence", {})
        for field in ("canonical_name", "classification", "combat_stats", "combat_ai_timing", "appearance", "drops", "status"):
            if field not in evidence:
                errors.append(f"monster_id={monster_id} missing source evidence {field}")
    catalog_special_normal = catalog.get("special_normal_spawn_authority", {})
    expected_catalog_provenance = special_normal_authority.get(
        "drop_binding", {}
    ).get("authority_provenance", {})
    if (
        not isinstance(catalog_special_normal, dict)
        or catalog_special_normal.get("authority_provenance")
        != expected_catalog_provenance
    ):
        errors.append("catalog special_normal DPV2 provenance drift")
    matrix = catalog.get("entries_by_id", {})

    # P3C: historical WOOma_IDS 保留为审计证据；生产校验只覆盖 active
    # Wooma 成员，retired 成员（65/67/69/71）不得出现在 catalog。
    EXPECTED_ACTIVE_WOOMA_IDS = {
        64, 66, 68, 70, 73, 74, 75, 76, 77, 78, 239,
    }
    EXPECTED_RETIRED_WOOMA_IDS = {
        65, 67, 69, 71,
    }
    actual_active_wooma_ids = {
        monster_id
        for monster_id in WOOma_IDS
        if str(monster_id) in matrix
    }
    if actual_active_wooma_ids != EXPECTED_ACTIVE_WOOMA_IDS:
        errors.append(
            "P3C active Wooma universe mismatch: "
            f"expected={sorted(EXPECTED_ACTIVE_WOOMA_IDS)} "
            f"actual={sorted(actual_active_wooma_ids)}"
        )
    for monster_id in EXPECTED_RETIRED_WOOMA_IDS:
        if str(monster_id) in matrix:
            errors.append(
                f"P3C retired Wooma monster_id={monster_id} "
                "must not appear in canonical catalog"
            )

    active_wooma_ids = [
        monster_id
        for monster_id in WOOma_IDS
        if str(monster_id) in matrix
    ]
    for monster_id in active_wooma_ids:
        entry = matrix[str(monster_id)]
        expected = {
            64: "ordinary", 65: "ordinary", 66: "ordinary", 67: "ordinary", 68: "ordinary", 69: "ordinary", 70: "ordinary", 71: "ordinary", 73: "elite", 74: "elite", 75: "elite", 76: "boss", 77: "special", 78: "version_difference", 239: "boss",
        }[monster_id]
        if entry.get("classification") != expected:
            errors.append(f"Wooma monster_id={monster_id} classification={entry.get('classification')} expected {expected}")
        if monster_id in WOOma_SLUG_BY_ID:
            if WOOma_SLUG_BY_ID[monster_id] not in str(entry.get("appearance_profile_id", "")):
                errors.append(f"Wooma monster_id={monster_id} appearance profile is not explicit {WOOma_SLUG_BY_ID[monster_id]}")
        # P3B: no placement fail-closed for any active identity. Appearance
        # exact-ID closure is enforced globally for runtime_allowed entries
        # and by tests/canonical_monster_exact_animation_closure_test.py.
    active_equivalence_ids = {
        monster_id
        for monster_id in WOOMA_EQUIVALENCE_IDS
        if str(monster_id) in matrix
    }
    if active_equivalence_ids != {68}:
        errors.append(
            "P3C active Wooma equivalence universe mismatch: "
            f"expected={{68}} actual={sorted(active_equivalence_ids)}"
        )
    for monster_id in sorted(active_equivalence_ids):
        entry = matrix[str(monster_id)]
        stats = entry["combat"]["stats"]
        expected_detail = detail_by_id.get(monster_id, {})
        if (
            stats.get("attack_min") != expected_detail.get("attack_min")
            or stats.get("attack_max") != expected_detail.get("attack_max")
            or stats.get("exp") != expected_detail.get("exp")
        ):
            errors.append(f"Wooma monster_id={monster_id} 21CQ stats override missing")
        evidence = entry.get("source_evidence", {}).get("combat_auxiliary", {})
        if not all(field in evidence for field in ("level", "hp", "defense", "magic_defense", "attack_min", "attack_max", "exp", "ai_code", "attack_interval_ms", "move_interval_ms", "view_range", "image")):
            errors.append(f"Wooma monster_id={monster_id} auxiliary fields lack per-field evidence")
        expected_drop_count = 58 if monster_id == 68 else 62
        drop = catalog.get("drop_profiles", {}).get(str(entry.get("drop_profile_id", "")), {})
        # The Excel source is now the canonical drop authority, so the Wooma
        # cross-distribution equivalence is retired; only require a non-empty
        # audited table for these hostile ordinary variants.
        if int(drop.get("entry_count", 0)) <= 0:
            errors.append(f"Wooma monster_id={monster_id} canonical drop table is empty")
    # 21CQ user-authoritative detail rows now win over all historical
    # candidates.  Vanilla remains the primary identity baseline and is
    # checked below only where no explicit 21CQ conflict existed.
    vanilla_records = load_json(VANILLA_PATH).get("records", [])
    vanilla_by_id = {int(r.get("monsterId", -1)): r for r in vanilla_records if isinstance(r, dict)}
    vanilla_combat_expectations = {
        mid: {
            "level": int(rec.get("level", 0)),
            "exp": int(rec.get("exp", 0)),
            "hp": int(rec.get("hp", 0)),
            "defense": int(rec.get("defense", 0)),
            "magic_defense": int(rec.get("magicDefense", 0)),
            "attack_min": int(rec.get("attackMin", 0)),
            "attack_max": int(rec.get("attackMax", 0)),
        }
        for mid, rec in vanilla_by_id.items()
        if rec.get("recordStatus") != "retired"
    }
    for monster_id, expected_stats in vanilla_combat_expectations.items():
        entry = matrix.get(str(monster_id))
        if not isinstance(entry, dict):
            continue
        actual_stats = entry.get("combat", {}).get("stats", {})
        # Skip IDs with explicit policy combat_override (e.g. 68/69)
        policy_wooma = load_json(POLICY_PATH).get("wooma_matrix", {}).get(str(monster_id), {})
        if isinstance(policy_wooma, dict) and isinstance(policy_wooma.get("combat_override"), dict):
            continue
        # Skip the fixed R4C Monster.DB core override IDs: their stats are
        # validated against the combat source instead of vanilla below.
        if monster_id in MONSTER_DB_CORE_OVERRIDE_IDS:
            continue
        for field, expected in expected_stats.items():
            if actual_stats.get(field) != expected:
                errors.append(
                    f"monster_id={monster_id} vanilla {field}={actual_stats.get(field)} expected {expected}"
                )
    # The six historical Monster.DB override IDs must now match 21CQ exactly,
    # while preserving the old Monster.DB value as superseded conflict
    # evidence on every changed field.
    for monster_id in sorted(MONSTER_DB_CORE_OVERRIDE_IDS):
        entry = matrix.get(str(monster_id))
        if not isinstance(entry, dict):
            errors.append(f"monster_id={monster_id} missing in catalog for Monster.DB override")
            continue
        db_entry = combat_source_by_id.get(str(monster_id), {})
        detail_entry = detail_by_id.get(monster_id, {})
        actual_stats = entry.get("combat", {}).get("stats", {})
        for field in MONSTER_DB_CORE_STATS_FIELDS:
            if actual_stats.get(field) != detail_entry.get(field):
                errors.append(
                    f"monster_id={monster_id} 21CQ {field}={actual_stats.get(field)} "
                    f"expected {detail_entry.get(field)}"
                )
            field_evidence = entry.get("source_evidence", {}).get("combat_stats", {}).get(field, {})
            if field_evidence.get("role") != "monster_21cq_detail_user_authoritative_override":
                errors.append(f"monster_id={monster_id} {field} evidence role is not 21CQ override")
            if db_entry.get(field) != detail_entry.get(field):
                conflicts = field_evidence.get("superseded_conflicts", [])
                if not any(
                    isinstance(candidate, dict)
                    and candidate.get("role") == "superseded_monster_db_exact_id_candidate"
                    and candidate.get("value") == db_entry.get(field)
                    for candidate in conflicts
                ):
                    errors.append(f"monster_id={monster_id} {field} missing superseded Monster.DB conflict evidence")
    for monster_id in sorted(MONSTER_DB_RACE_200_RUNTIME_IDS):
        entry = matrix.get(str(monster_id), {})
        combat = entry.get("combat", {}) if isinstance(entry, dict) else {}
        ai = combat.get("ai", {}) if isinstance(combat, dict) else {}
        timing = combat.get("timing", {}) if isinstance(combat, dict) else {}
        behavior = combat.get("behavior_profile", {}) if isinstance(combat, dict) else {}
        evidence = (
            entry.get("source_evidence", {})
            .get("combat_ai_timing", {})
            .get("service", {})
            if isinstance(entry, dict)
            else {}
        )
        if int(ai.get("ai_code", -1)) != 200:
            errors.append(f"monster_id={monster_id} lost primary Race 200 ai_code")
        if str(ai.get("resolution_status", "")) != "primary_monster_db_exact_id":
            errors.append(f"monster_id={monster_id} Race 200 AI is not primary exact-ID")
        if int(timing.get("attack_interval_ms", 0)) != 2000 or int(timing.get("move_interval_ms", 0)) != 1200:
            errors.append(f"monster_id={monster_id} Race 200 timing mismatch")
        if int(behavior.get("serviceClass", {}).get("race", -1)) != 200:
            errors.append(f"monster_id={monster_id} behavior profile lost Race 200 class")
        if evidence.get("role") != "race_200_ai_timing_monster_db_exact_id":
            errors.append(f"monster_id={monster_id} Race 200 evidence role mismatch")
        if evidence.get("sha256") != combat_source.get("source_sha256"):
            errors.append(f"monster_id={monster_id} Race 200 evidence sha256 mismatch")
    # Canonical name must come from vanilla exact-ID record.name for ALL active.
    for monster_id, rec in vanilla_by_id.items():
        if rec.get("recordStatus") == "retired":
            continue
        entry = matrix.get(str(monster_id))
        if not isinstance(entry, dict):
            continue
        expected_name = str(rec.get("name", ""))
        if entry.get("canonical_name") != expected_name:
            errors.append(f"monster_id={monster_id} canonical_name={entry.get('canonical_name')} expected vanilla={expected_name}")
        name_evidence = entry.get("source_evidence", {}).get("canonical_name", {})
        if name_evidence.get("tier") != "primary" or name_evidence.get("distribution") != "source.vanilla_176":
            errors.append(f"monster_id={monster_id} canonical_name source is not primary vanilla")
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
            print(f"CANONICAL_MONSTER_CATALOG_CHECK_PASS: identities={len(catalog['entries'])} runtime_allowed={catalog['summary']['runtime_allowed_count']} drop_rows={catalog['summary']['drop_final_row_count']} authoring_rows={catalog['summary']['drop_final_row_count'] - catalog['summary']['drop_base_row_count']}")
            return 0
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8", newline="\n")
        print(f"CANONICAL_MONSTER_CATALOG_BUILD_PASS: identities={len(catalog['entries'])} runtime_allowed={catalog['summary']['runtime_allowed_count']} drop_rows={catalog['summary']['drop_final_row_count']} authoring_rows={catalog['summary']['drop_final_row_count'] - catalog['summary']['drop_base_row_count']}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
