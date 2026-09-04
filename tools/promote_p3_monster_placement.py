#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PROJECT_PATH = ROOT / "assets/data/vanilla_176/monsters.json"

CLASSIFICATION_PATH = (
    ROOT
    / "assets/data/canonical_monster_classification_v1.json"
)

EXPECTED_PRODUCTION_IDENTITY_COUNT = 214

PROMOTABLE_CLASSIFICATIONS = {
    "ordinary",
    "elite",
    "boss",
    "special",
    "non_hostile",
}

# 只有已经存在 exact-ID 地图刷新证据的记录自动解除旧 fail-closed。
#
# 不允许：
# exact_id_stats_crosscheck
# exact_id_internal_variant_no_spawn
# exact_id_user_adjudicated
# hidden suffix
# version_difference
#
# 自动晋升。
PROMOTABLE_RESOLUTIONS = {
    "exact_id_map_spawn_audit",
}


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"expected JSON object: {path}")
    return value


def production_ids() -> set[int]:
    project = load_json(PROJECT_PATH)

    ids = {
        int(row["monsterId"])
        for row in project.get("records", [])
        if isinstance(row, dict)
        and int(row.get("monsterId", -1)) > 0
        and row.get("recordStatus") != "retired"
    }

    if len(ids) != EXPECTED_PRODUCTION_IDENTITY_COUNT:
        raise RuntimeError(
            "production identity universe changed: "
            f"expected={EXPECTED_PRODUCTION_IDENTITY_COUNT} "
            f"actual={len(ids)}"
        )

    return ids


def promotable_rows(
    authority: dict,
    ids: set[int],
) -> list[int]:

    overrides = authority.get("exact_id_overrides", {})

    if not isinstance(overrides, dict):
        raise RuntimeError("exact_id_overrides must be a dictionary")

    result: list[int] = []

    for monster_id in sorted(ids):
        row = overrides.get(str(monster_id))

        if not isinstance(row, dict):
            continue

        classification = str(
            row.get("classification", "")
        )

        resolution = str(
            row.get("resolution", "")
        )

        placement_allowed = bool(
            row.get("placement_allowed", False)
        )

        if placement_allowed:
            continue

        if classification not in PROMOTABLE_CLASSIFICATIONS:
            continue

        if resolution not in PROMOTABLE_RESOLUTIONS:
            continue

        result.append(monster_id)

    return result


def apply_promotion(
    authority: dict,
    ids: set[int],
) -> list[int]:

    overrides = authority["exact_id_overrides"]

    changed: list[int] = []

    for monster_id in promotable_rows(authority, ids):
        row = overrides[str(monster_id)]

        row["placement_allowed"] = True

        row["placement_policy_resolution"] = (
            "p3_promoted_from_exact_id_map_spawn_audit"
        )

        row["placement_policy_evidence"] = (
            "existing exact monster_id map-spawn audit proves "
            "this identity is a formal map-spawn candidate"
        )

        changed.append(monster_id)

    return changed


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--check",
        action="store_true",
    )

    parser.add_argument(
        "--write",
        action="store_true",
    )

    args = parser.parse_args()

    if args.check == args.write:
        raise SystemExit(
            "use exactly one of --check or --write"
        )

    ids = production_ids()

    authority = load_json(CLASSIFICATION_PATH)

    pending = promotable_rows(
        authority,
        ids,
    )

    if args.check:
        if pending:
            print(
                "P3_PLACEMENT_PROMOTION_REQUIRED "
                f"count={len(pending)} "
                f"ids={pending}"
            )
            return 1

        print(
            "P3_PLACEMENT_POLICY_PASS "
            f"production_ids={len(ids)} "
            "pending=0"
        )

        return 0

    changed = apply_promotion(
        authority,
        ids,
    )

    CLASSIFICATION_PATH.write_text(
        json.dumps(
            authority,
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print(
        "P3_PLACEMENT_POLICY_UPDATED "
        f"production_ids={len(ids)} "
        f"changed={len(changed)} "
        f"ids={changed}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
