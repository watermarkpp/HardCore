#!/usr/bin/env python3
"""Build/check the read-only M00 monster runtime authority.

This tool does not alter monster runtime behavior.  It freezes sourced facts
and keeps compatibility projections visibly separate from classic authority.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/data/monster_runtime_authority_v1.json"
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
BEHAVIOR_PATH = ROOT / "assets/data/monster_behavior_profiles.json"
BOSS_PATH = ROOT / "assets/data/boss_service_rules.json"
COMBAT_SOURCE_PATH = ROOT / "assets/data/canonical_monster_combat_source_v1.json"
MOVEMENT_MASTER_PATH = ROOT / "assets/data/monster_movement_source_master_v1.json"
DETAIL_SOURCE_PATH = ROOT / "assets/data/monster_21cq_detail_source_v1.json"
BASE_SHA = "f4879d33c78edf21ff189b7be451162e3dbcd37b"
M00_FINAL_SHA = "1945a5eceaf6efc49ddf4e5da4298834bf15c864"

FINAL_STATUSES = {
    "LOCKED",
    "CANDIDATE",
    "DATA_HOLD",
    "ACCEPTED_CANDIDATE",
    "COMPATIBILITY_HOLD",
}
AUTHORITY_CLASSES = {
    "A_LOCKED",
    "B_CANDIDATE",
    "C_COMPATIBILITY",
    "CONFLICT",
    "UNKNOWN",
}

CLASSIC_DB_SOURCE = {
    "distribution": "candidate.mylgd_mir2server_176",
    "declared_tier": "explicit_user_requested_candidate_after_routed_source_exhaustion",
    "policy_route_status": "accepted_by_M00R_after_all_routed_server_data_sources_failed_version_scope_or_field_coverage",
    "original_path": (
        "dev_art_sources/reference/mir2_database_candidates/"
        "mylgd_mir2server_176/Mud2/DB/Monster.DB"
    ),
    "rule_loader": "dev_art_sources/reference/original_gameofmir/M2Server/LocalDB.pas:1351-1353",
}

RULE_SOURCE = {
    "distribution": "source.original_gameofmir.server_suite",
    "tier": "primary",
}

SPECIAL_VIEW_BY_PROFILE = {
    "touch_dragon": (6, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:442-450"),
    "stationary_summoner": (9, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:370-374"),
    "stationary_demon": (16, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:588-593"),
    "millennium_tree": (16, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:588-593"),
    "stationary_spider": (9, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:648-655"),
    "zuma_boss": (8, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1446-1454"),
    "zuma_dormant": (7, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1357-1363"),
    "zuma_guard_holy_word": (7, "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1357-1363"),
    "zuma_archer": (5, "dev_art_sources/reference/original_gameofmir/M2Server/ObjAxeMon.pas:102-107"),
}

# Monster.DB Race selects the concrete Pascal actor in TUserEngine.AddBaseObject.
# The per-class ViewRange is then inherited from TMonster/TAnimalObject or
# overridden by that concrete class.  Keep the candidate DB binding authority
# separate from the A-grade source-code rule: an exact candidate row may apply
# this rule as B_CANDIDATE, while a reused/missing row must remain DATA_HOLD.
CLASSIC_TARGETING_BY_SERVER_RACE: dict[int, dict[str, Any]] = {
    52: {"pascal_class": "TMonster/TChickenDeer", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    53: {"pascal_class": "TATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    81: {"pascal_class": "TATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    82: {"pascal_class": "TSpitSpider", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    83: {"pascal_class": "TSlowATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    84: {"pascal_class": "TScorpion", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    85: {"pascal_class": "TStickMonster", "view_range_cells": 7, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:154-161"},
    86: {"pascal_class": "TATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    87: {"pascal_class": "TDualAxeMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjAxeMon.pas:102-107"},
    88: {"pascal_class": "TATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    89: {"pascal_class": "TATMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    90: {"pascal_class": "TGasAttackMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    91: {"pascal_class": "TMagCowMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    92: {"pascal_class": "TCowKingMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    93: {"pascal_class": "TThornDarkMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjAxeMon.pas:19-24,102-107"},
    94: {"pascal_class": "TLightingZombi", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    95: {"pascal_class": "TDigOutZombi", "view_range_cells": 7, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1193-1199"},
    96: {"pascal_class": "TZilKinZombi", "view_range_cells": 6, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1265-1270"},
    97: {"pascal_class": "TCowMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
    100: {"pascal_class": "TWhiteSkeleton", "view_range_cells": 6, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1317-1322"},
    101: {"pascal_class": "TScultureMonster", "view_range_cells": 7, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1357-1363"},
    102: {"pascal_class": "TScultureKingMonster", "view_range_cells": 8, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1446-1454"},
    103: {"pascal_class": "TBeeQueen", "view_range_cells": 9, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:370-374"},
    104: {"pascal_class": "TArcherMonster", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjAxeMon.pas:26-31,102-107"},
    105: {"pascal_class": "TGasMothMonster", "view_range_cells": 7, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1569-1572"},
    107: {"pascal_class": "TCentipedeKingMonster", "view_range_cells": 6, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:442-450"},
    112: {"pascal_class": "TArcherGuard", "view_range_cells": 12, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:889-893"},
    114: {"pascal_class": "TElfWarriorMonster", "view_range_cells": 6, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1718-1722"},
    115: {"pascal_class": "TBigHeartMonster", "view_range_cells": 16, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:588-593"},
    116: {"pascal_class": "TSpiderHouseMonster", "view_range_cells": 9, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:648-655"},
    117: {"pascal_class": "TExplosionSpider", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon2.pas:729-736"},
    120: {"pascal_class": "TSoccerBall", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:1203-1219"},
    200: {"pascal_class": "TElectronicScolpionMon", "view_range_cells": 5, "view_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"},
}

CLASS_BINDING_SOURCE = (
    "dev_art_sources/reference/original_gameofmir/M2Server/UsrEngn.pas:1831-1938"
)

SOURCE_ROW_MISSING_TARGETING_IDS = {
    41, 59, 78, 123, 161, 190, 228, 229, 230, 231, 232, 233,
}

KNOWN_EXACT_VIEW_CORRECTIONS = {
    30: 7,
    81: 7,
    83: 6,
    85: 6,
    87: 6,
    128: 7,
    143: 7,
    146: 6,
    166: 6,
    168: 7,
    187: 6,
    194: 12,
    226: 6,
    227: 6,
    234: 6,
}

SOURCE_LOCKED_STATIONARY_PROFILES = {
    "touch_dragon",
    "stationary_summoner",
    "stationary_demon",
    "stationary_spider",
    "millennium_tree",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_raw_monster_db() -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    module_path = ROOT / "tools/build_complete_monster_client_art.py"
    spec = importlib.util.spec_from_file_location("m00_monster_db_reader", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load Monster.DB reader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rows, metadata = module.read_monster_db()
    return {str(row["Name"]): row for row in rows}, metadata


def projection_value_gu(projection: dict[str, Any], default: float) -> float:
    if "move_speed_gu_per_sec" in projection:
        return max(0.0, float(projection["move_speed_gu_per_sec"]))
    if "moveSpeed" in projection:
        return max(0.0, float(projection["moveSpeed"]) / 32.0)
    return default


def current_runtime_speed_gu(
    entry: dict[str, Any], profile: dict[str, Any], boss_rule: dict[str, Any]
) -> float:
    value = 1.25 if entry.get("classification") == "boss" else 1.8125
    value = projection_value_gu(dict(profile.get("runtimeProjection", {})), value)
    if entry.get("classification") == "boss":
        value = projection_value_gu(dict(boss_rule.get("runtimeProjection", {})), value)
    if bool(dict(profile.get("movement", {})).get("stationary", False)):
        return 0.0
    return round(value, 6)


def movement_record(
    entry: dict[str, Any],
    profile_id: str,
    profile: dict[str, Any],
    boss_rule: dict[str, Any],
    combat_record: dict[str, Any] | None,
    raw_row: dict[str, Any] | None,
    combat_source: dict[str, Any],
    movement_source: dict[str, Any],
) -> dict[str, Any]:
    exact = combat_record is not None and raw_row is not None
    canonical_interval = int(
        dict(dict(entry.get("combat", {})).get("timing", {})).get("move_interval_ms", 0)
    )
    timing_profile = dict(dict(entry.get("combat", {})).get("behavior_profile", {})).get(
        "timing", {}
    )
    timing_confidence = str(timing_profile.get("confidence", "")) or None
    timing_resolution = str(timing_profile.get("resolutionStatus", "")) or "unknown"
    stationary = bool(dict(profile.get("movement", {})).get("stationary", False))
    stationary_locked = profile_id in SOURCE_LOCKED_STATIONARY_PROFILES
    unresolved: list[str] = []

    if exact:
        classic_raw_interval = int(combat_record.get("move_interval_ms", 0))
        classic_candidate = {
            "walk_interval_ms": max(200, classic_raw_interval),
            "walk_interval_raw_ms": classic_raw_interval,
            "walk_step": max(1, int(raw_row.get("WalkStep") or 0)),
            "walk_wait_ms": int(raw_row.get("WaLkWait") or 0),
            "authority": "B_CANDIDATE",
            "adoption": "adopted_by_M00R_movement_source_master_exact_binding",
            "source": {
                **CLASSIC_DB_SOURCE,
                "sha256": str(combat_source.get("source_sha256", "")),
                "binding": str(combat_record.get("binding", "")),
            },
        }
        if canonical_interval > 0 and canonical_interval != classic_raw_interval:
            classic_candidate["authority"] = "CONFLICT"
            unresolved.append(
                f"current_canonical_move_interval_ms={canonical_interval} differs from classic_walk_spd_ms={classic_raw_interval}"
            )
    else:
        classic_candidate = None
        unresolved.append("no exact monster_id binding to the selected classic Monster.DB row")

    canonical_candidate = {
        "walk_interval_ms": canonical_interval if canonical_interval > 0 else None,
        "status": "CANDIDATE",
        "authority": "B_CANDIDATE",
        "confidence": timing_confidence,
        "distribution": str(
            dict(timing_profile).get(
                "sourceDistribution",
                dict(dict(entry.get("combat", {})).get("behavior_profile", {}))
                .get("serviceBehavior", {})
                .get("sourceDistribution", "server.crystal.cjlaaa"),
            )
        ),
        "tier": "primary",
        "original_path": "assets/data/service_monster_runtime_catalog.json",
        "field": f"runtimeByMonsterId[{entry['monster_id']}].behaviorProfile.timing.moveIntervalMs",
        "resolution_status": timing_resolution,
    }

    selected_status = str(movement_source["movement_source_status"])
    selected_authority = {
        "LOCKED": "A_LOCKED",
        "ACCEPTED_CANDIDATE": "B_CANDIDATE",
        "COMPATIBILITY_HOLD": "C_COMPATIBILITY",
    }[selected_status]
    selected_confidence = {
        "LOCKED": "A",
        "ACCEPTED_CANDIDATE": "B",
        "COMPATIBILITY_HOLD": "C",
    }[selected_status]
    selected_binding = dict(movement_source["source_binding"])
    selected_binding["master"] = "assets/data/monster_movement_source_master_v1.json"
    interval_authority = dict(movement_source.get("interval_authority", {}))

    return {
        "movement_source_status": selected_status,
        "movement_enabled": bool(movement_source["movement_enabled"]),
        "walk_interval_ms": int(movement_source["walk_interval_ms"]),
        "walk_interval_status": selected_status,
        "walk_interval_authority": selected_authority,
        "walk_interval_confidence": selected_confidence,
        "source": selected_binding,
        "interval_authority": interval_authority,
        "walk_step": int(movement_source["walk_step"]),
        "walk_step_status": selected_status,
        "walk_step_authority": selected_authority,
        "walk_wait_ms": int(movement_source["walk_wait_ms"]),
        "walk_wait_status": selected_status,
        "walk_wait_authority": selected_authority,
        "walk_wait_explicit_zero": int(movement_source["walk_wait_ms"]) == 0,
        "primary_missing_evidence": None,
        "m00r_resolution": str(movement_source["decision_reason"]),
        "server_class_binding": dict(movement_source["server_class_binding"]),
        "interval_conflict": movement_source.get("interval_conflict"),
        "current_canonical_candidate": canonical_candidate,
        "classic_176_non_routed_candidate": classic_candidate,
        "stationary": stationary,
        "stationary_status": "LOCKED" if stationary_locked else "CANDIDATE",
        "stationary_authority": "A_LOCKED" if stationary_locked else "B_CANDIDATE",
        "current_runtime_move_speed_gu_per_sec": current_runtime_speed_gu(entry, profile, boss_rule),
        "current_runtime_projection_status": "C_COMPATIBILITY",
        "unresolved_conflicts": (
            ["compatibility hold requires explicit later review"]
            if selected_status == "COMPATIBILITY_HOLD"
            else []
        ),
    }


def targeting_record(
    monster_id: int,
    profile_id: str,
    movement_source: dict[str, Any],
) -> dict[str, Any]:
    source_binding = dict(movement_source.get("source_binding", {}))
    server_binding = dict(movement_source.get("server_class_binding", {}))
    exact_source_row = source_binding.get("binding_status") == "EXACT_SOURCE_ROW"

    if exact_source_row:
        server_race = int(server_binding.get("server_race", -1))
        class_rule = CLASSIC_TARGETING_BY_SERVER_RACE.get(server_race)
        if class_rule is None:
            raise RuntimeError(
                f"monster_id={monster_id} exact server_race={server_race} has no Pascal targeting rule"
            )
        view = int(class_rule["view_range_cells"])
        view_source: str | None = str(class_rule["view_source"])
        pascal_class: str | None = str(class_rule["pascal_class"])
        class_binding_status = "CANDIDATE"
        class_binding_authority = "B_CANDIDATE"
        view_status = "CANDIDATE"
        view_authority = "B_CANDIDATE"
        acquisition_status = "CANDIDATE"
        acquisition_authority = "B_CANDIDATE"

        profile_view = SPECIAL_VIEW_BY_PROFILE.get(profile_id)
        if profile_view is not None and int(profile_view[0]) != view:
            raise RuntimeError(
                f"monster_id={monster_id} profile={profile_id} view={profile_view[0]} "
                f"conflicts with server_race={server_race} class={pascal_class} view={view}"
            )
        missing_evidence = None
    else:
        # The movement master deliberately retains a candidate reused race for
        # audit, but it is not an exact row for this stable monster_id.  Do not
        # project that candidate race or its class/view into active targeting.
        server_race = None
        pascal_class = None
        class_binding_status = "DATA_HOLD"
        class_binding_authority = "UNKNOWN"
        view = None
        view_source = None
        view_status = "DATA_HOLD"
        view_authority = "UNKNOWN"
        acquisition_status = "DATA_HOLD"
        acquisition_authority = "UNKNOWN"
        missing_evidence = {
            "reason": "no exact Monster.DB source row; reused base-row Race cannot authorize target acquisition",
            "source_binding_status": source_binding.get("binding_status"),
            "source_binding_kind": source_binding.get("source_binding_kind"),
            "candidate_reused_server_race": server_binding.get("server_race"),
            "candidate_reused_behavior_family": server_binding.get("behavior_family"),
            "source": "assets/data/monster_movement_source_master_v1.json",
        }

    return {
        "server_race": server_race,
        "pascal_class": pascal_class,
        "class_binding_status": class_binding_status,
        "class_binding_authority": class_binding_authority,
        "class_binding_source": CLASS_BINDING_SOURCE if exact_source_row else None,
        "class_rule_authority": "A_LOCKED" if exact_source_row else "UNKNOWN",
        "class_binding_missing_evidence": missing_evidence,
        "view_range_cells": view,
        "view_range_status": view_status,
        "view_range_authority": view_authority,
        "view_range_rule_authority": "A_LOCKED" if exact_source_row else "UNKNOWN",
        "view_range_source": view_source,
        "view_range_primary_missing_evidence": {
            "monster_id": monster_id,
            "source": "assets/data/monster_21cq_detail_source_v1.json",
            "fields_checked": ["view_range", "view_range_cells", "viewRange"],
            "result": "MISSING",
            "reason": "21CQ exact-ID detail records contain timing and anti-stealth but no view-range field",
        },
        "acquisition_status": acquisition_status,
        "acquisition_authority": acquisition_authority,
        "idle_search_ms": None,
        "idle_search_status": "DATA_HOLD",
        "engaged_search_ms": None,
        "engaged_search_status": "DATA_HOLD",
        "standard_active_class_candidate": {
            "idle_search_ms": 1000,
            "engaged_search_ms": 8000,
            "authority": "A_LOCKED",
            "scope": "TATMonster-family class rule only; not a universal per-monster rule",
            "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:614-629",
        },
        "search_conflict": "primary classes also contain 5s, idle-only 1s, outer-8s, and walk/hit-cadence search paths",
        "target_selection_metric": "manhattan_abs_dx_plus_abs_dy_minimum",
        "target_selection_status": "LOCKED",
        "target_selection_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:22667-22692",
        "struck_policy": {
            "status": "LOCKED",
            "rule": "switch_to_proper_hitter_when_no_target_or_current_target_attackable_or_random_one_in_six",
            "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:2794-2805",
        },
        "focus_timeout_ms": 30000,
        "focus_timeout_status": "LOCKED",
        "focus_refresh_points": ["SetTargetCreat", "attack_release"],
        "focus_refresh_status": "LOCKED",
        "focus_source": [
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:21929-21933",
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:383-399",
        ],
        "disengage_axis_cells": 15,
        "disengage_status": "LOCKED",
        "disengage_rule": "abs(monster_x-target_x)>15 OR abs(monster_y-target_y)>15",
        "disengage_source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:3882-3895",
        "not_spawn_leash": True,
        "not_euclidean_radius": True,
    }


def recovery_record() -> dict[str, Any]:
    return {
        "status": "LOCKED",
        "authority": "A_LOCKED",
        "interval_ms": 6000,
        "interval_derivation": "nHealthFillTime=300 accumulated in elapsed_ms/20 units",
        "formula": "floor(max_hp/75)+1",
        "struck_reset": None,
        "struck_reset_status": "DATA_HOLD",
        "struck_reset_note": "base RM_STRUCK resets the timer, while TAnimalObject intercepts RM_STRUCK without that reset; exact monster dispatch requires a later stage test",
        "available_while_engaged": True,
        "source": [
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:3718-3737",
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:3765-3766",
            "dev_art_sources/reference/original_gameofmir/M2Server/M2Share.pas:1638",
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:2794-2815",
            "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:5468-5499",
        ],
        "rejected_candidate": {
            "formula": "fixed_base_28",
            "authority": "CONFLICT",
            "reason": "no support in the primary server-rule path; must not override MaxHP/75+1",
        },
    }


def wandering_record() -> dict[str, Any]:
    return {
        "status": "LOCKED",
        "authority": "A_LOCKED",
        "decision_rule": "on an eligible movement event: random(20)==0; then random(4)==1 turns random direction, otherwise walks current direction",
        "spawn_patrol_radius": None,
        "spawn_patrol_radius_status": "DATA_HOLD",
        "return_to_spawn": False,
        "return_to_spawn_status": "LOCKED",
        "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:22723-22728",
    }


def build_payload() -> dict[str, Any]:
    catalog = read_json(CATALOG_PATH)
    behavior = read_json(BEHAVIOR_PATH)
    boss_rules = read_json(BOSS_PATH)
    combat_source = read_json(COMBAT_SOURCE_PATH)
    movement_master = read_json(MOVEMENT_MASTER_PATH)
    raw_by_name, raw_meta = load_raw_monster_db()

    profiles = dict(behavior.get("profiles", {}))
    profile_by_id = dict(behavior.get("profileByMonsterId", {}))
    boss_by_id = dict(boss_rules.get("runtimeRulesByMonsterId", {}))
    combat_by_id = dict(combat_source.get("records_by_monster_id", {}))
    movement_by_id = {
        str(item["monster_id"]): item for item in movement_master.get("records", [])
    }

    records: list[dict[str, Any]] = []
    for entry in sorted(catalog.get("entries", []), key=lambda item: int(item["monster_id"])):
        monster_id = int(entry["monster_id"])
        profile_id = str(profile_by_id.get(str(monster_id), ""))
        profile = dict(profiles.get(profile_id, {}))
        boss_rule = dict(boss_by_id.get(str(monster_id), {}))
        combat_record = combat_by_id.get(str(monster_id))
        raw_row = None
        if combat_record is not None:
            raw_row = raw_by_name.get(str(combat_record.get("source_name", "")))

        movement = movement_record(
            entry,
            profile_id,
            profile,
            boss_rule,
            combat_record,
            raw_row,
            combat_source,
            dict(movement_by_id[str(monster_id)]),
        )
        dormant = bool(profile.get("dormant", False)) or bool(
            dict(boss_rule.get("mechanics", {})).get("burrowAmbush", {}).get("enabled", False)
        )
        delivery = dict(profile.get("attackDelivery", {}))
        area_attack = dict(profile.get("areaAttack", {}))
        summon_rule = dict(profile.get("summonRule", {}))
        special_classification = str(profile.get("specialClassification", ""))
        movement_override: dict[str, Any] | None = None
        if monster_id == 76:
            movement_override = {
                "kind": "health_stage_rage",
                "multiplier": 1.8,
                "status": "CANDIDATE",
                "authority": "C_COMPATIBILITY",
                "future_mapping": "multiply cadence frequency; do not multiply classic step distance",
                "source": "assets/data/boss_service_rules.json runtimeRulesByMonsterId[76].mechanics.healthStageRage",
            }

        records.append(
            {
                "monster_id": monster_id,
                "canonical_name": str(entry.get("canonical_name", "")),
                "classification": str(entry.get("classification", "")),
                "runtime_allowed": bool(entry.get("runtime_allowed", False)),
                "behavior_profile_id": profile_id or None,
                "movement": movement,
                "targeting": targeting_record(
                    monster_id,
                    profile_id,
                    dict(movement_by_id[str(monster_id)]),
                ),
                "recovery": recovery_record(),
                "wandering": wandering_record(),
                "special": {
                    "boss": entry.get("classification") == "boss",
                    "elite": entry.get("classification") == "elite",
                    "stationary": bool(movement["stationary"]),
                    "dormant": dormant,
                    "dormant_status": "LOCKED" if dormant else "CANDIDATE",
                    "ranged": delivery.get("kind") in {"physical_projectile", "target_magic"},
                    "special_attack": bool(
                        delivery or area_attack or summon_rule or special_classification
                    ),
                    "special_classification": special_classification or None,
                    "attack_delivery_kind": delivery.get("kind") or ("fixed_area" if area_attack else None),
                    "movement_override": movement_override,
                    "unresolved_conflicts": list(movement["unresolved_conflicts"]),
                },
            }
        )

    classification_counts: dict[str, int] = {}
    runtime_classification_counts: dict[str, int] = {}
    for item in records:
        classification = str(item["classification"])
        classification_counts[classification] = classification_counts.get(classification, 0) + 1
        if item["runtime_allowed"]:
            runtime_classification_counts[classification] = (
                runtime_classification_counts.get(classification, 0) + 1
            )

    counts = {
        "canonical_identities": len(records),
        "runtime_allowed": sum(1 for item in records if item["runtime_allowed"]),
        "classification": classification_counts,
        "runtime_classification": runtime_classification_counts,
        "stationary": sum(1 for item in records if item["special"]["stationary"]),
        "static_dormant": sum(
            1
            for item in records
            if item["special"]["dormant"] and item["behavior_profile_id"] != "touch_dragon"
        ),
        "dormant": sum(1 for item in records if item["special"]["dormant"]),
        "ranged": sum(1 for item in records if item["special"]["ranged"]),
        "special_attack": sum(1 for item in records if item["special"]["special_attack"]),
        "classic_db_non_routed_exact_candidates": sum(
            1
            for item in records
            if item["movement"]["classic_176_non_routed_candidate"] is not None
        ),
        "walk_interval_data_hold": sum(
            1 for item in records if item["movement"]["walk_interval_status"] == "DATA_HOLD"
        ),
        "walk_step_data_hold": sum(
            1 for item in records if item["movement"]["walk_step_status"] == "DATA_HOLD"
        ),
        "walk_wait_data_hold": sum(
            1 for item in records if item["movement"]["walk_wait_status"] == "DATA_HOLD"
        ),
        "movement_locked": sum(
            1 for item in records if item["movement"]["movement_source_status"] == "LOCKED"
        ),
        "movement_accepted_candidate": sum(
            1
            for item in records
            if item["movement"]["movement_source_status"] == "ACCEPTED_CANDIDATE"
        ),
        "movement_compatibility_hold": sum(
            1
            for item in records
            if item["movement"]["movement_source_status"] == "COMPATIBILITY_HOLD"
        ),
        "targeting_exact_class_bindings": sum(
            1
            for item in records
            if item["targeting"]["class_binding_status"] == "CANDIDATE"
        ),
        "targeting_class_binding_data_hold": sum(
            1
            for item in records
            if item["targeting"]["class_binding_status"] == "DATA_HOLD"
        ),
        "targeting_view_range_data_hold": sum(
            1
            for item in records
            if item["targeting"]["view_range_status"] == "DATA_HOLD"
        ),
        "targeting_view_range_distribution": {
            str(view_range): sum(
                1
                for item in records
                if item["targeting"]["view_range_cells"] == view_range
            )
            for view_range in (5, 6, 7, 8, 9, 12, 16)
        },
    }

    return {
        "schema_version": 1,
        "authority_id": "monster.runtime.authority.v1",
        "stage": "M00R_M01_RELEASE_SOURCE_CLOSURE",
        "identity_key": "monster_id",
        "monster_base_sha": BASE_SHA,
        "m00_final_sha": M00_FINAL_SHA,
        "generated_date": "2026-08-24",
        "stage_gate": {
            "m00": "PASS_AFTER_REPOSITORY_GATES",
            "m00r": "PASS_AFTER_REPOSITORY_GATES",
            "m01": "ALLOWED",
            "m01_contract": "RELEASED",
            "blockers": [],
            "deferred_to_m02": ["class-specific target search cadence"],
        },
        "status_vocabulary": {
            "delivery": sorted(FINAL_STATUSES),
            "m01_movement": ["LOCKED", "ACCEPTED_CANDIDATE", "COMPATIBILITY_HOLD"],
            "evidence": sorted(AUTHORITY_CLASSES),
            "unknown_encoding": "null + DATA_HOLD; numeric zero is allowed only when explicitly sourced",
        },
        "source_policy": {
            "policy": "assets/data/source_priority_policy.json",
            "primary_first": True,
            "monster_identity": "assets/data/runtime/canonical_monster_catalog.json",
            "movement_value_authority": "assets/data/monster_movement_source_master_v1.json",
            "move_interval_user_override": {
                "authority": "user_authoritative_override",
                "source": "assets/data/monster_21cq_detail_source_v1.json",
                "field": "move_interval_ms",
                "scope": "monster timing only; strict cadence algorithm and stationary gate unchanged",
            },
            "classic_176_db_candidate": {
                **CLASSIC_DB_SOURCE,
                "adoption": "adopted_by_M00R_audited_candidate_routing",
                "authority": "B_CANDIDATE",
            },
            "classic_server_rules": {
                **RULE_SOURCE,
                "original_path": "dev_art_sources/reference/original_gameofmir/M2Server",
            },
            "continuous_projection_role": "compatibility_only_not_historical_truth",
        },
        "spatial_contract": {
            "status": "LOCKED",
            "authority": "A_LOCKED",
            "persistent_position": "runtime_map_absolute_ground_gu",
            "classic_cell_role": "temporary_derived_only",
            "axis_neighbor_gu": 1.0,
            "diagonal_neighbor_gu": 1.4142135623730951,
            "event_semantics": "axis and diagonal are each one classic movement event",
            "ground_position_gu_to_ai_cell": {
                "value": "Vector2i(floor(position_ground_gu.x), floor(position_ground_gu.y))",
                "status": "LOCKED",
                "authority": "A_LOCKED",
                "reason": "M00R boundary and center round-trip validation against current map runtime cell-center contract",
            },
            "ai_neighbor_cell": {
                "status": "LOCKED",
                "authority": "A_LOCKED",
                "rule": "one of eight integer neighbor deltas per classic movement event",
                "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:1995-2054",
            },
            "cell_to_ground_target": {
                "value": "Vector2(cell)+Vector2(0.5,0.5)",
                "status": "LOCKED",
                "authority": "A_LOCKED",
                "source": "scripts/layers/runtime/map_editor_runtime_bridge.gd:400-401",
            },
            "quantization_validation": "tools/build_monster_movement_source_master.py validate_quantization",
            "source": "scripts/ground_unit_space.gd",
            "ground_unit_space_sha256": sha256(ROOT / "scripts/ground_unit_space.gd"),
        },
        "global_rules": {
            "default_monster_class_view_range_cells": {
                "value": 5,
                "status": "LOCKED",
                "authority": "A_LOCKED",
                "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258",
            },
            "standard_active_class_search": {
                "idle_search_ms": 1000,
                "engaged_search_ms": 8000,
                "status": "LOCKED",
                "authority": "A_LOCKED",
                "scope": "TATMonster-family; not universal",
            },
            "universal_per_monster_search": {
                "idle_search_ms": None,
                "engaged_search_ms": None,
                "status": "DATA_HOLD",
                "authority": "CONFLICT",
            },
            "focus_timeout_ms": 30000,
            "disengage_axis_cells": 15,
            "target_selection_metric": "manhattan_abs_dx_plus_abs_dy_minimum",
            "recovery": recovery_record(),
            "wandering": wandering_record(),
        },
        "classic_db_candidate_metadata": raw_meta,
        "summary": counts,
        "records": records,
    }


def validate(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    catalog = read_json(CATALOG_PATH)
    movement_master = read_json(MOVEMENT_MASTER_PATH)
    detail_source = read_json(DETAIL_SOURCE_PATH)
    canonical = {int(item["monster_id"]): item for item in catalog.get("entries", [])}
    movement_by_id = {
        int(item["monster_id"]): item for item in movement_master.get("records", [])
    }
    detail_by_id = {
        int(item["monster_id"]): item for item in detail_source.get("records", [])
    }
    records = payload.get("records", [])
    if len(records) != len(canonical):
        errors.append(f"record count {len(records)} != canonical count {len(canonical)}")
    seen: set[int] = set()
    for record in records:
        monster_id = int(record.get("monster_id", -1))
        if monster_id in seen:
            errors.append(f"duplicate monster_id={monster_id}")
        seen.add(monster_id)
        expected = canonical.get(monster_id)
        if expected is None:
            errors.append(f"unknown monster_id={monster_id}")
            continue
        if record.get("canonical_name") != expected.get("canonical_name"):
            errors.append(f"monster_id={monster_id} canonical_name drift")
        if record.get("classification") != expected.get("classification"):
            errors.append(f"monster_id={monster_id} classification drift")
        movement = dict(record.get("movement", {}))
        interval_authority = dict(movement.get("interval_authority", {}))
        if interval_authority.get("authority") != "user_authoritative_override":
            errors.append(f"monster_id={monster_id} move interval authority is not 21CQ")
        if interval_authority.get("source") != "assets/data/monster_21cq_detail_source_v1.json":
            errors.append(f"monster_id={monster_id} move interval source drift")
        if int(interval_authority.get("effective_interval_ms", -1)) != int(movement.get("walk_interval_ms", -2)):
            errors.append(f"monster_id={monster_id} move interval effective value drift")
        for value_key, status_key in (
            ("walk_interval_ms", "walk_interval_status"),
            ("walk_step", "walk_step_status"),
            ("walk_wait_ms", "walk_wait_status"),
        ):
            status = movement.get(status_key)
            if status not in FINAL_STATUSES:
                errors.append(f"monster_id={monster_id} invalid {status_key}={status}")
            if movement.get(value_key) is None and status != "DATA_HOLD":
                errors.append(f"monster_id={monster_id} {value_key}=null without DATA_HOLD")
        for authority_key in (
            "walk_interval_authority",
            "walk_step_authority",
            "walk_wait_authority",
            "stationary_authority",
            "current_runtime_projection_status",
        ):
            if movement.get(authority_key) not in AUTHORITY_CLASSES:
                errors.append(
                    f"monster_id={monster_id} invalid {authority_key}={movement.get(authority_key)}"
                )
        targeting = dict(record.get("targeting", {}))
        for required in (
            "view_range_cells",
            "acquisition_status",
            "idle_search_ms",
            "engaged_search_ms",
            "target_selection_metric",
            "struck_policy",
            "focus_timeout_ms",
            "disengage_axis_cells",
        ):
            if required not in targeting:
                errors.append(f"monster_id={monster_id} missing targeting.{required}")
        detail_record = dict(detail_by_id.get(monster_id, {}))
        if any(key in detail_record for key in ("view_range", "view_range_cells", "viewRange")):
            errors.append(f"monster_id={monster_id} 21CQ view-range missing evidence is stale")
        primary_missing = dict(targeting.get("view_range_primary_missing_evidence", {}))
        if (
            primary_missing.get("monster_id") != monster_id
            or primary_missing.get("source") != "assets/data/monster_21cq_detail_source_v1.json"
            or primary_missing.get("result") != "MISSING"
        ):
            errors.append(f"monster_id={monster_id} view-range primary missing evidence drift")
        movement_source = dict(movement_by_id.get(monster_id, {}))
        source_binding = dict(movement_source.get("source_binding", {}))
        exact_source_row = source_binding.get("binding_status") == "EXACT_SOURCE_ROW"
        if exact_source_row:
            source_class_binding = dict(movement_source.get("server_class_binding", {}))
            server_race = int(source_class_binding.get("server_race", -1))
            rule = CLASSIC_TARGETING_BY_SERVER_RACE.get(server_race)
            if rule is None:
                errors.append(
                    f"monster_id={monster_id} exact server_race={server_race} has no targeting rule"
                )
            else:
                if targeting.get("server_race") != server_race:
                    errors.append(f"monster_id={monster_id} targeting.server_race drift")
                if targeting.get("pascal_class") != rule["pascal_class"]:
                    errors.append(f"monster_id={monster_id} targeting.pascal_class drift")
                if targeting.get("view_range_cells") != rule["view_range_cells"]:
                    errors.append(f"monster_id={monster_id} targeting.view_range_cells drift")
                if targeting.get("view_range_source") != rule["view_source"]:
                    errors.append(f"monster_id={monster_id} targeting.view_range_source drift")
            if targeting.get("class_binding_status") != "CANDIDATE":
                errors.append(f"monster_id={monster_id} exact class binding not CANDIDATE")
            if targeting.get("class_binding_authority") != "B_CANDIDATE":
                errors.append(f"monster_id={monster_id} exact class binding authority promoted")
            if targeting.get("class_rule_authority") != "A_LOCKED":
                errors.append(f"monster_id={monster_id} Pascal class rule is not A_LOCKED")
            if targeting.get("view_range_status") != "CANDIDATE":
                errors.append(f"monster_id={monster_id} exact view range not CANDIDATE")
            if targeting.get("view_range_rule_authority") != "A_LOCKED":
                errors.append(f"monster_id={monster_id} view rule is not A_LOCKED")
            if targeting.get("acquisition_status") != "CANDIDATE":
                errors.append(f"monster_id={monster_id} exact acquisition not CANDIDATE")
        else:
            if monster_id not in SOURCE_ROW_MISSING_TARGETING_IDS:
                errors.append(f"monster_id={monster_id} unexpected non-exact targeting row")
            for key in ("server_race", "pascal_class", "view_range_cells", "view_range_source"):
                if targeting.get(key) is not None:
                    errors.append(f"monster_id={monster_id} DATA_HOLD targeting.{key} must be null")
            for key in ("class_binding_status", "view_range_status", "acquisition_status"):
                if targeting.get(key) != "DATA_HOLD":
                    errors.append(f"monster_id={monster_id} invalid DATA_HOLD {key}")
            missing_evidence = dict(targeting.get("class_binding_missing_evidence", {}))
            if missing_evidence.get("source_binding_status") != "SOURCE_ROW_MISSING":
                errors.append(f"monster_id={monster_id} missing exact-row evidence drift")
        recovery = dict(record.get("recovery", {}))
        if recovery.get("status") not in FINAL_STATUSES:
            errors.append(f"monster_id={monster_id} invalid recovery.status")
    if set(canonical) != seen:
        errors.append("monster_id set differs from canonical catalog")
    if payload.get("monster_base_sha") != BASE_SHA:
        errors.append("monster_base_sha drift")
    summary = payload.get("summary", {})
    if summary.get("movement_locked") != 6:
        errors.append("movement_locked must be 6")
    if summary.get("movement_accepted_candidate") != 138:
        errors.append("movement_accepted_candidate must be 138")
    if summary.get("movement_compatibility_hold") != 12:
        errors.append("movement_compatibility_hold must be 12")
    if any(summary.get(key) != 0 for key in (
        "walk_interval_data_hold", "walk_step_data_hold", "walk_wait_data_hold"
    )):
        errors.append("M01 movement fields still contain DATA_HOLD")
    if payload.get("stage_gate", {}).get("m01") != "ALLOWED":
        errors.append("M01 gate is not released")
    if summary.get("targeting_exact_class_bindings") != 144:
        errors.append("targeting_exact_class_bindings must be 144")
    if summary.get("targeting_class_binding_data_hold") != 12:
        errors.append("targeting_class_binding_data_hold must be 12")
    if summary.get("targeting_view_range_data_hold") != 12:
        errors.append("targeting_view_range_data_hold must be 12")
    expected_distribution = {"5": 117, "6": 10, "7": 11, "8": 1, "9": 2, "12": 1, "16": 2}
    if summary.get("targeting_view_range_distribution") != expected_distribution:
        errors.append("targeting_view_range_distribution drift")
    by_id = {int(item.get("monster_id", -1)): item for item in records}
    for monster_id, expected_view in KNOWN_EXACT_VIEW_CORRECTIONS.items():
        targeting = dict(by_id.get(monster_id, {}).get("targeting", {}))
        if targeting.get("view_range_cells") != expected_view:
            errors.append(
                f"monster_id={monster_id} exact view correction != {expected_view}"
            )
    actual_holds = {
        int(item.get("monster_id", -1))
        for item in records
        if dict(item.get("targeting", {})).get("acquisition_status") == "DATA_HOLD"
    }
    if actual_holds != SOURCE_ROW_MISSING_TARGETING_IDS:
        errors.append("targeting DATA_HOLD monster_id set drift")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = build_payload()
    if args.check:
        if not OUTPUT.exists():
            print("MONSTER_RUNTIME_AUTHORITY_CHECK_FAIL output missing")
            return 1
        actual = read_json(OUTPUT)
        errors = validate(actual)
        if actual != expected:
            errors.append("authority output is stale; rebuild required")
        if errors:
            for error in errors:
                print(f"ERROR: {error}")
            print(f"MONSTER_RUNTIME_AUTHORITY_CHECK_FAIL errors={len(errors)}")
            return 1
        print(
            "MONSTER_RUNTIME_AUTHORITY_CHECK_PASS "
            f"records={len(actual['records'])} runtime_allowed={actual['summary']['runtime_allowed']}"
        )
        return 0

    errors = validate(expected)
    if errors:
        raise RuntimeError("; ".join(errors))
    OUTPUT.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "MONSTER_RUNTIME_AUTHORITY_BUILD_PASS "
        f"records={len(expected['records'])} runtime_allowed={expected['summary']['runtime_allowed']}"
    )
    print(f"output={OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
