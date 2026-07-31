#!/usr/bin/env python3
"""Bake and route explicitly selected finalized helmet inventory/drop icons.

Only the requested inventory/ground outputs and their records are writable.
Paper-doll patches, world atlases, calibration drafts, and unrelated items are
snapshotted and verified byte-for-byte unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from finalize_helmet_calibrations import (
    build_final_helmet_icon,
    presentation_source,
    save_png,
    source_cutouts,
    to_res,
)


CATALOG_RELATIVE = Path("assets/data/equipment_visual_catalog.json")
MANIFEST_RELATIVE = Path("assets/data/equipment_helmet_finalization_manifest.json")
CLIENT_SOURCES_RELATIVE = Path("assets/data/equipment_client_art_sources.json")
ROUTES_RELATIVE = Path("assets/data/equipment_helmet_runtime_icon_routes.json")
ROLES = {"inventory": "inventoryIcon", "ground": "groundIcon"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict[str, Any]) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return
    path.write_bytes(text.encode("utf-8"))


def project_path(root: Path, value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"not a project resource path: {value}")
    return root / value.removeprefix("res://")


def finalization_owner(
    manifest: dict[str, Any], item_id: int
) -> tuple[int, dict[str, Any]]:
    for primary_key, record in manifest.get("items", {}).items():
        shared = [int(value) for value in record.get("sharedItemIds", [])]
        if item_id in shared:
            return int(primary_key), record
    raise KeyError(f"item {item_id} is not a finalized helmet")


def frozen_pixel_snapshot(
    root: Path, manifest: dict[str, Any]
) -> dict[str, str]:
    """Hash only frozen paper/world assets declared by the manifest."""
    result: dict[str, str] = {}
    for finalized in manifest["items"].values():
        for output in finalized["presentationOutputs"].values():
            paper = output["paperDoll"]
            for field in ("path", "eraseMaskPath"):
                path = project_path(root, str(paper[field]))
                result[path.relative_to(root).as_posix()] = sha256(path)
        for value in finalized["runtimeAtlases"].values():
            path = project_path(root, str(value))
            result[path.relative_to(root).as_posix()] = sha256(path)
    return result


def empty_routes_contract() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "contractId": "equipment.helmet.runtime_icon_routes.v1",
        "runtimeReadable": True,
        "sourceCatalog": "res://assets/data/equipment_visual_catalog.json",
        "sourceFinalizationManifest": (
            "res://assets/data/equipment_helmet_finalization_manifest.json"
        ),
        "sourceClientArt": (
            "res://assets/data/equipment_client_art_sources.json"
        ),
        "sourcePolicy": {
            "userPixels": "user_authorized_direct_source",
            "classicScaleReferenceLane": "client_assets",
            "classicScaleReferenceDistribution": (
                "client.classic_raw_complete"
            ),
            "fallbackUsed": False,
        },
        "routingRule": (
            "explicit item inventory/ground icons are baked once from the "
            "accepted high-resolution source with premultiplied-alpha Lanczos; "
            "classic same-item content area sets visual scale, source aspect "
            "is preserved, and runtime displays the final PNG at 1:1"
        ),
        "routesByItemId": {},
    }


def icon_record(
    root: Path,
    item_id: int,
    role: str,
    result: dict[str, Any],
    metadata: dict[str, Any],
    draft: dict[str, Any],
) -> dict[str, Any]:
    calibration = draft["presentationCalibration"][role]
    return {
        "path": to_res(root, result["path"]),
        "library": "project.user_final_helmet_calibration",
        "index": item_id,
        "size": result["size"],
        "drawOffset": [0, 0],
        "confidence": "user_approved_exact",
        "sourceDirection": str(calibration["source_direction"]),
        "sourceVariant": str(
            calibration.get("source_variant", "direction")
        ),
        "fileSha256": result["fileSha256"],
        "rgbaSha256": result["rgbaSha256"],
        **metadata,
    }


def route(
    root: Path, item_ids: list[int], verify_only: bool
) -> dict[str, Any]:
    catalog_path = root / CATALOG_RELATIVE
    manifest_path = root / MANIFEST_RELATIVE
    routes_path = root / ROUTES_RELATIVE
    catalog = load_json(catalog_path)
    manifest = load_json(manifest_path)
    client_sources = load_json(root / CLIENT_SOURCES_RELATIVE)
    prior_routes = load_json(routes_path) if routes_path.is_file() else {}
    if prior_routes and prior_routes.get("contractId") != (
        "equipment.helmet.runtime_icon_routes.v1"
    ):
        raise RuntimeError("unexpected helmet runtime icon route contract")
    routes = empty_routes_contract()
    routes["routesByItemId"] = dict(prior_routes.get("routesByItemId", {}))

    frozen_before = frozen_pixel_snapshot(root, manifest)
    draft_cache: dict[int, tuple[dict[str, Any], dict[int, Any], dict[int, Any]]] = {}
    for item_id in item_ids:
        item_key = str(item_id)
        catalog_item = catalog["itemsById"][item_key]
        item_name = str(catalog_item["itemName"])
        primary_item_id, finalized = finalization_owner(manifest, item_id)
        if primary_item_id not in draft_cache:
            draft = load_json(project_path(root, str(finalized["draftPath"])))
            cutouts, cutout_provenance = source_cutouts(root, draft)
            draft_cache[primary_item_id] = (
                draft,
                cutouts,
                cutout_provenance,
            )
        draft, cutouts, cutout_provenance = draft_cache[primary_item_id]
        runtime = catalog["runtimeMappings"].setdefault(item_name, {})
        final_output = finalized["presentationOutputs"][item_key]
        records: dict[str, dict[str, Any]] = {}

        for role, runtime_field in ROLES.items():
            output_path = project_path(
                root, str(catalog_item["icons"][role]["path"])
            )
            if verify_only:
                record = dict(catalog_item["icons"][role])
                if not output_path.is_file():
                    raise RuntimeError(f"missing final icon: {output_path}")
                if sha256(output_path) != record["fileSha256"]:
                    raise RuntimeError(f"final icon hash mismatch: {output_path}")
            else:
                source, provenance = presentation_source(
                    root, draft, cutouts, role
                )
                if provenance.get("sourceVariant") == "direction":
                    row = int(provenance["sourceRow"])
                    provenance = {
                        **cutout_provenance[row],
                        **provenance,
                    }
                image, metadata = build_final_helmet_icon(
                    root,
                    source,
                    provenance,
                    client_sources["runtimeMappings"][item_name],
                    item_id,
                    role,
                )
                result = save_png(image, output_path)
                record = {
                    **icon_record(root, item_id, role, result, metadata, draft),
                    "path": to_res(root, output_path),
                }
                catalog_item["icons"][role] = record
                final_output[role] = {
                    **record,
                    "provenance": provenance,
                }
                runtime[runtime_field] = dict(record)
            if verify_only:
                if runtime.get(runtime_field) != record:
                    raise RuntimeError(
                        f"item {item_id} {runtime_field} is not routed"
                    )
                if {
                    key: value
                    for key, value in final_output[role].items()
                    if key != "provenance"
                } != record:
                    raise RuntimeError(
                        f"item {item_id} {role} finalization mismatch"
                    )
            records[runtime_field] = record

        route_record = {
            "itemId": item_id,
            "itemName": item_name,
            "finalizationPrimaryItemId": primary_item_id,
            **records,
        }
        if verify_only:
            if routes["routesByItemId"].get(item_key) != route_record:
                raise RuntimeError(f"item {item_id} route evidence is not current")
        else:
            routes.setdefault("routesByItemId", {})[item_key] = route_record

    if not verify_only:
        write_json(catalog_path, catalog)
        write_json(manifest_path, manifest)
        write_json(routes_path, routes)
    if frozen_pixel_snapshot(root, manifest) != frozen_before:
        raise RuntimeError("frozen helmet paper/world pixels changed")
    return routes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--item-id", action="append", type=int, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    item_ids = list(dict.fromkeys(args.item_id))
    route(args.project_root.resolve(), item_ids, args.verify_only)
    print(
        "HELMET_RUNTIME_ICON_ROUTES_OK "
        f"mode={'verify' if args.verify_only else 'update'} "
        f"item_ids={','.join(map(str, item_ids))} "
        f"icons_written={0 if args.verify_only else len(item_ids) * 2} "
        "paper_world_written=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
