#!/usr/bin/env python3
"""Build a frame-level knowledge base for one complete MIR2 client.

Every WIL/WIX library and every indexed frame in the fully extracted 2013
client is recorded in SQLite.  For every valid frame the catalog stores real
geometry, opaque-pixel count and a pixel signature.  Any frame whose geometry
can overlap a classic human head is additionally decoded and scored, regardless
of filename or original category.  This is a full-client scan with a headwear
query layered on top, not a filename-filtered helmet scan.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT_DIR = ROOT / "outputs/resource_catalog/complete_client_frame_catalog"
DATABASE = OUTPUT_DIR / "frame_catalog.sqlite"
ORIGIN = (64, 80)
HEAD_RECT = (68, 0, 128, 64)
MAX_HEAD_LAYER_SIZE = (96, 80)
REFERENCE_ICON = ROOT / "assets/art/characters/warrior/paper_doll/classic/layers/stateitem_00344.png"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import read_library  # noqa: E402


def companion_wix(path: Path) -> Path:
    for candidate in (path.with_suffix(".WIX"), path.with_suffix(".wix")):
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"Missing WIX: {path}")


def intersects_head(width: int, height: int, x: int, y: int) -> bool:
    if width > MAX_HEAD_LAYER_SIZE[0] or height > MAX_HEAD_LAYER_SIZE[1]:
        return False
    left = ORIGIN[0] + x
    top = ORIGIN[1] + y
    right = left + width
    bottom = top + height
    overlap_w = max(0, min(right, HEAD_RECT[2]) - max(left, HEAD_RECT[0]))
    overlap_h = max(0, min(bottom, HEAD_RECT[3]) - max(top, HEAD_RECT[1]))
    if overlap_w <= 0 or overlap_h <= 0:
        return False
    overlap = overlap_w * overlap_h
    return overlap >= 12 and overlap / max(1, width * height) >= 0.08


def decode_sprite_fast(
    data: bytes,
    offset: int,
    width: int,
    height: int,
    palette: list[tuple[int, int, int, int]],
) -> Image.Image:
    indices = data[offset + 8 : offset + 8 + width * height]
    indexed = Image.frombytes("P", (width, height), indices)
    indexed.putpalette([channel for red, green, blue, _alpha in palette for channel in (red, green, blue)])
    indexed.info["transparency"] = 0
    return indexed.transpose(Image.Transpose.FLIP_TOP_BOTTOM).convert("RGBA")


def head_crop(image: Image.Image, x: int, y: int) -> Image.Image:
    cell = Image.new("RGBA", (128, 112), (0, 0, 0, 0))
    cell.alpha_composite(image, (ORIGIN[0] + x, ORIGIN[1] + y))
    return cell.crop(HEAD_RECT)


def pixel_stats(image: Image.Image) -> dict:
    opaque = [pixel for pixel in image.get_flattened_data() if pixel[3] > 0]
    if not opaque:
        return {
            "opaquePixels": 0,
            "darkRatio": 0.0,
            "neutralMetalRatio": 0.0,
            "coverage": 0.0,
            "opaqueBox": [],
        }
    dark = sum(max(r, g, b) <= 110 for r, g, b, _a in opaque)
    metal = sum(
        35 <= max(r, g, b) <= 215 and max(r, g, b) - min(r, g, b) <= 40
        for r, g, b, _a in opaque
    )
    return {
        "opaquePixels": len(opaque),
        "darkRatio": round(dark / len(opaque), 4),
        "neutralMetalRatio": round(metal / len(opaque), 4),
        "coverage": round(len(opaque) / (image.width * image.height), 4),
        "opaqueBox": list(image.getchannel("A").getbbox() or ()),
    }


def candidate_score(stats: dict) -> float:
    useful_area = min(1.0, stats["opaquePixels"] / 450.0) if stats["opaquePixels"] else 0.0
    return round(
        stats["neutralMetalRatio"] * 0.50
        + stats["darkRatio"] * 0.30
        + useful_area * 0.15
        + min(1.0, stats["coverage"] * 8.0) * 0.05,
        5,
    )


def create_database(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE libraries (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            source_path TEXT NOT NULL,
            wil_bytes INTEGER NOT NULL,
            wix_bytes INTEGER NOT NULL,
            wil_sha256 TEXT NOT NULL,
            wix_sha256 TEXT NOT NULL,
            image_count INTEGER NOT NULL,
            indexed_frames_scanned INTEGER NOT NULL,
            valid_frames INTEGER NOT NULL,
            head_geometry_candidates INTEGER NOT NULL,
            decoded_head_candidates INTEGER NOT NULL
        );
        CREATE TABLE frames (
            library_id INTEGER NOT NULL,
            frame_index INTEGER NOT NULL,
            byte_offset INTEGER NOT NULL,
            valid INTEGER NOT NULL,
            width INTEGER,
            height INTEGER,
            draw_x INTEGER,
            draw_y INTEGER,
            opaque_pixels INTEGER,
            pixel_sha256 BLOB,
            head_geometry INTEGER NOT NULL,
            PRIMARY KEY (library_id, frame_index)
        ) WITHOUT ROWID;
        CREATE TABLE head_candidates (
            library_id INTEGER NOT NULL,
            frame_index INTEGER NOT NULL,
            signature BLOB NOT NULL,
            score REAL NOT NULL,
            opaque_pixels INTEGER NOT NULL,
            dark_ratio REAL NOT NULL,
            neutral_metal_ratio REAL NOT NULL,
            coverage REAL NOT NULL,
            opaque_box TEXT NOT NULL,
            PRIMARY KEY (library_id, frame_index)
        ) WITHOUT ROWID;
        CREATE INDEX head_candidates_signature ON head_candidates(signature);
        CREATE INDEX head_candidates_score ON head_candidates(score DESC);
        """
    )
    return connection


def scan_library(connection: sqlite3.Connection, library_id: int, path: Path) -> dict:
    data, palette, offsets, info = read_library(path)
    wix = companion_wix(path)
    frame_rows = []
    candidate_rows = []
    valid_count = 0
    geometry_count = 0
    decoded_count = 0
    for index, offset in enumerate(offsets):
        valid = False
        width = height = x = y = None
        opaque_pixels = None
        pixel_signature = None
        is_head_geometry = False
        if offset > 0 and offset + 8 <= len(data):
            width, height, x, y = struct.unpack_from("<hhhh", data, offset)
            valid = (
                width > 0
                and height > 0
                and width <= 4096
                and height <= 4096
                and offset + 8 + width * height <= len(data)
            )
        if valid:
            valid_count += 1
            pixels = data[offset + 8 : offset + 8 + width * height]
            opaque_pixels = len(pixels) - pixels.count(0)
            pixel_signature = hashlib.sha256(pixels).digest()
            is_head_geometry = intersects_head(width, height, x, y)
            if is_head_geometry:
                geometry_count += 1
                image = decode_sprite_fast(data, offset, width, height, palette)
                crop = head_crop(image, x, y)
                stats = pixel_stats(crop)
                if stats["opaquePixels"] >= 18:
                    decoded_count += 1
                    signature = hashlib.sha256(crop.tobytes()).digest()
                    candidate_rows.append(
                        (
                            library_id,
                            index,
                            signature,
                            candidate_score(stats),
                            stats["opaquePixels"],
                            stats["darkRatio"],
                            stats["neutralMetalRatio"],
                            stats["coverage"],
                            json.dumps(stats["opaqueBox"]),
                        )
                    )
        frame_rows.append(
            (
                library_id,
                index,
                offset,
                1 if valid else 0,
                width if valid else None,
                height if valid else None,
                x if valid else None,
                y if valid else None,
                opaque_pixels,
                pixel_signature,
                1 if is_head_geometry else 0,
            )
        )
        if len(frame_rows) >= 5000:
            connection.executemany("INSERT INTO frames VALUES (?,?,?,?,?,?,?,?,?,?,?)", frame_rows)
            frame_rows.clear()
        if len(candidate_rows) >= 2000:
            connection.executemany("INSERT INTO head_candidates VALUES (?,?,?,?,?,?,?,?,?)", candidate_rows)
            candidate_rows.clear()
    if frame_rows:
        connection.executemany("INSERT INTO frames VALUES (?,?,?,?,?,?,?,?,?,?,?)", frame_rows)
    if candidate_rows:
        connection.executemany("INSERT INTO head_candidates VALUES (?,?,?,?,?,?,?,?,?)", candidate_rows)
    wix_data = wix.read_bytes()
    record = {
        "id": library_id,
        "name": path.name,
        "sourcePath": f"res://{path.relative_to(ROOT).as_posix()}",
        "wilBytes": len(data),
        "wixBytes": len(wix_data),
        "wilSha256": hashlib.sha256(data).hexdigest(),
        "wixSha256": hashlib.sha256(wix_data).hexdigest(),
        "imageCount": int(info["image_count"]),
        "indexedFramesScanned": len(offsets),
        "validFrames": valid_count,
        "headGeometryCandidates": geometry_count,
        "decodedHeadCandidates": decoded_count,
    }
    connection.execute(
        "INSERT INTO libraries VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            record["id"],
            record["name"],
            record["sourcePath"],
            record["wilBytes"],
            record["wixBytes"],
            record["wilSha256"],
            record["wixSha256"],
            record["imageCount"],
            record["indexedFramesScanned"],
            record["validFrames"],
            record["headGeometryCandidates"],
            record["decodedHeadCandidates"],
        ),
    )
    connection.commit()
    return record


def top_unique_candidates(connection: sqlite3.Connection, limit: int = 512) -> list[dict]:
    rows = connection.execute(
        """
        WITH ranked AS (
            SELECT
                h.*,
                l.name AS library,
                f.width,
                f.height,
                f.draw_x,
                f.draw_y,
                ROW_NUMBER() OVER (PARTITION BY h.signature ORDER BY h.score DESC, h.library_id, h.frame_index) AS rn,
                COUNT(*) OVER (PARTITION BY h.signature) AS occurrences
            FROM head_candidates h
            JOIN libraries l ON l.id = h.library_id
            JOIN frames f ON f.library_id = h.library_id AND f.frame_index = h.frame_index
        )
        SELECT library_id, library, frame_index, signature, score, opaque_pixels,
               dark_ratio, neutral_metal_ratio, coverage, opaque_box,
               width, height, draw_x, draw_y, occurrences
        FROM ranked
        WHERE rn = 1
        ORDER BY score DESC, library COLLATE NOCASE, frame_index
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [
        {
            "libraryId": row[0],
            "library": row[1],
            "index": row[2],
            "signature": row[3].hex(),
            "score": row[4],
            "opaquePixels": row[5],
            "darkRatio": row[6],
            "neutralMetalRatio": row[7],
            "coverage": row[8],
            "opaqueBox": json.loads(row[9]),
            "sourceSize": [row[10], row[11]],
            "drawOffset": [row[12], row[13]],
            "occurrences": row[14],
        }
        for row in rows
    ]


def load_candidate_images(records: list[dict]) -> dict[str, Image.Image]:
    by_library: dict[str, list[dict]] = {}
    for record in records:
        by_library.setdefault(record["library"], []).append(record)
    images: dict[str, Image.Image] = {}
    for library, library_records in by_library.items():
        path = DATA_DIR / library
        data, palette, offsets, _info = read_library(path)
        for record in library_records:
            index = record["index"]
            width, height = record["sourceSize"]
            x, y = record["drawOffset"]
            image = decode_sprite_fast(data, offsets[index], width, height, palette)
            images[record["signature"]] = head_crop(image, x, y)
    return images


def render_sheet(records: list[dict], images: dict[str, Image.Image]) -> Path:
    columns = 8
    tile = (156, 136)
    header = 92
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * tile[0], header + rows * tile[1]), (11, 12, 15, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 7), "Complete-client frame knowledge base: top unique head candidates", fill=(240, 240, 240, 255))
    draw.text((8, 23), "Reference: verified classic StateItem #344; filenames/categories were not filters", fill=(205, 214, 225, 255))
    if REFERENCE_ICON.exists():
        reference = Image.open(REFERENCE_ICON).convert("RGBA")
        reference = reference.resize((reference.width * 2, reference.height * 2), Image.Resampling.NEAREST)
        sheet.alpha_composite(reference, (8, 38))
    for position, record in enumerate(records):
        crop = images[record["signature"]]
        x0 = position % columns * tile[0]
        y0 = header + position // columns * tile[1]
        enlarged = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.NEAREST)
        sheet.alpha_composite(enlarged, (x0 + (tile[0] - enlarged.width) // 2, y0 + 30))
        draw.text((x0 + 3, y0 + 3), record["library"][:23], fill=(255, 218, 84, 255))
        draw.text((x0 + 3, y0 + 16), f"I{record['index']} S{record['score']:.3f}", fill=(210, 220, 231, 255))
        draw.text(
            (x0 + 3, y0 + tile[1] - 16),
            f"{record['sourceSize']} @{record['drawOffset']}",
            fill=(175, 188, 204, 255),
        )
    target = OUTPUT_DIR / "top_unique_head_candidates.png"
    sheet.save(target)
    return target


def main() -> None:
    libraries = sorted(DATA_DIR.glob("*.wil"), key=lambda path: path.name.lower())
    if not libraries:
        raise FileNotFoundError(f"No complete-client WIL libraries under {DATA_DIR}")
    connection = create_database(DATABASE)
    library_records = []
    for position, path in enumerate(libraries, 1):
        record = scan_library(connection, position, path)
        library_records.append(record)
        print(
            f"[{position:03d}/{len(libraries):03d}] {path.name}: "
            f"frames={record['indexedFramesScanned']} valid={record['validFrames']} "
            f"head={record['decodedHeadCandidates']}",
            flush=True,
        )
    connection.executescript(
        """
        CREATE INDEX frames_pixel_signature ON frames(pixel_sha256);
        CREATE INDEX frames_geometry ON frames(width, height, draw_x, draw_y);
        ANALYZE;
        """
    )
    connection.commit()
    totals = connection.execute(
        """
        SELECT COUNT(*), SUM(valid), SUM(head_geometry),
               (SELECT COUNT(*) FROM head_candidates),
               (SELECT COUNT(DISTINCT signature) FROM head_candidates)
        FROM frames
        """
    ).fetchone()
    top = top_unique_candidates(connection)
    images = load_candidate_images(top)
    sheet = render_sheet(top, images)
    payload = {
        "schemaVersion": 2,
        "policy": "One complete client is indexed frame-by-frame; source names are provenance only, never classification gates.",
        "selectedCompleteClient": "res://dev_art_sources/external/mir2opensource_full",
        "dataDirectory": f"res://{DATA_DIR.relative_to(ROOT).as_posix()}",
        "referenceIcon": f"res://{REFERENCE_ICON.relative_to(ROOT).as_posix()}",
        "database": f"res://{DATABASE.relative_to(ROOT).as_posix()}",
        "contactSheet": f"res://{sheet.relative_to(ROOT).as_posix()}",
        "libraryCount": len(library_records),
        "indexedFramesScanned": totals[0],
        "validFrames": totals[1],
        "headGeometryCandidates": totals[2],
        "decodedHeadCandidates": totals[3],
        "uniqueHeadPixelCandidates": totals[4],
        "frameFields": [
            "library",
            "frame index",
            "byte offset",
            "validity",
            "width/height",
            "draw x/y",
            "opaque pixel count",
            "pixel SHA-256",
            "head-overlap flag",
        ],
        "libraries": library_records,
        "topUniqueHeadCandidates": top,
    }
    manifest = OUTPUT_DIR / "manifest.json"
    manifest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    connection.close()
    print(
        "COMPLETE_CLIENT_FRAME_CATALOG_PASS "
        f"libraries={len(library_records)} frames={totals[0]} valid={totals[1]} "
        f"head={totals[3]} unique_head={totals[4]}",
        flush=True,
    )


if __name__ == "__main__":
    main()
