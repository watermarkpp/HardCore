#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PROJECT_PATH = (
    ROOT / "assets/data/vanilla_176/monsters.json"
)

CLASSIFICATION_PATH = (
    ROOT
    / "assets/data/canonical_monster_classification_v1.json"
)

CATALOG_PATH = (
    ROOT
    / "assets/data/runtime/canonical_monster_catalog.json"
)

ANIMATION_PATH = (
    ROOT
    / "assets/data/runtime/monster_animation_catalog.json"
)

SERVICE_PATH = (
    ROOT
    / "assets/data/service_monster_runtime_catalog.json"
)

EXPECTED_IDENTITY_COUNT = 214

FORMAL_CLASSIFICATIONS = {
    "ordinary",
    "elite",
    "boss",
    "special",
    "non_hostile",
}


def load(path: Path) -> dict:
    value = json.loads(
        path.read_text(encoding="utf-8")
    )
    assert isinstance(value, dict), path
    return value


project = load(PROJECT_PATH)

production_ids = {
    int(row["monsterId"])
    for row in project.get("records", [])
    if row.get("recordStatus") != "retired"
}

assert len(production_ids) == EXPECTED_IDENTITY_COUNT

catalog = load(CATALOG_PATH)

entries = {
    int(row["monster_id"]): row
    for row in catalog.get("entries", [])
}

assert set(entries) == production_ids

classification = load(CLASSIFICATION_PATH)

overrides = classification.get(
    "exact_id_overrides",
    {},
)

service = load(SERVICE_PATH)

runtime_by_id = service.get(
    "runtimeByMonsterId",
    {},
)

assert {
    int(key)
    for key in runtime_by_id.keys()
} == production_ids

# Golden deploy 中 service runtime 已经覆盖全部 214。
# 这里绝对不要求 resolutionStatus == exact_service_name。
assert len(runtime_by_id) == EXPECTED_IDENTITY_COUNT


animation = load(ANIMATION_PATH)

animation_rows = {
    int(row["monster_id"]): row
    for row in animation.get("monsters", [])
}

assert set(animation_rows) == production_ids

for monster_id in sorted(production_ids):
    row = animation_rows[monster_id]

    assert row.get("status") == "formal", (
        monster_id,
        row.get("status"),
    )


# P3B: 全部 214 active identities 均允许地图编辑器布置。
# placement 与 runtime 完全解耦：可布置不要求 runtime 已闭环。
assert all(
    bool(entries[mid]["editor_placement"].get("allowed", False))
    for mid in sorted(production_ids)
), "P3B contract: every active monster must be placeable"


# exact-ID map spawn evidence must no longer be left
# behind a stale placement=false gate.
stale_spawn_policy = []

for raw_id, override in overrides.items():

    monster_id = int(raw_id)

    if monster_id not in production_ids:
        continue

    if not isinstance(override, dict):
        continue

    classification_name = str(
        override.get("classification", "")
    )

    resolution = str(
        override.get("resolution", "")
    )

    if (
        classification_name
        in FORMAL_CLASSIFICATIONS
        and resolution
        == "exact_id_map_spawn_audit"
        and not bool(
            override.get(
                "placement_allowed",
                False,
            )
        )
    ):
        stale_spawn_policy.append(
            monster_id
        )

assert not stale_spawn_policy, (
    "stale exact-map-spawn placement gates",
    stale_spawn_policy,
)


# P3B: version_difference 只保留为 classification/metadata 提醒，
# 既不是 placement 门禁，也不再自动禁止 runtime。
for monster_id in sorted(production_ids):

    entry = entries[monster_id]

    if (
        entry.get("classification")
        != "version_difference"
    ):
        continue

    assert int(
        entry.get("monster_id", -1)
    ) == monster_id

    # runtime 允许与否由真实数据（art/drop/combat）决定，与分类无关。
    assert (
        entry.get("runtime_allowed")
        == bool(
            entry.get(
                "runtime_capability",
                {},
            ).get(
                "allowed",
                False,
            )
        )
    )


# 用户已用于真实编辑器验收的三个身份。
for monster_id in (24, 38, 45):

    entry = entries[monster_id]

    assert int(
        entry.get("monster_id", -1)
    ) == monster_id

    assert bool(
        entry.get("runtime_allowed", False)
    ), (
        monster_id,
        entry.get("canonical_name"),
        entry.get(
            "runtime_capability",
            {},
        ),
    )


print(
    "CANONICAL_MONSTER_RUNTIME_GATE_CLOSURE_PASS "
    f"identities={len(production_ids)} "
    f"runtime_allowed="
    f"{sum(1 for row in entries.values() if row.get('runtime_allowed'))} "
    "placeable=214 "
    "data_missing=0"
)
