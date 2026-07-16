#!/usr/bin/env python3
"""Prepare the six correctly ordered images for a ChatGPT helmet-art request."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/chatgpt_inputs/black_iron_helmet"
ICON = ROOT / "assets/art/characters/warrior/paper_doll/classic/layers/stateitem_00344.png"
BODY_DIR = ROOT / "assets/art/characters/warrior/male"

FILES = [
    ("02_warrior_idle.png", BODY_DIR / "warrior_idle.png", [768, 1280], 4),
    ("03_warrior_walk.png", BODY_DIR / "warrior_walk.png", [1152, 1280], 6),
    ("04_warrior_attack.png", BODY_DIR / "warrior_attack.png", [1152, 1280], 6),
    ("05_warrior_hit.png", BODY_DIR / "warrior_hit.png", [576, 1280], 3),
    ("06_warrior_death.png", BODY_DIR / "warrior_death.png", [768, 1280], 4),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_reference() -> Path:
    icon = Image.open(ICON).convert("RGBA")
    box = icon.getchannel("A").getbbox()
    if not box:
        raise ValueError("StateItem #344 is empty")
    crop = icon.crop(box)
    scale = 16
    enlarged = crop.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.alpha_composite(enlarged, ((512 - enlarged.width) // 2, (512 - enlarged.height) // 2))
    target = OUTPUT / "01_black_iron_helmet_reference.png"
    canvas.save(target)
    shutil.copy2(ICON, OUTPUT / "01_source_exact_stateitem_00344_28x32.png")
    return target


def main() -> None:
    if not ICON.exists():
        raise FileNotFoundError(ICON)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    reference = build_reference()
    records = [
        {
            "uploadOrder": 1,
            "file": reference.name,
            "role": "Black Iron Helmet unique appearance reference",
            "derivedFrom": f"res://{ICON.relative_to(ROOT).as_posix()}",
            "sourceImage": 344,
            "processing": "opaque crop, 16x nearest-neighbour enlargement, transparent 512x512 canvas",
            "size": [512, 512],
            "sha256": sha256(reference),
        }
    ]
    for order, (name, source, expected_size, frames_per_direction) in enumerate(FILES, 2):
        if not source.exists():
            raise FileNotFoundError(source)
        image = Image.open(source)
        if list(image.size) != expected_size or image.mode != "RGBA":
            raise AssertionError(f"Unexpected body atlas: {source} {image.size} {image.mode}")
        target = OUTPUT / name
        shutil.copy2(source, target)
        records.append(
            {
                "uploadOrder": order,
                "file": name,
                "role": name.removeprefix(f"{order:02d}_").removesuffix(".png"),
                "source": f"res://{source.relative_to(ROOT).as_posix()}",
                "size": expected_size,
                "cell": [192, 160],
                "directions": 8,
                "directionRowOrder": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
                "framesPerDirection": frames_per_direction,
                "sha256": sha256(target),
            }
        )
    manifest = {
        "schemaVersion": 1,
        "purpose": "Six image inputs for ChatGPT Black Iron Helmet world-layer generation",
        "uploadExactlyTheseSix": [record["file"] for record in records],
        "extraDoNotUploadAsOneOfSix": "01_source_exact_stateitem_00344_28x32.png",
        "records": records,
    }
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    readme = """# ChatGPT上传文件顺序

请一次上传下面6张PNG，不要上传`.import`文件，也不要使用游戏截图代替：

1. `01_black_iron_helmet_reference.png`：由经典`StateItem #344`最近邻放大，唯一造型参考。
2. `02_warrior_idle.png`：待机，4列×8方向。
3. `03_warrior_walk.png`：行走，6列×8方向。
4. `04_warrior_attack.png`：攻击，6列×8方向。
5. `05_warrior_hit.png`：受击，3列×8方向。
6. `06_warrior_death.png`：死亡，4列×8方向。

五张人物图集的单帧均为`192×160`，方向行顺序固定为`N、NE、E、SE、S、SW、W、NW`。
`01_source_exact_stateitem_00344_28x32.png`是原始尺寸存档，不属于必须上传的6张图。
"""
    (OUTPUT / "上传说明.md").write_text(readme, encoding="utf-8")
    print(f"BLACK_IRON_CHATGPT_INPUTS_PASS files=6 output={OUTPUT}")


if __name__ == "__main__":
    main()
