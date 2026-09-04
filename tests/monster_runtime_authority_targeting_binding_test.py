#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_PATH = ROOT / "assets/data/monster_runtime_authority_v1.json"
MOVEMENT_PATH = ROOT / "assets/data/monster_movement_source_master_v1.json"
DETAIL_PATH = ROOT / "assets/data/monster_21cq_detail_source_v1.json"

EXPECTED_BY_RACE = {
    52: ("TMonster/TChickenDeer", 5),
    53: ("TATMonster", 5),
    81: ("TATMonster", 5),
    82: ("TSpitSpider", 5),
    83: ("TSlowATMonster", 5),
    84: ("TScorpion", 5),
    85: ("TStickMonster", 7),
    86: ("TATMonster", 5),
    87: ("TDualAxeMonster", 5),
    88: ("TATMonster", 5),
    89: ("TATMonster", 5),
    90: ("TGasAttackMonster", 5),
    91: ("TMagCowMonster", 5),
    92: ("TCowKingMonster", 5),
    93: ("TThornDarkMonster", 5),
    94: ("TLightingZombi", 5),
    95: ("TDigOutZombi", 7),
    96: ("TZilKinZombi", 6),
    97: ("TCowMonster", 5),
    100: ("TWhiteSkeleton", 6),
    101: ("TScultureMonster", 7),
    102: ("TScultureKingMonster", 8),
    103: ("TBeeQueen", 9),
    104: ("TArcherMonster", 5),
    105: ("TGasMothMonster", 7),
    107: ("TCentipedeKingMonster", 6),
    112: ("TArcherGuard", 12),
    114: ("TElfWarriorMonster", 6),
    115: ("TBigHeartMonster", 16),
    116: ("TSpiderHouseMonster", 9),
    117: ("TExplosionSpider", 5),
    120: ("TSoccerBall", 5),
    200: ("TElectronicScolpionMon", 5),
}

HOLD_IDS = {41, 59, 78, 123, 161, 190, 228, 229, 230, 231, 232, 233}
CORRECTED_EXACT = {
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
EXPECTED_DISTRIBUTION = {"5": 78, "6": 9, "7": 34, "8": 0, "9": 20, "12": 1, "16": 2}
CLASSIFICATION_FLOORS = {"elite": 7, "boss": 9}
CLASSIFICATION_FLOOR_AUTHORITY = "HUMAN_FROZEN"
CLASSIFICATION_FLOOR_SOURCE = "user.authority.monster_classification_view_floor.2026-08-30"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


authority = load(AUTHORITY_PATH)
movement = load(MOVEMENT_PATH)
detail = load(DETAIL_PATH)
authority_by_id = {int(item["monster_id"]): item for item in authority["records"]}
movement_by_id = {int(item["monster_id"]): item for item in movement["records"]}
detail_by_id = {int(item["monster_id"]): item for item in detail["records"]}

assert set(authority_by_id) == set(movement_by_id)
assert len(authority_by_id) == 156

exact_count = 0
hold_count = 0
exact_races: set[int] = set()
for monster_id, movement_record in movement_by_id.items():
    targeting = authority_by_id[monster_id]["targeting"]
    authority_record = authority_by_id[monster_id]
    classification = authority_record["classification"]
    runtime_allowed = bool(authority_record["runtime_allowed"])
    expected_floor = (
        CLASSIFICATION_FLOORS.get(classification) if runtime_allowed else None
    )
    detail_record = detail_by_id[monster_id]
    assert not any(key in detail_record for key in ("view_range", "view_range_cells", "viewRange"))
    primary_missing = targeting["view_range_primary_missing_evidence"]
    assert primary_missing["source"] == "assets/data/monster_21cq_detail_source_v1.json"
    assert primary_missing["result"] == "MISSING"
    binding = movement_record["source_binding"]
    if binding["binding_status"] == "EXACT_SOURCE_ROW":
        exact_count += 1
        race = int(movement_record["server_class_binding"]["server_race"])
        exact_races.add(race)
        assert race in EXPECTED_BY_RACE, f"unmapped exact server_race={race} monster_id={monster_id}"
        expected_class, expected_view = EXPECTED_BY_RACE[race]
        assert targeting["server_race"] == race
        assert targeting["pascal_class"] == expected_class
        assert targeting["class_derived_view_range_cells"] == expected_view
        assert targeting["classification_floor_view_range_cells"] == expected_floor
        assert targeting["classification_floor_authority"] == (
            CLASSIFICATION_FLOOR_AUTHORITY if expected_floor is not None else None
        )
        assert targeting["classification_floor_source"] == (
            CLASSIFICATION_FLOOR_SOURCE if expected_floor is not None else None
        )
        expected_effective_view = max(
            expected_view,
            expected_floor if expected_floor is not None else expected_view,
        )
        assert targeting["view_range_cells"] == expected_effective_view
        assert targeting["classification_floor_applied"] == (
            expected_floor is not None and expected_floor > expected_view
        )
        assert targeting["class_binding_status"] == "CANDIDATE"
        assert targeting["class_binding_authority"] == "B_CANDIDATE"
        assert targeting["class_rule_authority"] == "A_LOCKED"
        assert targeting["view_range_status"] == "CANDIDATE"
        assert targeting["view_range_rule_authority"] == "A_LOCKED"
        assert targeting["acquisition_status"] == "CANDIDATE"
    else:
        hold_count += 1
        assert monster_id in HOLD_IDS
        assert binding["binding_status"] == "SOURCE_ROW_MISSING"
        assert targeting["server_race"] is None
        assert targeting["pascal_class"] is None
        assert targeting["view_range_cells"] is None
        assert targeting["view_range_source"] is None
        assert targeting["class_binding_status"] == "DATA_HOLD"
        assert targeting["view_range_status"] == "DATA_HOLD"
        assert targeting["acquisition_status"] == "DATA_HOLD"
        assert targeting["class_derived_view_range_cells"] is None
        assert targeting["classification_floor_view_range_cells"] is None
        assert targeting["classification_floor_authority"] is None
        assert targeting["classification_floor_source"] is None
        assert targeting["classification_floor_applied"] is False
        assert targeting["class_binding_missing_evidence"]["candidate_reused_server_race"] is not None

assert exact_count == 144
assert hold_count == 12
assert exact_races == set(EXPECTED_BY_RACE), "current exact Race coverage drifted"

for monster_id, expected_view in CORRECTED_EXACT.items():
    targeting = authority_by_id[monster_id]["targeting"]
    assert targeting["class_derived_view_range_cells"] == expected_view
    assert targeting["view_range_source"] != "dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:249-258"

for monster_id, record in authority_by_id.items():
    if not bool(record["runtime_allowed"]):
        continue
    minimum = CLASSIFICATION_FLOORS.get(record["classification"])
    if minimum is None:
        continue
    view = record["targeting"]["view_range_cells"]
    if view is None:
        # Keep source-row DATA_HOLD fail-closed; a classification floor must
        # not manufacture a target-acquisition authority for it.
        continue
    assert view >= minimum, f"active {record['classification']} below floor: {monster_id}"

assert authority_by_id[238]["targeting"]["class_derived_view_range_cells"] == 5
assert authority_by_id[238]["targeting"]["classification_floor_view_range_cells"] == 9
assert authority_by_id[238]["targeting"]["view_range_cells"] == 9
assert authority_by_id[238]["targeting"]["effective_view_range_authority"] == CLASSIFICATION_FLOOR_AUTHORITY

actual_holds = {
    monster_id
    for monster_id, record in authority_by_id.items()
    if record["targeting"]["acquisition_status"] == "DATA_HOLD"
}
assert actual_holds == HOLD_IDS
assert authority["summary"]["targeting_view_range_distribution"] == EXPECTED_DISTRIBUTION
assert authority["summary"]["targeting_exact_class_bindings"] == 144
assert authority["summary"]["targeting_class_binding_data_hold"] == 12
assert authority["summary"]["targeting_view_range_data_hold"] == 12

# The targeting closure must not disturb the 21CQ movement interval authority.
for record in authority_by_id.values():
    interval = record["movement"]["interval_authority"]
    assert interval["authority"] == "user_authoritative_override"
    assert interval["source"] == "assets/data/monster_21cq_detail_source_v1.json"

print(
    "MONSTER_RUNTIME_AUTHORITY_TARGETING_BINDING_PASS "
    f"records={len(authority_by_id)} exact={exact_count} hold={hold_count} "
    f"corrected={len(CORRECTED_EXACT)} races={len(exact_races)}"
)
