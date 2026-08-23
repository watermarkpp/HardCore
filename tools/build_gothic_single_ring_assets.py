#!/usr/bin/env python3
"""Normalize newly generated single-ring Gothic UI masters into runtime assets."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageOps


ASSET_SPECS = {
    "inset_rgba.png": ("inset_frame_single_v2.png", (604, 326), 4),
    "button_rgba.png": ("button_normal_single_v2.png", (360, 120), 4),
    "shop_card_rgba.png": ("shop_card_single_v2.png", (640, 161), 3),
    "close_rgba.png": ("close_ring_single_v2.png", (208, 208), 24),
}


def _visible_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value >= 8 else 0).getbbox()
    if bounds is None:
        raise ValueError("Source contains no visible pixels")
    return bounds


def _normalize(source: Path, size: tuple[int, int], padding: int) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    artwork = image.crop(_visible_bounds(image))
    target = (size[0] - padding * 2, size[1] - padding * 2)
    artwork = artwork.resize(target, Image.Resampling.LANCZOS)
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    result.alpha_composite(artwork, (padding, padding))
    return result


def _tint_visible(image: Image.Image, color: tuple[int, int, int], strength: float) -> Image.Image:
    alpha = image.getchannel("A")
    tint = Image.new("RGBA", image.size, (*color, 255))
    result = Image.blend(image.convert("RGBA"), tint, strength)
    result.putalpha(alpha)
    return result


def _disabled(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    gray = ImageOps.grayscale(image.convert("RGB")).convert("RGBA")
    gray = ImageEnhance.Brightness(gray).enhance(0.58)
    gray = _tint_visible(gray, (78, 72, 66), 0.18)
    gray.putalpha(alpha.point(lambda value: int(value * 0.82)))
    return gray


def _draw_item_slot(size: tuple[int, int] = (192, 192)) -> Image.Image:
    scale = 4
    width, height = size[0] * scale, size[1] * scale
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    inset = 5 * scale
    chamfer = 14 * scale
    points = [
        (inset + chamfer, inset),
        (width - inset - chamfer, inset),
        (width - inset, inset + chamfer),
        (width - inset, height - inset - chamfer),
        (width - inset - chamfer, height - inset),
        (inset + chamfer, height - inset),
        (inset, height - inset - chamfer),
        (inset, inset + chamfer),
    ]
    draw.polygon(points, fill=(12, 10, 9, 246))
    draw.line(points + [points[0]], fill=(151, 108, 61, 255), width=4 * scale, joint="curve")
    return image.resize(size, Image.Resampling.LANCZOS)


def build(source_dir: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    normalized: dict[str, Image.Image] = {}
    for source_name, (output_name, size, padding) in ASSET_SPECS.items():
        source = source_dir / source_name
        if not source.is_file():
            raise FileNotFoundError(source)
        image = _normalize(source, size, padding)
        image.save(output_dir / output_name, optimize=True)
        normalized[output_name] = image

    normal = normalized["button_normal_single_v2.png"]
    pressed = _tint_visible(ImageEnhance.Brightness(normal).enhance(1.06), (92, 20, 12), 0.22)
    pressed.save(output_dir / "button_pressed_single_v2.png", optimize=True)
    _disabled(normal).save(output_dir / "button_disabled_single_v2.png", optimize=True)

    tab = _tint_visible(normal.resize((480, 104), Image.Resampling.LANCZOS), (62, 34, 18), 0.08)
    tab.save(output_dir / "tab_frame_single_v2.png", optimize=True)
    _draw_item_slot().save(output_dir / "item_slot_single_v2.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    build(args.source_dir, args.output_dir)


if __name__ == "__main__":
    main()
