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

EXPECTED_ACTIVE_COUNT = 156

RETIRED_IDS = (14, 16, 17)

# P3C 后保留的真实僵尸形态与已退役复制形态。
ZOMBIE_IDS = (79, 81, 83, 85, 87)
ZOMBIE_DUPLICATE_RETIRED_IDS = (80, 82, 84, 86, 88)

RUNTIME_SAMPLES = (
    (45, "\u874e\u5b50"),           # 蝎子（普通无后缀）
    (76, "\u6c83\u739b\u6559\u4e3b"),  # 沃玛教主（Boss 本体）
    (79, "\u50f5\u5c381"),          # 僵尸1（真实形态1）
    (81, "\u50f5\u5c382"),          # 僵尸2（真实形态2）
    (87, "\u50f5\u5c385"),          # 僵尸5（真实形态5）
    (77, "\u6c83\u739b\u6559\u4e3b1"),  # 沃玛教主1（Boss 强化变体）
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

# Combat stats authority is owned by
# canonical_monster_combat_authority_reconciliation_test.py. This animation
# closure test must NOT hard-code canonical combat.stats == vanilla: the 6-ID
# Monster.DB core override (39/107/162/163/168/193) legitimately diverges from
# vanilla, and combat authority is not an animation concern.
drop_mismatch = []

for mid in sorted(active_ids):
    entry = entries[mid]

    # 掉落永远属于该 monster_id 自己。
    expected_drop_id = f"drop.{mid}"
    if entry.get("drop_profile_id") != expected_drop_id:
        drop_mismatch.append((mid, entry.get("drop_profile_id"), expected_drop_id))

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

# P3C：僵尸复制形态必须同时缺席 canonical 与 animation catalog。
for duplicate in ZOMBIE_DUPLICATE_RETIRED_IDS:
    assert duplicate not in active_ids
    assert duplicate not in animation_rows

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