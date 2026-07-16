#!/usr/bin/env python3
"""Decode Shanda MIR2 WZL/WZX libraries.

The binary layout follows the migrated open-source ``WeMadeLibrary.cs``.  The
implementation is intentionally small and read-only so resource-catalog tools
can inspect every local WZL frame without converting the original library.
"""

from __future__ import annotations

import re
import struct
import zlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_DECODER = (
    ROOT
    / "dev_art_sources/reference/mir2_sources/minipizza_mir2/LibraryEditor/Graphics/WeMadeLibrary.cs"
)


def _palette_from_reference() -> list[tuple[int, int, int, int]]:
    source = REFERENCE_DECODER.read_text(encoding="utf-8-sig")
    match = re.search(r"_palette\s*=\s*new int\[256\]\s*\{(.*?)\};", source, re.S)
    if not match:
        raise ValueError(f"Cannot locate Shanda palette in {REFERENCE_DECODER}")
    values = [int(value) & 0xFFFFFFFF for value in re.findall(r"-?\d+", match.group(1))]
    if len(values) != 256:
        raise ValueError(f"Expected 256 Shanda palette entries, got {len(values)}")
    result = []
    for index, argb in enumerate(values):
        alpha = (argb >> 24) & 0xFF
        red = (argb >> 16) & 0xFF
        green = (argb >> 8) & 0xFF
        blue = argb & 0xFF
        result.append((red, green, blue, 0 if index == 0 else alpha))
    return result


def read_library(wzl_path: Path) -> tuple[bytes, list[int], list[tuple[int, int, int, int]], dict]:
    data = wzl_path.read_bytes()
    wzx_path = next(
        (path for path in (wzl_path.with_suffix(".wzx"), wzl_path.with_suffix(".WZX")) if path.exists()),
        None,
    )
    if wzx_path is None:
        raise FileNotFoundError(f"Missing WZX for {wzl_path}")
    index_data = wzx_path.read_bytes()
    if len(index_data) < 48 or (len(index_data) - 48) % 4:
        raise ValueError(f"Unrecognized WZX header: {wzx_path}")
    offsets = list(struct.unpack_from(f"<{(len(index_data) - 48) // 4}i", index_data, 48))
    return data, offsets, _palette_from_reference(), {
        "image_count": len(offsets),
        "wzx_header_size": 48,
        "decoder_evidence": str(REFERENCE_DECODER),
    }


def sprite_meta(data: bytes, offset: int) -> dict:
    if offset <= 0 or offset + 16 > len(data):
        raise ValueError("empty or out-of-range WZL image")
    pixel_type = data[offset]
    width, height, x, y, compressed_size = struct.unpack_from("<hhhhI", data, offset + 4)
    if width <= 0 or height <= 0 or width > 4096 or height > 4096:
        raise ValueError("empty or invalid WZL dimensions")
    if compressed_size <= 0 or offset + 16 + compressed_size > len(data):
        raise ValueError("invalid WZL compressed payload")
    return {
        "offset": offset,
        "pixel_type": pixel_type,
        "width": width,
        "height": height,
        "x": x,
        "y": y,
        "compressed_size": compressed_size,
        "is_16bit": pixel_type == 5,
    }


def decode_sprite(
    data: bytes,
    offset: int,
    palette: list[tuple[int, int, int, int]],
) -> tuple[Image.Image, dict]:
    meta = sprite_meta(data, offset)
    payload = data[offset + 16 : offset + 16 + meta["compressed_size"]]
    raw = zlib.decompress(payload)
    width = int(meta["width"])
    height = int(meta["height"])
    bytes_per_pixel = 2 if meta["is_16bit"] else 1
    row_bytes = ((width * bytes_per_pixel + 3) // 4) * 4
    expected = row_bytes * height
    if len(raw) < expected:
        raise ValueError(f"short WZL pixel payload: {len(raw)} < {expected}")
    rgba = bytearray(width * height * 4)
    for source_y in range(height):
        target_y = height - 1 - source_y
        row_start = source_y * row_bytes
        for x in range(width):
            if meta["is_16bit"]:
                value = struct.unpack_from("<H", raw, row_start + x * 2)[0]
                if value == 0:
                    color = (0, 0, 0, 0)
                else:
                    color = (
                        (value & 0xF800) >> 8,
                        (value & 0x07E0) >> 3,
                        (value & 0x001F) << 3,
                        255,
                    )
            else:
                color = palette[raw[row_start + x]]
            target = (target_y * width + x) * 4
            rgba[target : target + 4] = bytes(color)
    return Image.frombytes("RGBA", (width, height), bytes(rgba)), meta

