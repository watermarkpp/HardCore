#!/usr/bin/env python3
"""Deterministically remove white matte RGB from decorations_1 non-tree PNGs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repair_tree_alpha_edges as alpha_core  # noqa: E402


ALGORITHM_ID = alpha_core.ALGORITHM_ID
DECOR_ROOT_REL = Path("assets/art/maps/_shared/user_palette/decorations_1")
TREE_ROOT_REL = DECOR_ROOT_REL / "trees"
MANIFEST_REL = Path("assets/data/assets/decoration_alpha_edge_repair_manifest.json")
TREE_MANIFEST_REL = Path("assets/data/assets/tree_alpha_edge_repair_manifest.json")
CATALOG_RELS = (
    Path("assets/data/assets/map_asset_catalog.json"),
    Path("assets/data/assets/map_direct_folder_asset_catalog.json"),
    Path("assets/data/assets/map_exit_asset_catalog.json"),
    Path("assets/data/assets/map_ground_graffiti_asset_catalog.json"),
    Path("assets/data/assets/map_new_carpet_asset_catalog.json"),
    Path("assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json"),
    Path("assets/data/assets/map_new_throne_asset_catalog.json"),
)
DIRECT_CATALOG_REL = Path("assets/data/assets/map_direct_folder_asset_catalog.json")
EXPECTED_GROUP_COUNTS = {
    "barricades": 8,
    "carpets": 6,
    "corpses_visual_only": 36,
    "ground_graffiti": 16,
    "houses_and_tents": 24,
    "map_entrances": 72,
    "pillars": 24,
    "small_decorations_visual_only": 24,
    "street_lamps": 4,
    "thrones": 12,
    "vendor_stalls": 8,
}
EXPECTED_ASSETS = 234
EXPECTED_CATALOG_REFS = 346
EXPECTED_TREE_DIRECT_REFS = 16


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def collect_scope(
    root: Path,
) -> tuple[list[Path], dict[Path, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    decor_root = root / DECOR_ROOT_REL
    image_rels = sorted(
        (
            path.relative_to(root)
            for path in decor_root.rglob("*.png")
            if path.is_file() and TREE_ROOT_REL not in path.relative_to(root).parents
        ),
        key=lambda path: path.as_posix(),
    )
    if len(image_rels) != EXPECTED_ASSETS:
        raise ValueError(f"decoration PNG count mismatch: {len(image_rels)}")

    group_counts: dict[str, int] = {}
    for image_rel in image_rels:
        relative = image_rel.relative_to(DECOR_ROOT_REL)
        group = relative.parts[0]
        group_counts[group] = group_counts.get(group, 0) + 1
    if group_counts != EXPECTED_GROUP_COUNTS:
        raise ValueError(f"decoration group counts mismatch: {group_counts}")

    catalogs: dict[Path, dict[str, Any]] = {}
    refs_by_image: dict[str, list[dict[str, Any]]] = {
        image_rel.as_posix(): [] for image_rel in image_rels
    }
    for catalog_rel in CATALOG_RELS:
        catalog_path = root / catalog_rel
        payload = load_json(catalog_path)
        assets = payload.get("assets")
        if not isinstance(assets, list):
            raise ValueError(f"catalog missing assets list: {catalog_rel}")
        catalogs[catalog_path] = payload
        for asset in assets:
            if not isinstance(asset, dict):
                continue
            image = str(asset.get("image", ""))
            if image in refs_by_image:
                refs_by_image[image].append(
                    {"catalog_rel": catalog_rel, "asset": asset}
                )

    missing = sorted(image for image, refs in refs_by_image.items() if not refs)
    ref_count = sum(len(refs) for refs in refs_by_image.values())
    if missing or ref_count != EXPECTED_CATALOG_REFS:
        raise ValueError(
            f"decoration catalog coverage mismatch: refs={ref_count}, missing={missing}"
        )
    return image_rels, catalogs, refs_by_image


def tree_direct_refs(
    root: Path, catalogs: dict[Path, dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    tree_manifest = load_json(root / TREE_MANIFEST_REL)
    entries = tree_manifest.get("assets")
    if not isinstance(entries, list) or len(entries) != 60:
        raise ValueError("tree repair manifest is missing its 60 assets")
    tree_by_image = {
        str(entry.get("image", "")): entry
        for entry in entries
        if isinstance(entry, dict)
    }
    direct_payload = catalogs.get(root / DIRECT_CATALOG_REL)
    if direct_payload is None:
        raise ValueError("direct-folder catalog was not loaded")
    refs = [
        asset
        for asset in direct_payload.get("assets", [])
        if isinstance(asset, dict) and str(asset.get("image", "")) in tree_by_image
    ]
    if len(refs) != EXPECTED_TREE_DIRECT_REFS:
        raise ValueError(f"tree direct-folder reference count mismatch: {len(refs)}")
    return refs, tree_by_image


def _catalog_record(ref: dict[str, Any]) -> dict[str, Any]:
    asset = ref["asset"]
    return {
        "catalog": ref["catalog_rel"].as_posix(),
        "asset_id": str(asset.get("asset_id", "")),
        "source_external_path": str(asset.get("source_external_path", "")),
        "source_sha256": str(asset.get("source_sha256", "")),
        "previous_output_sha256": str(asset.get("output_sha256", "")),
        "previous_thumbnail_source_sha256": str(
            asset.get("thumbnail_source_sha256", "")
        ),
        "previous_processing": asset.get("processing"),
    }


def repaired_processing(previous: Any) -> Any:
    if isinstance(previous, dict):
        repaired = dict(previous)
        repaired["alpha_edge_repair"] = ALGORITHM_ID
        return repaired
    return ALGORITHM_ID


def apply_repair(root: Path) -> None:
    image_rels, catalogs, refs_by_image = collect_scope(root)
    direct_tree_refs, tree_by_image = tree_direct_refs(root, catalogs)
    manifest_path = root / MANIFEST_REL
    existing_manifest = load_json(manifest_path) if manifest_path.exists() else None
    prior_entries: dict[str, dict[str, Any]] = {}
    if existing_manifest is not None:
        if existing_manifest.get("algorithm_id") != ALGORITHM_ID:
            raise ValueError("existing decoration manifest uses another algorithm")
        prior_entries = {
            str(entry.get("image", "")): entry
            for entry in existing_manifest.get("assets", [])
            if isinstance(entry, dict)
        }

    entries: list[dict[str, Any]] = []
    changed_pngs = 0
    visible_total = 0
    for image_rel in image_rels:
        image_text = image_rel.as_posix()
        image_path = root / image_rel
        current_sha = sha256_file(image_path)
        prior = prior_entries.get(image_text)
        refs = refs_by_image[image_text]

        with Image.open(image_path) as source:
            if source.mode != "RGBA":
                raise ValueError(f"expected RGBA image: {image_text}")
            image = source.copy()
        raw, alpha, opaque_rgb = alpha_core.image_invariants(image)
        if not any(0 < value < 255 for value in alpha):
            raise ValueError(f"image has no semitransparent edge pixels: {image_text}")
        fixed = alpha_core.repaired_rgba(image)

        visible_changes = 0
        for idx, alpha_value in enumerate(alpha):
            if 0 < alpha_value < 255:
                offset = idx * 4
                if raw[offset : offset + 3] != fixed[offset : offset + 3]:
                    visible_changes += 1
        if prior is not None and current_sha == str(prior.get("output_sha256", "")):
            if raw != fixed:
                raise ValueError(f"manifest says repaired but pixels drifted: {image_text}")
            input_sha = str(prior.get("input_sha256", ""))
            output_sha = current_sha
            visible_changes = int(
                prior.get("changed_visible_edge_pixels", visible_changes)
            )
            if visible_changes <= 0:
                raise ValueError(f"manifest recorded no edge RGB changes: {image_text}")
            catalog_records = prior.get("catalog_records", [])
        else:
            if visible_changes <= 0:
                raise ValueError(f"image had no edge RGB changes: {image_text}")
            if prior is not None and current_sha != str(prior.get("input_sha256", "")):
                raise ValueError(f"decoration image drifted outside manifest: {image_text}")
            for ref in refs:
                recorded = str(ref["asset"].get("output_sha256", ""))
                if recorded != current_sha:
                    raise ValueError(
                        f"catalog input hash does not match current PNG: {image_text}"
                    )
            input_sha = current_sha
            catalog_records = [_catalog_record(ref) for ref in refs]
            repaired = Image.frombytes("RGBA", image.size, fixed)
            repaired.save(image_path, format="PNG", optimize=True)
            changed_pngs += 1
            output_sha = sha256_file(image_path)

            with Image.open(image_path) as check_source:
                check = check_source.copy()
            check_raw, check_alpha, check_opaque = alpha_core.image_invariants(check)
            if (
                check.size != image.size
                or check_alpha != alpha
                or check_opaque != opaque_rgb
                or check_raw != fixed
            ):
                raise ValueError(f"post-write invariant failed: {image_text}")

        visible_total += visible_changes
        prior_by_ref = {
            (str(record.get("catalog", "")), str(record.get("asset_id", ""))): record
            for record in catalog_records
            if isinstance(record, dict)
        }
        for ref in refs:
            asset = ref["asset"]
            record = prior_by_ref.get(
                (ref["catalog_rel"].as_posix(), str(asset.get("asset_id", "")))
            )
            if record is None:
                raise ValueError(f"manifest missing catalog provenance: {image_text}")
            asset["output_sha256"] = output_sha
            asset["thumbnail_source_sha256"] = output_sha
            asset["processing"] = repaired_processing(record.get("previous_processing"))

        entries.append(
            {
                "image": image_text,
                "input_sha256": input_sha,
                "output_sha256": output_sha,
                "alpha_sha256": sha256_bytes(alpha),
                "opaque_rgb_sha256": sha256_bytes(opaque_rgb),
                "changed_visible_edge_pixels": visible_changes,
                "dimensions": list(image.size),
                "dimensions_preserved": True,
                "alpha_preserved": True,
                "opaque_rgb_preserved": True,
                "catalog_records": catalog_records,
            }
        )

    aligned_tree_records: list[dict[str, Any]] = []
    for asset in direct_tree_refs:
        image = str(asset["image"])
        entry = tree_by_image[image]
        output_sha = str(entry["output_sha256"])
        if sha256_file(root / image) != output_sha:
            raise ValueError(f"tree PNG does not match tree manifest: {image}")
        asset["output_sha256"] = output_sha
        asset["thumbnail_source_sha256"] = output_sha
        asset["processing"] = ALGORITHM_ID
        aligned_tree_records.append(
            {
                "catalog": DIRECT_CATALOG_REL.as_posix(),
                "asset_id": str(asset.get("asset_id", "")),
                "image": image,
                "output_sha256": output_sha,
            }
        )

    for path, payload in catalogs.items():
        write_json(path, payload)

    manifest = {
        "schema_version": 1,
        "repair_id": "decorations_1_non_tree_alpha_edge_decontamination_20260814",
        "algorithm_id": ALGORITHM_ID,
        "asset_scope": "canonical_mse_user_palette_decorations_1_non_tree",
        "source_priority_lane": "client_assets",
        "source_policy": "preserve_existing_catalog_sources_and_apply_deterministic_derived_repair",
        "asset_count": EXPECTED_ASSETS,
        "catalog_reference_count": EXPECTED_CATALOG_REFS,
        "group_counts": EXPECTED_GROUP_COUNTS,
        "repaired_png_count": EXPECTED_ASSETS,
        "changed_visible_edge_pixels": visible_total,
        "map_document_rewrite_required": False,
        "runtime_publish_policy": "deferred_until_user_requests_final_map_publish",
        "loading_contract": "existing map objects keep asset_id; catalogs resolve the repaired canonical PNG",
        "invariants": {
            "dimensions_preserved": True,
            "alpha_plane_preserved": True,
            "fully_opaque_rgb_preserved": True,
            "tree_pngs_preserved": True,
            "map_layout_preserved": True,
        },
        "aligned_tree_direct_folder_record_count": EXPECTED_TREE_DIRECT_REFS,
        "aligned_tree_direct_folder_records": aligned_tree_records,
        "assets": entries,
    }
    write_json(manifest_path, manifest)
    check_repair(root)
    print(
        f"DECORATION_ALPHA_EDGE_REPAIR_APPLY_PASS assets={EXPECTED_ASSETS} "
        f"catalog_refs={EXPECTED_CATALOG_REFS} changed_pngs={changed_pngs} "
        f"visible_edge_pixels={visible_total}"
    )


def check_repair(root: Path) -> None:
    image_rels, catalogs, refs_by_image = collect_scope(root)
    direct_tree_refs, tree_by_image = tree_direct_refs(root, catalogs)
    manifest = load_json(root / MANIFEST_REL)
    if (
        manifest.get("algorithm_id") != ALGORITHM_ID
        or manifest.get("asset_count") != EXPECTED_ASSETS
        or manifest.get("catalog_reference_count") != EXPECTED_CATALOG_REFS
        or manifest.get("group_counts") != EXPECTED_GROUP_COUNTS
    ):
        raise ValueError("decoration repair manifest header mismatch")
    entries = manifest.get("assets")
    if not isinstance(entries, list) or len(entries) != EXPECTED_ASSETS:
        raise ValueError("decoration repair manifest asset count mismatch")
    by_image = {
        str(entry.get("image", "")): entry
        for entry in entries
        if isinstance(entry, dict)
    }
    if len(by_image) != EXPECTED_ASSETS:
        raise ValueError("decoration repair manifest has duplicate image paths")

    for image_rel in image_rels:
        image = image_rel.as_posix()
        entry = by_image.get(image)
        if entry is None:
            raise ValueError(f"manifest missing image: {image}")
        digest = sha256_file(root / image_rel)
        if digest != str(entry.get("output_sha256", "")):
            raise ValueError(f"manifest output hash mismatch: {image}")
        refs = refs_by_image[image]
        if len(refs) != len(entry.get("catalog_records", [])):
            raise ValueError(f"catalog reference count drift: {image}")
        records = {
            (str(record.get("catalog", "")), str(record.get("asset_id", ""))): record
            for record in entry.get("catalog_records", [])
            if isinstance(record, dict)
        }
        for ref in refs:
            asset = ref["asset"]
            record = records.get(
                (ref["catalog_rel"].as_posix(), str(asset.get("asset_id", "")))
            )
            expected_processing = (
                repaired_processing(record.get("previous_processing"))
                if record is not None
                else None
            )
            if (
                str(asset.get("output_sha256", "")) != digest
                or str(asset.get("thumbnail_source_sha256", "")) != digest
                or asset.get("processing") != expected_processing
            ):
                raise ValueError(f"catalog repair metadata mismatch: {image}")
        with Image.open(root / image_rel) as source:
            decoded = source.copy()
        raw, alpha, opaque_rgb = alpha_core.image_invariants(decoded)
        if sha256_bytes(alpha) != str(entry.get("alpha_sha256", "")):
            raise ValueError(f"alpha hash mismatch: {image}")
        if sha256_bytes(opaque_rgb) != str(entry.get("opaque_rgb_sha256", "")):
            raise ValueError(f"opaque RGB hash mismatch: {image}")
        if alpha_core.repaired_rgba(decoded) != raw:
            raise ValueError(f"image is not idempotently repaired: {image}")

    for asset in direct_tree_refs:
        image = str(asset["image"])
        expected = str(tree_by_image[image]["output_sha256"])
        if (
            str(asset.get("output_sha256", "")) != expected
            or str(asset.get("thumbnail_source_sha256", "")) != expected
            or asset.get("processing") != ALGORITHM_ID
        ):
            raise ValueError(f"tree direct-folder metadata is stale: {image}")

    print(
        f"DECORATION_ALPHA_EDGE_REPAIR_CHECK_PASS assets={EXPECTED_ASSETS} "
        f"catalog_refs={EXPECTED_CATALOG_REFS} tree_direct_refs={EXPECTED_TREE_DIRECT_REFS}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.apply:
            apply_repair(args.root.resolve())
        else:
            check_repair(args.root.resolve())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"DECORATION_ALPHA_EDGE_REPAIR_FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
