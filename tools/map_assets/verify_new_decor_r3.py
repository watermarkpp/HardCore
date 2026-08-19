from __future__ import annotations

from collections import Counter

from PIL import Image

from new_decor_r3_common import (
    CATALOG_PATH,
    CATALOG_REL,
    R2_BASE_SHA,
    REPO_ROOT,
    UNRESOLVED_PATH,
    WHITE_CATEGORIES,
    asset_map,
    category_cn,
    git_json,
    is_split_cage,
    is_target_asset,
    load_json,
    original_new_batch_ids,
    positive_int_pair,
)

from clean_new_decor_white_residue_r3 import (
    opaque_white_review_pixels,
    safe_white_residue_pixels,
)


def main() -> None:
    errors = []

    catalog = load_json(
        CATALOG_PATH
    )

    current = asset_map(
        catalog
    )

    batch_ids = original_new_batch_ids()

    target_ids = {
        asset_id
        for asset_id, asset
        in current.items()
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
    }

    # --------------------------------------------------
    # 1. 旧素材绝对不能被修改
    # --------------------------------------------------

    base_catalog = git_json(
        R2_BASE_SHA,
        CATALOG_REL,
    )

    base_assets = asset_map(
        base_catalog
    )

    old_modified = []

    for asset_id, old_asset in (
        base_assets.items()
    ):
        if asset_id in target_ids:
            continue

        current_asset = current.get(
            asset_id
        )

        if current_asset != old_asset:
            old_modified.append(
                asset_id
            )

    if old_modified:
        errors.append(
            "OLD_ASSETS_MODIFIED="
            + ",".join(old_modified)
        )

    # --------------------------------------------------
    # 2. 所有目标素材必须有权威 geometry
    # --------------------------------------------------

    unresolved_file = []

    if UNRESOLVED_PATH.exists():
        value = load_json(
            UNRESOLVED_PATH
        )

        if isinstance(value, list):
            unresolved_file = value

    if unresolved_file:
        errors.append(
            "UNRESOLVED_GEOMETRY="
            f"{len(unresolved_file)}"
        )

    bad_authority = []

    bad_footprint = []

    rectangular_count = 0

    for asset_id in sorted(
        target_ids
    ):
        asset = current[
            asset_id
        ]

        authority = str(
            asset.get(
                "geometry_authority",
                "",
            )
        )

        if authority not in {
            "source_meta",
            "manual_override",
        }:
            bad_authority.append(
                asset_id
            )

        footprint = positive_int_pair(
            asset.get(
                "footprint_tiles"
            )
        )

        if footprint is None:
            bad_footprint.append(
                asset_id
            )
            continue

        if footprint[0] != footprint[1]:
            rectangular_count += 1

        for key in (
            "visual_footprint_tiles",
            "occupancy_footprint_tiles",
            "base_footprint_tiles",
        ):
            if asset.get(key) != footprint:
                errors.append(
                    f"{asset_id}:"
                    f"{key}_MISMATCH"
                )

    if bad_authority:
        errors.append(
            "BAD_GEOMETRY_AUTHORITY="
            + ",".join(
                bad_authority
            )
        )

    if bad_footprint:
        errors.append(
            "BAD_FOOTPRINT="
            + ",".join(
                bad_footprint
            )
        )

    # --------------------------------------------------
    # 3. 囚笼必须是 8 个独立可摆放素材
    # --------------------------------------------------

    cages = [
        asset
        for asset in current.values()
        if (
            is_split_cage(asset)
            and bool(
                asset.get(
                    "placeable",
                    False,
                )
            )
        )
    ]

    if len(cages) != 8:
        errors.append(
            "PLACEABLE_SPLIT_CAGE_COUNT="
            f"{len(cages)}"
        )

    cage_bad_depth = []

    for asset in cages:
        footprint = positive_int_pair(
            asset.get(
                "footprint_tiles"
            )
        )

        if footprint is None:
            cage_bad_depth.append(
                str(
                    asset.get(
                        "asset_id",
                        "",
                    )
                )
            )
            continue

        # 已经人工证明 [2,1]/[3,1]
        # 这种一格深度是错误的。
        if min(footprint) < 2:
            cage_bad_depth.append(
                str(
                    asset.get(
                        "asset_id",
                        "",
                    )
                )
            )

    if cage_bad_depth:
        errors.append(
            "CAGE_ONE_TILE_DEPTH="
            + ",".join(
                cage_bad_depth
            )
        )

    # --------------------------------------------------
    # 4. 白色背景残留
    # --------------------------------------------------

    white_safe_remaining = 0
    opaque_review_pixels = 0
    opaque_review_assets = 0

    white_counts = Counter()

    for asset_id in sorted(
        target_ids
    ):
        asset = current[
            asset_id
        ]

        category = category_cn(asset)

        if category not in WHITE_CATEGORIES:
            continue

        image_path = (
            REPO_ROOT
            / str(
                asset.get(
                    "image",
                    "",
                )
            )
        )

        if not image_path.is_file():
            errors.append(
                f"MISSING_IMAGE={asset_id}"
            )
            continue

        image = Image.open(
            image_path
        ).convert("RGBA")

        safe_remaining = len(
            safe_white_residue_pixels(
                image
            )
        )

        opaque_review = len(
            opaque_white_review_pixels(
                image
            )
        )

        white_safe_remaining += (
            safe_remaining
        )

        opaque_review_pixels += (
            opaque_review
        )

        if opaque_review > 0:
            opaque_review_assets += 1

        white_counts[
            category
        ] += 1

    if white_safe_remaining != 0:
        errors.append(
            "SAFE_WHITE_RESIDUE_REMAINING="
            f"{white_safe_remaining}"
        )

    # opaque near-white 不能自动删。
    # 有的话必须人工看 preview。
    if opaque_review_assets != 0:
        errors.append(
            "OPAQUE_WHITE_REVIEW_ASSETS="
            f"{opaque_review_assets}"
        )

    # --------------------------------------------------
    # 5. 静态确认缩放体系仍然存在
    # --------------------------------------------------

    instance_service = (
        REPO_ROOT
        / "scripts"
        / "map_editor"
        / "map_editor_instance_service.gd"
    ).read_text(
        encoding="utf-8"
    )

    required_resize_tokens = [
        "base_footprint_tiles",
        "resized_visual_scale",
        "if int(base_fp[0]) == int(base_fp[1]):",
        "elif int(base_fp[0]) > int(base_fp[1]):",
        "var height := maxi(1, old_height + (1 if direction > 0 else -1))",
        "PlacementAnchorPolicy.refresh_custom_instance",
    ]

    missing_resize_tokens = [
        token
        for token in required_resize_tokens
        if token not in instance_service
    ]

    if missing_resize_tokens:
        errors.append(
            "RESIZE_CONTRACT_MISSING="
            + ",".join(
                missing_resize_tokens
            )
        )

    # --------------------------------------------------
    # 6. 输出
    # --------------------------------------------------

    print(
        f"TARGET_ASSETS={len(target_ids)}"
    )

    print(
        "RECTANGULAR_FOOTPRINT_COUNT="
        f"{rectangular_count}"
    )

    print(
        "PLACEABLE_SPLIT_CAGE_COUNT="
        f"{len(cages)}"
    )

    print(
        "UNRESOLVED_GEOMETRY="
        f"{len(unresolved_file)}"
    )

    print(
        "SAFE_WHITE_RESIDUE_REMAINING="
        f"{white_safe_remaining}"
    )

    print(
        "OPAQUE_WHITE_REVIEW_ASSETS="
        f"{opaque_review_assets}"
    )

    print(
        "OPAQUE_WHITE_REVIEW_PIXELS="
        f"{opaque_review_pixels}"
    )

    print(
        "OLD_ASSETS_MODIFIED="
        f"{len(old_modified)}"
    )

    print(
        "RESIZE_CONTRACT_CHECK="
        + (
            "PASS"
            if not missing_resize_tokens
            else "FAIL"
        )
    )

    print(
        "ERRORS="
        f"{len(errors)}"
    )

    for error in errors:
        print(
            "ERROR="
            + error
        )

    if errors:
        print(
            "NEW_DECOR_R3_VERIFY=FAIL"
        )
        raise SystemExit(1)

    print(
        "NEW_DECOR_R3_VERIFY=PASS"
    )


if __name__ == "__main__":
    main()
