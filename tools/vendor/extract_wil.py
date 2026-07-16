#!/usr/bin/env python3
"""Extract classic Legend of Mir 2 WIL/WIX sprites to transparent PNG."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw


def read_library(wil_path: Path) -> tuple[bytes, list[tuple[int, int, int, int]], list[int], dict]:
    data = wil_path.read_bytes()
    wix_path = next((path for path in [wil_path.with_suffix(".WIX"), wil_path.with_suffix(".wix")] if path.exists()), None)
    if wix_path is None:
        raise FileNotFoundError(f"找不到对应WIX：{wil_path}")
    index_data = wix_path.read_bytes()
    if len(data) < 1080 or len(index_data) < 48:
        raise ValueError("WIL/WIX文件过小")

    image_count, color_count, palette_size = struct.unpack_from("<III", data, 44)
    if color_count != 256 or palette_size != 1024:
        raise ValueError(f"不支持的WIL调色板：{color_count}色/{palette_size}字节")
    old_wix_size = 48 + image_count * 4
    new_wix_size = 52 + image_count * 4
    if len(index_data) == old_wix_size:
        wil_header_size, wix_header_size, version = 56, 48, 0
    elif len(index_data) == new_wix_size:
        wil_header_size, wix_header_size, version = 60, 52, 1
    else:
        index_count = struct.unpack_from("<I", index_data, 44)[0]
        if 48 + index_count * 4 <= len(index_data):
            image_count, wil_header_size, wix_header_size, version = index_count, 56, 48, 0
        elif index_count > 0 and index_count - ((len(index_data) - 48) // 4) == 1:
            # Some classic Weapon.WIX packages declare one trailing empty slot
            # but omit its final four-byte offset.  Accept only that exact,
            # bounded truncation and expose the offsets actually present.
            image_count = (len(index_data) - 48) // 4
            wil_header_size, wix_header_size, version = 56, 48, 0
        else:
            raise ValueError("无法识别WIX头部")

    palette = []
    for index in range(256):
        b, g, r, _reserved = struct.unpack_from("<BBBB", data, wil_header_size + index * 4)
        palette.append((r, g, b, 0 if index == 0 else 255))
    offsets = list(struct.unpack_from(f"<{image_count}i", index_data, wix_header_size))
    return data, palette, offsets, {
        "image_count": image_count,
        "version": version,
        "wil_header_size": wil_header_size,
        "wix_header_size": wix_header_size,
    }


def decode_sprite(data: bytes, offset: int, palette: list[tuple[int, int, int, int]]) -> tuple[Image.Image, dict]:
    if offset <= 0 or offset + 8 > len(data):
        raise ValueError("图像偏移越界")
    width, height, x, y = struct.unpack_from("<hhhh", data, offset)
    if width <= 0 or height <= 0 or width > 4096 or height > 4096:
        raise ValueError("空图像或尺寸异常")
    start, end = offset + 8, offset + 8 + width * height
    if end > len(data):
        raise ValueError("像素数据越界")
    indices = data[start:end]
    rgba = bytearray(width * height * 4)
    for source_y in range(height):
        target_y = height - 1 - source_y
        for px in range(width):
            color = palette[indices[source_y * width + px]]
            target = (target_y * width + px) * 4
            rgba[target:target + 4] = bytes(color)
    return Image.frombytes("RGBA", (width, height), bytes(rgba)), {
        "offset": offset,
        "width": width,
        "height": height,
        "x": x,
        "y": y,
    }


def build_sheet(records: list[dict], output: Path, columns: int = 8) -> None:
    if not records:
        return
    cell_w, cell_h = 144, 144
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h), (31, 27, 23, 255))
    draw = ImageDraw.Draw(sheet)
    for position, record in enumerate(records):
        sprite = Image.open(record["file"]).convert("RGBA")
        sprite.thumbnail((cell_w - 12, cell_h - 28), Image.Resampling.NEAREST)
        cell_x, cell_y = (position % columns) * cell_w, (position // columns) * cell_h
        sheet.alpha_composite(sprite, (cell_x + (cell_w - sprite.width) // 2, cell_y + cell_h - 24 - sprite.height))
        draw.text((cell_x + 5, cell_y + cell_h - 19), f"#{record['index']} ({record['x']},{record['y']})", fill=(255, 220, 150, 255))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def parse_indices(text: str) -> list[int]:
    output = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = (int(value) for value in part.split("-", 1))
            output.extend(range(start, end + 1))
        else:
            output.append(int(part))
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--indices", required=True, help="例如 200-205,264-269")
    parser.add_argument("--contact-sheet", type=Path)
    parser.add_argument(
        "--allow-failures",
        action="store_true",
        help="Continue successfully when scanning libraries with expected empty/out-of-range slots.",
    )
    args = parser.parse_args()

    data, palette, offsets, library_info = read_library(args.library)
    args.output.mkdir(parents=True, exist_ok=True)
    records, failures = [], []
    for index in parse_indices(args.indices):
        if index < 0 or index >= len(offsets):
            failures.append({"index": index, "error": "索引越界"})
            continue
        try:
            image, metadata = decode_sprite(data, offsets[index], palette)
            output = args.output / f"{args.library.stem}_{index:05d}.png"
            image.save(output)
            records.append({"index": index, "file": str(output.resolve()), **metadata})
        except ValueError as exc:
            failures.append({"index": index, "error": str(exc)})
    manifest = {"library": str(args.library.resolve()), **library_info, "images": records, "failures": failures}
    (args.output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.contact_sheet:
        build_sheet(records, args.contact_sheet)
    print(f"WIL_EXTRACT_DONE: {args.library.name} -> {len(records)} images, {len(failures)} failures")
    return 0 if args.allow_failures or not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())
