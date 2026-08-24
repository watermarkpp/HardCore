#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Split the 8-in-1 cage sheet into 8 individual cage assets.
Marks the original combined sheet as non-placeable.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from collections import deque
from pathlib import Path

from PIL import Image

from decor_grounding_policy import (
    calibrate_asset_geometry,
    category_occlusion,
)

REPO = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO / "assets" / "data" / "assets" / "map_asset_catalog.json"
REPORT_PATH = REPO / "docs" / "mafa_scene_editor" / "split_cage_sheet_report.md"
BACKUP_DIR = REPO / "docs" / "mafa_scene_editor" / "backups" / "split_cage_sheet"


def read_json(path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def find_alpha_components(image, threshold=10, min_size=100):
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    w, h = rgba.size
    pixels = alpha.load()
    visited = set()
    boxes = []

    for y in range(h):
        for x in range(w):
            if (x, y) in visited:
                continue
            if pixels[x, y] < threshold:
                visited.add((x, y))
                continue
            q = deque([(x, y)])
            visited.add((x, y))
            mn_x = mx_x = x
            mn_y = mx_y = y
            while q:
                cx, cy = q.popleft()
                mn_x = min(mn_x, cx)
                mx_x = max(mx_x, cx)
                mn_y = min(mn_y, cy)
                mx_y = max(mx_y, cy)
                for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited and pixels[nx, ny] >= threshold:
                        visited.add((nx, ny))
                        q.append((nx, ny))
            bw = mx_x - mn_x + 1
            bh = mx_y - mn_y + 1
            if bw >= min_size and bh >= min_size:
                boxes.append((mn_x, mn_y, mx_x + 1, mx_y + 1))

    return sorted(boxes, key=lambda b: (b[1], b[0]))


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def make_asset_id(name, sha):
    return "user.cage." + hashlib.md5((name + sha).encode()).hexdigest()[:16]


def main():
    catalog = read_json(CATALOG_PATH)

    # Find the cage sheet asset
    cage_assets = []
    for asset in catalog["assets"]:
        pp = str(asset.get("palette_path", ""))
        if pp.endswith("/囚笼") or "/囚笼" in pp:
            cage_assets.append(asset)

    if len(cage_assets) != 1:
        print(f"CAGE_ASSET_COUNT={len(cage_assets)}")
        if len(cage_assets) == 0:
            print("No cage asset found - may already be split")
            print("SPLIT_CAGE_SHEET=SKIP")
            return
        raise SystemExit("Expected exactly 1 cage sheet asset")

    cage = cage_assets[0]
    image_rel = str(cage["image"])
    image_path = REPO / image_rel

    if not image_path.exists():
        raise SystemExit(f"Missing cage image: {image_path}")

    print(f"ORIGINAL_ASSET_ID={cage['asset_id']}")
    print(f"ORIGINAL_IMAGE={image_rel}")

    with Image.open(image_path) as img:
        print(f"IMAGE_SIZE={img.size}")
        boxes = find_alpha_components(img, min_size=100)
        print(f"COMPONENTS_FOUND={len(boxes)}")

        if len(boxes) != 8:
            raise SystemExit(f"Expected 8 cage components, found {len(boxes)}")

        output_dir = image_path.parent / "split_cages"
        output_dir.mkdir(parents=True, exist_ok=True)

        generated = []

        for idx, box in enumerate(boxes, start=1):
            pad = 2
            x1 = max(0, box[0] - pad)
            y1 = max(0, box[1] - pad)
            x2 = min(img.width, box[2] + pad)
            y2 = min(img.height, box[3] + pad)

            crop = img.crop((x1, y1, x2, y2))
            out_name = f"cage_split_{idx:02d}.png"
            out_path = output_dir / out_name
            crop.save(out_path, "PNG")

            crop_bytes = crop.tobytes()
            crop_sha = sha256_bytes(crop_bytes)
            asset_id = make_asset_id(out_name, crop_sha)

            geometry = calibrate_asset_geometry(crop, "囚笼", 1.0)
            occ = category_occlusion("囚笼")

            image_out_rel = f"assets/art/maps/_shared/user_palette/decorations_1/cages/split_cages/{out_name}"

            entry = {
                "asset_id": asset_id,
                "display_name": f"cage_split_{idx:02d}",
                "asset_type": "large_prop",
                "category": "decoration",
                "object_class": "decoration",
                "theme": "user_palette",
                "image": image_out_rel,
                "thumbnail": image_out_rel,
            }
            entry.update(geometry)
            entry.update({
                "approved_scale": 1.0,
                "logical_scale_level": 0,
                "scale_approved": True,
                "anchor_approved": True,
                "occlusion": occ,
                "content_layer": "personal_expansion",
                "placeable": True,
                "calibration_status": "placeable",
                "palette_path": "装饰物1/囚笼",
                "source_external_path": f"{image_rel}::split_component_{idx}",
                "source_sha256": crop_sha,
                "output_sha256": crop_sha,
                "thumbnail_source_sha256": crop_sha,
                "processing": "split_from_combined_sheet",
                "tags": ["cage_split", "囚笼"],
                "editable": True,
                "allows_edge_clipping": True,
                "semantic_role": "",
                "trigger_on_enter": False,
                "grounding_repair_version": "MSE-NEW-DECOR-OCCLUSION-R2",
            })

            generated.append({
                "path": out_path,
                "entry": entry,
                "box": box,
            })

    # Backup catalog
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup_path = BACKUP_DIR / "map_asset_catalog.before.json"
    if not backup_path.exists():
        shutil.copy2(CATALOG_PATH, backup_path)

    # Mark original as non-placeable
    cage["placeable"] = False
    cage["calibration_status"] = "disabled_combined_sheet"
    cage["disabled_reason"] = "split_into_8_individual_cage_assets"

    # Add new entries
    for g in generated:
        catalog["assets"].append(g["entry"])

    write_json(CATALOG_PATH, catalog)

    # Report
    lines = [
        "# Split Cage Sheet Report",
        "",
        f"ORIGINAL_ASSET_ID = {cage['asset_id']}",
        f"ORIGINAL_IMAGE = {image_rel}",
        f"GENERATED_COUNT = {len(generated)}",
        "",
        "## Generated Assets",
        "",
        "| # | asset_id | display_name | footprint | box |",
        "|---|---|---|---|---|",
    ]
    for i, g in enumerate(generated, 1):
        e = g["entry"]
        lines.append(
            f"| {i} | {e['asset_id']} | {e['display_name']} | "
            f"{e['footprint_tiles']} | {g['box']} |"
        )

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"GENERATED_COUNT={len(generated)}")
    print(f"WROTE_REPORT={REPORT_PATH}")
    print("SPLIT_CAGE_SHEET=PASS")


if __name__ == "__main__":
    main()
