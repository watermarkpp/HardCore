#!/usr/bin/env python3
"""Build deterministic alpha-safe feedback layers for character hall frames."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets/ui/gothic_theme/v1/sample"
MANIFEST = ASSET_DIR / "character_hall_feedback_layers_manifest.json"
SOURCES = (
    "character_profile_frame_v7.png",
    "character_profession_frame_v7.png",
    "character_ai_status_frame_v7.png",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def derive_layers(source: Image.Image) -> tuple[Image.Image, Image.Image]:
    rgba = source.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    alpha_pixels = alpha.load()
    outside = bytearray(width * height)
    queue: deque[int] = deque()

    def queue_outside(x: int, y: int) -> None:
        index = y * width + x
        if outside[index] or alpha_pixels[x, y] > 2:
            return
        outside[index] = 1
        queue.append(index)

    for x in range(width):
        queue_outside(x, 0)
        queue_outside(x, height - 1)
    for y in range(height):
        queue_outside(0, y)
        queue_outside(width - 1, y)
    while queue:
        index = queue.popleft()
        x = index % width
        y = index // width
        if x > 0:
            queue_outside(x - 1, y)
        if x + 1 < width:
            queue_outside(x + 1, y)
        if y > 0:
            queue_outside(x, y - 1)
        if y + 1 < height:
            queue_outside(x, y + 1)

    mask = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    frame = rgba.copy()
    mask_pixels = mask.load()
    frame_pixels = frame.load()
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if alpha_pixels[x, y] <= 2 and not outside[index]:
                mask_pixels[x, y] = (255, 255, 255, 255)
                frame_pixels[x, y] = (0, 0, 0, 0)
    return mask, frame


def save_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG", optimize=False, compress_level=9)


def build(write_outputs: bool) -> dict[str, object]:
    records: list[dict[str, object]] = []
    for source_name in SOURCES:
        source_path = ASSET_DIR / source_name
        stem = source_path.stem
        mask_path = ASSET_DIR / f"{stem}_feedback_mask_v1.png"
        frame_path = ASSET_DIR / f"{stem}_frame_only_v1.png"
        source = Image.open(source_path).convert("RGBA")
        mask, frame = derive_layers(source)
        if write_outputs:
            save_png(mask, mask_path)
            save_png(frame, frame_path)
        else:
            actual_mask = Image.open(mask_path).convert("RGBA")
            actual_frame = Image.open(frame_path).convert("RGBA")
            if actual_mask.tobytes() != mask.tobytes():
                raise ValueError(f"feedback mask pixels are stale: {mask_path}")
            if actual_frame.tobytes() != frame.tobytes():
                raise ValueError(f"frame-only pixels are stale: {frame_path}")
        records.append(
            {
                "source": source_name,
                "sourceFileSha256": sha256(source_path),
                "sourceRgbaSha256": rgba_sha256(source),
                "size": list(source.size),
                "feedbackMask": mask_path.name,
                "feedbackMaskFileSha256": sha256(mask_path),
                "feedbackMaskRgbaSha256": rgba_sha256(mask),
                "frameOnly": frame_path.name,
                "frameOnlyFileSha256": sha256(frame_path),
                "frameOnlyRgbaSha256": rgba_sha256(frame),
            }
        )
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "assetSetId": "ui.theme.gothic.v1.character-hall-feedback-layers.v1",
        "generator": "tools/build_character_hall_feedback_layers.py",
        "algorithm": "alpha-barrier-four-neighbor-outside-flood-fill-threshold-2-of-255",
        "renderContract": "white-alpha-mask-modulated-at-runtime-plus-unmodulated-frame-only-source-pixels",
        "components": records,
    }
    if write_outputs:
        MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    else:
        actual_manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if actual_manifest != payload:
            raise ValueError(f"manifest is stale: {MANIFEST}")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify generated pixels and manifest without writing")
    args = parser.parse_args()
    build(not args.check)
    if args.check:
        print("CHARACTER_HALL_FEEDBACK_LAYERS_CHECK_PASS")


if __name__ == "__main__":
    main()
