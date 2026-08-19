#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import copy
import json
import shutil
import subprocess
from pathlib import Path

from decor_grounding_policy import (
    PLACEMENT_ANCHOR_POLICY_ID,
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

REPORT_DIR = (
    REPO
    / "docs"
    / "mafa_scene_editor"
)

REPORT_PATH = (
    REPORT_DIR
    / "new_decor_instance_migration_report.md"
)

BACKUP_ROOT = (
    REPORT_DIR
    / "backups"
    / "new_decor_grounding_v1"
    / "editor_maps"
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


def write_json(
    path: Path,
    data,
):
    with path.open(
        "w",
        encoding="utf-8",
        newline="\n",
    ) as file:
        json.dump(
            data,
            file,
            ensure_ascii=False,
            indent=2,
        )
        file.write("\n")


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
    pre = load_catalog_at(
        PRE_IMPORT_BASE
    )

    imported = load_catalog_at(
        IMPORT_COMMIT
    )

    return (
        set(asset_map(imported))
        - set(asset_map(pre))
    )


def as_pair(
    value,
    fallback,
):
    if (
        isinstance(value, list)
        and len(value) == 2
    ):
        return [
            value[0],
            value[1],
        ]

    return [
        fallback[0],
        fallback[1],
    ]


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--apply",
        action="store_true",
    )

    args = parser.parse_args()

    current_catalog = read_json(
        CATALOG_PATH
    )

    imported_catalog = load_catalog_at(
        IMPORT_COMMIT
    )

    current_assets = asset_map(
        current_catalog
    )

    imported_assets = asset_map(
        imported_catalog
    )

    batch_ids = new_batch_ids()

    if not EDITOR_ROOT.exists():
        print(
            "EDITOR_ROOT_NOT_FOUND"
        )
        print(
            "No editor maps need migration."
        )
        return

    editor_files = sorted(
        EDITOR_ROOT.rglob(
            "*.editor.json"
        )
    )

    touched_files = 0
    migrated_instances = 0
    custom_instances_preserved = 0
    unchanged_instances = 0

    file_rows = []

    for editor_file in editor_files:
        document = read_json(
            editor_file
        )

        layers = document.get(
            "layers",
            {},
        )

        file_changed = False
        file_migrated = 0
        file_custom = 0

        if not isinstance(
            layers,
            dict,
        ):
            continue

        for layer_name, entries in layers.items():
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

                if asset_id not in batch_ids:
                    continue

                asset = current_assets.get(
                    asset_id
                )

                old_asset = imported_assets.get(
                    asset_id
                )

                if not asset:
                    continue

                new_base_fp = as_pair(
                    asset.get(
                        "footprint_tiles",
                        [1, 1],
                    ),
                    [1, 1],
                )

                old_base_fp = (
                    as_pair(
                        old_asset.get(
                            "footprint_tiles",
                            [1, 1],
                        ),
                        [1, 1],
                    )
                    if old_asset
                    else [1, 1]
                )

                current_fp = as_pair(
                    instance.get(
                        "footprint_tiles",
                        old_base_fp,
                    ),
                    old_base_fp,
                )

                is_custom = bool(
                    instance.get(
                        "instance_custom_scale",
                        False,
                    )
                )

                # 如果实例 footprint 与旧批次基础 footprint 不一致，
                # 说明用户可能手动调整过。
                if current_fp != old_base_fp:
                    is_custom = True

                if is_custom:
                    final_fp = current_fp
                    custom_instances_preserved += 1
                    file_custom += 1
                else:
                    final_fp = new_base_fp

                    instance[
                        "footprint_tiles"
                    ] = copy.deepcopy(
                        new_base_fp
                    )

                    instance[
                        "visual_footprint_tiles"
                    ] = copy.deepcopy(
                        new_base_fp
                    )

                    instance[
                        "occupancy_footprint_tiles"
                    ] = copy.deepcopy(
                        new_base_fp
                    )

                    file_changed = True

                scale_fallback = float(
                    asset.get(
                        "approved_scale",
                        1.0,
                    )
                )

                scale = as_pair(
                    instance.get(
                        "scale",
                        [
                            scale_fallback,
                            scale_fallback,
                        ],
                    ),
                    [
                        scale_fallback,
                        scale_fallback,
                    ],
                )

                source_anchor = as_pair(
                    asset.get(
                        "anchor_px",
                        [0, 0],
                    ),
                    [0, 0],
                )

                effective_anchor = (
                    placement_anchor_px(
                        source_anchor,
                        final_fp,
                        scale,
                    )
                )

                instance[
                    "anchor_px"
                ] = [
                    effective_anchor[0],
                    effective_anchor[1],
                ]

                instance[
                    "placement_anchor_px"
                ] = [
                    effective_anchor[0],
                    effective_anchor[1],
                ]

                instance[
                    "anchor_mode"
                ] = "foot_tile"

                instance[
                    "placement_anchor_policy_id"
                ] = (
                    PLACEMENT_ANCHOR_POLICY_ID
                )

                instance[
                    "occlusion"
                ] = bool(
                    asset.get(
                        "occlusion",
                        False,
                    )
                )

                instance[
                    "instance_base_footprint_tiles"
                ] = copy.deepcopy(
                    new_base_fp
                )

                instance[
                    "instance_base_scale"
                ] = float(
                    asset.get(
                        "approved_scale",
                        1.0,
                    )
                )

                # 碰撞只同步 catalog 现有值。
                # 本任务绝对不发明新碰撞。
                for key in [
                    "collision_policy",
                    "collision_profile_id",
                    "collision_footprint_tiles",
                    "collision_cells",
                    "navigation_policy",
                    "manual_collision_expected",
                    "map_collision_override",
                    "collision_authority",
                    "collision_policy_id",
                ]:
                    if key in asset:
                        instance[key] = (
                            copy.deepcopy(
                                asset[key]
                            )
                        )

                instance[
                    "grounding_policy_id"
                ] = str(
                    asset.get(
                        "grounding_policy_id",
                        "",
                    )
                )

                instance[
                    "grounding_instance_migration"
                ] = (
                    "MSE-NEW-DECOR-GROUNDING-R1"
                )

                file_changed = True
                file_migrated += 1
                migrated_instances += 1

        if not file_changed:
            unchanged_instances += 1
            continue

        touched_files += 1

        file_rows.append(
            (
                str(
                    editor_file.relative_to(
                        EDITOR_ROOT
                    )
                ),
                file_migrated,
                file_custom,
            )
        )

        if args.apply:
            relative = editor_file.relative_to(
                EDITOR_ROOT
            )

            backup_file = (
                BACKUP_ROOT
                / relative
            )

            backup_file.parent.mkdir(
                parents=True,
                exist_ok=True,
            )

            if not backup_file.exists():
                shutil.copy2(
                    editor_file,
                    backup_file,
                )

            write_json(
                editor_file,
                document,
            )

    print(
        f"EDITOR_FILES={len(editor_files)}"
    )

    print(
        f"TOUCHED_FILES={touched_files}"
    )

    print(
        f"MIGRATED_INSTANCES={migrated_instances}"
    )

    print(
        "CUSTOM_INSTANCES_PRESERVED="
        f"{custom_instances_preserved}"
    )

    if not args.apply:
        print(
            "DRY_RUN_OK"
        )
        print(
            "Use --apply to write migrated maps."
        )
        return

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    lines = [
        "# New Decoration Instance Migration Report",
        "",
        f"TOUCHED_FILES = {touched_files}",
        f"MIGRATED_INSTANCES = {migrated_instances}",
        (
            "CUSTOM_INSTANCES_PRESERVED = "
            f"{custom_instances_preserved}"
        ),
        "",
        "## Files",
        "",
        "| file | migrated | custom footprint preserved |",
        "|---|---:|---:|",
    ]

    for (
        filename,
        migrated,
        custom,
    ) in file_rows:
        lines.append(
            f"| {filename} | {migrated} | {custom} |"
        )

    REPORT_PATH.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print(
        f"WROTE_REPORT={REPORT_PATH}"
    )

    print(
        "INSTANCE_MIGRATION_APPLY_OK"
    )


if __name__ == "__main__":
    main()
