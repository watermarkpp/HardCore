from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools/rebuild_bronze_magic_world_resolution.py"


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    result = subprocess.run(
        [sys.executable, str(BUILDER), "--check"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["identityId"] == "bronze_magic"
    assert report["itemIds"] == [147, 148]
    assert report["changedActions"] == []
    assert report["pipelineId"].endswith(
        "premultiplied_alpha_lanczos_high_res_single_pass_nearest_runtime_v2"
    )
    assert set(report["actions"]) == {
        "idle",
        "walk",
        "attack",
        "cast",
        "hit",
        "death",
    }
    override = json.loads(
        (
            ROOT / "assets/data/equipment_helmet_visual_v2_overrides.json"
        ).read_text(encoding="utf-8")
    )["visualAssetOverrides"]["bronze_magic"]
    assert override["bakePolicy"]["filter"] == "nearest"
    assert override["bakePolicy"]["offlineDownsampleFilter"] == (
        "premultiplied_alpha_lanczos_high_res_single_pass"
    )
    assert override["bakePolicy"]["sourceRecipeId"].endswith(
        "premultiplied_alpha_lanczos_high_res_single_pass_"
        "nearest_runtime_v2.direct_png_v3"
    )
    for action, digest in report["actions"].items():
        path = (
            ROOT
            / "assets/generated/helmet_v2/bronze_magic/scale_100"
            / f"bronze_magic_{action}_scale_100.png"
        )
        assert file_sha256(path) == digest
        assert override["derivedAtlasSha256"][action] == digest
    print("equipment_bronze_magic_world_resolution_test: PASS")


if __name__ == "__main__":
    main()
