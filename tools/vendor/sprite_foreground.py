"""Deterministic foreground extraction for classic UI-backed WIL records."""

from __future__ import annotations

from statistics import median

from PIL import Image, ImageChops, ImageFilter


def remove_dark_border_background(image: Image.Image) -> tuple[Image.Image, dict]:
    """Remove a dark UI backdrop without changing record size or draw offset.

    Most WIL equipment records already use palette index 0 as transparency and
    pass through unchanged.  Some helmet records are almost fully opaque
    because they were authored over the equipment-window background.  For
    those records, build bright foreground seeds relative to the border's
    median luminance, dilate them into the dark helmet outline, and retain only
    the connected component containing the brightest source pixel.
    """

    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    opaque = sum(value > 0 for value in alpha.getdata())
    coverage = opaque / max(1, width * height)
    if coverage < 0.70:
        return rgba, {"applied": False, "opaqueCoverage": coverage}

    pixels = rgba.load()
    border_luminance: list[int] = []
    brightest = (0, 0)
    brightest_luminance = -1
    for y in range(height):
        for x in range(width):
            red, green, blue, source_alpha = pixels[x, y]
            if source_alpha == 0:
                continue
            luminance = (red * 3 + green * 6 + blue) // 10
            if luminance > brightest_luminance:
                brightest_luminance = luminance
                brightest = (x, y)
            if x in (0, width - 1) or y in (0, height - 1):
                border_luminance.append(luminance)

    border_median = int(median(border_luminance)) if border_luminance else 0
    threshold = max(45, border_median + 18)
    seed = Image.new("L", rgba.size, 0)
    seed_pixels = seed.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, source_alpha = pixels[x, y]
            luminance = (red * 3 + green * 6 + blue) // 10
            if source_alpha > 0 and max(red, green, blue) >= threshold and luminance >= threshold - 15:
                seed_pixels[x, y] = 255

    expanded = seed.filter(ImageFilter.MaxFilter(5))
    expanded_pixels = expanded.load()
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if expanded_pixels[x, y] == 0 or (x, y) in seen:
                continue
            pending = [(x, y)]
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while pending:
                px, py = pending.pop()
                component.append((px, py))
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and expanded_pixels[nx, ny] > 0
                        and (nx, ny) not in seen
                    ):
                        seen.add((nx, ny))
                        pending.append((nx, ny))
            components.append(component)

    if not components:
        return rgba, {"applied": False, "opaqueCoverage": coverage, "reason": "no foreground seed"}
    target = next((component for component in components if brightest in component), max(components, key=len))
    component_mask = Image.new("L", rgba.size, 0)
    component_pixels = component_mask.load()
    for x, y in target:
        component_pixels[x, y] = 255
    final_alpha = ImageChops.multiply(alpha, component_mask)
    result = rgba.copy()
    result.putalpha(final_alpha)
    return result, {
        "applied": True,
        "opaqueCoverage": coverage,
        "borderMedianLuminance": border_median,
        "seedThreshold": threshold,
        "foregroundBounds": list(final_alpha.getbbox() or (0, 0, 0, 0)),
        "recordSizePreserved": True,
    }
