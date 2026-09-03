#!/usr/bin/env python3
"""Build and validate the DPV2 single-player x25 probability overlay.

The direct baseline remains the immutable probability source.  This builder
classifies slots once, by exact canonical IDs, and emits a complete 1:1 ledger
whose rational probabilities can be consumed without runtime name/tier guesses.
"""

from __future__ import annotations

import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from math import gcd
from pathlib import Path
import subprocess
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
BASELINE_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_v2.json"
PROVENANCE_PATH = ROOT / "assets/data/drop/dpv2_21cq_source_provenance_v1.json"
CLASSIFICATION_PATH = (
    ROOT
    / "assets/data/drop/dpv2_single_player_item_boost_classification_v1.json"
)
GLOBAL_PATH = ROOT / "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_single_player_drop_boost_v1.json"
EFFECTIVE_PATH = (
    ROOT / "assets/data/drop/dpv2_single_player_effective_probability_v1.json"
)

BASE_SHA = "98ea003b66915622b5c265602e54386f9213016c"
EXPECTED_SOURCE_SHA256 = (
    "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"
)
EXPECTED_BASELINE_SHA256 = (
    "9E9225DF113BDC94ECDA071388DC5FCFA92ED34BF8028519B06F205E06FF4DD0"
)
EXPECTED_PROVENANCE_SHA256 = (
    "F48A033D5A33D80B795A838BE837AE84FA93469B6055FE012309ACC07082E347"
)
EXPECTED_GLOBAL_SHA256 = (
    "653BB10069CE3B9C06F7412F23EB2D7931FD4C1CA0BCB00C0428C82F2E4DFCC0"
)
EXPECTED_SLOT_COUNT = 6809
EXPECTED_LEDGER_SHA256 = (
    "057F3664C2CE5376B2A937CB317E978769860AA1B3390D0EF038B512CD496B80"
)
EXPECTED_OVERLAPPING_COUNTS = {
    "gold_slots": 134,
    "common_recovery_slots": 1597,
    "new_armor_boss_slots": 324,
    "blessing_oil_slots": 22,
    "equipment_candidate_slots": 4311,
    "rare_consumable_candidate_slots": 277,
    "unclassified_candidate_slots": 490,
}
EXPECTED_CLASSIFICATION_COUNTS = {
    "EQUIPMENT": 167,
    "RARE_FUNCTIONAL_CONSUMABLE": 14,
    "COMMON_RECOVERY": 10,
    "BYPASS_UNCLASSIFIED": 42,
}
EXPECTED_EFFECTIVE_POLICY_COUNTS = {
    "AUTO_BOOST": 4546,
    "BYPASS_COMMON_RECOVERY": 1357,
    "BYPASS_GOLD": 128,
    "BYPASS_NEW_ARMOR_BOSS": 324,
    "BYPASS_UNCLASSIFIED": 454,
}

MULTIPLIER = (25, 1)
CEILING = (1, 20)
GOLD_AMOUNT_MULTIPLIER = (5, 1)
COMMON_RECOVERY_IDS = (
    920045,
    920044,
    920053,
    920052,
    920017,
    920042,
    920001,
    910007,
    920014,
    920016,
)
NEW_ARMOR_BOSS_IDS = (235, 236, 237, 238, 239, 240)
BLESSING_OIL_ID = 920033
EXCLUDED_NON_BOSS_ID = 225
LEDGER_FIELDS = (
    "slot_uid",
    "canonical_monster_id",
    "canonical_item_id",
    "gold_amount",
    "base_numerator",
    "base_denominator",
    "source_provenance_id",
    "protected_drop",
    "overflow_priority",
    "baseline_origin",
)


class BoostBuildError(RuntimeError):
    """Raised when an immutable input or overlay invariant is violated."""


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise BoostBuildError(f"{path.relative_to(ROOT)} is not a JSON object")
    return value


def raw_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def canonical_json(value: Any) -> str:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )


def git_show_bytes(relative_path: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "show", f"{BASE_SHA}:{relative_path}"],
            cwd=ROOT,
            stderr=subprocess.STDOUT,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise BoostBuildError(
            f"cannot read immutable BASE_SHA object {BASE_SHA}:{relative_path}"
        ) from exc


def git_show_json(relative_path: str) -> dict[str, Any]:
    try:
        value = json.loads(git_show_bytes(relative_path).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BoostBuildError(
            f"BASE_SHA object is not valid UTF-8 JSON: {relative_path}"
        ) from exc
    if not isinstance(value, dict):
        raise BoostBuildError(f"BASE_SHA object is not a JSON object: {relative_path}")
    return value


def _flatten_slots(baseline: dict[str, Any]) -> list[dict[str, Any]]:
    profiles = baseline.get("profiles")
    if not isinstance(profiles, list):
        raise BoostBuildError("direct baseline profiles are not an array")
    rows: list[dict[str, Any]] = []
    for profile in profiles:
        if not isinstance(profile, dict) or not isinstance(profile.get("slots"), list):
            raise BoostBuildError("direct baseline profile/slots contract is invalid")
        monster_id = int(profile.get("canonical_monster_id", -1))
        for slot in profile["slots"]:
            if not isinstance(slot, dict):
                raise BoostBuildError("direct baseline slot is not an object")
            rows.append({"canonical_monster_id": monster_id, **slot})
    return rows


def immutable_ledger(slots: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {key: row[key] for key in LEDGER_FIELDS if key in row}
        for row in sorted(slots, key=lambda item: str(item.get("slot_uid", "")))
    ]


def ledger_sha256(slots: list[dict[str, Any]]) -> str:
    return hashlib.sha256(
        canonical_json(immutable_ledger(slots)).encode("utf-8")
    ).hexdigest().upper()


def reduce_rational(numerator: int, denominator: int) -> tuple[int, int]:
    if numerator <= 0 or denominator <= 0:
        raise BoostBuildError("probability rational must be positive")
    divisor = gcd(numerator, denominator)
    return numerator // divisor, denominator // divisor


def effective_rational(
    base_numerator: int,
    base_denominator: int,
    *,
    auto_boost: bool,
    enabled: bool,
) -> tuple[int, int, bool, str]:
    """Return exact effective rational, ceiling flag, and formula reason."""

    base_numerator, base_denominator = reduce_rational(
        base_numerator, base_denominator
    )
    if not enabled:
        return base_numerator, base_denominator, False, "BOOST_DISABLED_BASE_PARITY"
    if not auto_boost:
        return base_numerator, base_denominator, False, "BYPASS_BASE_PARITY"
    ceiling_numerator, ceiling_denominator = CEILING
    if base_numerator * ceiling_denominator >= base_denominator * ceiling_numerator:
        return (
            base_numerator,
            base_denominator,
            False,
            "BASE_AT_OR_ABOVE_CEILING_UNCHANGED",
        )
    boosted_numerator = base_numerator * MULTIPLIER[0]
    boosted_denominator = base_denominator * MULTIPLIER[1]
    if (
        boosted_numerator * ceiling_denominator
        > boosted_denominator * ceiling_numerator
    ):
        return ceiling_numerator, ceiling_denominator, True, "AUTO_BOOST_CEILING_APPLIED"
    numerator, denominator = reduce_rational(boosted_numerator, boosted_denominator)
    return numerator, denominator, False, "AUTO_BOOST_EXACT_X25"


def _validate_immutable_inputs(
    baseline: dict[str, Any], current_slots: list[dict[str, Any]]
) -> dict[str, Any]:
    bindings = (
        (SOURCE_PATH, EXPECTED_SOURCE_SHA256),
        (BASELINE_PATH, EXPECTED_BASELINE_SHA256),
        (PROVENANCE_PATH, EXPECTED_PROVENANCE_SHA256),
    )
    for path, expected_hash in bindings:
        current_hash = raw_sha256(path)
        if current_hash != expected_hash:
            raise BoostBuildError(
                f"immutable input drift: {path.relative_to(ROOT)}={current_hash} "
                f"expected={expected_hash}"
            )
        relative = path.relative_to(ROOT).as_posix()
        # Git stores normalized LF blobs while this Windows checkout is CRLF.
        # Compare parsed JSON for BASE_SHA identity, and retain the separately
        # mandated raw-checkout hash above as the byte-level freeze.
        if load_json(path) != git_show_json(relative):
            raise BoostBuildError(
                f"BASE_SHA semantic JSON binding drift: {relative}"
            )

    frozen_baseline = git_show_json(BASELINE_PATH.relative_to(ROOT).as_posix())
    frozen_slots = _flatten_slots(frozen_baseline)
    if len(current_slots) != EXPECTED_SLOT_COUNT or len(frozen_slots) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError(
            f"direct slot cardinality drift current={len(current_slots)} "
            f"frozen={len(frozen_slots)} expected={EXPECTED_SLOT_COUNT}"
        )
    current_ledger = immutable_ledger(current_slots)
    frozen_ledger = immutable_ledger(frozen_slots)
    if current_ledger != frozen_ledger:
        raise BoostBuildError("complete immutable direct-slot ledger drift")
    digest = ledger_sha256(current_slots)
    if digest != EXPECTED_LEDGER_SHA256:
        raise BoostBuildError(
            f"direct-slot ledger hash drift={digest} expected={EXPECTED_LEDGER_SHA256}"
        )
    uids = [str(row.get("slot_uid", "")) for row in current_slots]
    provenance_ids = [str(row.get("source_provenance_id", "")) for row in current_slots]
    if len(set(uids)) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError("duplicate or missing slot_uid in direct baseline")
    if len(set(provenance_ids)) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError("duplicate or missing source_provenance_id in direct baseline")
    if baseline.get("summary", {}).get("duplicate_slot_collapse") != 0:
        raise BoostBuildError("direct baseline reports duplicate slot collapse")
    return {
        "base_sha": BASE_SHA,
        "source_sha256_raw": EXPECTED_SOURCE_SHA256,
        "direct_baseline_sha256_raw": EXPECTED_BASELINE_SHA256,
        "source_provenance_sha256_raw": EXPECTED_PROVENANCE_SHA256,
        "direct_slot_count": EXPECTED_SLOT_COUNT,
        "direct_slot_ledger_sha256": digest,
        "direct_slot_ledger_fields": list(LEDGER_FIELDS),
        "source_drift": 0,
        "base_probability_drift": 0,
        "slot_uid_drift": 0,
        "reward_identity_drift": 0,
        "provenance_drift": 0,
        "protected_priority_origin_drift": 0,
        "duplicate_slot_collapse": 0,
    }


def _classification_records(
    authority: dict[str, Any], baseline_item_ids: set[int]
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    dict[int, dict[str, Any]],
]:
    if (
        authority.get("schema")
        != "hardcore.dpv2.single_player_item_boost_classification.v1"
        or authority.get("authority_id")
        != "dpv2.single_player_item_boost_classification.v1"
        or authority.get("status") != "PRODUCTION_CLASSIFICATION_AUTHORITY"
        or authority.get("production_active") is not True
        or authority.get("identity_key") != "canonical_item_id"
    ):
        raise BoostBuildError("item boost classification authority contract mismatch")
    records = authority.get("records")
    if not isinstance(records, list) or len(records) != 233:
        raise BoostBuildError("item boost classification must contain 233 records")
    by_id: dict[int, dict[str, Any]] = {}
    counts: Counter[str] = Counter()
    for row in records:
        if not isinstance(row, dict):
            raise BoostBuildError("item boost classification record is not an object")
        item_id = int(row.get("canonical_item_id", -1))
        classification = str(row.get("classification", ""))
        evidence = row.get("evidence")
        if item_id <= 0 or item_id in by_id:
            raise BoostBuildError(f"duplicate/invalid classified canonical item ID {item_id}")
        if classification not in EXPECTED_CLASSIFICATION_COUNTS:
            raise BoostBuildError(f"invalid item boost classification {item_id}")
        if (
            not str(row.get("canonical_item_name", ""))
            or not str(row.get("reason", ""))
            or not isinstance(evidence, list)
            or not evidence
            or any(not str(value) for value in evidence)
            or row.get("human_frozen") is not True
        ):
            raise BoostBuildError(f"incomplete human-frozen classification {item_id}")
        by_id[item_id] = row
        counts[classification] += 1
    if set(by_id) != baseline_item_ids:
        missing = sorted(baseline_item_ids - set(by_id))
        extra = sorted(set(by_id) - baseline_item_ids)
        raise BoostBuildError(
            f"classification/direct exact identity mismatch missing={missing[:3]} "
            f"extra={extra[:3]}"
        )
    if dict(counts) != EXPECTED_CLASSIFICATION_COUNTS:
        raise BoostBuildError(f"item boost classification count drift={dict(counts)}")
    common_ids = {
        item_id
        for item_id, row in by_id.items()
        if row["classification"] == "COMMON_RECOVERY"
    }
    if common_ids != set(COMMON_RECOVERY_IDS):
        raise BoostBuildError("common recovery exact-ID classification drift")
    if (
        by_id[BLESSING_OIL_ID]["classification"]
        != "RARE_FUNCTIONAL_CONSUMABLE"
        or by_id[920019]["classification"]
        != "RARE_FUNCTIONAL_CONSUMABLE"
        or by_id[920007]["classification"] != "BYPASS_UNCLASSIFIED"
    ):
        raise BoostBuildError("item boost classification semantic anchor drift")
    summary = authority.get("summary", {})
    if (
        summary.get("canonical_items") != 233
        or summary.get("duplicate_canonical_item_ids") != 0
        or summary.get("human_frozen_records") != 233
        or summary.get("classification_counts") != dict(sorted(counts.items()))
    ):
        raise BoostBuildError("item boost classification summary drift")

    def project(row: dict[str, Any], policy: str) -> dict[str, Any]:
        return {
            "canonical_item_id": int(row["canonical_item_id"]),
            "canonical_item_name": row["canonical_item_name"],
            "classification": row["classification"],
            "boost_policy": policy,
            "reason_code": row["reason"],
            "evidence": row["evidence"],
            "human_frozen": True,
        }

    equipment = [
        project(row, "AUTO_BOOST")
        for _item_id, row in sorted(by_id.items())
        if row["classification"] == "EQUIPMENT"
    ]
    rare = [
        project(row, "AUTO_BOOST")
        for _item_id, row in sorted(by_id.items())
        if row["classification"] == "RARE_FUNCTIONAL_CONSUMABLE"
    ]
    common = [project(by_id[item_id], "BYPASS_COMMON_RECOVERY") for item_id in COMMON_RECOVERY_IDS]
    return equipment, rare, common, by_id


def classify_slot(
    row: dict[str, Any],
    classification_by_id: dict[int, dict[str, Any]],
) -> tuple[str, str]:
    monster_id = int(row["canonical_monster_id"])
    item_id = row.get("canonical_item_id")
    # Whole-monster manual exclusion is deliberately strongest: all 54 slots
    # for each new-armor boss remain base, regardless of reward kind.
    if monster_id in NEW_ARMOR_BOSS_IDS:
        return "BYPASS_NEW_ARMOR_BOSS", "NEW_ARMOR_BOSS_MANUAL_LATER"
    if "gold_amount" in row:
        return (
            "BYPASS_GOLD",
            "GOLD_PROBABILITY_UNCHANGED_AMOUNT_X10_WHEN_ENABLED",
        )
    classification = classification_by_id.get(int(item_id), {})
    class_name = classification.get("classification")
    reason = str(classification.get("reason", ""))
    if class_name == "COMMON_RECOVERY":
        return "BYPASS_COMMON_RECOVERY", reason
    if class_name in {"RARE_FUNCTIONAL_CONSUMABLE", "EQUIPMENT"}:
        return "AUTO_BOOST", reason
    if class_name == "BYPASS_UNCLASSIFIED":
        return "BYPASS_UNCLASSIFIED", reason
    raise BoostBuildError(f"missing current classification for item {item_id}")


def build_documents() -> tuple[dict[str, Any], dict[str, Any]]:
    baseline = load_json(BASELINE_PATH)
    slots = _flatten_slots(baseline)
    freeze = _validate_immutable_inputs(baseline, slots)
    classification_authority = load_json(CLASSIFICATION_PATH)
    global_authority = load_json(GLOBAL_PATH)
    for path, expected_hash in (
        (GLOBAL_PATH, EXPECTED_GLOBAL_SHA256),
    ):
        digest = raw_sha256(path)
        if digest != expected_hash:
            raise BoostBuildError(
                f"supporting authority drift: {path.relative_to(ROOT)}={digest} "
                f"expected={expected_hash}"
            )
    if global_authority.get("active_preset") != "1x":
        raise BoostBuildError("SPB requires global drop rate preset 1x")
    active_preset = next(
        (
            row
            for row in global_authority.get("presets", [])
            if row.get("preset") == "1x"
        ),
        None,
    )
    if active_preset != {"preset": "1x", "numerator": 1, "denominator": 1}:
        raise BoostBuildError("global 1x preset is not exact 1/1")

    baseline_item_ids = {
        int(row["canonical_item_id"])
        for row in slots
        if "canonical_item_id" in row
    }
    equipment, rare, common_records, classification_by_id = _classification_records(
        classification_authority, baseline_item_ids
    )
    equipment_ids = frozenset(row["canonical_item_id"] for row in equipment)
    rare_consumable_ids = frozenset(row["canonical_item_id"] for row in rare)
    if EXCLUDED_NON_BOSS_ID in NEW_ARMOR_BOSS_IDS:
        raise BoostBuildError("monster 225 must not be a new-armor boss exclusion")

    profiles_by_id = {
        int(row["canonical_monster_id"]): row for row in baseline["profiles"]
    }
    boss_records = []
    for monster_id in NEW_ARMOR_BOSS_IDS:
        profile = profiles_by_id.get(monster_id)
        if profile is None or len(profile.get("slots", [])) != 54:
            raise BoostBuildError(
                f"new-armor boss identity/slot binding drift: {monster_id}"
            )
        boss_records.append(
            {
                "canonical_monster_id": monster_id,
                "canonical_monster_name": profile.get("canonical_monster_name"),
                "boost_policy": "BYPASS_NEW_ARMOR_BOSS",
                "reason_code": "NEW_ARMOR_BOSS_MANUAL_LATER",
            }
        )

    overlap_counts = {
        "gold_slots": sum("gold_amount" in row for row in slots),
        "common_recovery_slots": sum(
            row.get("canonical_item_id") in COMMON_RECOVERY_IDS for row in slots
        ),
        "new_armor_boss_slots": sum(
            row["canonical_monster_id"] in NEW_ARMOR_BOSS_IDS for row in slots
        ),
        "blessing_oil_slots": sum(
            row.get("canonical_item_id") == BLESSING_OIL_ID for row in slots
        ),
        "equipment_candidate_slots": sum(
            row.get("canonical_item_id") in equipment_ids for row in slots
        ),
        "rare_consumable_candidate_slots": sum(
            row.get("canonical_item_id") in rare_consumable_ids for row in slots
        ),
        # Candidate populations intentionally overlap the whole-boss bypass.
        # This is the audit view. The effective policy bucket is smaller because
        # BYPASS_NEW_ARMOR_BOSS has the strongest precedence.
        "unclassified_candidate_slots": sum(
            "canonical_item_id" in row
            and row.get("canonical_item_id") not in COMMON_RECOVERY_IDS
            and row.get("canonical_item_id") not in equipment_ids
            and row.get("canonical_item_id") not in rare_consumable_ids
            for row in slots
        ),
    }
    if overlap_counts != EXPECTED_OVERLAPPING_COUNTS:
        raise BoostBuildError(
            f"expected classification population drift={overlap_counts}"
        )

    policy_counts: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    effective_records: list[dict[str, Any]] = []
    ceiling_count = 0
    disabled_mismatch = 0
    probability_decreases = 0
    ceiling_violations = 0
    boost_mismatches = 0
    bypass_mismatches = 0
    gold_amount_mismatches = 0
    disabled_gold_amount_mismatches = 0
    for row in slots:
        policy, classification_reason = classify_slot(
            row, classification_by_id
        )
        auto = policy == "AUTO_BOOST"
        base_numerator = int(row["base_numerator"])
        base_denominator = int(row["base_denominator"])
        numerator, denominator, ceiling_applied, formula_reason = effective_rational(
            base_numerator, base_denominator, auto_boost=auto, enabled=True
        )
        disabled = effective_rational(
            base_numerator, base_denominator, auto_boost=auto, enabled=False
        )[:2]
        base_reduced = reduce_rational(base_numerator, base_denominator)
        if disabled != base_reduced:
            disabled_mismatch += 1
        base_fraction = Fraction(*base_reduced)
        effective_fraction = Fraction(numerator, denominator)
        if effective_fraction < base_fraction:
            probability_decreases += 1
        if auto:
            if base_fraction < Fraction(*CEILING) and effective_fraction > Fraction(*CEILING):
                ceiling_violations += 1
            expected = min(base_fraction * Fraction(*MULTIPLIER), Fraction(*CEILING))
            if base_fraction >= Fraction(*CEILING):
                expected = base_fraction
            if effective_fraction != expected:
                boost_mismatches += 1
        elif effective_fraction != base_fraction:
            bypass_mismatches += 1

        record = {
            key: row[key]
            for key in LEDGER_FIELDS
            if key in row
        }
        record["reward_kind"] = "GOLD" if "gold_amount" in row else "ITEM"
        if "gold_amount" in row:
            base_gold_amount = int(row["gold_amount"])
            effective_gold_amount = (
                base_gold_amount * GOLD_AMOUNT_MULTIPLIER[0]
                // GOLD_AMOUNT_MULTIPLIER[1]
            )
            record["base_gold_amount"] = base_gold_amount
            record["effective_gold_amount"] = effective_gold_amount
            if effective_gold_amount != (
                base_gold_amount * GOLD_AMOUNT_MULTIPLIER[0]
                // GOLD_AMOUNT_MULTIPLIER[1]
            ):
                gold_amount_mismatches += 1
            if base_gold_amount != int(row["gold_amount"]):
                disabled_gold_amount_mismatches += 1
        record.update(
            {
                "boost_policy": policy,
                "boost_multiplier_numerator": MULTIPLIER[0] if auto else 1,
                "boost_multiplier_denominator": MULTIPLIER[1] if auto else 1,
                "auto_boost_ceiling_numerator": CEILING[0],
                "auto_boost_ceiling_denominator": CEILING[1],
                "ceiling_applied": ceiling_applied,
                "effective_numerator": numerator,
                "effective_denominator": denominator,
                "reason_code": classification_reason,
                "formula_reason_code": formula_reason,
            }
        )
        effective_records.append(record)
        policy_counts[policy] += 1
        reason_counts[classification_reason] += 1
        ceiling_count += int(ceiling_applied)

    if len(effective_records) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError("effective record cardinality mismatch")
    effective_uids = [row["slot_uid"] for row in effective_records]
    if len(set(effective_uids)) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError("effective slot duplicate collapse")
    if any(
        (
            disabled_mismatch,
            probability_decreases,
            ceiling_violations,
            boost_mismatches,
            bypass_mismatches,
            gold_amount_mismatches,
            disabled_gold_amount_mismatches,
        )
    ):
        raise BoostBuildError("effective probability invariant mismatch")
    if dict(policy_counts) != EXPECTED_EFFECTIVE_POLICY_COUNTS:
        raise BoostBuildError(f"effective policy count drift={dict(policy_counts)}")

    source_bindings = {
        **freeze,
        "item_boost_classification_path": CLASSIFICATION_PATH.relative_to(ROOT).as_posix(),
        "item_boost_classification_sha256_raw": raw_sha256(CLASSIFICATION_PATH),
        "global_drop_rate_path": GLOBAL_PATH.relative_to(ROOT).as_posix(),
        "global_drop_rate_sha256_raw": raw_sha256(GLOBAL_PATH),
    }
    authority = {
        "schema": "hardcore.dpv2.single_player_drop_boost.v1",
        "authority_id": "dpv2.single_player_drop_boost.v1",
        "status": "PRODUCTION_ENABLED",
        "production": {
            "enabled": True,
            "boost_multiplier": {"numerator": 25, "denominator": 1},
            "auto_boost_ceiling": {"numerator": 1, "denominator": 20},
            "gold_amount_multiplier": {
                "numerator": GOLD_AMOUNT_MULTIPLIER[0],
                "denominator": GOLD_AMOUNT_MULTIPLIER[1],
            },
            "required_global_drop_rate_preset": "1x",
            "required_global_drop_rate_multiplier": {
                "numerator": 1,
                "denominator": 1,
            },
            "disabled_mode": "SELECT_BASE_NUMERATOR_AND_DENOMINATOR",
        },
        "probability_contract": {
            "arithmetic": "EXACT_POSITIVE_INTEGER_RATIONAL_GCD_REDUCED",
            "formula": "if_bypass_or_base_gte_1_over_20_then_base_else_min(base_times_25,1_over_20)",
            "runtime_float_authority_forbidden": True,
            "base_mutation_forbidden": True,
            "independent_slot_rng_preserved": True,
            "overflow_occurs_after_all_rng": True,
            "protected_drop_and_overflow_priority_do_not_affect_probability": True,
            "missing_effective_record_runtime_result": "FAIL_CLOSED_SPB_EFFECTIVE_PROBABILITY_UNRESOLVED",
        },
        "reward_amount_contract": {
            "gold_probability_policy": "BYPASS_GOLD_BASE_PROBABILITY",
            "enabled_gold_amount": "base_gold_amount_times_5",
            "disabled_gold_amount": "base_gold_amount",
            "direct_baseline_gold_amount_mutation_forbidden": True,
            "non_gold_reward_amount_overlay_forbidden": True,
        },
        "classification_contract": {
            "production_authority": "dpv2.single_player_item_boost_classification.v1",
            "runtime_classification": "EXACT_CANONICAL_IDS_HUMAN_FROZEN_IN_CURRENT_AUTHORITY",
            "runtime_name_tier_or_fuzzy_inference_forbidden": True,
            "build_time_source": "CURRENT_PRODUCTION_CLASSIFICATION_AUTHORITY_EXACT_IDS",
            "precedence": [
                "BYPASS_NEW_ARMOR_BOSS",
                "BYPASS_GOLD",
                "BYPASS_COMMON_RECOVERY",
                "AUTO_BOOST_RARE_FUNCTIONAL_CONSUMABLE",
                "AUTO_BOOST_EQUIPMENT",
                "BYPASS_UNCLASSIFIED",
            ],
            "unclassified_default": "BYPASS_UNCLASSIFIED",
            "monster_225_is_manual_boss_exclusion": False,
        },
        "source_bindings": source_bindings,
        "common_recovery_items": common_records,
        "manual_boss_exclusions": boss_records,
        "auto_boost_items": equipment + rare,
        "summary": {
            "production_slots": EXPECTED_SLOT_COUNT,
            "equipment_item_ids": len(equipment),
            "rare_functional_consumable_item_ids": len(rare),
            "auto_boost_item_ids": len(equipment) + len(rare),
            "overlapping_population_counts": overlap_counts,
            "effective_policy_counts": dict(sorted(policy_counts.items())),
            "ceiling_applied_slots": ceiling_count,
            "disabled_counterfactual_mismatch": disabled_mismatch,
            "gold_amount_multiplier": {
                "numerator": GOLD_AMOUNT_MULTIPLIER[0],
                "denominator": GOLD_AMOUNT_MULTIPLIER[1],
            },
            "gold_amount_slots": overlap_counts["gold_slots"],
            "gold_amount_mismatch": gold_amount_mismatches,
            "disabled_gold_amount_mismatch": disabled_gold_amount_mismatches,
            "probability_decreases": probability_decreases,
            "ceiling_violations": ceiling_violations,
            "boost_formula_mismatch": boost_mismatches,
            "bypass_probability_mismatch": bypass_mismatches,
            "duplicate_slot_collapse": 0,
        },
    }
    effective = {
        "schema": "hardcore.dpv2.single_player_effective_probability.v1",
        "authority_id": "dpv2.single_player_effective_probability.v1",
        "status": "PRODUCTION_EFFECTIVE_LEDGER",
        "production_enabled": True,
        "source_authority": "dpv2.single_player_drop_boost.v1",
        "source_direct_baseline": "dpv2.direct_baseline.v2",
        "selection_contract": {
            "enabled_true": "effective_numerator_over_effective_denominator",
            "enabled_false": "base_numerator_over_base_denominator",
            "missing_slot": "FAIL_CLOSED_SPB_EFFECTIVE_PROBABILITY_UNRESOLVED",
        },
        "source_bindings": source_bindings,
        "summary": {
            "records": len(effective_records),
            "effective_policy_counts": dict(sorted(policy_counts.items())),
            "reason_counts": dict(sorted(reason_counts.items())),
            "overlapping_population_counts": overlap_counts,
            "ceiling_applied_slots": ceiling_count,
            "disabled_counterfactual_records": len(effective_records),
            "disabled_counterfactual_mismatch": disabled_mismatch,
            "gold_amount_multiplier": {
                "numerator": GOLD_AMOUNT_MULTIPLIER[0],
                "denominator": GOLD_AMOUNT_MULTIPLIER[1],
            },
            "gold_amount_slots": overlap_counts["gold_slots"],
            "gold_amount_mismatch": gold_amount_mismatches,
            "disabled_gold_amount_mismatch": disabled_gold_amount_mismatches,
            "base_mirror_mismatch": 0,
            "probability_decreases": probability_decreases,
            "ceiling_violations": ceiling_violations,
            "boost_formula_mismatch": boost_mismatches,
            "bypass_probability_mismatch": bypass_mismatches,
            "duplicate_slot_collapse": 0,
        },
        "records": effective_records,
    }
    validate_documents(authority, effective, baseline)
    return authority, effective


def validate_documents(
    authority: dict[str, Any],
    effective: dict[str, Any],
    baseline: dict[str, Any] | None = None,
) -> None:
    if authority.get("schema") != "hardcore.dpv2.single_player_drop_boost.v1":
        raise BoostBuildError("boost authority schema mismatch")
    if authority.get("production", {}).get("enabled") is not True:
        raise BoostBuildError("production boost must be enabled")
    if effective.get("schema") != "hardcore.dpv2.single_player_effective_probability.v1":
        raise BoostBuildError("effective ledger schema mismatch")
    records = effective.get("records")
    if not isinstance(records, list) or len(records) != EXPECTED_SLOT_COUNT:
        raise BoostBuildError("effective ledger must contain exactly 6809 records")
    baseline = baseline or load_json(BASELINE_PATH)
    direct = {row["slot_uid"]: row for row in _flatten_slots(baseline)}
    emitted = {row.get("slot_uid"): row for row in records}
    if len(emitted) != EXPECTED_SLOT_COUNT or set(emitted) != set(direct):
        raise BoostBuildError("effective/direct slot UID identity mismatch")
    for uid, source in direct.items():
        row = emitted[uid]
        for field in LEDGER_FIELDS:
            if row.get(field) != source.get(field):
                raise BoostBuildError(f"effective base mirror drift {uid}:{field}")
        expected_reward_kind = "GOLD" if "gold_amount" in source else "ITEM"
        if row.get("reward_kind") != expected_reward_kind:
            raise BoostBuildError(f"effective reward kind drift {uid}")
        if expected_reward_kind == "GOLD":
            base_gold_amount = int(source["gold_amount"])
            if (
                row.get("base_gold_amount") != base_gold_amount
                or row.get("effective_gold_amount")
                != (
                    base_gold_amount * GOLD_AMOUNT_MULTIPLIER[0]
                    // GOLD_AMOUNT_MULTIPLIER[1]
                )
            ):
                raise BoostBuildError(f"effective gold amount mismatch {uid}")
        elif "base_gold_amount" in row or "effective_gold_amount" in row:
            raise BoostBuildError(f"non-gold record has gold amount overlay {uid}")
        if gcd(int(row["effective_numerator"]), int(row["effective_denominator"])) != 1:
            raise BoostBuildError(f"effective probability is not reduced {uid}")


def render_json(document: dict[str, Any]) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n"


def write_documents(authority: dict[str, Any], effective: dict[str, Any]) -> None:
    AUTHORITY_PATH.write_text(render_json(authority), encoding="utf-8", newline="\n")
    EFFECTIVE_PATH.write_text(render_json(effective), encoding="utf-8", newline="\n")


def check_document(path: Path, expected: dict[str, Any]) -> None:
    if not path.is_file():
        raise BoostBuildError(f"missing generated artifact {path.relative_to(ROOT)}")
    actual = load_json(path)
    if actual != expected:
        raise BoostBuildError(f"generated artifact is stale: {path.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        authority, effective = build_documents()
        if args.write:
            write_documents(authority, effective)
            action = "WROTE"
        else:
            check_document(AUTHORITY_PATH, authority)
            check_document(EFFECTIVE_PATH, effective)
            action = "PASS"
        summary = effective["summary"]
        print(
            "DPV2_SINGLE_PLAYER_DROP_BOOST_"
            f"{action} slots={summary['records']} "
            f"policy_counts={json.dumps(summary['effective_policy_counts'], sort_keys=True)} "
            f"ceiling={summary['ceiling_applied_slots']} "
            f"disabled_mismatch={summary['disabled_counterfactual_mismatch']} "
            "source_drift=0 base_probability_drift=0 slot_uid_drift=0 "
            "reward_drift=0 duplicate_slot_collapse=0"
        )
        return 0
    except (BoostBuildError, OSError, ValueError, KeyError) as exc:
        print(f"DPV2_SINGLE_PLAYER_DROP_BOOST_FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
