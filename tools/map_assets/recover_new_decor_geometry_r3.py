from __future__ import annotations

import argparse
import copy
from collections import Counter

from new_decor_r3_common import (
    CATALOG_PATH,
    GEOMETRY_REPORT_PATH,
    MANUAL_OVERRIDE_PATH,
    UNRESOLVED_PATH,
    asset_map,
    build_source_metadata_index,
    category_cn,
    collision_snapshot,
    is_target_asset,
    load_json,
    match_asset_to_source_meta,
    numeric_pair,
    original_new_batch_ids,
    positive_int_pair,
    save_json,
)


def load_manual_overrides() -> dict:
    if not MANUAL_OVERRIDE_PATH.exists():
        save_json(
            MANUAL_OVERRIDE_PATH,
            {},
        )
        return {}

    value = load_json(
        MANUAL_OVERRIDE_PATH
    )

    if not isinstance(value, dict):
        raise SystemExit(
            "MANUAL_OVERRIDE_FILE_MUST_BE_OBJECT"
        )

    return value


def apply_geometry(
    asset: dict,
    geometry: dict,
    authority: str,
    source: str,
) -> None:
    footprint = positive_int_pair(
        geometry.get("footprint_tiles")
    )

    if footprint is None:
        raise ValueError(
            "invalid authoritative footprint"
        )

    # 保存碰撞/导航数据。
    collision_before = collision_snapshot(
        asset
    )

    asset["footprint_tiles"] = (
        footprint.copy()
    )
    asset["visual_footprint_tiles"] = (
        footprint.copy()
    )
    asset["occupancy_footprint_tiles"] = (
        footprint.copy()
    )
    asset["base_footprint_tiles"] = (
        footprint.copy()
    )

    # authoritative anchor 有就采用。
    # manual override 没有 anchor 时，
    # 保留素材现有 source anchor。
    anchor = numeric_pair(
        geometry.get("anchor_px")
    )

    if anchor is not None:
        asset["anchor_px"] = [
            anchor[0],
            anchor[1],
        ]

    # placement_anchor_px 在 raw catalog
    # 保存 source anchor。
    # catalog service 会继续执行项目已有
    # footprint_bottom_vertex_v1。
    source_anchor = numeric_pair(
        asset.get("anchor_px")
    )

    if source_anchor is not None:
        asset["placement_anchor_px"] = [
            source_anchor[0],
            source_anchor[1],
        ]

    asset["anchor_mode"] = "foot_tile"

    if (
        "visible_bounds_px"
        in geometry
        and isinstance(
            geometry["visible_bounds_px"],
            list,
        )
        and len(
            geometry["visible_bounds_px"]
        ) == 4
    ):
        asset["visible_bounds_px"] = [
            int(v)
            for v in geometry[
                "visible_bounds_px"
            ]
        ]

    if isinstance(
        geometry.get("occlusion"),
        bool,
    ):
        asset["occlusion"] = bool(
            geometry["occlusion"]
        )

    for key in (
        "sort_baseline_tile_offset",
        "sort_baseline_offset_px",
    ):
        pair = numeric_pair(
            geometry.get(key)
        )

        if pair is not None:
            asset[key] = [
                pair[0],
                pair[1],
            ]

    if "approved_scale" in geometry:
        try:
            approved_scale = float(
                geometry["approved_scale"]
            )

            if approved_scale > 0:
                asset["approved_scale"] = (
                    approved_scale
                )
        except Exception:
            pass

    asset["geometry_authority"] = (
        authority
    )

    asset[
        "footprint_calibration_source"
    ] = source

    asset[
        "ground_contact_is_advisory"
    ] = True

    # R1/R2 的 bottom-contact 结果
    # 不再作为 geometry authority。
    asset.pop(
        "grounding_policy_id",
        None,
    )
    asset.pop(
        "grounding_policy_version",
        None,
    )
    asset.pop(
        "fallback_inferred",
        None,
    )

    # 碰撞和导航绝对不能被本任务修改。
    collision_after = collision_snapshot(
        asset
    )

    if collision_before != collision_after:
        raise RuntimeError(
            "collision/navigation changed unexpectedly"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
    )
    args = parser.parse_args()

    catalog = load_json(
        CATALOG_PATH
    )

    working = copy.deepcopy(
        catalog
    )

    assets = asset_map(
        working
    )

    batch_ids = original_new_batch_ids()

    target_ids = sorted(
        asset_id
        for asset_id, asset
        in assets.items()
        if (
            is_target_asset(
                asset,
                batch_ids,
            )
            and bool(
                asset.get(
                    "placeable",
                    True,
                )
            )
        )
    )

    overrides = load_manual_overrides()

    source_index = (
        build_source_metadata_index()
    )

    fixed_source = []
    fixed_manual = []
    unresolved = []

    category_counts = Counter()

    for asset_id in target_ids:
        asset = assets[asset_id]

        category = category_cn(asset)

        category_counts[category] += 1

        manual = overrides.get(asset_id)

        if isinstance(manual, dict):
            footprint = positive_int_pair(
                manual.get(
                    "footprint_tiles"
                )
            )

            if footprint is not None:
                geometry = {
                    "footprint_tiles":
                        footprint,
                }

                anchor = numeric_pair(
                    manual.get(
                        "anchor_px"
                    )
                )

                if anchor is not None:
                    geometry[
                        "anchor_px"
                    ] = anchor

                if isinstance(
                    manual.get("occlusion"),
                    bool,
                ):
                    geometry[
                        "occlusion"
                    ] = bool(
                        manual[
                            "occlusion"
                        ]
                    )

                apply_geometry(
                    asset,
                    geometry,
                    "manual_override",
                    str(
                        MANUAL_OVERRIDE_PATH
                    ),
                )

                fixed_manual.append(
                    asset_id
                )

                continue

        candidate, match_method = (
            match_asset_to_source_meta(
                asset,
                source_index,
            )
        )

        if candidate is None:
            unresolved.append({
                "asset_id": asset_id,
                "display_name": str(
                    asset.get(
                        "display_name",
                        "",
                    )
                ),
                "category": category,
                "image": str(
                    asset.get(
                        "image",
                        "",
                    )
                ),
                "current_footprint": (
                    asset.get(
                        "footprint_tiles",
                        [1, 1],
                    )
                ),
                "source_external_path": str(
                    asset.get(
                        "source_external_path",
                        "",
                    )
                ),
                "reason": match_method,
            })
            continue

        geometry = candidate[
            "geometry"
        ]

        apply_geometry(
            asset,
            geometry,
            "source_meta",
            str(
                candidate.get(
                    "source",
                    "",
                )
            ),
        )

        fixed_source.append(
            asset_id
        )

    # 把修改后的 asset 写回原顺序 catalog。
    modified_map = asset_map(
        working
    )

    for index, asset in enumerate(
        working.get("assets", [])
    ):
        asset_id = str(
            asset.get(
                "asset_id",
                "",
            )
        )

        if asset_id in modified_map:
            working["assets"][index] = (
                modified_map[asset_id]
            )

    save_json(
        UNRESOLVED_PATH,
        unresolved,
    )

    lines = [
        "# New Decor Authoritative Geometry R3",
        "",
        f"TARGET_ASSETS = {len(target_ids)}",
        (
            "SOURCE_METADATA_CANDIDATES = "
            f"{len(source_index.all_candidates)}"
        ),
        (
            "AUTHORITATIVE_META_FOUND = "
            f"{len(fixed_source)}"
        ),
        (
            "MANUAL_OVERRIDES = "
            f"{len(fixed_manual)}"
        ),
        (
            "UNRESOLVED_GEOMETRY = "
            f"{len(unresolved)}"
        ),
        "",
        "## Category Counts",
        "",
    ]

    for category in sorted(
        category_counts
    ):
        lines.append(
            f"- {category}: "
            f"{category_counts[category]}"
        )

    lines.extend([
        "",
        "## Unresolved",
        "",
    ])

    for entry in unresolved:
        lines.append(
            "- "
            f"{entry['asset_id']} | "
            f"{entry['category']} | "
            f"{entry['image']} | "
            f"{entry['reason']}"
        )

    GEOMETRY_REPORT_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    GEOMETRY_REPORT_PATH.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print(
        f"TARGET_ASSETS={len(target_ids)}"
    )
    print(
        "SOURCE_METADATA_CANDIDATES="
        f"{len(source_index.all_candidates)}"
    )
    print(
        "AUTHORITATIVE_META_FOUND="
        f"{len(fixed_source)}"
    )
    print(
        "MANUAL_OVERRIDES="
        f"{len(fixed_manual)}"
    )
    print(
        "UNRESOLVED_GEOMETRY="
        f"{len(unresolved)}"
    )

    if args.apply:
        save_json(
            CATALOG_PATH,
            working,
        )
        print(
            "AUTHORITATIVE_GEOMETRY_APPLY=OK"
        )
    else:
        print(
            "AUTHORITATIVE_GEOMETRY_DRY_RUN=OK"
        )

    if unresolved:
        print(
            "GEOMETRY_FINAL=NEEDS_MANUAL_OVERRIDES"
        )
    else:
        print(
            "GEOMETRY_FINAL=PASS"
        )


if __name__ == "__main__":
    main()
