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
            if alpha >= 128:
                opaque.append((x, y, (red, green, blue)))
    if not opaque:
        raise ValueError("Template has no opaque pixels")

    screen_frequency = Counter(screen_pixels)
    anchor = min(opaque, key=lambda value: screen_frequency[value[2]])
    positions: dict[tuple[int, int, int], list[tuple[int, int]]] = defaultdict(list)
    anchor_colour = anchor[2]
    for index, colour in enumerate(screen_pixels):
        if colour == anchor_colour:
            positions[colour].append((index % screen.width, index // screen.width))

    screen_access = screen.load()
    best_score = -1.0
    best_location = (0, 0)
    for anchor_x, anchor_y in positions.get(anchor_colour, []):
        left = anchor_x - anchor[0]
        top = anchor_y - anchor[1]
        if left < 0 or top < 0 or left + sprite.width > screen.width or top + sprite.height > screen.height:
            continue
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
