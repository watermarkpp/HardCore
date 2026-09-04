#!/usr/bin/env python3
"""Build deterministic feedback layers for the shared v4/v5 button families."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets/ui/gothic_theme/v1/sample"
MANIFEST = ASSET_DIR / "button_feedback_layers_manifest.json"
SOURCES = (
    "button_compact_normal_v4.png",
    "button_standard_normal_v4.png",
    "button_wide_normal_v4.png",
    "button_square_normal_v5.png",
    "button_shortwide_normal_v5.png",
    "button_widesmall_normal_v5.png",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def _transparent_layers(rgba: Image.Image) -> tuple[Image.Image, Image.Image]:
    width, height = rgba.size
    pixels = rgba.load()
    outside = bytearray(width * height)
    queue: deque[int] = deque()

    def queue_outside(x: int, y: int) -> None:
        index = y * width + x
        if outside[index] or pixels[x, y][3] > 2:
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
        x, y = index % width, index // width
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
            if pixels[x, y][3] <= 2 and not outside[index]:
                mask_pixels[x, y] = (255, 255, 255, 255)
                frame_pixels[x, y] = (0, 0, 0, 0)
    return mask, frame


def _opaque_candidate(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    maximum = max(red, green, blue)
    minimum = min(red, green, blue)
    return alpha > 0 and maximum <= 119 and maximum - minimum <= 40


def _opaque_layers(rgba: Image.Image) -> tuple[Image.Image, Image.Image]:
    width, height = rgba.size
    pixels = rgba.load()
    seed_x, seed_y = width // 2, height // 2
    candidate = bytearray(width * height)
    for y in range(max(0, min(height - 1, int(height * 0.12))), max(1, min(height, int(height * 0.88)))):
        if not _opaque_candidate(pixels[seed_x, y]):
            continue
        left = seed_x
        while left > 0 and _opaque_candidate(pixels[left - 1, y]):
            left -= 1
        right = seed_x
        while right < width - 1 and _opaque_candidate(pixels[right + 1, y]):
            right += 1
        for x in range(left, right + 1):
            candidate[y * width + x] = 1

    visited = bytearray(width * height)
    seed_index = seed_y * width + seed_x
    visited[seed_index] = 1
    queue: deque[int] = deque([seed_index])
    while queue:
        index = queue.popleft()
        x, y = index % width, index // width
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or nx >= width or ny < 0 or ny >= height:
                continue
            next_index = ny * width + nx
            if visited[next_index] or not candidate[next_index]:
                continue
            visited[next_index] = 1
            queue.append(next_index)

    mask = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    frame = rgba.copy()
    mask_pixels = mask.load()
    frame_pixels = frame.load()
    for index, is_interior in enumerate(visited):
        if not is_interior:
            continue
        x, y = index % width, index // width
        mask_pixels[x, y] = (255, 255, 255, 255)
        frame_pixels[x, y] = (0, 0, 0, 0)
    return mask, frame


def derive_layers(source: Image.Image) -> tuple[Image.Image, Image.Image, str]:
    rgba = source.convert("RGBA")
    center = rgba.getpixel((rgba.width // 2, rgba.height // 2))
    if center[3] > 2:
        mask, frame = _opaque_layers(rgba)
        return mask, frame, "opaque-center-dark-component-four-neighbor"
    mask, frame = _transparent_layers(rgba)
    return mask, frame, "alpha-barrier-four-neighbor-outside-flood-fill"


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
        mask, frame, algorithm = derive_layers(source)
        if write_outputs:
            save_png(mask, mask_path)
            save_png(frame, frame_path)
        else:
            if Image.open(mask_path).convert("RGBA").tobytes() != mask.tobytes():
                raise ValueError(f"feedback mask pixels are stale: {mask_path}")
            if Image.open(frame_path).convert("RGBA").tobytes() != frame.tobytes():
                raise ValueError(f"frame-only pixels are stale: {frame_path}")
        records.append(
            {
                "source": source_name,
                "algorithm": algorithm,
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
        "assetSetId": "ui.theme.gothic.v1.button-feedback-layers.v1",
        "generator": "tools/build_button_feedback_layers.py",
        "runtimeContract": "precomputed-white-mask-modulated-at-runtime-plus-unmodulated-source-frame",
        "components": records,
    }
    if write_outputs:
        MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elif json.loads(MANIFEST.read_text(encoding="utf-8")) != payload:
        raise ValueError(f"manifest is stale: {MANIFEST}")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(not args.check)
    if args.check:
        print("BUTTON_FEEDBACK_LAYERS_CHECK_PASS")


if __name__ == "__main__":
    main()
