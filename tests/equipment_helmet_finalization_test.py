#!/usr/bin/env python3
"""Verify the immutable-draft, single-pass final helmet bake."""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "assets/data/equipment_helmet_finalization_manifest.json"
FRAME_SIZE = (192, 160)
ACTIONS = ("idle", "walk", "attack", "cast", "hit", "death")
EXPECTED_DRAFT_HASHES = {
    146: "69cda4143e9cb989a3156c8e5d881fcafab0cf7e074e76b4f3960067f52484d6",
    147: "2753cdd7ba86f540ee29f9a6a7279085e5e952fa8bc4064b9ad168bac082b0e5",
    149: "6047d7bac6de781d44498749598176c06a677c075054e5b224186a608e6e954c",
    150: "29f8f5d4c2c1a90535a9e08eb70c93c5b58ebec74fe378a6177d30b224b0ce10",
    151: "24b7774b8724676bc2deeeb925f92f61ff071ced9ea24a52f2ff8b2b2d8d2cdd",
    218: "8e347ccb67df29f18bd4511172fc29e9ce2e14e626c6db8ef404499f47472307",
    224: "4747c24a259c6eb8b73c88e42061096d5164f7bd740a124be48d5f7301ddd8f6",
    228: "b8aa296e7d4b42612efd14107c6e661167aa5a378f8232b6e0d47d5fc4de41a3",
    232: "291e39829b96ef60c0471394f9d8ebf6fbd383e69e3203b684361e9737513418",
    236: "d89124686256e2f3ec6eb08fc031dd68b373d5939a3b4b67ee0a2cbe4c740322",
    240: "e114ad10fc5ac48492cb932828200712f1aa2de0717436426a7f4b9639beaf70",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_path(value: str) -> Path:
    assert value.startswith("res://"), value
    return ROOT / value.removeprefix("res://")


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def output_hashes(manifest: dict) -> dict[str, str]:
    result = {
        "manifest": sha256(MANIFEST_PATH),
        "overrides": sha256(
            ROOT / "assets/data/equipment_helmet_visual_v2_overrides.json"
        ),
        "catalog": sha256(ROOT / "assets/data/equipment_visual_catalog.json"),
        "paper": sha256(
            ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
        ),
    }
    for item in manifest["items"].values():
        presentation = item["presentationOutputs"][str(item["itemId"])]
        for role, record in presentation.items():
            result[f'{item["itemId"]}:presentation:{role}'] = sha256(
                project_path(record["path"])
            )
        paper = presentation["paperDoll"]
        result[f'{item["itemId"]}:presentation:erase_mask'] = sha256(
            project_path(paper["eraseMaskPath"])
        )
        for action, path in item["runtimeAtlases"].items():
            result[f'{item["itemId"]}:world:{action}'] = sha256(
                project_path(path)
            )
    return result


def verify() -> None:
    manifest = load_json(MANIFEST_PATH)
    assert manifest["contractId"] == "equipment.helmet.finalization.v1"
    assert manifest["runtimeReadable"] is True
    policy = manifest["sourcePolicy"]
    assert policy["primary"] == "immutable_final_calibration_drafts"
    assert policy["baseAtlasesUsedForPixels"] is False
    assert policy["baseAtlasesUsedForMotionEvidenceOnly"] is True
    assert policy["singlePassDownsample"] == (
        "premultiplied_alpha_lanczos_from_original"
    )
    assert policy["runtimeTextureFilter"] == "nearest"
    assert policy["runtimeScale"] == [1, 1]
    assert {int(value) for value in manifest["items"]} == set(
        EXPECTED_DRAFT_HASHES
    )

    for item_id, expected_draft_hash in EXPECTED_DRAFT_HASHES.items():
        item = manifest["items"][str(item_id)]
        draft_path = project_path(item["draftPath"])
        assert sha256(draft_path) == expected_draft_hash
        assert item["draftSha256"] == expected_draft_hash
        assert load_json(draft_path)["finalized"] is False
        assert item["sharedItemIds"] == (
            [147, 148] if item_id == 147 else [item_id]
        )
        assert set(item["runtimeAtlases"]) == set(ACTIONS)
        assert set(item["actionMetrics"]) == set(ACTIONS)

        presentation = item["presentationOutputs"][str(item_id)]
        for role, record in presentation.items():
            path = project_path(record["path"])
            assert path.is_file(), (item_id, role, path)
            assert sha256(path) == record["fileSha256"]
            image = Image.open(path).convert("RGBA")
            assert image.getchannel("A").getbbox() is not None
            if role == "paperDoll":
                corners = (
                    (0, 0),
                    (image.width - 1, 0),
                    (0, image.height - 1),
                    (image.width - 1, image.height - 1),
                )
                assert all(image.getpixel(point)[3] == 0 for point in corners)
        paper = presentation["paperDoll"]
        erase_mask_path = project_path(paper["eraseMaskPath"])
        assert sha256(erase_mask_path) == paper["eraseMaskFileSha256"]
        assert Image.open(erase_mask_path).convert("RGBA").getchannel(
            "A"
        ).getbbox() is not None

        for action in ACTIONS:
            atlas_path = project_path(item["runtimeAtlases"][action])
            assert atlas_path.is_file(), (item_id, action, atlas_path)
            assert sha256(atlas_path) == item["runtimeAtlasSha256"][action]
            atlas = Image.open(atlas_path).convert("RGBA")
            metrics = item["actionMetrics"][action]
            frame_count = int(metrics["frameCount"])
            assert atlas.size == (FRAME_SIZE[0] * frame_count, FRAME_SIZE[1] * 8)
            aspect_limit = 0.18 if action == "death" else 0.08
            for row in range(8):
                row_metrics = metrics["rows"][str(row)]
                source_aspect = float(row_metrics["sourceAspect"])
                anchor_x, anchor_y = map(
                    float, row_metrics["anchorFraction"]
                )
                assert len(row_metrics["frames"]) == frame_count
                for frame in row_metrics["frames"]:
                    frame_index = int(frame["frame"])
                    target_width, target_height = map(int, frame["size"])
                    deform_x, deform_y = map(float, frame["deformation"])
                    assert target_width > 0 and target_height > 0
                    # The bake clamps the symmetric half-log ratio, so the
                    # resulting X/Y ratio is bounded by twice that value.
                    assert abs(math.log(deform_x / deform_y)) <= (
                        2.0 * aspect_limit + 1e-4
                    )
                    expected_aspect = source_aspect * deform_x / deform_y
                    # Final cells are deliberately tiny; one-pixel integer
                    # quantization can dominate their ratio.
                    assert abs(
                        math.log((target_width / target_height) / expected_aspect)
                    ) <= 0.30
                    pivot_x, pivot_y = map(float, frame["pivot"])
                    top_left_x, top_left_y = map(int, frame["topLeft"])
                    assert abs(
                        top_left_x - round(pivot_x - anchor_x * target_width)
                    ) <= 1
                    assert abs(
                        top_left_y - round(pivot_y - anchor_y * target_height)
                    ) <= 1
                    cell = atlas.crop(
                        (
                            frame_index * FRAME_SIZE[0],
                            row * FRAME_SIZE[1],
                            (frame_index + 1) * FRAME_SIZE[0],
                            (row + 1) * FRAME_SIZE[1],
                        )
                    )
                    assert cell.getchannel("A").getbbox() is not None, (
                        item_id,
                        action,
                        row,
                        frame_index,
                    )

    draft_bytes = {
        item_id: project_path(
            manifest["items"][str(item_id)]["draftPath"]
        ).read_bytes()
        for item_id in EXPECTED_DRAFT_HASHES
    }
    before = output_hashes(manifest)
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/finalize_helmet_calibrations.py"),
            "--project-root",
            str(ROOT),
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert "FINALIZED_HELMETS=" in completed.stdout
    rerun_manifest = load_json(MANIFEST_PATH)
    assert output_hashes(rerun_manifest) == before
    for item_id, content in draft_bytes.items():
        assert project_path(
            rerun_manifest["items"][str(item_id)]["draftPath"]
        ).read_bytes() == content


if __name__ == "__main__":
    verify()
    print(
        "EQUIPMENT_HELMET_FINALIZATION_TEST_PASS "
        "visual_identities=11 item_ids=12 actions=6 directions=8 "
        "immutable_drafts=true single_pass=true"
    )
