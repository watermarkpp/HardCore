#!/usr/bin/env python3
"""Validate and report the Fresh P1A DPV2 direct-baseline snapshot.

P1A has two intentionally separate views:

* source_rows is the 156-profile/7032-row current semantic source view. Its
  chance token is provenance, including the one malformed 1/00 row. The
  logical source authority retains 9590 rows, including retired audit rows.
* compiled_slots is the 156-profile/6809-slot V2 Runtime authority. Only
  these rows carry direct canonical identity and can reach independent RNG.

This analyzer consumes the classifications exported by Godot. It does not
resolve source labels, derive probability, or consult historical authorities.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


SNAPSHOT_SCHEMA = "monster_drop_p1a_runtime_snapshot_v3"

EXPECTED_SOURCE_PROFILE_COUNT = 156
EXPECTED_SOURCE_ROW_COUNT = 7032
EXPECTED_LOGICAL_SOURCE_ROW_COUNT = 9590
EXPECTED_ENABLED_SOURCE_ROW_COUNT = 6809
EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT = 223
EXPECTED_RETIRED_SOURCE_ROW_COUNT = 2558
EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT = 1
EXPECTED_RUNTIME_PROFILE_COUNT = 156
EXPECTED_RUNTIME_ALLOWED_PROFILE_COUNT = 153
EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT = 144
EXPECTED_RUNTIME_EXPLICIT_NON_LOOT_PROFILE_COUNT = 9
EXPECTED_RUNTIME_DISABLED_PROFILE_COUNT = 3
EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT = 9
EXPECTED_RUNTIME_SLOT_COUNT = 6809
EXPECTED_LEGACY_RUNTIME_SLOT_COUNT = 6740
EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT = 69

EXPECTED_ANOMALY = {
    "source_profile_id": "drop.168",
    "canonical_monster_id": 168,
    "source_line_number": 20,
    "source_entry_ordinal_zero_based": 19,
    "source_entry_ordinal_one_based": 20,
    "source_slot_index": "slot_020",
    "source_chance": "1/00",
    "source_raw_text": "1/00 灵魂战衣(男)",
    "corrected_base_numerator": 1,
    "corrected_base_denominator": 2800,
}


class SnapshotValidationError(RuntimeError):
    pass


def _as_bool(value: Any) -> bool:
    return bool(value)


def _counter_dict(values: Iterable[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def runtime_semantics_key(row: dict[str, Any]) -> tuple[Any, ...]:
    """Return direct Runtime semantics, deliberately excluding provenance."""

    return (
        row.get("runtime_compiled"),
        row.get("runtime_reward_resolved"),
        row.get("runtime_probability_resolved"),
        row.get("runtime_rng_eligible"),
        row.get("runtime_rng_eligible_before_overflow"),
        row.get("runtime_rejection_reason"),
        row.get("slot_uid"),
        row.get("canonical_item_id"),
        row.get("gold_amount"),
        row.get("reward_kind"),
        row.get("baseline_origin"),
        row.get("base_numerator"),
        row.get("base_denominator"),
        row.get("global_scale_numerator"),
        row.get("global_scale_denominator"),
        row.get("final_numerator"),
        row.get("final_denominator"),
    )


def validate_source_row_contract(row: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    prefix = (
        f"{row.get('source_profile_id', '<profile?>')}:"
        f"{row.get('source_line_number', '<line?>')}"
    )

    required = (
        "canonical_monster_id",
        "source_entry_ordinal_zero_based",
        "source_entry_ordinal_one_based",
        "source_line_number",
        "source_slot_index",
        "source_chance",
        "source_chance_valid",
        "source_rate_policy",
        "source_slot_status",
        "runtime_compiled",
        "runtime_reward_resolved",
        "runtime_probability_resolved",
        "runtime_rng_eligible",
        "runtime_rng_eligible_before_overflow",
    )
    for field in required:
        if field not in row:
            errors.append(f"{prefix} {field} is required")

    chance_valid = _as_bool(row.get("source_chance_valid", False))
    chance_denominator = row.get("source_chance_denominator")
    if chance_valid:
        if not isinstance(chance_denominator, int) or chance_denominator <= 0:
            errors.append(
                f"{prefix} valid source chance requires positive denominator"
            )
    elif chance_denominator is not None:
        errors.append(
            f"{prefix} invalid source chance requires null denominator"
        )

    if row.get("source_rate_policy") != "AUDIT_ONLY":
        errors.append(f"{prefix} source_rate_policy must be AUDIT_ONLY")
    if row.get("source_slot_status") != "CONFIRMED_SOURCE_SLOT":
        errors.append(
            f"{prefix} source_slot_status must be CONFIRMED_SOURCE_SLOT"
        )
    source_entry = row.get("source_entry")
    if not isinstance(source_entry, dict):
        errors.append(f"{prefix} source_entry must be an object")
    else:
        if source_entry.get("rate_policy") != row.get("source_rate_policy"):
            errors.append(f"{prefix} source rate policy was not preserved")
        if source_entry.get("slot_status") != row.get("source_slot_status"):
            errors.append(f"{prefix} source slot status was not preserved")

    runtime_compiled = _as_bool(row.get("runtime_compiled", False))
    runtime_reward_resolved = _as_bool(
        row.get("runtime_reward_resolved", False)
    )
    runtime_probability_resolved = _as_bool(
        row.get("runtime_probability_resolved", False)
    )
    runtime_rng_eligible = _as_bool(row.get("runtime_rng_eligible", False))
    runtime_rng_before_overflow = _as_bool(
        row.get("runtime_rng_eligible_before_overflow", False)
    )

    if not runtime_compiled:
        if any(
            (
                runtime_reward_resolved,
                runtime_probability_resolved,
                runtime_rng_eligible,
                runtime_rng_before_overflow,
            )
        ):
            errors.append(f"{prefix} NON_LOOT source row reached Runtime RNG")
        if row.get("runtime_slot") is not None:
            errors.append(f"{prefix} NON_LOOT row has a compiled slot")
        if row.get("slot_uid") != "":
            errors.append(f"{prefix} NON_LOOT row has a slot_uid")
        if row.get("canonical_item_id") is not None:
            errors.append(f"{prefix} NON_LOOT row has canonical item identity")
        if row.get("gold_amount") is not None:
            errors.append(f"{prefix} NON_LOOT row has gold identity")
        if row.get("runtime_rejection_reason") != "non_loot_profile":
            errors.append(f"{prefix} NON_LOOT row has an invalid rejection reason")
        return errors

    runtime_profile_id = row.get("runtime_profile_id")
    if (
        not isinstance(runtime_profile_id, str)
        or not runtime_profile_id.startswith("dpv2.direct.")
    ):
        errors.append(f"{prefix} compiled row lacks a V2 direct profile ID")
    runtime_slot = row.get("runtime_slot")
    if not isinstance(runtime_slot, dict):
        errors.append(f"{prefix} compiled row runtime_slot must be an object")
        runtime_slot = {}
    if not runtime_rng_eligible:
        errors.append(f"{prefix} compiled row must be RNG eligible")
    if not runtime_reward_resolved or not runtime_probability_resolved:
        errors.append(f"{prefix} compiled row reward/probability is unresolved")
    if not runtime_rng_before_overflow:
        errors.append(f"{prefix} compiled row must reach RNG before overflow")

    slot_uid = row.get("slot_uid")
    provenance_id = row.get("source_provenance_id")
    if not isinstance(slot_uid, str) or not slot_uid:
        errors.append(f"{prefix} compiled slot_uid is required")
    if not isinstance(provenance_id, str) or not provenance_id:
        errors.append(f"{prefix} source_provenance_id is required")
    if runtime_slot.get("slot_uid") != slot_uid:
        errors.append(f"{prefix} flattened slot_uid disagrees with runtime_slot")
    if runtime_slot.get("source_provenance_id") != provenance_id:
        errors.append(
            f"{prefix} flattened provenance disagrees with runtime_slot"
        )

    reward_kind = row.get("reward_kind")
    has_item = row.get("canonical_item_id") is not None
    has_gold = row.get("gold_amount") is not None
    if reward_kind == "item":
        if not has_item or int(row.get("canonical_item_id", 0)) <= 0:
            errors.append(f"{prefix} item reward lacks positive canonical ID")
        if has_gold:
            errors.append(f"{prefix} item reward carries gold identity")
    elif reward_kind == "gold":
        if not has_gold or int(row.get("gold_amount", 0)) <= 0:
            errors.append(f"{prefix} gold reward lacks positive amount")
        if has_item:
            errors.append(f"{prefix} gold reward carries item identity")
    else:
        errors.append(f"{prefix} reward_kind is invalid: {reward_kind!r}")

    for field in (
        "base_numerator",
        "base_denominator",
        "global_scale_numerator",
        "global_scale_denominator",
        "final_numerator",
        "final_denominator",
    ):
        value = row.get(field)
        if not isinstance(value, int) or value <= 0:
            errors.append(f"{prefix} {field} must be positive integer")
    for field in ("base_probability", "global_scale", "final_probability"):
        value = row.get(field)
        if not isinstance(value, (int, float)) or value < 0:
            errors.append(f"{prefix} {field} must be non-negative number")

    if row.get("runtime_rejection_reason") != "":
        errors.append(f"{prefix} resolved row carries a rejection reason")
    return errors


def _recompute_summary(
    source_rows: list[dict[str, Any]],
    compiled_slots: list[dict[str, Any]] | None = None,
    source_profiles: list[dict[str, Any]] | None = None,
    compiled_profiles: list[dict[str, Any]] | None = None,
    logical_source_summary: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if compiled_slots is None:
        compiled_slots = [
            row for row in source_rows
            if _as_bool(row.get("runtime_compiled", False))
        ]
    if source_profiles is None:
        source_profiles = []
    if compiled_profiles is None:
        compiled_profiles = []
    if logical_source_summary is None:
        logical_source_summary = {
            "path": "",
            "schema": "",
            "row_count": len(source_rows),
            "disposition_counts": {
                "LEGACY_21CQ_COMPILED": sum(
                    1 for row in source_rows
                    if _as_bool(row.get("runtime_compiled", False))
                    and row.get("baseline_origin") == "LEGACY_21CQ_MONITEMS"
                ),
                "PROJECT_EXTENSION_COMPILED": sum(
                    1 for row in source_rows
                    if _as_bool(row.get("runtime_compiled", False))
                    and row.get("baseline_origin") == "PROJECT_EXTENSION"
                ),
                "EXPLICIT_NON_LOOT_EXCLUDED": sum(
                    1 for row in source_rows
                    if not _as_bool(row.get("runtime_compiled", False))
                ),
                "RETIRED_OUT_OF_RUNTIME": 0,
            },
            "disposition_sum": len(source_rows),
        }

    rate_policy = [
        str(row.get("source_rate_policy", "<missing>"))
        for row in source_rows
    ]
    slot_status = [
        str(row.get("source_slot_status", "<missing>"))
        for row in source_rows
    ]
    malformed_count = sum(
        1 for row in source_rows
        if not _as_bool(row.get("source_chance_valid", False))
    )
    enabled_count = sum(
        1 for row in source_rows
        if _as_bool(row.get("runtime_compiled", False))
    )
    disabled_count = len(source_rows) - enabled_count
    origin_counts = _counter_dict(
        str(row.get("baseline_origin", ""))
        for row in compiled_slots
    )
    item_counts = Counter(
        str(row.get("canonical_item_id"))
        for row in compiled_slots
        if row.get("canonical_item_id") is not None
    )
    duplicate_item_occurrences = sum(
        count - 1 for count in item_counts.values() if count > 1
    )
    slot_uids = [
        str(row.get("slot_uid", ""))
        for row in compiled_slots
    ]
    source_summary = {
        "profile_count": len(source_profiles),
        "row_count": len(source_rows),
        "logical_source_row_count": int(
            logical_source_summary.get("row_count", len(source_rows))
        ),
        "enabled_source_row_count": enabled_count,
        "non_loot_disabled_source_row_count": disabled_count,
        "explicit_non_loot_source_row_count": disabled_count,
        "retired_source_row_count": int(
            logical_source_summary.get("disposition_counts", {}).get(
                "RETIRED_OUT_OF_RUNTIME", 0
            )
        ),
        "semantic_source_accounting": logical_source_summary.get(
            "disposition_counts", {}
        ),
        "malformed_source_provenance_count": malformed_count,
        "rate_policy_counts": _counter_dict(rate_policy),
        "slot_status_counts": _counter_dict(slot_status),
    }
    runtime_summary = {
        "profile_count": len(compiled_profiles),
        "runtime_allowed_profile_count": sum(
            1 for profile in compiled_profiles
            if _as_bool(profile.get(
                "runtime_allowed",
                profile.get("drop_enabled", False),
            ))
        ),
        "enabled_profile_count": sum(
            1 for profile in compiled_profiles
            if _as_bool(profile.get("drop_enabled", False))
        ),
        "non_loot_profile_count": sum(
            1 for profile in compiled_profiles
            if not _as_bool(profile.get("drop_enabled", False))
            and profile.get(
                "drop_semantic_state",
                profile.get("semantic_status"),
            ) != "RUNTIME_DISABLED"
        ),
        "explicit_non_loot_profile_count": sum(
            1 for profile in compiled_profiles
            if profile.get(
                "drop_semantic_state",
                profile.get("semantic_status"),
            ) == "EXPLICIT_NON_LOOT"
        ),
        "runtime_disabled_profile_count": sum(
            1 for profile in compiled_profiles
            if profile.get(
                "drop_semantic_state",
                profile.get("semantic_status"),
            ) == "RUNTIME_DISABLED"
        ),
        "slot_count": len(compiled_slots),
        "baseline_origin_counts": origin_counts,
        "reward_resolved_slot_count": sum(
            1 for row in compiled_slots
            if _as_bool(row.get("runtime_reward_resolved", False))
        ),
        "probability_resolved_slot_count": sum(
            1 for row in compiled_slots
            if _as_bool(row.get("runtime_probability_resolved", False))
        ),
        "rng_eligible_slot_count": sum(
            1 for row in compiled_slots
            if _as_bool(row.get("runtime_rng_eligible", False))
        ),
        "rng_roll_stage_slot_count": len(compiled_slots),
        "all_compiled_slots_rng_before_overflow": all(
            _as_bool(row.get("runtime_rng_eligible_before_overflow", False))
            for row in compiled_slots
        ),
        "duplicate_canonical_item_occurrences": duplicate_item_occurrences,
        "unique_slot_uid_count": len(set(slot_uids)),
        "post_rng_ground_slot_limit": 9,
    }
    return {
        "source_corpus": source_summary,
        "compiled_runtime": runtime_summary,
    }


def _check_expected_counts(
    snapshot: dict[str, Any],
    observed: dict[str, Any],
    errors: list[str],
    *,
    enforce_current_corpus: bool,
) -> None:
    if not enforce_current_corpus:
        return
    source = observed["source_corpus"]
    runtime = observed["compiled_runtime"]
    expected_source = {
        "profile_count": EXPECTED_SOURCE_PROFILE_COUNT,
        "row_count": EXPECTED_SOURCE_ROW_COUNT,
        "logical_source_row_count": EXPECTED_LOGICAL_SOURCE_ROW_COUNT,
        "enabled_source_row_count": EXPECTED_ENABLED_SOURCE_ROW_COUNT,
        "non_loot_disabled_source_row_count": EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT,
        "explicit_non_loot_source_row_count": EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT,
        "retired_source_row_count": EXPECTED_RETIRED_SOURCE_ROW_COUNT,
        "malformed_source_provenance_count": (
            EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT
        ),
    }
    expected_runtime = {
        "profile_count": EXPECTED_RUNTIME_PROFILE_COUNT,
        "runtime_allowed_profile_count": EXPECTED_RUNTIME_ALLOWED_PROFILE_COUNT,
        "enabled_profile_count": EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT,
        "non_loot_profile_count": EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT,
        "explicit_non_loot_profile_count": EXPECTED_RUNTIME_EXPLICIT_NON_LOOT_PROFILE_COUNT,
        "runtime_disabled_profile_count": EXPECTED_RUNTIME_DISABLED_PROFILE_COUNT,
        "slot_count": EXPECTED_RUNTIME_SLOT_COUNT,
        "reward_resolved_slot_count": EXPECTED_RUNTIME_SLOT_COUNT,
        "probability_resolved_slot_count": EXPECTED_RUNTIME_SLOT_COUNT,
        "rng_eligible_slot_count": EXPECTED_RUNTIME_SLOT_COUNT,
        "rng_roll_stage_slot_count": EXPECTED_RUNTIME_SLOT_COUNT,
    }
    for key, expected in expected_source.items():
        if source.get(key) != expected:
            errors.append(
                f"source_corpus.{key}={source.get(key)!r} expected={expected}"
            )
    for key, expected in expected_runtime.items():
        if runtime.get(key) != expected:
            errors.append(
                f"compiled_runtime.{key}={runtime.get(key)!r} "
                f"expected={expected}"
            )
    if source.get("semantic_source_accounting") != {
        "EXPLICIT_NON_LOOT_EXCLUDED": EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT,
        "LEGACY_21CQ_COMPILED": EXPECTED_LEGACY_RUNTIME_SLOT_COUNT,
        "PROJECT_EXTENSION_COMPILED": EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT,
        "RETIRED_OUT_OF_RUNTIME": EXPECTED_RETIRED_SOURCE_ROW_COUNT,
    }:
        errors.append("source_corpus semantic source accounting drifted")
    if runtime.get("baseline_origin_counts") != {
        "LEGACY_21CQ_MONITEMS": EXPECTED_LEGACY_RUNTIME_SLOT_COUNT,
        "PROJECT_EXTENSION": EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT,
    }:
        errors.append(
            "compiled_runtime.baseline_origin_counts does not match frozen "
            "6740/69 split"
        )
    source_summary = snapshot.get("source_summary", {})
    if isinstance(source_summary, dict):
        for key, expected in expected_source.items():
            if source_summary.get(key) != expected:
                errors.append(
                    f"source_summary.{key}={source_summary.get(key)!r} "
                    f"expected={expected}"
                )
    runtime_summary = snapshot.get("compiled_runtime_summary", {})
    if isinstance(runtime_summary, dict):
        for key, expected in expected_runtime.items():
            if runtime_summary.get(key) != expected:
                errors.append(
                    f"compiled_runtime_summary.{key}={runtime_summary.get(key)!r} "
                    f"expected={expected}"
                )
    logical_summary = snapshot.get("logical_source_summary")
    if isinstance(logical_summary, dict):
        if logical_summary.get("row_count") != EXPECTED_LOGICAL_SOURCE_ROW_COUNT:
            errors.append(
                "logical_source_summary.row_count="
                f"{logical_summary.get('row_count')!r} expected={EXPECTED_LOGICAL_SOURCE_ROW_COUNT}"
            )
        if logical_summary.get("disposition_counts") != {
            "EXPLICIT_NON_LOOT_EXCLUDED": EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT,
            "LEGACY_21CQ_COMPILED": EXPECTED_LEGACY_RUNTIME_SLOT_COUNT,
            "PROJECT_EXTENSION_COMPILED": EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT,
            "RETIRED_OUT_OF_RUNTIME": EXPECTED_RETIRED_SOURCE_ROW_COUNT,
        }:
            errors.append("logical_source_summary disposition accounting drifted")


def validate_snapshot(
    snapshot: dict[str, Any],
    *,
    enforce_current_corpus: bool = True,
) -> list[str]:
    errors: list[str] = []
    if snapshot.get("schema") != SNAPSHOT_SCHEMA:
        errors.append(
            f"schema={snapshot.get('schema')!r} expected={SNAPSHOT_SCHEMA!r}"
        )

    authority = snapshot.get("authority")
    if not isinstance(authority, dict):
        errors.append("authority must be an object")
        authority = {}
    if authority.get("catalog_sha256_before") != authority.get(
        "catalog_sha256_after"
    ):
        errors.append("canonical catalog changed during export")
    runtime_authority = authority.get("runtime_authority")
    if not isinstance(runtime_authority, dict):
        errors.append("authority.runtime_authority must be an object")
        runtime_authority = {}
    expected_authority = {
        "authority_id": "dpv2.direct_baseline.v2",
        "schema": "hardcore.dpv2.direct_monster_drop_baseline.v2",
        "production_runtime": "V2_DIRECT_BASELINE",
        "identity_key": "canonical_monster_id",
        "direct_profile_join": "canonical_monster_id_exact",
        "source_profile_id_is_audit_only": True,
        "fallback_forbidden": True,
    }
    if enforce_current_corpus:
        expected_authority.update({
            "semantic_authority_id": "dpv2.monster_drop_semantic.v1",
            "semantic_authority_schema": "hardcore.dpv2.monster_drop_semantic_authority.v1",
        })
    for key, expected in expected_authority.items():
        if runtime_authority.get(key) != expected:
            errors.append(
                f"authority.runtime_authority.{key}="
                f"{runtime_authority.get(key)!r} expected={expected!r}"
            )
    if (
        authority.get("source_corpus_is_audit_only") is not True
        or authority.get("compiled_runtime_is_rng_authority") is not True
        or authority.get("overflow_stage") != "after_all_probability_rolls"
    ):
        errors.append("authority source/runtime view split is invalid")
    gate = authority.get("source_slot_gate")
    if not isinstance(gate, dict):
        errors.append("authority.source_slot_gate must be an object")
    else:
        expected_gate = {
            "available": True,
            "authority": "dpv2.direct_baseline.v2",
            "maximum_ground_slots": 9,
        }
        if enforce_current_corpus:
            expected_gate.update({
                "compiled_slots": EXPECTED_RUNTIME_SLOT_COUNT,
                "logical_source_rows": EXPECTED_LOGICAL_SOURCE_ROW_COUNT,
                "drop_enabled_source_slots": EXPECTED_RUNTIME_SLOT_COUNT,
                "drop_disabled_source_slots": (
                    EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT
                    + EXPECTED_RETIRED_SOURCE_ROW_COUNT
                ),
                "explicit_non_loot_source_rows": EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT,
                "retired_source_rows": EXPECTED_RETIRED_SOURCE_ROW_COUNT,
                "excluded_source_rows": (
                    EXPECTED_EXPLICIT_NON_LOOT_SOURCE_ROW_COUNT
                    + EXPECTED_RETIRED_SOURCE_ROW_COUNT
                ),
                "runtime_allowed_monsters": EXPECTED_RUNTIME_ALLOWED_PROFILE_COUNT,
                "drop_enabled_monsters": EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT,
                "explicit_non_loot_monsters": EXPECTED_RUNTIME_EXPLICIT_NON_LOOT_PROFILE_COUNT,
                "runtime_disabled_monsters": EXPECTED_RUNTIME_DISABLED_PROFILE_COUNT,
            })
        for key, expected in expected_gate.items():
            if gate.get(key) != expected:
                errors.append(
                    f"authority.source_slot_gate.{key}={gate.get(key)!r} "
                    f"expected={expected!r}"
                )

    source_profiles = snapshot.get("source_profiles")
    compiled_profiles = snapshot.get("compiled_profiles")
    source_rows_raw = snapshot.get("source_rows")
    compiled_slots_raw = snapshot.get("compiled_slots")
    if not isinstance(source_profiles, list):
        errors.append("source_profiles must be an array")
        source_profiles = []
    if not isinstance(compiled_profiles, list):
        errors.append("compiled_profiles must be an array")
        compiled_profiles = []
    if not isinstance(source_rows_raw, list):
        errors.append("source_rows must be an array")
        source_rows_raw = []
    if not isinstance(compiled_slots_raw, list):
        errors.append("compiled_slots must be an array")
        compiled_slots_raw = []
    source_rows = [
        row for row in source_rows_raw if isinstance(row, dict)
    ]
    compiled_slots = [
        row for row in compiled_slots_raw if isinstance(row, dict)
    ]
    if len(source_rows) != len(source_rows_raw):
        errors.append("source_rows contains a non-object")
    if len(compiled_slots) != len(compiled_slots_raw):
        errors.append("compiled_slots contains a non-object")
    for index, row in enumerate(source_rows):
        errors.extend(
            f"source_rows[{index}] {error}"
            for error in validate_source_row_contract(row)
        )

    source_compiled = [
        row for row in source_rows
        if _as_bool(row.get("runtime_compiled", False))
    ]
    source_by_uid = {
        str(row.get("slot_uid", "")): row for row in source_compiled
    }
    compiled_uids: list[str] = []
    for index, row in enumerate(compiled_slots):
        if not _as_bool(row.get("runtime_compiled", False)):
            errors.append(f"compiled_slots[{index}] is not marked compiled")
        compiled_uids.append(str(row.get("slot_uid", "")))
        if source_by_uid.get(str(row.get("slot_uid", ""))) != row:
            errors.append(
                f"compiled_slots[{index}] does not exactly match source row"
            )
    if len(compiled_uids) != len(set(compiled_uids)):
        errors.append("compiled slot UID collision")
    if len(source_compiled) != len(compiled_slots):
        errors.append(
            "source compiled rows and compiled_slots have different counts"
        )

    logical_source_summary_value = snapshot.get("logical_source_summary")
    logical_source_summary = (
        logical_source_summary_value
        if isinstance(logical_source_summary_value, dict)
        else None
    )
    if enforce_current_corpus and logical_source_summary is None:
        errors.append("logical_source_summary must be an object")
    observed = _recompute_summary(
        source_rows,
        compiled_slots,
        source_profiles,
        compiled_profiles,
        logical_source_summary,
    )
    reported = snapshot.get("summary")
    if reported != observed:
        errors.append(
            "summary does not equal recomputed source/compiled dual view"
        )
    if snapshot.get("source_summary") != observed["source_corpus"]:
        errors.append("source_summary does not equal recomputed source view")
    if snapshot.get("compiled_runtime_summary") != observed["compiled_runtime"]:
        errors.append(
            "compiled_runtime_summary does not equal recomputed Runtime view"
        )
    _check_expected_counts(
        snapshot,
        observed,
        errors,
        enforce_current_corpus=enforce_current_corpus,
    )

    correction = snapshot.get("correction_provenance")
    if not isinstance(correction, dict):
        errors.append("correction_provenance must be an object")
    else:
        malformed = [
            row for row in source_rows
            if not _as_bool(row.get("source_chance_valid", False))
        ]
        if len(malformed) == 1:
            anomaly = malformed[0]
            for key, expected in EXPECTED_ANOMALY.items():
                if key in correction:
                    actual = correction.get(key)
                else:
                    actual = anomaly.get(key)
                if actual != expected:
                    errors.append(
                        f"correction.{key}={actual!r} expected={expected!r}"
                    )
            runtime_slot = anomaly.get("runtime_slot")
            if not isinstance(runtime_slot, dict) or runtime_slot.get(
                "base_denominator"
            ) != EXPECTED_ANOMALY["corrected_base_denominator"]:
                errors.append(
                    "1/00 source provenance does not point to base 1/2800"
                )
            if not _as_bool(anomaly.get("runtime_rng_eligible", False)):
                errors.append("1/00 provenance incorrectly blocked Runtime RNG")
    direct_summary = snapshot.get("direct_baseline_summary")
    if not isinstance(direct_summary, dict):
        errors.append("direct_baseline_summary must be an object")
    elif enforce_current_corpus:
        for key, expected in {
            "active_monsters": EXPECTED_RUNTIME_PROFILE_COUNT,
            "runtime_allowed_monsters": EXPECTED_RUNTIME_ALLOWED_PROFILE_COUNT,
            "drop_enabled_monsters": EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT,
            "explicit_non_loot_monsters": EXPECTED_RUNTIME_EXPLICIT_NON_LOOT_PROFILE_COUNT,
            "runtime_disabled_monsters": EXPECTED_RUNTIME_DISABLED_PROFILE_COUNT,
            "non_loot_monsters": EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT,
            "compiled_slots": EXPECTED_RUNTIME_SLOT_COUNT,
        }.items():
            if direct_summary.get(key) != expected:
                errors.append(
                    f"direct_baseline_summary.{key}="
                    f"{direct_summary.get(key)!r} expected={expected}"
                )
    return errors


def analyze_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    source_rows = [
        row for row in snapshot.get("source_rows", [])
        if isinstance(row, dict)
    ]
    compiled_slots = [
        row for row in snapshot.get("compiled_slots", [])
        if isinstance(row, dict)
    ]
    source_profiles = [
        row for row in snapshot.get("source_profiles", [])
        if isinstance(row, dict)
    ]
    compiled_profiles = [
        row for row in snapshot.get("compiled_profiles", [])
        if isinstance(row, dict)
    ]
    summary = _recompute_summary(
        source_rows,
        compiled_slots,
        source_profiles,
        compiled_profiles,
        snapshot.get("logical_source_summary")
        if isinstance(snapshot.get("logical_source_summary"), dict)
        else None,
    )
    malformed = [
        row for row in source_rows
        if not _as_bool(row.get("source_chance_valid", False))
    ]
    return {
        "schema": "monster_drop_p1a_analysis_v3",
        "snapshot_schema": snapshot.get("schema"),
        "authority": snapshot.get("authority", {}),
        "direct_baseline_summary": snapshot.get(
            "direct_baseline_summary", {}
        ),
        "summary": summary,
        "source_profiles": source_profiles,
        "compiled_profiles": compiled_profiles,
        "malformed_source_provenance_rows": malformed,
        "source_rows": source_rows,
        "compiled_slots": compiled_slots,
        "correction_provenance": snapshot.get(
            "correction_provenance", {}
        ),
    }


def _slot_csv_row(row: dict[str, Any]) -> dict[str, Any]:
    runtime_slot = row.get("runtime_slot", {})
    if not isinstance(runtime_slot, dict):
        runtime_slot = {}
    return {
        "source_profile_id": row.get("source_profile_id"),
        "runtime_profile_id": row.get("runtime_profile_id"),
        "canonical_monster_id": row.get("canonical_monster_id"),
        "source_entry_ordinal_zero_based": row.get(
            "source_entry_ordinal_zero_based"
        ),
        "source_entry_ordinal_one_based": row.get(
            "source_entry_ordinal_one_based"
        ),
        "source_line_number": row.get("source_line_number"),
        "source_slot_index": row.get("source_slot_index"),
        "source_item_label": row.get("source_item_label"),
        "source_raw_text": row.get("source_raw_text"),
        "source_chance": row.get("source_chance"),
        "source_chance_denominator": row.get(
            "source_chance_denominator"
        ),
        "source_chance_valid": row.get("source_chance_valid"),
        "source_rate_policy": row.get("source_rate_policy"),
        "source_slot_status": row.get("source_slot_status"),
        "runtime_compiled": row.get("runtime_compiled"),
        "slot_uid": row.get("slot_uid"),
        "source_provenance_id": row.get("source_provenance_id"),
        "canonical_item_id": row.get("canonical_item_id"),
        "gold_amount": row.get("gold_amount"),
        "reward_kind": row.get("reward_kind"),
        "item_name": row.get("item_name"),
        "baseline_origin": row.get("baseline_origin"),
        "base_numerator": row.get("base_numerator"),
        "base_denominator": row.get("base_denominator"),
        "base_probability": row.get("base_probability"),
        "global_preset": row.get("global_preset"),
        "global_scale_numerator": row.get("global_scale_numerator"),
        "global_scale_denominator": row.get(
            "global_scale_denominator"
        ),
        "global_scale": row.get("global_scale"),
        "final_numerator": row.get("final_numerator"),
        "final_denominator": row.get("final_denominator"),
        "final_probability": row.get("final_probability"),
        "overflow_priority": row.get("overflow_priority"),
        "protected_drop": row.get("protected_drop"),
        "runtime_reward_resolved": row.get("runtime_reward_resolved"),
        "runtime_probability_resolved": row.get(
            "runtime_probability_resolved"
        ),
        "runtime_rng_eligible": row.get("runtime_rng_eligible"),
        "runtime_rng_eligible_before_overflow": row.get(
            "runtime_rng_eligible_before_overflow"
        ),
        "runtime_rejection_reason": row.get(
            "runtime_rejection_reason"
        ),
        "runtime_slot_json": json.dumps(
            runtime_slot,
            ensure_ascii=False,
            sort_keys=True,
        ) if runtime_slot else "",
    }


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _markdown_report(analysis: dict[str, Any]) -> str:
    summary = analysis["summary"]
    source = summary["source_corpus"]
    runtime = summary["compiled_runtime"]
    correction = analysis["correction_provenance"]
    lines = [
        "# MONSTER-DROP-P1A Fresh DPV2 Direct-Baseline Audit",
        "",
        "Status: P1A_DIRECT_BASELINE_CLOSED / BLOCKER_COUNT=0",
        "",
        "## Dual view",
        "",
        "The source corpus is retained for audit and provenance only. It is not "
        "a Runtime RNG table. The compiled V2 view is joined by exact "
        "canonical_monster_id; source drop labels are audit metadata. The "
        "logical source authority retains retired rows independently.",
        "",
        "| View | Profiles | Rows/slots | Enabled | NON_LOOT/disabled | RNG |",
        "|---|---:|---:|---:|---:|---:|",
        (
            f"| source corpus | {source['profile_count']} | "
            f"{source['row_count']} | {source['enabled_source_row_count']} | "
            f"{source['non_loot_disabled_source_row_count']} | 0 |"
        ),
        (
            f"| logical source authority | n/a | {source['logical_source_row_count']} | "
            "6740+69 compiled | 223+2558 excluded | 0 |"
        ),
        (
            f"| compiled Runtime V2 | {runtime['profile_count']} | "
            f"{runtime['slot_count']} | {runtime['enabled_profile_count']} "
            f"profiles | {runtime['non_loot_profile_count']} profiles | "
            f"{runtime['rng_eligible_slot_count']} |"
        ),
        "",
        "Current semantic source metrics: 156 profiles, 7032 retained source "
        "rows, 6809 compiled-source rows and 223 explicit NON_LOOT source "
        "rows. The logical source authority contains 9590 rows: "
        "6740 LEGACY_21CQ_COMPILED + 69 PROJECT_EXTENSION_COMPILED + "
        "223 EXPLICIT_NON_LOOT_EXCLUDED + 2558 RETIRED_OUT_OF_RUNTIME; "
        "1 malformed source-provenance row remains auditable.",
        "",
        "Compiled Runtime current production metrics: 156 profiles, 153 "
        "runtime_allowed profiles, 144 enabled profiles, 9 explicit NON_LOOT "
        "profiles and 3 runtime-disabled profiles; 6809 V2 slots; 6740 "
        "LEGACY_21CQ_MONITEMS slots plus 69 PROJECT_EXTENSION slots. "
        "Reward, probability, eligibility, and RNG stages each close at 6809.",
        "",
        "## Direct probability and identity contract",
        "",
        "P(slot) = min(1, base_numerator * scale_num / "
        "(base_denominator * scale_den)) with one global positive rational "
        "scale. Duplicate canonical item IDs remain independent slots. "
        "The nine-slot retention limit is post-RNG only.",
        "",
        "## Explicit source correction",
        "",
        (
            f"- {correction.get('source_profile_id')} canonical monster "
            f"{correction.get('canonical_monster_id')}, line "
            f"{correction.get('source_line_number')}, "
            f"{correction.get('source_slot_index')}: source "
            f"{correction.get('source_chance')} remains unchanged as "
            "provenance."
        ),
        (
            f"- Frozen direct value: "
            f"{correction.get('corrected_base_numerator')}/"
            f"{correction.get('corrected_base_denominator')} from "
            f"{correction.get('path')}."
        ),
        "",
        "## Gate result",
        "",
        "- Source provenance is never used to reject a compiled V2 slot.",
        "- NON_LOOT source rows never enter compiled_slots or RNG.",
        "- All compiled slots resolve reward identity and exact probability "
        "before the post-RNG overflow stage.",
        "- Blocker count: 0.",
        "",
    ]
    return "\n".join(lines)


def write_outputs(
    snapshot: dict[str, Any],
    output_dir: Path,
) -> dict[str, Path]:
    analysis = analyze_snapshot(snapshot)
    output_dir.mkdir(parents=True, exist_ok=True)
    analysis_path = output_dir / "analysis.json"
    slots_path = output_dir / "monster_drop_p1a_slots.csv"
    monsters_path = output_dir / "monster_drop_p1a_monsters.csv"
    report_path = output_dir / "report.md"
    analysis_path.write_text(
        json.dumps(analysis, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    _write_csv(
        slots_path,
        [
            _slot_csv_row(row)
            for row in snapshot.get("source_rows", [])
            if isinstance(row, dict)
        ],
    )
    _write_csv(
        monsters_path,
        [
            row for row in analysis["compiled_profiles"]
            if isinstance(row, dict)
        ],
    )
    report_path.write_text(
        _markdown_report(analysis),
        encoding="utf-8",
    )
    return {
        "analysis": analysis_path,
        "slots_csv": slots_path,
        "monsters_csv": monsters_path,
        "report": report_path,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--snapshot",
        type=Path,
        default=Path("outputs/monster_drop_p1a/runtime_snapshot.json"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("outputs/monster_drop_p1a"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.snapshot.is_file():
        print(f"P1A_ANALYZER_FAIL: missing snapshot {args.snapshot}")
        return 2
    with args.snapshot.open("r", encoding="utf-8") as handle:
        snapshot = json.load(handle)
    if not isinstance(snapshot, dict):
        print("P1A_ANALYZER_FAIL: snapshot root is not an object")
        return 2
    errors = validate_snapshot(snapshot, enforce_current_corpus=True)
    if errors:
        for error in errors:
            print(f"P1A_ANALYZER_FAIL: {error}")
        print(f"P1A_ANALYZER_FAIL_COUNT={len(errors)}")
        return 2
    paths = write_outputs(snapshot, args.output_dir)
    summary = analyze_snapshot(snapshot)["summary"]
    source = summary["source_corpus"]
    runtime = summary["compiled_runtime"]
    print(
        "P1A_ANALYZER_PASS: "
        f"source_profiles={source['profile_count']} "
        f"source_rows={source['row_count']} "
        f"logical_source_rows={source['logical_source_row_count']} "
        f"enabled_source={source['enabled_source_row_count']} "
        f"explicit_non_loot_source={source['explicit_non_loot_source_row_count']} "
        f"retired_source={source['retired_source_row_count']} "
        f"malformed_provenance={source['malformed_source_provenance_count']} "
        f"compiled_profiles={runtime['profile_count']} "
        f"runtime_allowed={runtime['runtime_allowed_profile_count']} "
        f"enabled_profiles={runtime['enabled_profile_count']} "
        f"explicit_non_loot_profiles={runtime['explicit_non_loot_profile_count']} "
        f"runtime_disabled={runtime['runtime_disabled_profile_count']} "
        f"compiled_slots={runtime['slot_count']} "
        f"rng_eligible={runtime['rng_eligible_slot_count']}"
    )
    for key, path in paths.items():
        print(f"P1A_OUTPUT {key}={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
