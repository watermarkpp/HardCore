#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from PIL import Image

from decor_grounding_policy import (
    GROUNDING_POLICY_ID,
    PLACEMENT_ANCHOR_POLICY_ID,
    calibrate_asset_geometry,
    category_occlusion,
    placement_anchor_px,
)


REPO = Path(__file__).resolve().parents[2]

CATALOG_REL = (
    "assets/data/assets/map_asset_catalog.json"
)

CATALOG_PATH = REPO / CATALOG_REL

EDITOR_ROOT = (
    REPO
    / "map_editor_workspace"
)

PRE_IMPORT_BASE = (
    "cf4ceb344d7a612104347917c1e32ef0392eeff6"
)

IMPORT_COMMIT = (
    "c4d260866935132b95a4a2498fe322acf7050e17"
)


def read_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8",
    ) as file:
        return json.load(file)


def load_catalog_at(commit: str):
    raw = subprocess.check_output(
        [
            "git",
            "show",
            f"{commit}:{CATALOG_REL}",
        ],
        cwd=str(REPO),
    )

    return json.loads(
        raw.decode("utf-8")
    )


def asset_map(catalog: dict):
    return {
        str(asset.get("asset_id", "")):
        asset
        for asset
        in catalog.get("assets", [])
    }


def new_batch_ids():
    pre = asset_map(
        load_catalog_at(
            PRE_IMPORT_BASE
        )
    )

    imported = asset_map(
        load_catalog_at(
            IMPORT_COMMIT
        )
    )

    return (
        set(imported)
        - set(pre)
    )


def category_from_asset(asset: dict):
    path = str(
        asset.get(
            "palette_path",
            "",
        )
    )

    if "/" not in path:
        return ""

    return path.rsplit(
        "/",
        1,
    )[-1]


def pair(value):
    if (
        isinstance(value, list)
        and len(value) == 2
    ):
        return [
            value[0],
            value[1],
        ]

    return [0, 0]


def almost_equal_pair(
    left,
    right,
    tolerance=0.01,
):
    if (
        len(left) != 2
        or len(right) != 2
    ):
        return False

    return (
        abs(
            float(left[0])
            - float(right[0])
        )
        <= tolerance

        and

        abs(
            float(left[1])
            - float(right[1])
        )
        <= tolerance
    )


def main():
    current = read_json(
        CATALOG_PATH
    )

    imported = load_catalog_at(
        IMPORT_COMMIT
    )

    current_assets = asset_map(
        current
    )

    imported_assets = asset_map(
        imported
    )

    batch_ids = new_batch_ids()

    target_ids = sorted(
        asset_id
        for asset_id in batch_ids
        if asset_id in current_assets
    )

    errors = []
    changed_footprints = 0

    for asset_id in target_ids:
        asset = current_assets[
            asset_id
        ]

        old_asset = imported_assets.get(
            asset_id,
            {},
        )

        category = category_from_asset(
            asset
        )

        image_rel = str(
            asset.get(
                "image",
                "",
            )
        )

        image_path = (
            REPO
            / image_rel
        )

        if not image_path.exists():
            errors.append(
                f"{asset_id}: missing image"
            )
            continue

        scale = float(
            asset.get(
                "approved_scale",
                1.0,
            )
        )

        with Image.open(
            image_path
        ) as image:
            expected = (
                calibrate_asset_geometry(
                    image,
                    category,
                    scale,
                )
            )

        actual_fp = pair(
            asset.get(
                "footprint_tiles",
                [],
            )
        )

        expected_fp = pair(
            expected.get(
                "footprint_tiles",
                [],
            )
        )

        if actual_fp != expected_fp:
            errors.append(
                f"{asset_id}: footprint "
                f"{actual_fp} != {expected_fp}"
            )

        old_fp = pair(
            old_asset.get(
                "footprint_tiles",
                [],
            )
        )

        if old_fp != actual_fp:
            changed_footprints += 1

        if (
            str(
                asset.get(
                    "grounding_policy_id",
                    "",
                )
            )
            != GROUNDING_POLICY_ID
        ):
            errors.append(
                f"{asset_id}: bad grounding policy"
            )

        if (
            str(
                asset.get(
                    "anchor_mode",
                    "",
                )
            )
            != "foot_tile"
        ):
            errors.append(
                f"{asset_id}: anchor_mode not foot_tile"
            )

        expected_occ = (
            category_occlusion(
                category
            )
        )

        if (
            bool(
                asset.get(
                    "occlusion",
                    False,
                )
            )
            != expected_occ
        ):
            errors.append(
                f"{asset_id}: occlusion mismatch"
            )

        if pair(
            asset.get(
                "anchor_px",
                [],
            )
        ) != pair(
            expected.get(
                "anchor_px",
                [],
            )
        ):
            errors.append(
                f"{asset_id}: anchor mismatch"
            )

        if (
            asset.get(
                "ground_contact_bounds_px",
                []
            )
            != expected.get(
                "ground_contact_bounds_px",
                []
            )
        ):
            errors.append(
                f"{asset_id}: ground contact mismatch"
            )

        # 本任务禁止擅自改变游戏碰撞策略。
        for key in [
            "collision_policy",
            "collision_profile_id",
            "navigation_policy",
        ]:
            if (
                key in old_asset
                and asset.get(key)
                != old_asset.get(key)
            ):
                errors.append(
                    f"{asset_id}: "
                    f"unexpected collision/navigation "
                    f"change: {key}"
                )

    checked_instances = 0

    if EDITOR_ROOT.exists():
        for editor_file in sorted(
            EDITOR_ROOT.rglob(
                "*.editor.json"
            )
        ):
            document = read_json(
                editor_file
            )

            layers = document.get(
                "layers",
                {},
            )

            if not isinstance(
                layers,
                dict,
            ):
                continue

            for entries in layers.values():
                if not isinstance(
                    entries,
                    list,
                ):
                    continue

                for instance in entries:
                    if not isinstance(
                        instance,
                        dict,
                    ):
                        continue

                    asset_id = str(
                        instance.get(
                            "asset_id",
                            "",
                        )
                    )

                    if asset_id not in target_ids:
                        continue

                    checked_instances += 1

                    asset = current_assets[
                        asset_id
                    ]

                    old_asset = imported_assets.get(
                        asset_id,
                        {},
                    )

                    old_fp = pair(
                        old_asset.get(
                            "footprint_tiles",
                            [1, 1],
                        )
                    )

                    instance_fp = pair(
                        instance.get(
                            "footprint_tiles",
                            [],
                        )
                    )

                    custom = bool(
                        instance.get(
                            "instance_custom_scale",
                            False,
                        )
                    )

                    if (
                        instance_fp != old_fp
                        and not bool(
                            instance.get(
                                "grounding_instance_migration",
                                ""
                            )
                        )
                    ):
                        custom = True

                    if not custom:
                        expected_fp = pair(
                            asset.get(
                                "footprint_tiles",
                                [],
                            )
                        )

                        if (
                            instance_fp
                            != expected_fp
                        ):
                            errors.append(
                                f"{editor_file.name}: "
                                f"{asset_id}: "
                                "instance footprint stale"
                            )

                    expected_occ = bool(
                        asset.get(
                            "occlusion",
                            False,
                        )
                    )

                    if (
                        bool(
                            instance.get(
                                "occlusion",
                                False,
                            )
                        )
                        != expected_occ
                    ):
                        errors.append(
                            f"{editor_file.name}: "
                            f"{asset_id}: "
                            "instance occlusion stale"
                        )

                    scale_default = float(
                        asset.get(
                            "approved_scale",
                            1.0,
                        )
                    )

                    scale = pair(
                        instance.get(
                            "scale",
                            [
                                scale_default,
                                scale_default,
                            ],
                        )
                    )

                    if (
                        not scale
                        or len(scale) != 2
                    ):
                        scale = [
                            scale_default,
                            scale_default,
                        ]

                    expected_anchor = (
                        placement_anchor_px(
                            pair(
                                asset.get(
                                    "anchor_px",
                                    [0, 0],
                                )
                            ),
                            instance_fp,
                            scale,
                        )
                    )

                    actual_anchor = pair(
                        instance.get(
                            "placement_anchor_px",
                            [],
                        )
                    )

                    if not almost_equal_pair(
                        actual_anchor,
                        expected_anchor,
                    ):
                        errors.append(
                            f"{editor_file.name}: "
                            f"{asset_id}: "
                            "instance placement anchor stale"
                        )

                    if (
                        str(
                            instance.get(
                                "placement_anchor_policy_id",
                                "",
                            )
                        )
                        != PLACEMENT_ANCHOR_POLICY_ID
                    ):
                        errors.append(
                            f"{editor_file.name}: "
                            f"{asset_id}: "
                            "bad placement anchor policy"
                        )

    print(
        f"CURRENT_BATCH_ASSETS={len(target_ids)}"
    )

    print(
        f"CHANGED_FOOTPRINTS={changed_footprints}"
    )

    print(
        f"CHECKED_EDITOR_INSTANCES={checked_instances}"
    )

    print(
        f"ERRORS={len(errors)}"
    )

    if errors:
        for error in errors:
            print(
                "ERROR:",
                error,
            )

        print(
            "NEW_DECOR_GROUNDING_VERIFY=FAIL"
        )

        raise SystemExit(1)

    print(
        "NEW_DECOR_GROUNDING_VERIFY=PASS"
    )


if __name__ == "__main__":
    main()
