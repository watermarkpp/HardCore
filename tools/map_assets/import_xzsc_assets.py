#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
import tempfile
from pathlib import Path

import import_new_decor_assets as core


PALETTE_ROOT = "装饰物1/xzsc"
OUTPUT_ROOT = "xzsc"


def category_storage_dir(category_name: str) -> str:
    digest = hashlib.sha256(
        category_name.encode("utf-8")
    ).hexdigest()[:10]

    return f"cat_{digest}"


def add_entry_to_effective_index(
    effective_index: dict,
    entry: dict,
) -> None:
    asset_id = str(entry.get("asset_id", ""))
    image = str(entry.get("image", ""))
    source = str(entry.get("source_external_path", ""))
    source_sha = str(entry.get("source_sha256", ""))

    if asset_id:
        effective_index["by_id"][asset_id] = entry

    if image:
        effective_index["by_image"][image] = entry

    if source:
        effective_index["by_source"][source] = entry

    if source_sha:
        effective_index["by_source_sha"][source_sha] = entry


def direct_category_dirs(source_root: Path) -> list[Path]:
    return sorted(
        [
            path
            for path in source_root.iterdir()
            if path.is_dir()
            and not path.name.startswith(".")
        ],
        key=lambda path: path.name.casefold(),
    )


def source_media_files(category_dir: Path) -> list[Path]:
    return sorted(
        [
            path
            for path in category_dir.iterdir()
            if path.is_file()
            and path.suffix.lower() in {".png", ".zip"}
        ],
        key=lambda path: path.name.casefold(),
    )


def validate_source_structure(
    source_root: Path,
) -> list[Path]:
    if not source_root.exists():
        raise RuntimeError(
            f"SOURCE_NOT_FOUND: {source_root}"
        )

    if not source_root.is_dir():
        raise RuntimeError(
            f"SOURCE_NOT_DIRECTORY: {source_root}"
        )

    root_media = [
        path
        for path in source_root.iterdir()
        if path.is_file()
        and path.suffix.lower() in {".png", ".zip"}
    ]

    if root_media:
        raise RuntimeError(
            "XZSC_UNCATEGORIZED_SOURCE: "
            + ", ".join(path.name for path in root_media)
        )

    categories = direct_category_dirs(source_root)

    if not categories:
        raise RuntimeError(
            "XZSC_NO_CATEGORY_FOLDERS"
        )

    seen_names: set[str] = set()

    for category_dir in categories:
        category_name = category_dir.name.strip()

        if not category_name:
            raise RuntimeError(
                f"XZSC_EMPTY_CATEGORY_NAME: {category_dir}"
            )

        normalized_name = category_name.casefold()

        if normalized_name in seen_names:
            raise RuntimeError(
                f"XZSC_CATEGORY_NAME_COLLISION: {category_name}"
            )

        seen_names.add(normalized_name)

        nested_dirs = [
            path
            for path in category_dir.iterdir()
            if path.is_dir()
            and not path.name.startswith(".")
        ]

        if nested_dirs:
            raise RuntimeError(
                "XZSC_NESTED_CATEGORY_AMBIGUOUS: "
                + category_name
                + " -> "
                + ", ".join(
                    path.name
                    for path in nested_dirs
                )
            )

        media = source_media_files(category_dir)

        if not media:
            raise RuntimeError(
                f"XZSC_EMPTY_SOURCE_CATEGORY: {category_name}"
            )

        unsupported = [
            path.name
            for path in category_dir.iterdir()
            if path.is_file()
            and not path.name.startswith(".")
            and path.suffix.lower()
            not in {".png", ".zip"}
        ]

        if unsupported:
            raise RuntimeError(
                "XZSC_UNSUPPORTED_SOURCE_FORMAT: "
                + category_name
                + " -> "
                + ", ".join(unsupported)
            )

    return categories


def process_category(
    category_dir: Path,
    source_root: Path,
    temp_dir: str,
    effective_index: dict,
    audit_only: bool,
    dry_run: bool,
) -> list[dict]:
    category_name = category_dir.name.strip()

    storage_dir = category_storage_dir(
        category_name
    )

    category_en = (
        f"{OUTPUT_ROOT}/{storage_dir}"
    )

    output_dir = (
        core.ASSET_BASE
        / OUTPUT_ROOT
        / storage_dir
    )

    if not audit_only and not dry_run:
        output_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

    png_inputs: list[
        tuple[str, str | None, str | None]
    ] = []

    for source_file in source_media_files(
        category_dir
    ):
        if source_file.suffix.lower() == ".png":
            png_inputs.append(
                (
                    str(source_file),
                    None,
                    None,
                )
            )
            continue

        extracted = (
            core.extract_zip_transparent_assets(
                str(source_file),
                temp_dir,
            )
        )

        if not extracted:
            raise RuntimeError(
                "XZSC_ZIP_HAS_NO_TRANSPARENT_ASSETS: "
                + str(source_file)
            )

        for temp_path, zip_member in extracted:
            png_inputs.append(
                (
                    temp_path,
                    str(source_file),
                    zip_member,
                )
            )

    core.stats.source_dirs += 1

    category_entries: list[dict] = []

    for (
        png_path,
        zip_path,
        zip_member,
    ) in png_inputs:
        entries = core.process_single_png(
            png_path,
            category_en,
            category_name,
            output_dir,
            effective_index,
            source_root,
            zip_path,
            zip_member,
            audit_only,
            dry_run,
        )

        for entry in entries:
            entry["palette_path"] = (
                f"{PALETTE_ROOT}/{category_name}"
            )

            entry["tags"] = [
                "user_source",
                "装饰物1",
                "xzsc",
                category_name,
            ]

            category_entries.append(entry)

            add_entry_to_effective_index(
                effective_index,
                entry,
            )

    return category_entries


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Import direct xzsc subfolders into "
            "装饰物1/xzsc/<folder-name>"
        )
    )

    parser.add_argument(
        "--source",
        required=True,
    )

    parser.add_argument(
        "--audit-only",
        action="store_true",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
    )

    args = parser.parse_args()

    source_root = Path(args.source)

    try:
        categories = validate_source_structure(
            source_root
        )
    except RuntimeError as exc:
        print(str(exc))
        return 2

    core.stats = core.Stats()
    core.stats.audit_only = args.audit_only
    core.stats.dry_run = args.dry_run

    effective_assets = (
        core.load_effective_catalogs()
    )

    effective_index = (
        core.build_effective_index(
            effective_assets
        )
    )

    temp_dir = tempfile.mkdtemp(
        prefix="xzsc_import_"
    )

    all_entries: list[dict] = []

    try:
        for category_dir in categories:
            entries = process_category(
                category_dir,
                source_root,
                temp_dir,
                effective_index,
                args.audit_only,
                args.dry_run,
            )

            all_entries.extend(entries)

        if core.stats.rejected > 0:
            print(
                "XZSC_IMPORT_REJECTED_COUNT="
                + str(core.stats.rejected)
            )

            for problem in core.stats.problems:
                print(
                    "XZSC_PROBLEM="
                    + str(problem)
                )

            return 3

        if (
            not args.audit_only
            and not args.dry_run
        ):
            result = core.update_catalog(
                all_entries
            )

            if result is False:
                return 4

        print(
            "XZSC_CATEGORY_COUNT="
            + str(len(categories))
        )

        print(
            "XZSC_CATEGORY_NAMES="
            + "|".join(
                path.name
                for path in categories
            )
        )

        print(
            "XZSC_SOURCE_PNG_COUNT="
            + str(core.stats.source_pngs)
        )

        print(
            "XZSC_IDENTIFIED_ASSET_COUNT="
            + str(
                core.stats.identifed_individual
            )
        )

        print(
            "XZSC_IMPORTED_COUNT="
            + str(core.stats.imported)
        )

        print(
            "XZSC_REJECTED_COUNT="
            + str(core.stats.rejected)
        )

        print(
            "XZSC_DUPLICATE_SKIPPED="
            + str(
                core.stats.duplicate_skipped
            )
        )

        if not args.audit_only and not args.dry_run:
            print(
                "XZSC_CATALOG_ENTRIES_WRITTEN="
                + str(len(all_entries))
            )

            for category_dir in categories:
                category_name = (
                    category_dir.name.strip()
                )

                storage_dir = (
                    category_storage_dir(
                        category_name
                    )
                )

                print(
                    "XZSC_CATEGORY_STORAGE="
                    + category_name
                    + "=>"
                    + storage_dir
                )

        return 0

    finally:
        shutil.rmtree(
            temp_dir,
            ignore_errors=True,
        )


if __name__ == "__main__":
    sys.exit(main())