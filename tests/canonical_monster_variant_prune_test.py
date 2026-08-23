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

SERVICE_PATH = (
    ROOT / "assets/data/service_monster_runtime_catalog.json"
)

EXPECTED_ACTIVE_COUNT = 156

# P3C 固定退役名单（58 个）。不得增删。
RETIRE_IDS = [
    23, 25, 27, 29, 35, 37, 44, 48, 49, 51, 53, 63, 65, 67, 69, 71,
    80, 82, 84, 86, 88,
    93, 95, 98, 102, 106, 108, 111, 113, 115, 117, 119,
    130, 139, 149, 151, 154,
    165, 167, 169, 171, 173, 175, 177, 179, 184, 197,
    201, 203, 205, 207,
    211, 213, 215, 217, 219, 221, 223,
]

assert len(RETIRE_IDS) == 58
assert len(set(RETIRE_IDS)) == 58

RETIRE_SET = set(RETIRE_IDS)

# 精英/Boss/强化变体、多形态普通怪、特殊/召唤/脚本实体：必须保留 active。
KEEP_IDS = {
    39, 41,
    55, 57, 59,
    74, 75, 77, 78,
    79, 81, 83, 85, 87,
    90, 91,
    121, 122, 123,
    131, 134, 136, 137, 140,
    145, 146, 147,
    152, 155, 157, 158, 159, 161,
    189, 190, 192, 199, 209,
    226, 227, 228, 229, 230, 231, 232, 233, 234,
}

EXPECTED_ZOMBIE_TRUE_FORMS = {79, 81, 83, 85, 87}
EXPECTED_ZOMBIE_DUPLICATES_RETIRED = {80, 82, 84, 86, 88}

RETIRED_BASELINE = {14, 16, 17}


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


project = load(PROJECT_PATH)

records = project.get("records", [])
by_id = {int(r.get("monsterId", -1)): r for r in records if isinstance(r, dict)}
assert len(by_id) == len(records), "duplicate monsterId"

retired_ids = {
    mid for mid, row in by_id.items() if row.get("recordStatus") == "retired"
}

# 本施工单 58 个固定 ID 必须全部 retired。
for mid in RETIRE_IDS:
    assert mid in retired_ids, "retire id %d not retired" % mid
    assert by_id[mid].get("recordStatus") == "retired"
    assert "P3C" in str(by_id[mid].get("retirementReason", "")), mid

# 既有退役基线保持。
assert RETIRED_BASELINE <= retired_ids

# KEEP_IDS 全部 active。
for mid in KEEP_IDS:
    assert mid in by_id and by_id[mid].get("recordStatus") != "retired", (
        "keep id %d must stay active" % mid
    )

assert len(retired_ids) == 58 + len(RETIRED_BASELINE) == 61
active_ids = {
    mid for mid, row in by_id.items() if row.get("recordStatus") != "retired"
}
assert len(active_ids) == EXPECTED_ACTIVE_COUNT

# 僵尸真实形态 active / 复制形态 retired。
assert EXPECTED_ZOMBIE_TRUE_FORMS <= active_ids
assert EXPECTED_ZOMBIE_DUPLICATES_RETIRED <= retired_ids

# canonical / animation / service universe 全部 == active universe。
catalog = load(CATALOG_PATH)
canonical_ids = {int(e["monster_id"]) for e in catalog["entries"]}
assert canonical_ids == active_ids

animation = load(ANIMATION_PATH)
animation_ids = {int(r["monster_id"]) for r in animation["monsters"]}
assert animation_ids == active_ids

service = load(SERVICE_PATH)
service_ids = {int(k) for k in service["runtimeByMonsterId"].keys()}
assert service_ids == active_ids

# 退役 ID 不得出现在任何 production artifact。
for mid in RETIRE_IDS:
    assert mid not in canonical_ids
    assert mid not in animation_ids
    assert mid not in service_ids

print(
    "P3C_MONSTER_VARIANT_PRUNE_PASS "
    f"active={len(active_ids)} "
    f"retired={len(retired_ids)} "
    f"retire_list={len(RETIRE_IDS)} "
    "zombie_true_forms=79,81,83,85,87 "
    "zombie_duplicates_retired=80,82,84,86,88"
)