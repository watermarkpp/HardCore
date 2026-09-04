#!/usr/bin/env python3
"""Build one helmet draft into isolated preview atlases only."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import finalize_helmet_calibrations as finalizer


PROTECTED_FORMAL_PATHS = (
    "assets/data/equipment_helmet_visual_v2_overrides.json",
    "assets/data/equipment_visual_catalog.json",
    "assets/data/equipment_classic_avatar_head_patches.json",
    "assets/data/equipment_helmet_finalization_manifest.json",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(
        (root / "assets/data/helmet_calibration_drafts").glob("item_*.json")
    ):
        result[path.relative_to(root).as_posix()] = sha256(path)
    for value in PROTECTED_FORMAL_PATHS:
        path = root / value
        result[value] = sha256(path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--item-id", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    output_dir = args.output_dir.resolve()
    draft_path = (
        root
        / "assets/data/helmet_calibration_drafts"
        / f"item_{args.item_id}.json"
    )
    protected_before = snapshot(root)
    draft_bytes = draft_path.read_bytes()
    draft = json.loads(draft_bytes)
    if int(draft["itemId"]) != args.item_id:
        raise ValueError("draft item id mismatch")
    if not bool(
        draft.get("previewPolicy", {}).get(
            "poseFrameIndependentSource", False
        )
    ):
        raise ValueError("draft has no independent per-pose source contract")
    catalog = json.loads(
        (root / "assets/data/equipment_helmet_visual_v2.json").read_text(
            encoding="utf-8"
        )
    )
    visual_asset = catalog["visualAssets"][draft["visualAssetId"]]
    cutouts, source_provenance = finalizer.source_cutouts(root, draft)
    (
        derived_paths,
        source_sha,
        derived_sha,
        action_metrics,
    ) = finalizer.build_world_atlases(
        root, draft, visual_asset, cutouts, output_dir
    )
    protected_after = snapshot(root)
    if protected_after != protected_before:
        raise RuntimeError("protected helmet input or formal runtime file changed")
    manifest = {
        "schemaVersion": 1,
        "contractId": "equipment.helmet.single_target_preview.v1",
        "itemId": args.item_id,
        "visualAssetId": draft["visualAssetId"],
        "isolatedPreviewOnly": True,
        "formalRuntimeMappingModified": False,
        "draftPath": finalizer.to_res(root, draft_path),
        "draftSha256": hashlib.sha256(draft_bytes).hexdigest(),
        "hiddenHelmetActions": sorted(finalizer.HIDDEN_HELMET_ACTIONS),
        "sharedSourceRowsAllowed": True,
        "perTargetPoseBakedIndependently": True,
        "runtimeAtlases": derived_paths,
        "runtimeAtlasSha256": derived_sha,
        "motionEvidenceAtlasSha256": source_sha,
        "sourceDirections": source_provenance,
        "actionMetrics": action_metrics,
        "protectedHashesBefore": protected_before,
        "protectedHashesAfter": protected_after,
    }
    manifest_path = output_dir / "preview_manifest.json"
    finalizer.write_json(manifest_path, manifest)
    print(
        "HELMET_SINGLE_TARGET_PREVIEW_PASS "
        f"item_id={args.item_id} "
        f"draft_sha256={manifest['draftSha256']} "
        "formal_changes=0 death_hidden=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
