from __future__ import annotations

from fractions import Fraction
import hashlib
import importlib.util
import json
from math import gcd
from pathlib import Path
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/build_dpv2_single_player_drop_boost.py"
AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_single_player_drop_boost_v1.json"
EFFECTIVE_PATH = (
    ROOT / "assets/data/drop/dpv2_single_player_effective_probability_v1.json"
)
SPEC = importlib.util.spec_from_file_location("dpv2_spb_builder", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def documents() -> tuple[dict, dict, dict, list[dict]]:
    authority = load_json(AUTHORITY_PATH)
    effective = load_json(EFFECTIVE_PATH)
    baseline = load_json(builder.BASELINE_PATH)
    direct_slots = builder._flatten_slots(baseline)
    return authority, effective, baseline, direct_slots


@pytest.mark.parametrize(
    ("denominator", "expected_numerator", "expected_denominator", "ceiling"),
    [
        (10, 1, 10, False),
        (20, 1, 20, False),
        (30, 1, 20, True),
        (50, 1, 20, True),
        (100, 1, 20, True),
        (200, 1, 20, True),
        (500, 1, 20, False),
        (1000, 1, 40, False),
        (2000, 1, 80, False),
        (5000, 1, 200, False),
        (6000, 1, 240, False),
        (10000, 1, 400, False),
        (30000, 1, 1200, False),
        (100000, 1, 4000, False),
    ],
)
def test_exact_x25_formula_samples(
    denominator: int,
    expected_numerator: int,
    expected_denominator: int,
    ceiling: bool,
) -> None:
    numerator, output_denominator, applied, _reason = builder.effective_rational(
        1, denominator, auto_boost=True, enabled=True
    )
    assert (numerator, output_denominator, applied) == (
        expected_numerator,
        expected_denominator,
        ceiling,
    )
    assert gcd(numerator, output_denominator) == 1


def test_bypass_and_disabled_modes_select_exact_base() -> None:
    assert builder.effective_rational(3, 7000, auto_boost=False, enabled=True)[:2] == (
        3,
        7000,
    )
    assert builder.effective_rational(3, 7000, auto_boost=True, enabled=False)[:2] == (
        3,
        7000,
    )


def test_authority_contract_and_exact_id_freeze(documents) -> None:
    authority, _effective, _baseline, _slots = documents
    assert authority["schema"] == "hardcore.dpv2.single_player_drop_boost.v1"
    assert authority["production"] == {
        "enabled": True,
        "boost_multiplier": {"numerator": 25, "denominator": 1},
        "auto_boost_ceiling": {"numerator": 1, "denominator": 20},
        "gold_amount_multiplier": {"numerator": 10, "denominator": 1},
        "required_global_drop_rate_preset": "1x",
        "required_global_drop_rate_multiplier": {"numerator": 1, "denominator": 1},
        "disabled_mode": "SELECT_BASE_NUMERATOR_AND_DENOMINATOR",
    }
    assert [
        row["canonical_item_id"] for row in authority["common_recovery_items"]
    ] == list(builder.COMMON_RECOVERY_IDS)
    assert [
        row["canonical_monster_id"] for row in authority["manual_boss_exclusions"]
    ] == list(builder.NEW_ARMOR_BOSS_IDS)
    assert builder.EXCLUDED_NON_BOSS_ID not in {
        row["canonical_monster_id"] for row in authority["manual_boss_exclusions"]
    }
    auto_ids = [row["canonical_item_id"] for row in authority["auto_boost_items"]]
    assert len(auto_ids) == len(set(auto_ids)) == 180
    assert builder.BLESSING_OIL_ID in auto_ids


def test_equipment_ids_are_frozen_from_a07_exact_identity(documents) -> None:
    authority, _effective, _baseline, direct_slots = documents
    tier = load_json(builder.TIER_PATH)
    expected_equipment = {
        row["canonical_item_id"]
        for row in tier["records"]
        if row["tier_status"] == "RESOLVED"
        and row["item_type"] in builder.EQUIPMENT_ITEM_TYPES
    }
    frozen_equipment = {
        row["canonical_item_id"]
        for row in authority["auto_boost_items"]
        if row["classification"] == "EQUIPMENT"
    }
    assert frozen_equipment == expected_equipment
    assert len(frozen_equipment) == 167
    assert {
        row["canonical_item_id"]
        for row in direct_slots
        if "canonical_item_id" in row
    } == {row["canonical_item_id"] for row in tier["records"]}
    expected_rare = {
        row["canonical_item_id"]
        for row in tier["records"]
        if row["tier_status"] == "RESOLVED" and row["tier"] == "RARE_CONSUMABLE"
    }
    frozen_rare = {
        row["canonical_item_id"]
        for row in authority["auto_boost_items"]
        if row["classification"] == "RARE_FUNCTIONAL_CONSUMABLE"
    }
    assert frozen_rare == expected_rare
    assert len(frozen_rare) == 13
    # A07 identifies these FUNCTIONAL_SPECIAL rows as rings, so they remain
    # equipment AUTO_BOOST even though their tier name is not EQUIP_*.
    assert {253, 254, 260}.issubset(frozen_equipment)


def test_all_three_immutable_sources_match_raw_sha_and_base_sha(documents) -> None:
    _authority, _effective, _baseline, direct_slots = documents
    expected = {
        builder.SOURCE_PATH: builder.EXPECTED_SOURCE_SHA256,
        builder.BASELINE_PATH: builder.EXPECTED_BASELINE_SHA256,
        builder.PROVENANCE_PATH: builder.EXPECTED_PROVENANCE_SHA256,
    }
    for path, digest in expected.items():
        assert hashlib.sha256(path.read_bytes()).hexdigest().upper() == digest
        relative = path.relative_to(ROOT).as_posix()
        frozen = json.loads(
            subprocess.check_output(
                ["git", "show", f"{builder.BASE_SHA}:{relative}"], cwd=ROOT
            ).decode("utf-8")
        )
        assert frozen == load_json(path)
    assert len(direct_slots) == 6809
    assert builder.ledger_sha256(direct_slots) == builder.EXPECTED_LEDGER_SHA256


def test_effective_ledger_is_complete_unique_and_mirrors_direct(documents) -> None:
    _authority, effective, _baseline, direct_slots = documents
    records = effective["records"]
    assert effective["schema"] == "hardcore.dpv2.single_player_effective_probability.v1"
    assert len(records) == len(direct_slots) == 6809
    by_uid = {row["slot_uid"]: row for row in records}
    direct_by_uid = {row["slot_uid"]: row for row in direct_slots}
    assert len(by_uid) == len(direct_by_uid) == 6809
    assert set(by_uid) == set(direct_by_uid)
    for uid, source in direct_by_uid.items():
        emitted = by_uid[uid]
        for field in builder.LEDGER_FIELDS:
            assert emitted.get(field) == source.get(field), (uid, field)
        assert emitted["reward_kind"] == (
            "GOLD" if "gold_amount" in source else "ITEM"
        )


def test_all_formula_and_no_debuff_gates(documents) -> None:
    _authority, effective, _baseline, _slots = documents
    for row in effective["records"]:
        base = Fraction(row["base_numerator"], row["base_denominator"])
        actual = Fraction(row["effective_numerator"], row["effective_denominator"])
        assert actual >= base
        assert gcd(row["effective_numerator"], row["effective_denominator"]) == 1
        if row["boost_policy"] == "AUTO_BOOST":
            expected = base if base >= Fraction(1, 20) else min(base * 25, Fraction(1, 20))
            assert actual == expected
            if base < Fraction(1, 20):
                assert actual <= Fraction(1, 20)
        else:
            assert actual == base
    summary = effective["summary"]
    assert summary["base_mirror_mismatch"] == 0
    assert summary["probability_decreases"] == 0
    assert summary["ceiling_violations"] == 0
    assert summary["boost_formula_mismatch"] == 0
    assert summary["bypass_probability_mismatch"] == 0
    assert summary["duplicate_slot_collapse"] == 0


def test_disabled_counterfactual_parity_is_6809_of_6809(documents) -> None:
    _authority, effective, _baseline, _slots = documents
    mismatch = 0
    for row in effective["records"]:
        disabled = builder.effective_rational(
            row["base_numerator"],
            row["base_denominator"],
            auto_boost=row["boost_policy"] == "AUTO_BOOST",
            enabled=False,
        )[:2]
        if Fraction(*disabled) != Fraction(
            row["base_numerator"], row["base_denominator"]
        ):
            mismatch += 1
    assert len(effective["records"]) == 6809
    assert mismatch == effective["summary"]["disabled_counterfactual_mismatch"] == 0


def test_white_boar_judgement_anchor_is_real_production_slot(documents) -> None:
    _authority, effective, _baseline, _slots = documents
    row = next(
        row
        for row in effective["records"]
        if row["slot_uid"] == "dpv2.direct.m135.slot_124"
    )
    assert row["canonical_monster_id"] == 135
    assert row["canonical_item_id"] == 105
    assert (row["base_numerator"], row["base_denominator"]) == (1, 5000)
    assert row["boost_policy"] == "AUTO_BOOST"
    assert (row["effective_numerator"], row["effective_denominator"]) == (1, 200)


def test_common_recovery_gold_boss_and_blessing_populations(documents) -> None:
    authority, effective, _baseline, _slots = documents
    records = effective["records"]
    common = [
        row
        for row in records
        if row.get("canonical_item_id") in builder.COMMON_RECOVERY_IDS
    ]
    gold = [row for row in records if row["reward_kind"] == "GOLD"]
    bosses = [
        row
        for row in records
        if row["canonical_monster_id"] in builder.NEW_ARMOR_BOSS_IDS
    ]
    blessing = [
        row
        for row in records
        if row.get("canonical_item_id") == builder.BLESSING_OIL_ID
    ]
    assert (len(common), len(gold), len(bosses), len(blessing)) == (1597, 134, 324, 22)
    assert authority["summary"]["overlapping_population_counts"] == {
        "gold_slots": 134,
        "common_recovery_slots": 1597,
        "new_armor_boss_slots": 324,
        "blessing_oil_slots": 22,
        "equipment_candidate_slots": 4311,
        "rare_consumable_candidate_slots": 268,
        "unclassified_candidate_slots": 499,
    }
    assert all(
        Fraction(row["effective_numerator"], row["effective_denominator"])
        == Fraction(row["base_numerator"], row["base_denominator"])
        for row in common + gold + bosses
    )
    assert all(row["boost_policy"] == "BYPASS_NEW_ARMOR_BOSS" for row in bosses)
    assert all(row["boost_policy"] == "AUTO_BOOST" for row in blessing)
    assert all(
        row["boost_policy"] in {"BYPASS_GOLD", "BYPASS_NEW_ARMOR_BOSS"}
        and (row["effective_numerator"], row["effective_denominator"])
        == (row["base_numerator"], row["base_denominator"])
        and row["base_gold_amount"] == row["gold_amount"]
        and row["effective_gold_amount"] == row["gold_amount"] * 10
        for row in gold
    )
    assert all(
        "base_gold_amount" not in row and "effective_gold_amount" not in row
        for row in records
        if row["reward_kind"] != "GOLD"
    )
    assert effective["summary"]["gold_amount_slots"] == 134
    assert effective["summary"]["gold_amount_multiplier"] == {
        "numerator": 10,
        "denominator": 1,
    }
    assert effective["summary"]["gold_amount_mismatch"] == 0
    assert effective["summary"]["disabled_gold_amount_mismatch"] == 0
    assert effective["summary"]["effective_policy_counts"] == {
        "AUTO_BOOST": 4537,
        "BYPASS_COMMON_RECOVERY": 1357,
        "BYPASS_GOLD": 128,
        "BYPASS_NEW_ARMOR_BOSS": 324,
        "BYPASS_UNCLASSIFIED": 463,
    }


def test_unclassified_categories_fail_safe_and_named_examples_bypass(documents) -> None:
    _authority, effective, _baseline, _slots = documents
    records = effective["records"]
    unclassified = [
        row for row in records if row["boost_policy"] == "BYPASS_UNCLASSIFIED"
    ]
    # Full audit candidate population is 499.  Whole-boss precedence removes
    # 36 of those into BYPASS_NEW_ARMOR_BOSS in the effective policy partition.
    assert len(unclassified) == 463
    assert {920007, 920019}.issubset(
        {row.get("canonical_item_id") for row in unclassified}
    )
    assert all(
        (row["effective_numerator"], row["effective_denominator"])
        == builder.reduce_rational(row["base_numerator"], row["base_denominator"])
        for row in unclassified
    )


def test_generated_documents_are_current() -> None:
    expected_authority, expected_effective = builder.build_documents()
    assert load_json(AUTHORITY_PATH) == expected_authority
    assert load_json(EFFECTIVE_PATH) == expected_effective
