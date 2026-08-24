#!/usr/bin/env python3
"""
Import new decoration assets into Mafa Scene Editor '装饰物 1' category.

Reads source PNGs, processes them (cut multi-asset sheets, validate transparency, trim),
and registers them in the map_asset_catalog.json.

Idempotent: safe to re-run. Will not duplicate existing entries.

Usage:
    python import_new_decor_assets.py --source "C:\\Users\\Administrator\\Desktop\\sucai\\新增"
    python import_new_decor_assets.py --source "..." --audit-only
    python import_new_decor_assets.py --source "..." --dry-run
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

from decor_grounding_policy import (
    calibrate_asset_geometry,
    category_occlusion,
)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from repair_new_decor_package_metadata import read_package_meta, apply_package_meta

# ── paths (no hardcoded worktree) ──────────────────────────────────────
REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = REPO_ROOT / "assets" / "data" / "assets" / "map_asset_catalog.json"
ASSET_BASE = REPO_ROOT / "assets" / "art" / "maps" / "_shared" / "user_palette" / "decorations_1"
REPORT_PATH = REPO_ROOT / "docs" / "mafa_scene_editor" / "new_decor_assets_import_report.md"
CATALOG_SERVICE_PATH = REPO_ROOT / "scripts" / "map_assets" / "map_asset_catalog_service.gd"

# ── folder mapping: source folder name → (english_dir, palette_sub) ──
FOLDER_MAP = {
    "雕塑":       ("sculptures",  "雕塑"),
    "烛台":       ("candlesticks", "烛台"),
    "囚笼":       ("cages",       "囚笼"),
    "旗帜":       ("banners",     "旗帜"),
    "王座":       ("thrones",     "王座"),
    "立柱":       ("pillars",     "立柱"),
    "树木":       ("trees",       "树木"),
    "地毯":       ("carpets",     "地毯"),
    "地面":       ("ground_decor","地面"),
    "地面涂鸦":   ("ground_graffiti", "地面涂鸦"),
    "地图出入口": ("map_entrances", "地图出入口"),
}

TILE_W, TILE_H = 64, 32
MIN_GAP_PX = 20
ALPHA_THRESHOLD = 10

# ── Occlusion defaults by category ─────────────────────────────────────
OCCLUSION_DEFAULTS = {
    "地面": False,
    "地毯": False,
    "地面涂鸦": False,
    "树木": True,
    "雕塑": True,
    "立柱": True,
    "旗帜": True,
    "烛台": True,
    "囚笼": True,
    "王座": True,
    "地图出入口": True,
}


# ── stats tracking ─────────────────────────────────────────────────────
class Stats:
    def __init__(self):
        self.source_dirs = 0
        self.source_pngs = 0
        self.identifed_individual = 0
        self.successfully_cut = 0
        self.transparency_pass = 0
        self.transparency_fail = 0
        self.imported = 0
        self.rejected = 0
        self.duplicate_skipped = 0
        self.canonical_existing = 0
        self.by_category = {}
        self.problems = []
        self.would_import = []
        self.canonical_existing_list = []
        self.main_existing_list = []

    def cat_count(self, cat):
        self.by_category.setdefault(cat, 0)
        self.by_category[cat] += 1


stats = Stats()


# ── effective catalog loading ──────────────────────────────────────────
def load_effective_catalogs():
    """Load all catalogs that MapAssetCatalogService loads."""
    catalogs = []

    # Parse CATALOG_PATH and EXTENSION_CATALOG_PATHS from service script
    if CATALOG_SERVICE_PATH.exists():
        with open(CATALOG_SERVICE_PATH, 'r', encoding='utf-8') as f:
            content = f.read()

        # Extract CATALOG_PATH
        cat_match = re.search(r'CATALOG_PATH\s*:=\s*"([^"]+)"', content)
        if cat_match:
            main_path = cat_match.group(1).replace('res://', str(REPO_ROOT) + '/')
            catalogs.append(main_path)

        # Extract EXTENSION_CATALOG_PATHS
        ext_match = re.search(r'EXTENSION_CATALOG_PATHS\s*:=\s*\[(.*?)\]', content, re.DOTALL)
        if ext_match:
            ext_text = ext_match.group(1)
            ext_paths = re.findall(r'"([^"]+)"', ext_text)
            for ep in ext_paths:
                full_path = ep.replace('res://', str(REPO_ROOT) + '/')
                catalogs.append(full_path)
    else:
        # Fallback: just main catalog
        catalogs.append(str(CATALOG_PATH))

    # Load all assets
    all_assets = []
    for cat_path in catalogs:
        if os.path.exists(cat_path):
            with open(cat_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            assets = data.get('assets', [])
            all_assets.extend(assets)

    return all_assets


def build_effective_index(assets):
    """Build index for duplicate detection."""
    index = {
        'by_id': {},
        'by_image': {},
        'by_source': {},
        'by_source_sha': {},
    }
    for a in assets:
        aid = a.get('asset_id', '')
        img = a.get('image', '')
        src = a.get('source_external_path', '')
        src_sha = a.get('source_sha256', '')

        if aid:
            index['by_id'][aid] = a
        if img:
            index['by_image'][img] = a
        if src:
            index['by_source'][src] = a
        if src_sha:
            index['by_source_sha'][src_sha] = a

    return index


# ── stable source locator ──────────────────────────────────────────────
def compute_stable_source_locator(source_path, source_root, zip_path=None, zip_member=None):
    """Compute stable source locator for identity."""
    if zip_path and zip_member:
        # ZIP: relative/archive.zip::member_path
        rel_archive = os.path.relpath(zip_path, source_root)
        return f"{rel_archive}::{zip_member}"
    else:
        # Direct PNG: relative/path/from/source/root.png
        return os.path.relpath(source_path, source_root)


def compute_asset_id(stable_locator, source_sha, part_index=0):
    """Compute stable asset_id from stable inputs."""
    h = hashlib.sha256()
    h.update(stable_locator.encode('utf-8'))
    h.update(source_sha.encode('utf-8'))
    if part_index > 0:
        h.update(f"_part{part_index}".encode('utf-8'))
    return "user." + h.hexdigest()[:16]


# ── ZIP extraction ─────────────────────────────────────────────────────
def extract_zip_transparent_assets(zip_path, temp_dir):
    """Extract only transparent_assets/*.png from a ZIP file."""
    extracted = []
    with zipfile.ZipFile(zip_path, 'r') as zf:
        for entry in zf.infolist():
            if entry.is_dir():
                continue
            name = entry.filename.replace('\\', '/')
            if '/transparent_assets/' in name and name.lower().endswith('.png'):
                out_name = Path(name).name
                out_path = os.path.join(temp_dir, out_name)
                counter = 1
                base, ext = os.path.splitext(out_name)
                while os.path.exists(out_path):
                    out_path = os.path.join(temp_dir, f"{base}_{counter}{ext}")
                    counter += 1
                with zf.open(entry) as src, open(out_path, 'wb') as dst:
                    dst.write(src.read())
                extracted.append((out_path, name))  # (temp_path, zip_member_path)
    return extracted


# ── image analysis ─────────────────────────────────────────────────────
def get_alpha_row_col_status(img):
    """Return (row_transparent, col_transparent) boolean lists."""
    w, h = img.size
    alpha = img.getchannel('A') if img.mode == 'RGBA' else None
    if alpha is None:
        return [False] * h, [False] * w

    pixels = list(alpha.getdata())
    row_transparent = []
    for y in range(h):
        row = pixels[y * w:(y + 1) * w]
        row_transparent.append(all(a < ALPHA_THRESHOLD for a in row))

    col_transparent = []
    for x in range(w):
        col = pixels[x::w]
        col_transparent.append(all(a < ALPHA_THRESHOLD for a in col))

    return row_transparent, col_transparent


def find_cut_positions(status_list, length):
    """Find groups of consecutive transparent rows/cols that form valid cut points."""
    runs = []
    i = 0
    while i < length:
        if status_list[i]:
            start = i
            while i < length and status_list[i]:
                i += 1
            runs.append((start, i - 1, i - start))
        else:
            i += 1

    valid_cuts = []
    for start, end, width in runs:
        if width < MIN_GAP_PX:
            continue
        has_before = any(not status_list[j] for j in range(0, start))
        has_after = any(not status_list[j] for j in range(end + 1, length))
        if has_before and has_after:
            valid_cuts.append((start + width // 2, width))

    return valid_cuts


def detect_multi_asset(img):
    """Detect if image contains multiple assets arranged in grid."""
    w, h = img.size
    if w < 200 or h < 200:
        return False

    row_tr, col_tr = get_alpha_row_col_status(img)

    h_cuts = find_cut_positions(row_tr, h)
    v_cuts = find_cut_positions(col_tr, w)

    return len(h_cuts) > 0 or len(v_cuts) > 0


def find_grid_layout(img):
    """Detect grid layout by finding transparent gaps and narrow connections."""
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    w, h = img.size
    alpha = img.getchannel('A')
    pixels = list(alpha.getdata())

    # Vertical splits: fully transparent columns
    v_splits = []
    in_gap = False
    gap_start = 0
    for x in range(w):
        col = pixels[x::w]
        opaque = sum(1 for a in col if a > 10)
        if opaque == 0:
            if not in_gap:
                gap_start = x
                in_gap = True
        else:
            if in_gap:
                gw = x - gap_start
                if gw > 20:
                    v_splits.append(gap_start + gw // 2)
                in_gap = False

    # Horizontal split: narrowest point in middle 50%
    row_opaque = []
    for y in range(h):
        row = pixels[y*w:(y+1)*w]
        row_opaque.append(sum(1 for a in row if a > 10))

    mid_start = h // 4
    mid_end = 3 * h // 4
    min_row = mid_start
    min_val = row_opaque[mid_start]
    for y in range(mid_start, mid_end):
        if row_opaque[y] < min_val:
            min_val = row_opaque[y]
            min_row = y

    edge_avg = (row_opaque[h//10] + row_opaque[9*h//10]) // 2
    h_splits = [min_row] if min_val < edge_avg * 0.5 else []

    return h_splits, v_splits


def cut_image(img, row_tr, col_tr, h, w):
    """Cut image into individual assets based on transparent gaps."""
    h_cuts = find_cut_positions(row_tr, h)
    v_cuts = find_cut_positions(col_tr, w)

    if h_cuts:
        row_segments = []
        prev = 0
        for cut_pos, _ in h_cuts:
            gap_start = cut_pos - MIN_GAP_PX // 2
            gap_end = cut_pos + MIN_GAP_PX // 2
            while gap_start > prev and row_tr[gap_start - 1]:
                gap_start -= 1
            while gap_end < h - 1 and not row_tr[gap_end]:
                gap_end -= 1
            if gap_start > prev:
                row_segments.append((prev, gap_start))
            prev = gap_end + 1
        if prev < h:
            row_segments.append((prev, h))
    else:
        row_segments = [(0, h)]

    if v_cuts:
        col_segments = []
        prev = 0
        for cut_pos, _ in v_cuts:
            gap_start = cut_pos - MIN_GAP_PX // 2
            gap_end = cut_pos + MIN_GAP_PX // 2
            while gap_start > prev and col_tr[gap_start - 1]:
                gap_start -= 1
            while gap_end < w - 1 and not col_tr[gap_end]:
                gap_end -= 1
            if gap_start > prev:
                col_segments.append((prev, gap_start))
            prev = gap_end + 1
        if prev < w:
            col_segments.append((prev, w))
    else:
        col_segments = [(0, w)]

    crops = []
    for ry1, ry2 in row_segments:
        for cx1, cx2 in col_segments:
            crop = img.crop((cx1, ry1, cx2, ry2))
            if has_visible_content(crop):
                crops.append(crop)

    return crops if len(crops) > 1 else [img]


def has_visible_content(img, min_alpha=20, min_pixels=100):
    """Check if image has meaningful visible content."""
    if img.mode != 'RGBA':
        return True
    alpha = img.getchannel('A')
    pixels = list(alpha.getdata())
    count = sum(1 for a in pixels if a >= min_alpha)
    return count >= min_pixels


# ── visible bounds & trimming ──────────────────────────────────────────
def compute_visible_bounds(img):
    """Compute bounding box of visible (alpha > threshold) content."""
    if img.mode != 'RGBA':
        return (0, 0, img.size[0], img.size[1])

    alpha = img.getchannel('A')
    w, h = img.size
    pixels = list(alpha.getdata())

    min_x, min_y = w, h
    max_x, max_y = 0, 0

    for y in range(h):
        for x in range(w):
            if pixels[y * w + x] >= ALPHA_THRESHOLD:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if max_x < min_x or max_y < min_y:
        return (0, 0, w, h)

    return (min_x, min_y, max_x + 1, max_y + 1)


def trim_with_padding(img, padding=16):
    """Trim transparent space around content, keeping padding."""
    bounds = compute_visible_bounds(img)
    w, h = img.size
    vx1, vy1, vx2, vy2 = bounds

    x1 = max(0, vx1 - padding)
    y1 = max(0, vy1 - padding)
    x2 = min(w, vx2 + padding)
    y2 = min(h, vy2 + padding)
    y1 = max(0, y1 - padding // 2)

    cropped = img.crop((x1, y1, x2, y2))
    return cropped, (vx1 - x1, vy1 - y1, vx2 - x1, vy2 - y1)


# ── transparency validation ────────────────────────────────────────────
def validate_transparency(img, source_name=""):
    """Check transparency quality. Returns (pass: bool, issues: list[str])"""
    issues = []

    if img.mode != 'RGBA':
        issues.append("No alpha channel")
        return False, issues

    w, h = img.size
    alpha = img.getchannel('A')
    pixels_alpha = list(alpha.getdata())
    pixels_rgb = list(img.convert('RGB').getdata())

    corner_size = min(10, w // 4, h // 4)
    corners = [
        (0, 0, corner_size, corner_size),
        (w - corner_size, 0, w, corner_size),
        (0, h - corner_size, corner_size, h),
        (w - corner_size, h - corner_size, w, h),
    ]

    for cx1, cy1, cx2, cy2 in corners:
        opaque_count = 0
        total = 0
        for y in range(cy1, cy2):
            for x in range(cx1, cx2):
                total += 1
                if pixels_alpha[y * w + x] > 200:
                    opaque_count += 1
        if total > 0 and opaque_count / total > 0.8:
            issues.append(f"Corner ({cx1},{cy1})-({cx2},{cy2}) has opaque background")

    passed = len(issues) == 0
    return passed, issues


# ── metadata computation ───────────────────────────────────────────────
def compute_metadata(img, category_cn):
    """
    Ground footprint MUST describe the real ground/base area.

    It is forbidden to calculate vertical prop footprint from
    the complete visible sprite height.

    Trees, banners, statues, pillars and other upright props
    use bottom-contact grounding.

    Carpets / ground decoration use flat-ground geometry.
    """
    return calibrate_asset_geometry(
        img,
        category_cn,
        approved_scale=1.0,
    )


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


# ─ main processing ────────────────────────────────────────────────────
def process_single_png(png_path, category_en, category_cn, output_dir, effective_index, source_root, zip_path=None, zip_member=None, audit_only=False, dry_run=False):
    """Process a single PNG file. Returns list of catalog entries."""
    entries = []

    try:
        img = Image.open(png_path)
    except Exception as e:
        stats.problems.append({
            "source": str(png_path),
            "category": category_cn,
            "issue": f"Cannot open image: {e}",
            "fixable": False,
            "status": "SOURCE_INVALID",
        })
        stats.rejected += 1
        return entries

    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    stats.source_pngs += 1

    # Compute stable source locator
    stable_locator = compute_stable_source_locator(png_path, source_root, zip_path, zip_member)

    # Compute source SHA256
    if zip_path and zip_member:
        # ZIP member SHA
        with zipfile.ZipFile(zip_path, 'r') as zf:
            with zf.open(zip_member) as m:
                source_sha = sha256_bytes(m.read())
    else:
        source_sha = sha256_file(png_path)

    # Check canonical ownership FIRST
    if stable_locator in effective_index.get('by_source', {}):
        stats.canonical_existing += 1
        stats.canonical_existing_list.append(stable_locator)
        return entries

    if source_sha in effective_index.get('by_source_sha', {}):
        stats.canonical_existing += 1
        stats.canonical_existing_list.append(f"sha:{source_sha}")
        return entries

    # Detect multi-asset
    is_multi = detect_multi_asset(img)

    if is_multi:
        row_tr, col_tr = get_alpha_row_col_status(img)
        h_splits, v_splits = find_grid_layout(img)

        if h_splits or v_splits:
            # Grid layout
            row_bounds = [0] + h_splits + [img.size[1]]
            col_bounds = [0] + v_splits + [img.size[0]]

            crops = []
            crop_origins = []
            for ri in range(len(row_bounds) - 1):
                for ci in range(len(col_bounds) - 1):
                    ry1, ry2 = row_bounds[ri], row_bounds[ri + 1]
                    cx1, cx2 = col_bounds[ci], col_bounds[ci + 1]
                    crop = img.crop((cx1, ry1, cx2, ry2))
                    if has_visible_content(crop):
                        crops.append(crop)
                        crop_origins.append((cx1, ry1))
        else:
            crops = cut_image(img, row_tr, col_tr, img.size[1], img.size[0])
            # cut_image does not report crop origins; package anchor
            # conversion is skipped for these (see below).
            crop_origins = [None] * len(crops)

        stats.identifed_individual += len(crops)
    else:
        crops = [img]
        crop_origins = [(0, 0)]
        stats.identifed_individual += 1

    for i, crop_img in enumerate(crops):
        if crop_img.mode != 'RGBA':
            crop_img = crop_img.convert('RGBA')

        trimmed, vis_bounds = trim_with_padding(crop_img, padding=20)

        passed, issues = validate_transparency(trimmed, str(png_path))
        if passed:
            stats.transparency_pass += 1
        else:
            stats.transparency_fail += 1
            if any("opaque background" in iss.lower() for iss in issues):
                stats.problems.append({
                    "source": str(png_path),
                    "category": category_cn,
                    "issue": "; ".join(issues),
                    "fixable": False,
                    "status": "REJECTED",
                })
                stats.rejected += 1
                continue
            else:
                stats.problems.append({
                    "source": str(png_path),
                    "category": category_cn,
                    "issue": "; ".join(issues),
                    "fixable": True,
                    "status": "EDGE_WARNING",
                })

        # Compute asset_id using stable inputs
        part_index = i if is_multi and len(crops) > 1 else 0
        asset_id = compute_asset_id(stable_locator, source_sha, part_index)

        if asset_id in effective_index.get('by_id', {}):
            stats.duplicate_skipped += 1
            continue

        # Determine output filename
        src_stem = Path(png_path).stem
        if is_multi and len(crops) > 1:
            out_name = f"{src_stem}_part{i+1}.png"
        else:
            out_name = f"{src_stem}.png"

        out_name = "".join(c for c in out_name if c.isalnum() or c in "._-").strip()
        if not out_name.endswith('.png'):
            out_name += '.png'

        out_path = output_dir / out_name

        counter = 1
        stem = Path(out_name).stem
        while out_path.exists():
            existing_sha = sha256_file(out_path)
            new_sha = sha256_bytes(trimmed.tobytes())
            if existing_sha == new_sha:
                stats.duplicate_skipped += 1
                break
            out_name = f"{stem}_{counter}.png"
            out_path = output_dir / out_name
            counter += 1

        if audit_only or dry_run:
            stats.would_import.append({
                "asset_id": asset_id,
                "image": f"assets/art/maps/_shared/user_palette/decorations_1/{category_en}/{out_name}",
                "source": stable_locator,
            })
            stats.imported += 1
            stats.cat_count(category_cn)
            continue

        # Save
        trimmed.save(out_path, 'PNG')
        stats.successfully_cut += 1

        # Compute metadata
        meta = compute_metadata(
            trimmed,
            category_cn,
        )

        meta["occlusion"] = category_occlusion(
            category_cn
        )

        # P3C: package-aware import. ZIP members that ship a sibling
        # meta/{asset_id}.json carry source-authoritative placement data
        # (footprint/anchor/layer/role/occlusion); restore it instead of
        # keeping the pixel-derived guess. Never derive footprint from PNG
        # pixel extent when package metadata exists.
        if zip_path and zip_member:
            package_meta, _pm_status = read_package_meta(zip_path, zip_member)
            if package_meta is not None:
                origin = crop_origins[i] if i < len(crop_origins) else None
                if origin is not None:
                    bounds = compute_visible_bounds(crop_img)
                    tx1 = max(0, bounds[0] - 20)
                    ty1 = max(0, bounds[1] - 20)
                    ty1 = max(0, ty1 - 10)
                    offset = (origin[0] + tx1, origin[1] + ty1)
                    try:
                        applied = apply_package_meta(
                            meta, package_meta, offset, trimmed.size
                        )
                        meta.update(applied)
                        meta["footprint_inference"] = "package_meta"
                    except ValueError as exc:
                        stats.problems.append({
                            "source": str(png_path),
                            "category": category_cn,
                            "issue": f"package meta rejected: {exc}",
                            "fixable": False,
                            "status": "META_WARNING",
                        })
                else:
                    meta["footprint_inference"] = "auto_unverified_crop_origin_unknown"

        output_sha = sha256_bytes(trimmed.tobytes())
        rel_image_path = f"assets/art/maps/_shared/user_palette/decorations_1/{category_en}/{out_name}"

        # Correct provenance
        if zip_path and zip_member:
            source_external_path = f"{zip_path}::{zip_member}"
        else:
            source_external_path = str(png_path)

        entry = {
            "asset_id": asset_id,
            "display_name": stem,
            "asset_type": "large_prop",
            "category": "decoration",
            "object_class": "decoration",
            "theme": "user_palette",
            "image": rel_image_path,
            "thumbnail": rel_image_path,
        }
        entry.update(meta)
        entry.update({
            "approved_scale": 1.0,
            "logical_scale_level": 0,
            "scale_approved": True,
            "anchor_approved": True,
            "default_layer": "object_base",
            "default_object_role": "decoration",
            "collision_policy": "none",
            "collision_profile_id": "none_visual",
            "navigation_policy": "ignore",
            "content_layer": "personal_expansion",
            "placeable": True,
            "calibration_status": "placeable",
            "palette_path": f"装饰物 1/{category_cn}",
            "source_external_path": source_external_path,
            "source_sha256": source_sha,
            "output_sha256": output_sha,
            "thumbnail_source_sha256": output_sha,
            "processing": "user_pre_cut_transparent_passthrough",
            "tags": ["user_source", "装饰物 1", category_cn],
            "editable": True,
            "allows_edge_clipping": False,
            "semantic_role": "",
            "trigger_on_enter": False,
        })

        entries.append(entry)
        stats.imported += 1
        stats.cat_count(category_cn)

    return entries


def process_source_folder(folder_name, temp_dir, source_root, effective_index, audit_only=False, dry_run=False):
    """Process all PNGs from a source folder."""
    if folder_name not in FOLDER_MAP:
        return []

    category_en, category_cn = FOLDER_MAP[folder_name]
    source_dir = source_root / folder_name
    output_dir = ASSET_BASE / category_en
    output_dir.mkdir(parents=True, exist_ok=True)

    stats.source_dirs += 1

    png_files = []

    for f in sorted(source_dir.glob("*.png")):
        png_files.append((str(f), None, None))

    for z in sorted(source_dir.glob("*.zip")):
        extracted = extract_zip_transparent_assets(str(z), temp_dir)
        for temp_path, zip_member in extracted:
            png_files.append((temp_path, str(z), zip_member))

    if not png_files:
        return []

    all_entries = []
    for png_path, zip_path, zip_member in png_files:
        entries = process_single_png(png_path, category_en, category_cn, output_dir, effective_index, source_root, zip_path, zip_member, audit_only, dry_run)
        all_entries.extend(entries)

    return all_entries


def update_catalog(new_entries, audit_only=False, dry_run=False):
    """Add new entries to the catalog JSON."""
    if audit_only or dry_run:
        return

    if not CATALOG_PATH.exists():
        print(f"ERROR: Catalog not found at {CATALOG_PATH}")
        return False

    with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
        catalog = json.load(f)

    existing_ids = set(a['asset_id'] for a in catalog['assets'])
    existing_paths = set(a['image'] for a in catalog['assets'])

    added = 0
    for entry in new_entries:
        if entry['asset_id'] in existing_ids:
            stats.duplicate_skipped += 1
            continue
        if entry['image'] in existing_paths:
            stats.duplicate_skipped += 1
            continue
        catalog['assets'].append(entry)
        existing_ids.add(entry['asset_id'])
        existing_paths.add(entry['image'])
        added += 1

    if added > 0:
        with open(CATALOG_PATH, 'w', encoding='utf-8') as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2)
        print(f"Added {added} entries to catalog")
    else:
        print("No new entries to add")

    return True


def generate_report(base_sha, final_sha, source_root):
    """Generate the import report."""
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    lines.append("# NEW_DECOR_ASSET_IMPORT_REPORT")
    lines.append("")
    lines.append(f"BASE_SHA = {base_sha}")
    lines.append(f"FINAL_SHA = {final_sha}")
    lines.append("")
    lines.append(f"SOURCE = {source_root}")
    lines.append("")
    lines.append(f"扫描源图 = {stats.source_pngs}")
    lines.append(f"识别独立素材 = {stats.identifed_individual}")
    lines.append(f"正式导入 = {stats.imported}")
    lines.append(f"拒绝 = {stats.rejected}")
    lines.append(f"重复跳过 = {stats.duplicate_skipped}")
    lines.append(f"Canonical 已存在 = {stats.canonical_existing}")
    lines.append("")
    lines.append("分类统计：")
    for cat in ["雕塑", "烛台", "囚笼", "旗帜", "王座", "立柱", "树木", "地毯", "地面", "地面涂鸦", "地图出入口"]:
        count = stats.by_category.get(cat, 0)
        lines.append(f"{cat} = {count}")
    lines.append("")
    lines.append("透明检查：")
    lines.append(f"PASS = {stats.transparency_pass}")
    lines.append(f"FAIL = {stats.transparency_fail}")
    lines.append("")

    if stats.problems:
        lines.append("问题素材：")
        for p in stats.problems:
            lines.append(f"- 文件：{p['source']}")
            lines.append(f"  分类：{p['category']}")
            lines.append(f"  原因：{p['issue']}")
            lines.append(f"  可自动修复：{'是' if p['fixable'] else '否'}")
            lines.append(f"  状态：{p['status']}")
            lines.append("")
    else:
        lines.append("问题素材：无")
        lines.append("")

    report_text = "\n".join(lines)

    if not (stats.audit_only if hasattr(stats, 'audit_only') else False):
        with open(REPORT_PATH, 'w', encoding='utf-8') as f:
            f.write(report_text)
        print(f"Report written to {REPORT_PATH}")

    return report_text


def main():
    parser = argparse.ArgumentParser(description='Import decoration assets')
    parser.add_argument('--source', type=str, default=r"C:\Users\Administrator\Desktop\sucai\新增",
                        help='Source directory')
    parser.add_argument('--audit-only', action='store_true',
                        help='Only audit, do not write anything')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run full logic but do not modify Catalog or write PNGs')

    args = parser.parse_args()

    source_root = Path(args.source)
    stats.audit_only = args.audit_only
    stats.dry_run = args.dry_run

    print("=" * 60)
    print("New Decoration Asset Import Pipeline")
    print("=" * 60)
    print(f"Source: {source_root}")
    print(f"Mode: {'audit-only' if args.audit_only else 'dry-run' if args.dry_run else 'import'}")

    if not source_root.exists():
        print(f"ERROR: Source directory not found: {source_root}")
        sys.exit(1)
    if not CATALOG_PATH.exists():
        print(f"ERROR: Catalog not found: {CATALOG_PATH}")
        sys.exit(1)

    # Get base SHA
    base_sha = subprocess.check_output(
        ['git', 'log', '-1', '--format=%H'],
        cwd=str(REPO_ROOT)
    ).decode().strip()
    print(f"Base SHA: {base_sha}")

    # Load effective catalogs
    print("\nLoading effective catalogs...")
    effective_assets = load_effective_catalogs()
    effective_index = build_effective_index(effective_assets)
    print(f"  Total effective assets: {len(effective_assets)}")

    # Create temp dir for ZIP extraction
    temp_dir = tempfile.mkdtemp(prefix="decor_import_")
    print(f"Temp dir: {temp_dir}")

    try:
        source_folders = sorted([
            d.name for d in source_root.iterdir()
            if d.is_dir() and d.name in FOLDER_MAP
        ])
        print(f"Found {len(source_folders)} source folders: {source_folders}")

        all_new_entries = []
        for folder_name in source_folders:
            print(f"\n--- Processing: {folder_name} ---")
            entries = process_source_folder(folder_name, temp_dir, source_root, effective_index, args.audit_only, args.dry_run)
            all_new_entries.extend(entries)
            print(f"  → {len(entries)} entries generated")

        print(f"\n{'=' * 60}")
        print(f"Total new entries: {len(all_new_entries)}")
        print(f"Would import: {len(stats.would_import)}")
        print(f"Canonical existing: {stats.canonical_existing}")

        if not args.audit_only and not args.dry_run:
            update_catalog(all_new_entries)

        final_sha = base_sha
        report = generate_report(base_sha, final_sha, source_root)
        print("\n" + report)

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        print(f"\nCleaned up temp dir: {temp_dir}")

    print("\nDone!")


if __name__ == '__main__':
    main()
