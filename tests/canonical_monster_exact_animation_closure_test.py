#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PROJECT_PATH = ROOT / "assets/data/vanilla_176/monsters.json"

CATALOG_PATH = (
    ROOT / "assets/data/runtime/canonical_monster_catalog.json"
)

ANIMATION_PATH = (
    ROOT / "assets/data/runtime/monster_animation_catalog.json"
)

POLICY_PATH = (
    ROOT / "assets/data/canonical_monster_catalog_policy_v1.json"
)

EXPECTED_ACTIVE_COUNT = 214

RETIRED_IDS = (14, 16, 17)

ZOMBIE_IDS = (79, 80, 81, 82, 83, 84, 85)

RUNTIME_SAMPLES = (
    (45, "\u874e\u5b50"),           # 蝎子
    (48, "\u9ab7\u9ac50"),          # 骷髅0
    (79, "\u50f5\u5c381"),          # 僵尸1
    (80, "\u50f5\u5c3810"),         # 僵尸10
    (77, "\u6c83\u739b\u6559\u4e3b1"),  # 沃玛教主1
)

COMBAT_FIELD_MAP = {
    "level": "level",
    "exp": "exp",
    "hp": "hp",
    "defense": "defense",
    "magic_defense": "magicDefense",
    "attack_min": "attackMin",
    "attack_max": "attackMax",
}


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


project = load(PROJECT_PATH)

active_ids = {
    int(row["monsterId"])
    for row in project.get("records", [])
    if isinstance(row, dict)
    and row.get("recordStatus") != "retired"
    and int(row.get("monsterId", -1)) > 0
}

assert len(active_ids) == EXPECTED_ACTIVE_COUNT

for retired_id in RETIRED_IDS:
    assert retired_id not in active_ids

records_by_id = {
    int(row["monsterId"]): row
    for row in project.get("records", [])
    if isinstance(row, dict) and row.get("recordStatus") != "retired"
}

animation = load(ANIMATION_PATH)

animation_rows = {
    int(row["monster_id"]): row
    for row in animation.get("monsters", [])
    if isinstance(row, dict)
}

# 集合必须完全相等，不是仅仅数量相等。
assert set(animation_rows) == active_ids

animation_missing = sorted(active_ids - set(animation_rows))
animation_unresolved = sorted(
    mid
    for mid in active_ids
    if animation_rows[mid].get("status") != "formal"
)

assert not animation_missing
assert not animation_unresolved

for mid in sorted(active_ids):
    row = animation_rows[mid]
    assert row.get("monster_id") == mid
    # 每条 exact-ID record 必须能独立解析形态/资源。
    assert str(row.get("resource_lookup", ""))
    assert isinstance(row.get("frame_size", []), list)
    assert str(row.get("direction_mode", ""))

catalog = load(CATALOG_PATH)

entries = {
    int(entry["monster_id"]): entry
    for entry in catalog.get("entries", [])
}

assert set(entries) == active_ids

# P3B: 全部 active 可布置。
assert all(
    bool(entries[mid]["editor_placement"].get("allowed", False))
    for mid in sorted(active_ids)
)

policy = load(POLICY_PATH)

attribute_mismatch = []
drop_mismatch = []

for mid in sorted(active_ids):
    entry = entries[mid]

    # 属性/掉落永远属于该 monster_id 自己。
    expected_drop_id = f"drop.{mid}"
    if entry.get("drop_profile_id") != expected_drop_id:
        drop_mismatch.append((mid, entry.get("drop_profile_id"), expected_drop_id))

    stats = entry.get("combat", {}).get("stats", {})
    record = records_by_id[mid]

    # 68/69 使用 policy combat_override（已验收的 auxiliary 覆盖）。
    wooma_policy = policy.get("wooma_matrix", {}).get(str(mid), {})
    if isinstance(wooma_policy, dict) and isinstance(
        wooma_policy.get("combat_override"), dict
    ):
        continue

    for stat_field, vanilla_key in COMBAT_FIELD_MAP.items():
        expected = int(record.get(vanilla_key, 0))
        if int(stats.get(stat_field, 0)) != expected:
            attribute_mismatch.append(
                (mid, stat_field, stats.get(stat_field), expected)
            )

assert not attribute_mismatch, attribute_mismatch
assert not drop_mismatch, drop_mismatch

# 僵尸多形态专项：每个形态各自 exact-ID 独立解析，不要求相同。
zombie_matrix = []
for mid in ZOMBIE_IDS:
    row = animation_rows[mid]
    assert int(row["monster_id"]) == mid
    assert row.get("status") == "formal"
    zombie_matrix.append(
        {
            "monster_id": mid,
            "canonical_name": entries[mid]["canonical_name"],
            "animation_profile": entries[mid]["appearance_profile_id"],
            "resource_lookup": row.get("resource_lookup", ""),
            "frame_size": row.get("frame_size", []),
            "foot_anchor": row.get("foot_anchor", []),
        }
    )

# 运行时链样本：runtime monster_id 必须等于 animation authority
# lookup 使用的 monster_id。
runtime_animation_rows = []
for mid, expected_name in RUNTIME_SAMPLES:
    assert mid in active_ids
    row = animation_rows[mid]
    entry = entries[mid]
    assert str(entry.get("canonical_name", "")) == expected_name
    assert int(row["monster_id"]) == int(entry["monster_id"])
    runtime_animation_rows.append(
        {
            "runtime_monster_id": mid,
            "animation_authority_monster_id": row["monster_id"],
            "appearance_profile": entry["appearance_profile_id"],
            "resource_lookup": row.get("resource_lookup", ""),
        }
    )


def as_ascii(value: object) -> str:
    return json.dumps(value, ensure_ascii=True)


print(
    "P3B_EXACT_ID_ANIMATION_CLOSURE_PASS "
    f"ACTIVE_COUNT={len(active_ids)} "
    f"PLACEABLE_COUNT={sum(1 for e in entries.values() if e['editor_placement']['allowed'])} "
    f"EXACT_ID_ANIMATION_COUNT={len(animation_rows)} "
    f"ANIMATION_MISSING_COUNT={len(animation_missing)} "
    f"ANIMATION_UNRESOLVED_COUNT={len(animation_unresolved)} "
    f"RUNTIME_ALLOWED={sum(1 for e in entries.values() if e['runtime_allowed'])}"
)
print("ZOMBIE_ANIMATION_MATRIX=" + as_ascii(zombie_matrix))
print("RUNTIME_ANIMATION_RESULT=" + as_ascii(runtime_animation_rows))
print(
    "ATTRIBUTE_ID_MISMATCH_COUNT=0 "
    "DROP_ID_MISMATCH_COUNT=0 "
    "ZOMBIE_EXACT_ID_ANIMATION_PASS=true"
)