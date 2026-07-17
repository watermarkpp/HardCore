#!/usr/bin/env python3
"""Trim, resize, and validate generated profession skill art."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "outputs/profession_skill_art"
MANIFEST = ROOT / "assets/data/caster_skill_visuals.json"

ASSETS = {
    "arcane_projectile": (ROOT / "assets/art/characters/wizard/effects/arcane_projectile.png", 128),
    "area_burst": (ROOT / "assets/art/characters/wizard/effects/area_burst.png", 256),
    "soul_fire_talisman": (ROOT / "assets/art/characters/taoist/effects/soul_fire_talisman.png", 128),
    "binding_circle": (ROOT / "assets/art/characters/taoist/effects/binding_circle.png", 256),
    "summon_skeleton": (ROOT / "assets/art/characters/taoist/effects/summon_skeleton.png", 192),
    "summon_divine_beast": (ROOT / "assets/art/characters/taoist/effects/summon_divine_beast.png", 224),
}


def process(source: Path, output: Path, maximum_size: int) -> dict:
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"{source} has no visible pixels")
    cropped = image.crop(bounds)
    padding = max(4, round(max(cropped.size) * 0.06))
    canvas = Image.new("RGBA", (cropped.width + padding * 2, cropped.height + padding * 2), (0, 0, 0, 0))
    canvas.alpha_composite(cropped, (padding, padding))
    scale = min(1.0, maximum_size / max(canvas.size))
    final_size = (max(1, round(canvas.width * scale)), max(1, round(canvas.height * scale)))
    if final_size != canvas.size:
        canvas = canvas.resize(final_size, Image.Resampling.LANCZOS)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    final_alpha = canvas.getchannel("A")
    corner_alpha = [final_alpha.getpixel(point) for point in ((0, 0), (canvas.width - 1, 0), (0, canvas.height - 1), (canvas.width - 1, canvas.height - 1))]
    if any(corner_alpha):
        raise ValueError(f"{output} corners are not transparent: {corner_alpha}")
    visible = sum(final_alpha.histogram()[1:])
    return {
        "path": str(output.relative_to(ROOT)).replace("\\", "/"),
        "size": list(canvas.size),
        "visible_pixels": visible,
        "transparent_corners": True,
    }


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    results = {}
    for asset_id, (output, maximum_size) in ASSETS.items():
        results[asset_id] = process(SOURCE / f"{asset_id}.png", output, maximum_size)
    manifest["validation"] = results
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PROFESSION_SKILL_ART_PASS assets={len(results)} transparent_corners=6")


if __name__ == "__main__":
    main()
