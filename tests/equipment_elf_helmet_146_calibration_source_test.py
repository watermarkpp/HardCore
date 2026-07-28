from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
FROZEN_RUNTIME_SHA256 = {
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_idle_scale_100.png": (
        "ea0655119b0541d73d1f1e753a0fe9aef29f4df3076b25de50d9a21d9eb94210"
    ),
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_walk_scale_100.png": (
        "39da47f429c20932208243c6ad844fde9564244d8b78962f25076053c67cc24c"
    ),
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_attack_scale_100.png": (
        "9de2421d0e44f4b7cc8c77c05b5547471f2052fbf62e4a1c6f9135987ce31591"
    ),
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_cast_scale_100.png": (
        "1dcaca96632725d01c893d8f40c15c9813a7d3a3392ddff7448801fe6f8243b6"
    ),
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_hit_scale_100.png": (
        "b214ca2d7b2fd6ddbe70b12449cdf8ebf5d350ec686c55fa050de78a4a00136f"
    ),
    "assets/generated/helmet_v2/elf_146/scale_100/"
    "elf_146_death_scale_100.png": (
        "363a33235eef72ea58ac321534f0948c5f7bf1d9491df1d4f454b7fb11e59ad2"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00146_head.png": (
        "144d45f422031bdc5202191aff6e6aec0bd482f62653337798891d1d904aa28b"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00146_erase_mask.png": (
        "2372e371a38948df97477de8b44953ebeee4abf969eb954f32a060611d4975e9"
    ),
    "assets/art/items/client/inventory/105.png": (
        "76b1b68428408bb20d9eccf2abd4863e54f71fe84f0c74eada37aed6418ffcf4"
    ),
    "assets/art/items/client/ground/105.png": (
        "fdb8545154f11de5988bd292e4759026f22d1e4bafff001d36cd2d95ab4105be"
    ),
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/prepare_elf_helmet_146_calibration_source.py"),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 146
    assert report["visualAssetId"] == "elf_146"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["transparentSheet"]["size"] == [1448, 1086]
    assert len(report["directions"]) == 8
    assert all(
        record["size"][0] >= 290 and record["size"][1] >= 200
        for record in report["directions"].values()
    )

    target = json.loads(
        (
            ROOT / "assets/data/helmet_calibration_active_target.json"
        ).read_text(encoding="utf-8")
    )
    assert target["itemId"] == 146
    assert target["visualAssetId"] == "elf_146"
    assert target["sourceDirectionOrder"] == list(DIRECTIONS)
    assert target["initializeSessionDirectionMapping"] is True
    assert target["resolutionPolicy"] == (
        "retain_original_direction_cutouts_until_one_final_runtime_bake"
    )
    assert set(target["preparedDirectionFiles"]) == set(DIRECTIONS)
    for direction in DIRECTIONS:
        path = ROOT / target["preparedDirectionFiles"][direction][6:]
        assert file_sha256(path) == target["preparedDirectionSha256"][direction]

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_elf_helmet_146_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
