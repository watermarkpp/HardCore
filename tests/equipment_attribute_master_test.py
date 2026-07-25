#!/usr/bin/env python3
"""Static contract checks for the user-authorized equipment attribute master."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MASTER = json.loads(
    (ROOT / "assets/data/equipment_attribute_master.json").read_text(encoding="utf-8")
)
ITEMS = json.loads(
    (ROOT / "assets/data/vanilla_176/items.json").read_text(encoding="utf-8")
)

CONTRACT = "equipment.attribute.master.v1"
DISTRIBUTION = "project.hardcore.equipment_attribute_master.v1"
SHA256 = "8C87CD85F4E5FAF00E8D9F85E4394F021EB5EA26AC74CB453CC370BA10452F98"
WEAPON_IDS = set(range(80, 116)) | {223}
ARMOR_IDS = {116, 118, 120, 122, 124, 126, 128, 130, 132, 140, 142, 144}
REQUIREMENTS = {
    80: ("level", 1), 81: ("level", 1), 82: ("level", 1),
    83: ("level", 5), 84: ("level", 10), 85: ("level", 10),
    86: ("level", 11), 87: ("level", 13), 88: ("level", 15),
    89: ("level", 15), 90: ("level", 15), 91: ("level", 15),
    92: ("level", 19), 93: ("level", 20), 94: ("level", 20),
    95: ("level", 20), 96: ("level", 20), 97: ("level", 22),
    98: ("level", 25), 99: ("level", 26), 100: ("level", 26),
    101: ("level", 26), 102: ("level", 28), 103: ("max_mc", 27),
    104: ("max_sc", 25), 105: ("level", 30), 106: ("level", 35),
    107: ("level", 35), 108: ("level", 34), 109: ("level", 35),
    110: ("level", 35), 111: ("level", 40), 112: ("level", 0),
    113: ("max_dc", 46), 114: ("max_mc", 28), 115: ("level", 35),
    223: ("level", 20),
    116: ("level", 1), 118: ("level", 11), 120: ("level", 16),
    122: ("level", 22), 128: ("max_dc", 46), 140: ("level", 40),
    124: ("level", 22), 130: ("max_mc", 28), 142: ("level", 40),
    126: ("level", 22), 132: ("max_sc", 27), 144: ("level", 40),
}
WEIGHTS = {
    80: 7, 81: 5, 82: 8, 83: 9, 84: 9, 85: 10, 86: 10, 87: 10,
    88: 30, 89: 25, 90: 12, 91: 16, 92: 20, 93: 8, 94: 27,
    95: 13, 96: 20, 97: 40, 98: 20, 99: 60, 100: 10, 101: 26,
    102: 58, 103: 12, 104: 15, 105: 80, 106: 20, 107: 40,
    108: 99, 109: 26, 110: 48, 111: 40, 112: 22, 113: 85,
    114: 25, 115: 45, 223: 10,
    116: 5, 118: 8, 120: 12, 122: 23, 128: 45, 140: 62,
    124: 12, 130: 19, 142: 21, 126: 15, 132: 26, 144: 37,
}
NEED = {"level": 0, "max_dc": 1, "max_mc": 2, "max_sc": 3}


def main() -> None:
    assert MASTER["contractId"] == CONTRACT
    assert MASTER["distribution"] == DISTRIBUTION
    assert MASTER["evidenceSha256"] == SHA256
    assert MASTER["sourceTier"] == "primary"
    assert MASTER["fallbackEvidence"] == []
    assert MASTER["scope"] == {
        "weaponRecords": 37,
        "maleArmorRecords": 12,
        "totalRecords": 49,
    }

    records = {row["itemId"]: row for row in MASTER["records"]}
    assert set(records) == WEAPON_IDS | ARMOR_IDS
    assert len(records) == 49
    synced = {
        row["itemId"]: row
        for row in ITEMS["records"]
        if row["itemId"] in records
    }
    assert set(synced) == set(records)

    reverse_warnings = []
    for item_id, master in records.items():
        item = synced[item_id]
        req_type, req_value = REQUIREMENTS[item_id]
        assert (master["requirementType"], master["requirementValue"]) == (
            req_type,
            req_value,
        )
        assert (master["legacyNeed"], master["legacyNeedLevel"]) == (
            NEED[req_type],
            req_value,
        )
        assert master["jobLock"] is None and item["jobLock"] is None
        assert master["weightRequirementValue"] == WEIGHTS[item_id]
        assert master["weightRequirementType"] == (
            "wear" if item_id in ARMOR_IDS else "hand"
        )
        assert master["genderRestriction"] == (
            "male" if item_id in ARMOR_IDS else None
        )
        assert master["rollPolicy"] == "legacy_clamp_negative_span"
        assert item["source"] == DISTRIBUTION
        assert item["attributeSource"]["contractId"] == CONTRACT
        assert item["attributeSource"]["evidenceSha256"] == SHA256
        assert item["sourceUrlRole"] == "supporting_reference"
        assert item["secondarySourceUrlRole"] == "supporting_reference"
        assert (
            item["requirementType"],
            item["requirementValue"],
            item["legacyNeed"],
            item["legacyNeedLevel"],
        ) == (req_type, req_value, NEED[req_type], req_value)
        assert item["reqLevel"] == (req_value if req_type == "level" else 0)
        assert item["reqAttack"] == (req_value if req_type == "max_dc" else None)
        assert item["reqMagic"] == (req_value if req_type == "max_mc" else None)
        assert item["reqTao"] == (req_value if req_type == "max_sc" else None)
        reverse_warnings.extend(
            (item_id, warning["field"], warning)
            for warning in master["warnings"]
        )

    assert [(item_id, field) for item_id, field, _ in reverse_warnings] == [
        (88, "dc"),
        (111, "dc"),
        (112, "dc"),
        (112, "mc"),
        (112, "sc"),
    ]
    for _, _, warning in reverse_warnings:
        assert warning["warningCode"] == "legacy_reverse_range"
        assert warning["runtimeBehavior"] == "legacy_clamp_negative_span"
        assert warning["isError"] is False

    lost_soul = records[111]
    assert lost_soul["stats"]["dc"] == {
        "min": 30,
        "max": 0,
        "rollPolicy": "legacy_clamp_negative_span",
    }
    assert lost_soul["contentLayer"] == "classic_legendary"
    assert lost_soul["historicalStatus"] == "official_existence_unverified"
    assert records[112]["jobAffinity"] == "general"
    assert records[112]["stats"]["dc"]["min"] == 15
    assert records[112]["stats"]["dc"]["max"] == 10
    print("EQUIPMENT_ATTRIBUTE_MASTER_STATIC_PASS: 49 records and primary contract verified")


if __name__ == "__main__":
    main()
