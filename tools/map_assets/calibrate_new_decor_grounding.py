#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

from decor_grounding_policy import (
    GROUNDING_POLICY_ID,
    calibrate_asset_geometry,
    category_occlusion,
)


REPO = Path(__file__).resolve().parents[2]

CATALOG_REL = (
    "assets/data/assets/map_asset_catalog.json"
)

CATALOG_PATH = REPO / CATALOG_REL

PRE_IMPORT_BASE = (
    "cf4ceb344d7a612104347917c1e32ef0392eeff6"
)

IMPORT_COMMIT = (
    "c4d260866935132b95a4a2498fe322acf7050e17"
)

REPORT_DIR = (
    REPO
    / "docs"
    / "mafa_scene_editor"
)

REPORT_PATH = (
    REPORT_DIR
    / "new_decor_grounding_repair_report.md"
)

BACKUP_DIR = (
    REPORT_DIR
    / "backups"
    / "new_decor_grounding_v1"
)

BACKUP_CATALOG = (
    BACKUP_DIR
    / "map_asset_catalog.before.json"
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
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

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


def new_batch_ids():
    pre = load_catalog_at(
        PRE_IMPORT_BASE
    )

    imported = load_catalog_at(
        IMPORT_COMMIT
    )

    pre_ids = {
        str(asset.get("asset_id", ""))
        for asset in pre.get("assets", [])
    }

    import_ids = {
        str(asset.get("asset_id", ""))
        for asset in imported.get("assets", [])
    }

    return import_ids - pre_ids


def category_from_asset(asset: dict) -> str:
    palette_path = str(
        asset.get("palette_path", "")
    )

    if "/" not in palette_path:
        return ""

    return palette_path.rsplit(
        "/",
        1,
    )[-1]


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually write catalog changes",
    )

    args = parser.parse_args()

    catalog = read_json(
        CATALOG_PATH
    )

    batch_ids = new_batch_ids()

    current_assets = catalog.get(
        "assets",
        [],
    )

    current_batch = [
        asset
        for asset in current_assets
        if str(
            asset.get("asset_id", "")
        )
        in batch_ids
    ]

    report_rows = []
    errors = []

    changed_count = 0

    category_counts = {}

    for asset in current_batch:
        asset_id = str(
            asset.get("asset_id", "")
        )

        category = category_from_asset(
            asset
        )

        image_rel = str(
            asset.get("image", "")
        )

        image_path = (
            REPO
            / image_rel
        )

        if not image_path.exists():
            errors.append(
                f"{asset_id}: missing image {image_rel}"
            )
            continue

        old_fp = list(
            asset.get(
                "footprint_tiles",
                [1, 1],
            )
        )

        old_occlusion = bool(
            asset.get(
                "occlusion",
                False,
            )
        )

        approved_scale = float(
            asset.get(
                "approved_scale",
                1.0,
            )
        )

        with Image.open(
            image_path
        ) as image:
            geometry = (
                calibrate_asset_geometry(
                    image,
                    category,
                    approved_scale,
                )
            )

        new_fp = list(
            geometry[
                "footprint_tiles"
            ]
        )

        new_occlusion = (
            category_occlusion(
                category
            )
        )

        # 只改与本次 grounding/occlusion 有关的数据。
        for key, value in geometry.items():
            asset[key] = value

        asset[
            "occlusion"
        ] = new_occlusion

        asset[
            "grounding_repair_version"
        ] = "MSE-NEW-DECOR-GROUNDING-R1"

        asset[
            "calibration_status"
        ] = "placeable"

        asset[
            "placeable"
        ] = True

        asset[
            "anchor_approved"
        ] = True

        category_counts[
            category
        ] = (
            category_counts.get(
                category,
                0,
            )
            + 1
        )

        if (
            old_fp != new_fp
            or old_occlusion
            != new_occlusion
        ):
            changed_count += 1

        report_rows.append({
            "asset_id": asset_id,
            "category": category,
            "old_fp": old_fp,
            "new_fp": new_fp,
            "old_occ": old_occlusion,
            "new_occ": new_occlusion,
            "contact": geometry.get(
                "ground_contact_bounds_px",
                [],
            ),
        })

    print(
        f"NEW_BATCH_IDS_TOTAL={len(batch_ids)}"
    )

    print(
        f"CURRENT_BATCH_ASSETS={len(current_batch)}"
    )

    print(
        f"METADATA_CHANGED={changed_count}"
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

        raise SystemExit(1)

    if not args.apply:
        print(
            "DRY_RUN_OK"
        )
        print(
            "Use --apply to write changes."
        )
        return

    BACKUP_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    if not BACKUP_CATALOG.exists():
        shutil.copy2(
            CATALOG_PATH,
            BACKUP_CATALOG,
        )

    write_json(
        CATALOG_PATH,
        catalog,
    )

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    lines = []

    lines.append(
        "# New Decoration Grounding Repair Report"
    )
    lines.append("")
    lines.append(
        f"POLICY = {GROUNDING_POLICY_ID}"
    )
    lines.append(
        f"PRE_IMPORT_BASE = {PRE_IMPORT_BASE}"
    )
    lines.append(
        f"IMPORT_COMMIT = {IMPORT_COMMIT}"
    )
    lines.append("")
    lines.append(
        f"NEW_BATCH_IDS_TOTAL = {len(batch_ids)}"
    )
    lines.append(
        f"CURRENT_BATCH_ASSETS = {len(current_batch)}"
    )
    lines.append(
        f"METADATA_CHANGED = {changed_count}"
    )
    lines.append("")

    lines.append(
        "## Category Counts"
    )

    for category in sorted(
        category_counts.keys()
    ):
        lines.append(
            f"- {category}: {category_counts[category]}"
        )

    lines.append("")
    lines.append(
        "## Asset Changes"
    )

    lines.append("")
    lines.append(
        "| asset_id | category | old footprint | new footprint | old occlusion | new occlusion | ground contact |"
    )
    lines.append(
        "|---|---|---|---|---|---|---|"
    )

    for row in report_rows:
        lines.append(
            "| "
            + str(row["asset_id"])
            + " | "
            + str(row["category"])
            + " | "
            + str(row["old_fp"])
            + " | "
            + str(row["new_fp"])
            + " | "
            + str(row["old_occ"])
            + " | "
            + str(row["new_occ"])
            + " | "
            + str(row["contact"])
            + " |"
        )

    REPORT_PATH.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print(
        f"WROTE_CATALOG={CATALOG_PATH}"
    )

    print(
        f"WROTE_REPORT={REPORT_PATH}"
    )

    print(
        "CALIBRATION_APPLY_OK"
    )


if __name__ == "__main__":
    main()
