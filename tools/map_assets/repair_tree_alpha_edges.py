#!/usr/bin/env python3
"""Remove white matte contamination from the canonical MSE tree assets.

The repair is intentionally non-generative.  It keeps the image dimensions,
alpha plane, and every fully opaque pixel byte-identical.  RGB values for
transparent and partially transparent pixels are filled from the nearest
fully opaque pixel with a deterministic four-neighbour multi-source BFS.
"""

from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

from PIL import Image


ALGORITHM_ID = "opaque_rgb_nearest_fill_alpha_preserved_v1"
MANIFEST_REL = Path("assets/data/assets/tree_alpha_edge_repair_manifest.json")
MAIN_CATALOG_REL = Path("assets/data/assets/map_asset_catalog.json")
DEEP_CATALOG_REL = Path("assets/data/assets/map_deep_forest_asset_catalog.json")
TREE_ROOT_REL = Path("assets/art/maps/_shared/user_palette/decorations_1/trees")
DEEP_ROOT_REL = TREE_ROOT_REL / "mse_deep_forest_44"
EXPECTED_MAIN = 16
EXPECTED_DEEP = 44
EXPECTED_TOTAL = 60


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


def _is_under(path_text: str, root: Path) -> bool:
    try:
        Path(path_text).relative_to(root)
        return True
    except ValueError:
        return False


def collect_targets(root: Path) -> tuple[list[dict[str, Any]], dict[Path, dict[str, Any]]]:
    catalogs: dict[Path, dict[str, Any]] = {}
    targets: list[dict[str, Any]] = []

    main_path = root / MAIN_CATALOG_REL
    deep_path = root / DEEP_CATALOG_REL
    main = load_json(main_path)
    deep = load_json(deep_path)
    catalogs[main_path] = main
    catalogs[deep_path] = deep

    main_assets = main.get("assets")
    deep_assets = deep.get("assets")
    if not isinstance(main_assets, list) or not isinstance(deep_assets, list):
        raise ValueError("both tree catalogs must contain an assets list")

    old_root = TREE_ROOT_REL.as_posix()
    for asset in main_assets:
        if not isinstance(asset, dict):
            continue
        image = str(asset.get("image", ""))
        p = Path(image)
        if (
            asset.get("category") == "tree"
            and asset.get("object_class") == "tree"
            and p.parent.as_posix() == old_root
            and p.suffix.lower() == ".png"
        ):
            targets.append({"catalog_path": MAIN_CATALOG_REL, "asset": asset})

    for asset in deep_assets:
        if not isinstance(asset, dict):
            continue
        image = str(asset.get("image", ""))
        if (
            asset.get("category") == "tree"
            and asset.get("object_class") == "tree"
            and image.lower().endswith(".png")
            and _is_under(image, DEEP_ROOT_REL)
        ):
            targets.append({"catalog_path": DEEP_CATALOG_REL, "asset": asset})

    main_count = sum(1 for t in targets if t["catalog_path"] == MAIN_CATALOG_REL)
    deep_count = sum(1 for t in targets if t["catalog_path"] == DEEP_CATALOG_REL)
    if (main_count, deep_count, len(targets)) != (EXPECTED_MAIN, EXPECTED_DEEP, EXPECTED_TOTAL):
        raise ValueError(
            f"tree target count mismatch: main={main_count}, deep={deep_count}, total={len(targets)}"
        )

    images = [str(t["asset"].get("image", "")) for t in targets]
    if len(set(images)) != EXPECTED_TOTAL:
        raise ValueError("tree catalog contains duplicate image paths")

    actual = {
        p.relative_to(root).as_posix()
        for p in (root / TREE_ROOT_REL).rglob("*.png")
        if p.is_file()
    }
    expected = set(images)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise ValueError(f"tree file/catalog mismatch: missing={missing}, extra={extra}")

    targets.sort(key=lambda t: str(t["asset"]["image"]))
    return targets, catalogs


def image_invariants(image: Image.Image) -> tuple[bytes, bytes, bytes]:
    if image.mode != "RGBA":
        raise ValueError(f"expected RGBA image, got {image.mode}")
    raw = image.tobytes()
    alpha = raw[3::4]
    opaque_rgb = bytearray()
    for i, a in enumerate(alpha):
        if a == 255:
            off = i * 4
            opaque_rgb.extend(raw[off : off + 3])
    if not opaque_rgb:
        raise ValueError("image has no fully opaque pixels")
    return raw, alpha, bytes(opaque_rgb)


def repaired_rgba(image: Image.Image) -> bytes:
    raw, alpha, _ = image_invariants(image)
    width, height = image.size
    pixel_count = width * height
    owners = [-1] * pixel_count
    queue: deque[int] = deque()

    for idx, a in enumerate(alpha):
        if a == 255:
            owners[idx] = idx
            queue.append(idx)

    while queue:
        idx = queue.popleft()
        x = idx % width
        owner = owners[idx]
        # Fixed order is part of the deterministic algorithm contract.
        if idx >= width and owners[idx - width] < 0:
            owners[idx - width] = owner
            queue.append(idx - width)
        if x > 0 and owners[idx - 1] < 0:
            owners[idx - 1] = owner
            queue.append(idx - 1)
        if x + 1 < width and owners[idx + 1] < 0:
            owners[idx + 1] = owner
            queue.append(idx + 1)
        if idx + width < pixel_count and owners[idx + width] < 0:
            owners[idx + width] = owner
            queue.append(idx + width)

    if any(owner < 0 for owner in owners):
        raise ValueError("opaque RGB propagation did not cover the full canvas")

    out = bytearray(raw)
    for idx, a in enumerate(alpha):
        if a == 255:
            continue
        source = owners[idx] * 4
        target = idx * 4
        out[target : target + 3] = raw[source : source + 3]
    return bytes(out)


def _entry_for(
    catalog_rel: Path,
    asset: dict[str, Any],
    before_sha: str,
    after_sha: str,
    alpha_sha: str,
    opaque_rgb_sha: str,
    changed_visible_pixels: int,
) -> dict[str, Any]:
    return {
        "asset_id": str(asset.get("asset_id", "")),
        "catalog": catalog_rel.as_posix(),
        "image": str(asset.get("image", "")),
        "source_authority": "existing_user_palette_catalog_record",
        "source_external_path": str(asset.get("source_external_path", "")),
        "source_sha256": str(asset.get("source_sha256", "")),
        "input_sha256": before_sha,
        "output_sha256": after_sha,
        "alpha_sha256": alpha_sha,
        "opaque_rgb_sha256": opaque_rgb_sha,
        "changed_visible_edge_pixels": changed_visible_pixels,
        "dimensions_preserved": True,
        "alpha_preserved": True,
        "opaque_rgb_preserved": True,
    }


def apply_repair(root: Path) -> None:
    targets, catalogs = collect_targets(root)
    manifest_path = root / MANIFEST_REL
    existing_manifest = load_json(manifest_path) if manifest_path.exists() else None
    prior_entries: dict[str, dict[str, Any]] = {}
    if existing_manifest is not None:
        if existing_manifest.get("algorithm_id") != ALGORITHM_ID:
            raise ValueError("existing tree repair manifest uses a different algorithm")
        prior_entries = {
            str(entry.get("image", "")): entry
            for entry in existing_manifest.get("assets", [])
            if isinstance(entry, dict)
        }

    manifest_entries: list[dict[str, Any]] = []
    changed_files = 0
    changed_visible_total = 0
    for target in targets:
        catalog_rel: Path = target["catalog_path"]
        asset: dict[str, Any] = target["asset"]
        image_rel = Path(str(asset["image"]))
        image_path = root / image_rel
        current_sha = sha256_file(image_path)
        prior = prior_entries.get(image_rel.as_posix())

        with Image.open(image_path) as source:
            if source.mode != "RGBA":
                raise ValueError(f"expected RGBA image: {image_rel}")
            image = source.copy()
        raw, alpha, opaque_rgb = image_invariants(image)
        alpha_sha = sha256_bytes(alpha)
        opaque_sha = sha256_bytes(opaque_rgb)
        fixed = repaired_rgba(image)

        visible_changes = 0
        for idx, a in enumerate(alpha):
            if 0 < a < 255:
                off = idx * 4
                if raw[off : off + 3] != fixed[off : off + 3]:
                    visible_changes += 1

        if prior is not None and current_sha == str(prior.get("output_sha256", "")):
            before_sha = str(prior.get("input_sha256", ""))
            if fixed != raw:
                raise ValueError(f"manifest says repaired but pixels are not idempotent: {image_rel}")
            after_sha = current_sha
            visible_changes = int(prior.get("changed_visible_edge_pixels", visible_changes))
        else:
            if prior is not None and current_sha != str(prior.get("input_sha256", "")):
                raise ValueError(f"tree image drifted outside the repair manifest: {image_rel}")
            before_sha = current_sha
            if fixed != raw:
                repaired = Image.frombytes("RGBA", image.size, fixed)
                repaired.save(image_path, format="PNG", optimize=True)
                changed_files += 1
            after_sha = sha256_file(image_path)

            with Image.open(image_path) as check_source:
                check = check_source.copy()
            check_raw, check_alpha, check_opaque = image_invariants(check)
            if check.size != image.size or check_alpha != alpha or check_opaque != opaque_rgb:
                raise ValueError(f"tree repair invariant failed after write: {image_rel}")
            if check_raw != fixed:
                raise ValueError(f"tree repair pixel payload changed during PNG encode: {image_rel}")

        if visible_changes <= 0:
            raise ValueError(f"tree image had no visible edge RGB contamination to repair: {image_rel}")
        changed_visible_total += visible_changes

        asset["output_sha256"] = after_sha
        asset["thumbnail_source_sha256"] = after_sha
        asset["processing"] = ALGORITHM_ID
        manifest_entries.append(
            _entry_for(
                catalog_rel,
                asset,
                before_sha,
                after_sha,
                alpha_sha,
                opaque_sha,
                visible_changes,
            )
        )

    for path, payload in catalogs.items():
        write_json(path, payload)

    manifest = {
        "schema_version": 1,
        "repair_id": "tree_alpha_edge_decontamination_20260814",
        "algorithm_id": ALGORITHM_ID,
        "asset_scope": "canonical_mse_user_palette_tree_assets",
        "source_priority_lane": "client_assets",
        "source_policy": "preserve_existing_user_primary_catalog_source_and_apply_deterministic_derived_repair",
        "asset_count": EXPECTED_TOTAL,
        "map_document_rewrite_required": False,
        "runtime_publish_policy": "deferred_until_user_requests_final_map_publish",
        "loading_contract": "existing map objects keep asset_id; catalogs resolve the repaired canonical PNG",
        "invariants": {
            "dimensions_preserved": True,
            "alpha_plane_preserved": True,
            "fully_opaque_rgb_preserved": True,
            "map_layout_preserved": True,
        },
        "repaired_png_count": EXPECTED_TOTAL,
        "changed_visible_edge_pixels": changed_visible_total,
        "assets": manifest_entries,
    }
    write_json(manifest_path, manifest)
    check_repair(root)
    print(
        f"TREE_ALPHA_EDGE_REPAIR_APPLY_PASS assets={len(manifest_entries)} "
        f"changed_pngs={changed_files} visible_edge_pixels={changed_visible_total}"
    )


def check_repair(root: Path) -> None:
    targets, _ = collect_targets(root)
    manifest_path = root / MANIFEST_REL
    if not manifest_path.exists():
        raise ValueError(f"missing repair manifest: {MANIFEST_REL.as_posix()}")
    manifest = load_json(manifest_path)
    if manifest.get("algorithm_id") != ALGORITHM_ID or manifest.get("asset_count") != EXPECTED_TOTAL:
        raise ValueError("tree repair manifest header mismatch")
    entries = manifest.get("assets")
    if not isinstance(entries, list) or len(entries) != EXPECTED_TOTAL:
        raise ValueError("tree repair manifest asset count mismatch")
    by_image = {str(entry.get("image", "")): entry for entry in entries if isinstance(entry, dict)}
    if len(by_image) != EXPECTED_TOTAL:
        raise ValueError("tree repair manifest contains duplicate image paths")

    for target in targets:
        asset: dict[str, Any] = target["asset"]
        image_rel = str(asset["image"])
        entry = by_image.get(image_rel)
        if entry is None:
            raise ValueError(f"manifest missing tree asset: {image_rel}")
        image_path = root / image_rel
        digest = sha256_file(image_path)
        if digest != str(entry.get("output_sha256", "")):
            raise ValueError(f"manifest output hash mismatch: {image_rel}")
        if digest != str(asset.get("output_sha256", "")):
            raise ValueError(f"catalog output hash mismatch: {image_rel}")
        if digest != str(asset.get("thumbnail_source_sha256", "")):
            raise ValueError(f"catalog thumbnail hash mismatch: {image_rel}")
        if asset.get("processing") != ALGORITHM_ID:
            raise ValueError(f"catalog processing mismatch: {image_rel}")
        if str(entry.get("source_sha256", "")) != str(asset.get("source_sha256", "")):
            raise ValueError(f"catalog source provenance mismatch: {image_rel}")
        if str(entry.get("input_sha256", "")) != str(entry.get("source_sha256", "")):
            raise ValueError(f"repair input does not match the recorded canonical source: {image_rel}")

        with Image.open(image_path) as source:
            image = source.copy()
        raw, alpha, opaque_rgb = image_invariants(image)
        if sha256_bytes(alpha) != str(entry.get("alpha_sha256", "")):
            raise ValueError(f"alpha hash mismatch: {image_rel}")
        if sha256_bytes(opaque_rgb) != str(entry.get("opaque_rgb_sha256", "")):
            raise ValueError(f"opaque RGB hash mismatch: {image_rel}")
        if repaired_rgba(image) != raw:
            raise ValueError(f"tree image is not edge-decontaminated/idempotent: {image_rel}")

    print(f"TREE_ALPHA_EDGE_REPAIR_CHECK_PASS assets={EXPECTED_TOTAL}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    try:
        if args.apply:
            apply_repair(root)
        else:
            check_repair(root)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"TREE_ALPHA_EDGE_REPAIR_FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
