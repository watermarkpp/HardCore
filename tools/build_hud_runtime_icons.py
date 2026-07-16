#!/usr/bin/env python3
"""Build HUD icons from source imagery without background removal.

The generated gothic artwork remains a frame only. Full-background source
imagery covers the frame aperture; already-transparent effects retain their
native alpha and are only fitted to the icon canvas.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/gothic_preview/icons/runtime_v2"
OUTPUT_SIZE = 128
CONTENT_SIZE = 116


SOURCES = [
    {
        "id": "skill_long_hit",
        "source": "assets/art/characters/warrior/effects/long_hit.png",
        "region": [1260, 496, 160, 160],
        "tight_alpha": True,
    },
    {
        "id": "skill_wide_hit",
        "source": "assets/art/characters/warrior/effects/wide_hit.png",
        "region": [988, 500, 208, 144],
        "tight_alpha": True,
    },
    {
        "id": "skill_fire_hit",
        "source": "assets/ui/gothic_preview/icons/source_skill_frames/fire_hit_audit.png",
        "region": [920, 220, 200, 210],
        "tight_alpha": False,
    },
    {
        "id": "skill_wild_rush",
        "source": "assets/ui/gothic_preview/icons/source_skill_frames/wild_rush_audit.png",
        "region": [344, 300, 136, 100],
        "tight_alpha": False,
    },
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def crop_region(image: Image.Image, region: list[int]) -> Image.Image:
    x, y, width, height = region
    return image.crop((x, y, x + width, y + height))


def alpha_tight_crop(image: Image.Image) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("source region has no visible pixels")
    left, top, right, bottom = bbox
    padding = 3
    return image.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(image.width, right + padding),
            min(image.height, bottom + padding),
        )
    )


def fit_to_canvas(image: Image.Image) -> Image.Image:
    scale = min(CONTENT_SIZE / image.width, CONTENT_SIZE / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    resized = image.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))
    position = ((OUTPUT_SIZE - size[0]) // 2, (OUTPUT_SIZE - size[1]) // 2)
    canvas.alpha_composite(resized, position)
    return canvas


def cover_canvas(image: Image.Image) -> Image.Image:
    scale = max(OUTPUT_SIZE / image.width, OUTPUT_SIZE / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    resized = image.resize(size, Image.Resampling.LANCZOS)
    left = (size[0] - OUTPUT_SIZE) // 2
    top = (size[1] - OUTPUT_SIZE) // 2
    return resized.crop((left, top, left + OUTPUT_SIZE, top + OUTPUT_SIZE))


def function_cell(index: int) -> Image.Image:
    source = Image.open(ROOT / "assets/ui/gothic_preview/icons/hud_function_icon_atlas_v1.png").convert("RGBA")
    cell_width = source.width // 4
    cell_height = source.height // 4
    x = (index % 4) * cell_width
    y = (index // 4) * cell_height
    return source.crop((x, y, x + cell_width, y + cell_height))


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "version": 2,
        "policy": "source_pixels_cover_frame_aperture_no_matting",
        "outputSize": [OUTPUT_SIZE, OUTPUT_SIZE],
        "contentSize": CONTENT_SIZE,
        "icons": [],
    }
    entries = list(SOURCES)
    for icon_id, atlas_index in [("function_attack", 0), ("function_empty_skill", 8)]:
        image = function_cell(atlas_index)
        output_path = OUTPUT / f"{icon_id}.png"
        cover_canvas(image).save(output_path)
        manifest["icons"].append(
            {
                "id": icon_id,
                "source": "assets/ui/gothic_preview/icons/hud_function_icon_atlas_v1.png",
                "atlasIndex": atlas_index,
                "output": output_path.relative_to(ROOT).as_posix(),
                "sha256": sha256(output_path),
            }
        )
    for entry in entries:
        source_path = ROOT / str(entry["source"])
        image = crop_region(Image.open(source_path).convert("RGBA"), entry["region"])
        if bool(entry["tight_alpha"]):
            image = alpha_tight_crop(image)
        output_path = OUTPUT / f"{entry['id']}.png"
        (fit_to_canvas(image) if bool(entry["tight_alpha"]) else cover_canvas(image)).save(output_path)
        manifest["icons"].append(
            {
                "id": entry["id"],
                "source": entry["source"],
                "region": entry["region"],
                "output": output_path.relative_to(ROOT).as_posix(),
                "sha256": sha256(output_path),
            }
        )
    (OUTPUT / "runtime_icon_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"HUD_RUNTIME_ICON_BUILD_PASS icons={len(manifest['icons'])} output={OUTPUT}")


if __name__ == "__main__":
    main()
