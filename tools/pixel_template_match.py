#!/usr/bin/env python3
"""Small Pillow-only masked template matcher for nearest-neighbour sprites."""

from __future__ import annotations

import math
from collections import Counter, defaultdict

from PIL import Image


def find_masked_template(screenshot: Image.Image, template: Image.Image) -> tuple[float, tuple[int, int]]:
    screen = screenshot.convert("RGB")
    sprite = template.convert("RGBA")
    screen_pixels = list(screen.getdata())
    sprite_pixels = sprite.load()
    opaque: list[tuple[int, int, tuple[int, int, int]]] = []
    for y in range(sprite.height):
        for x in range(sprite.width):
            red, green, blue, alpha = sprite_pixels[x, y]
            # Godot composites partially transparent Lanczos edge pixels over
            # the actor, so their stored RGB values cannot appear verbatim in
            # a runtime screenshot. Match only the fully opaque design pixels.
            if alpha >= 250:
                opaque.append((x, y, (red, green, blue)))
    if not opaque:
        raise ValueError("Template has no opaque pixels")

    screen_frequency = Counter(screen_pixels)
    template_positions: dict[tuple[int, int, int], list[tuple[int, int]]] = defaultdict(list)
    for x, y, colour in opaque:
        template_positions[colour].append((x, y))
    present_colours = [
        colour
        for colour in template_positions
        if 0 < screen_frequency[colour] <= 1024
    ]
    if not present_colours:
        return -1.0, (0, 0)
    positions: dict[tuple[int, int, int], list[tuple[int, int]]] = defaultdict(list)
    for index, colour in enumerate(screen_pixels):
        if colour in template_positions:
            positions[colour].append((index % screen.width, index // screen.width))

    screen_access = screen.load()
    best_score = -1.0
    best_location = (0, 0)
    offset_votes: Counter[tuple[int, int]] = Counter()
    # A single rare colour is unreliable on textured terrain. Let up to 64
    # independently present design colours vote for the template origin, then
    # score the strongest origins against every fully opaque template pixel.
    selected_colours = sorted(
        present_colours,
        key=lambda colour: (screen_frequency[colour], -len(template_positions[colour])),
    )[:64]
    for colour in selected_colours:
        for screen_x, screen_y in positions[colour]:
            for template_x, template_y in template_positions[colour]:
                left = screen_x - template_x
                top = screen_y - template_y
                if (
                    left >= 0
                    and top >= 0
                    and left + sprite.width <= screen.width
                    and top + sprite.height <= screen.height
                ):
                    offset_votes[(left, top)] += 1

    for (left, top), _votes in offset_votes.most_common(256):
        squared_error = 0
        for x, y, expected in opaque:
            actual = screen_access[left + x, top + y]
            squared_error += sum((actual[channel] - expected[channel]) ** 2 for channel in range(3))
        rms = math.sqrt(squared_error / (len(opaque) * 3.0))
        score = max(0.0, 1.0 - rms / 255.0)
        if score > best_score:
            best_score = score
            best_location = (left, top)
            if score >= 0.999999:
                break
    return best_score, best_location
