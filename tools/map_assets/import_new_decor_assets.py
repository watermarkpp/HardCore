#!/usr/bin/env python3
"""
Import new decoration assets into Mafa Scene Editor '装饰物1' category.

Reads source PNGs from C:\\Users\\Administrator\\Desktop\\sucai\\新增,
processes them (cut multi-asset sheets, validate transparency, trim),
and registers them in the map_asset_catalog.json.

Idempotent: safe to re-run. Will not duplicate existing entries.
"""

import hashlib
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

# ── paths ──────────────────────────────────────────────────────────────
REPO_ROOT = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\maps")
SOURCE_ROOT = Path(r"C:\Users\Administrator\Desktop\sucai\新增")
CATALOG_PATH = REPO_ROOT / "assets" / "data" / "assets" / "map_asset_catalog.json"
ASSET_BASE = REPO_ROOT / "assets" / "art" / "maps" / "_shared" / "user_palette" / "decorations_1"
REPORT_PATH = REPO_ROOT / "docs" / "mafa_scene_editor" / "new_decor_assets_import_report.md"

# ── folder mapping: source folder name → (english_dir, palette_sub) ───
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
MIN_GAP_PX = 20  # minimum transparent gap to consider a cut boundary
ALPHA_THRESHOLD = 10  # pixels below this alpha are "transparent" for gap detection


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
        self.by_category = {}
        self.problems = []

    def cat_count(self, cat):
        self.by_category.setdefault(cat, 0)
        self.by_category[cat] += 1


stats = Stats()


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
                # avoid name collision
                counter = 1
                base, ext = os.path.splitext(out_name)
                while os.path.exists(out_path):
                    out_path = os.path.join(temp_dir, f"{base}_{counter}{ext}")
                    counter += 1
                with zf.open(entry) as src, open(out_path, 'wb') as dst:
                    dst.write(src.read())
                extracted.append(out_path)
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
    # Find runs of transparent lines
    runs = []
    i = 0
    while i < length:
        if status_list[i]:
            start = i
            while i < length and status_list[i]:
                i += 1
            runs.append((start, i - 1, i - start))  # start, end, width
        else:
            i += 1

    # Filter: only keep runs that are wide enough AND have opaque content on both sides
    valid_cuts = []
    for start, end, width in runs:
        if width < MIN_GAP_PX:
            continue
        # Check there's opaque content before and after
        has_before = any(not status_list[j] for j in range(0, start))
        has_after = any(not status_list[j] for j in range(end + 1, length))
        if has_before and has_after:
            valid_cuts.append((start + width // 2, width))  # cut at center of gap

    return valid_cuts


def detect_multi_asset(img):
    """Detect if image contains multiple assets arranged in grid."""
    w, h = img.size
    if w < 200 or h < 200:
        return False  # too small to be a sprite sheet

    row_tr, col_tr = get_alpha_row_col_status(img)

    # Count opaque rows/cols
    opaque_rows = sum(1 for r in row_tr if not r)
    opaque_cols = sum(1 for c in col_tr if not c)

    # If most rows and cols have some opaque content, it's likely a single asset
    # If there are clear horizontal/vertical gaps, it's multi-asset
    h_cuts = find_cut_positions(row_tr, h)
    v_cuts = find_cut_positions(col_tr, w)

    return len(h_cuts) > 0 or len(v_cuts) > 0


def cut_image(img, row_tr, col_tr, h, w):
    """Cut image into individual assets based on transparent gaps."""
    h_cuts = find_cut_positions(row_tr, h)
    v_cuts = find_cut_positions(col_tr, w)

    # Build row segments
    if h_cuts:
        row_segments = []
        prev = 0
        for cut_pos, _ in h_cuts:
            # Find the actual gap boundaries
            gap_start = cut_pos - MIN_GAP_PX // 2
            gap_end = cut_pos + MIN_GAP_PX // 2
            # Refine: find exact transparent boundaries
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

    # Build col segments
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

    # Generate crops
    crops = []
    for ry1, ry2 in row_segments:
        for cx1, cx2 in col_segments:
            # Check this segment has actual content
            crop = img.crop((cx1, ry1, cx2, ry2))
            if has_visible_content(crop):
                crops.append(crop)

    return crops if len(crops) > 1 else [img]  # fallback to single if cutting produced ≤1


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

    # Add padding
    x1 = max(0, vx1 - padding)
    y1 = max(0, vy1 - padding)
    x2 = min(w, vx2 + padding)
    y2 = min(h, vy2 + padding)

    # Extra top padding for visual breathing room
    y1 = max(0, y1 - padding // 2)

    cropped = img.crop((x1, y1, x2, y2))
    return cropped, (vx1 - x1, vy1 - y1, vx2 - x1, vy2 - y1)


# ── transparency validation ────────────────────────────────────────────
def validate_transparency(img, source_name=""):
    """
    Check transparency quality.
    Returns (pass: bool, issues: list[str])
    """
    issues = []

    # Must have alpha
    if img.mode != 'RGBA':
        issues.append("No alpha channel")
        return False, issues

    w, h = img.size
    alpha = img.getchannel('A')
    pixels_alpha = list(alpha.getdata())
    pixels_rgb = list(img.convert('RGB').getdata())

    # Check corners (10x10 region) - should be mostly transparent
    corner_size = min(10, w // 4, h // 4)
    corners = [
        (0, 0, corner_size, corner_size),  # top-left
        (w - corner_size, 0, w, corner_size),  # top-right
        (0, h - corner_size, corner_size, h),  # bottom-left
        (w - corner_size, h - corner_size, w, h),  # bottom-right
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
            issues.append(f"Corner ({cx1},{cy1})-({cx2},{cy2}) has opaque background ({opaque_count}/{total})")

    # Check for background color residue in semi-transparent edge pixels
    # Sample edge pixels (alpha 1-254) and check for color contamination
    bounds = compute_visible_bounds(img)
    vx1, vy1, vx2, vy2 = bounds

    # Expand bounds by 4px for edge scanning
    scan_x1 = max(0, vx1 - 4)
    scan_y1 = max(0, vy1 - 4)
    scan_x2 = min(w, vx2 + 4)
    scan_y2 = min(h, vy2 + 4)

    bg_colors = {"white": 0, "black": 0, "green": 0, "magenta": 0, "cyan": 0, "blue": 0}
    semi_transparent_count = 0

    for y in range(scan_y1, scan_y2):
        for x in range(scan_x1, scan_x2):
            idx = y * w + x
            a = pixels_alpha[idx]
            if 1 <= a <= 200:  # semi-transparent
                semi_transparent_count += 1
                r, g, b = pixels_rgb[idx]
                # Check for common background colors
                if r > 220 and g > 220 and b > 220:
                    bg_colors["white"] += 1
                elif r < 30 and g < 30 and b < 30:
                    bg_colors["black"] += 1
                elif g > 180 and r < 100 and b < 100:
                    bg_colors["green"] += 1
                elif r > 180 and g < 100 and b > 180:
                    bg_colors["magenta"] += 1
                elif r < 100 and g > 180 and b > 180:
                    bg_colors["cyan"] += 1
                elif b > 180 and r < 100 and g < 100:
                    bg_colors["blue"] += 1

    if semi_transparent_count > 0:
        for color_name, count in bg_colors.items():
            ratio = count / semi_transparent_count
            if ratio > 0.3 and count > 20:
                issues.append(f"Edge contamination: {color_name} residue ({count}/{semi_transparent_count} = {ratio:.0%})")

    # Check for large opaque background areas outside the visible content
    total_outside = 0
    opaque_outside = 0
    for y in range(h):
        for x in range(w):
            idx = y * w + x
            inside = vx1 <= x < vx2 and vy1 <= y < vy2
            if not inside:
                total_outside += 1
                if pixels_alpha[idx] > 200:
                    opaque_outside += 1

    if total_outside > 100 and opaque_outside / total_outside > 0.5:
        issues.append(f"Large opaque area outside content ({opaque_outside}/{total_outside})")

    passed = len(issues) == 0
    return passed, issues


# ── metadata computation ───────────────────────────────────────────────
def compute_metadata(img, visible_bounds_in_trimmed):
    """Compute catalog metadata fields from image and visible bounds."""
    w, h = img.size
    vx1, vy1, vx2, vy2 = visible_bounds_in_trimmed
    vis_w = vx2 - vx1
    vis_h = vy2 - vy1

    canvas_size = [w, h]
    image_size = [w, h]
    visible_bounds = [vx1, vy1, vis_w, vis_h]

    # Anchor: bottom center of visible content
    anchor_x = vx1 + vis_w // 2
    anchor_y = vy2  # bottom of visible content
    anchor_px = [anchor_x, anchor_y]
    placement_anchor_px = [anchor_x, anchor_y]

    # Footprint: based on visible pixel extent
    fp_w = max(1, (vis_w + TILE_W - 1) // TILE_W)
    fp_h = max(1, (vis_h + TILE_H - 1) // TILE_H)
    # Clamp to reasonable range
    fp_w = min(fp_w, 12)
    fp_h = min(fp_h, 12)

    footprint_tiles = [fp_w, fp_h]

    return {
        "canvas_size": canvas_size,
        "image_size": image_size,
        "visible_bounds_px": visible_bounds,
        "anchor_px": anchor_px,
        "placement_anchor_px": placement_anchor_px,
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint_tiles,
        "visual_footprint_tiles": footprint_tiles,
        "occupancy_footprint_tiles": footprint_tiles,
        "base_footprint_tiles": footprint_tiles,
        "collision_footprint_tiles": [0, 0],
        "tile_size": [TILE_W, TILE_H],
    }


def generate_asset_id(source_path, img_data):
    """Generate a unique asset_id in the format user.{hex16}."""
    h = hashlib.sha256()
    h.update(source_path.encode('utf-8'))
    h.update(img_data)
    return "user." + h.hexdigest()[:16]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


# ── main processing ────────────────────────────────────────────────────
def process_single_png(png_path, category_en, category_cn, output_dir, existing_ids):
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
            "status": "REJECTED",
        })
        stats.rejected += 1
        return entries

    # Ensure RGBA
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    stats.source_pngs += 1

    # Detect multi-asset
    is_multi = detect_multi_asset(img)

    if is_multi:
        row_tr, col_tr = get_alpha_row_col_status(img)
        crops = cut_image(img, row_tr, col_tr, img.size[1], img.size[0])
        stats.identifed_individual += len(crops)
    else:
        crops = [img]
        stats.identifed_individual += 1

    for i, crop_img in enumerate(crops):
        if crop_img.mode != 'RGBA':
            crop_img = crop_img.convert('RGBA')

        # Trim with padding
        trimmed, vis_bounds = trim_with_padding(crop_img, padding=20)

        # Validate transparency
        passed, issues = validate_transparency(trimmed, str(png_path))
        if passed:
            stats.transparency_pass += 1
        else:
            stats.transparency_fail += 1
            if any("opaque background" in iss.lower() for iss in issues):
                # Serious issue - reject
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
                # Minor edge issues - still import but note in report
                stats.problems.append({
                    "source": str(png_path),
                    "category": category_cn,
                    "issue": "; ".join(issues),
                    "fixable": True,
                    "status": "IMPORTED_WITH_WARNINGS",
                })

        # Generate output filename
        img_bytes = io_bytes(trimmed)
        asset_id = generate_asset_id(str(png_path) + f"_{i}", img_bytes)

        if asset_id in existing_ids:
            stats.duplicate_skipped += 1
            continue

        # Determine display name and file name
        src_stem = Path(png_path).stem
        if is_multi and len(crops) > 1:
            out_name = f"{src_stem}_part{i+1}.png"
        else:
            out_name = f"{src_stem}.png"

        # Sanitize filename
        out_name = "".join(c for c in out_name if c.isalnum() or c in "._-").strip()
        if not out_name.endswith('.png'):
            out_name += '.png'

        out_path = output_dir / out_name

        # Handle name collision
        counter = 1
        stem = Path(out_name).stem
        while out_path.exists():
            existing_sha = sha256_file(out_path)
            new_sha = sha256_bytes(img_bytes)
            if existing_sha == new_sha:
                stats.duplicate_skipped += 1
                # Still register if not in catalog
                break
            out_name = f"{stem}_{counter}.png"
            out_path = output_dir / out_name
            counter += 1

        # Save
        trimmed.save(out_path, 'PNG')
        stats.successfully_cut += 1

        # Compute metadata
        trimmed_w, trimmed_h = trimmed.size
        meta = compute_metadata(trimmed, vis_bounds)

        source_sha = sha256_bytes(img_bytes)
        rel_image_path = f"assets/art/maps/_shared/user_palette/decorations_1/{category_en}/{out_name}"

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
            "occlusion": True,
            "content_layer": "personal_expansion",
            "placeable": True,
            "calibration_status": "placeable",
            "palette_path": f"装饰物1/{category_cn}",
            "source_external_path": str(png_path),
            "source_sha256": source_sha,
            "output_sha256": source_sha,
            "thumbnail_source_sha256": source_sha,
            "processing": "user_pre_cut_transparent_passthrough",
            "tags": ["user_source", "装饰物1", category_cn],
            "editable": True,
            "allows_edge_clipping": False,
            "semantic_role": "",
            "trigger_on_enter": False,
        })

        entries.append(entry)
        stats.imported += 1
        stats.cat_count(category_cn)

    return entries


def io_bytes(img):
    """Get PNG bytes for hashing."""
    import io
    buf = io.BytesIO()
    img.save(buf, 'PNG')
    return buf.getvalue()


def process_source_folder(folder_name, temp_extract_dir):
    """Process all PNGs from a source folder."""
    if folder_name not in FOLDER_MAP:
        return []

    category_en, category_cn = FOLDER_MAP[folder_name]
    source_dir = SOURCE_ROOT / folder_name
    output_dir = ASSET_BASE / category_en
    output_dir.mkdir(parents=True, exist_ok=True)

    stats.source_dirs += 1

    # Collect PNGs
    png_files = []

    # Direct PNGs
    for f in sorted(source_dir.glob("*.png")):
        png_files.append(str(f))

    # ZIP files - extract transparent_assets
    for z in sorted(source_dir.glob("*.zip")):
        extracted = extract_zip_transparent_assets(str(z), temp_extract_dir)
        png_files.extend(extracted)

    if not png_files:
        return []

    # Load existing catalog to check for duplicates
    existing_ids = set()
    if CATALOG_PATH.exists():
        with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
            catalog = json.load(f)
        existing_ids = set(a['asset_id'] for a in catalog['assets'])
        # Also check existing image paths
        existing_paths = set(a['image'] for a in catalog['assets'])
    else:
        existing_paths = set()

    all_entries = []
    for png_path in png_files:
        entries = process_single_png(png_path, category_en, category_cn, output_dir, existing_ids)
        for e in entries:
            if e['image'] not in existing_paths:
                all_entries.append(e)
                existing_ids.add(e['asset_id'])
                existing_paths.add(e['image'])

    return all_entries


def update_catalog(new_entries):
    """Add new entries to the catalog JSON."""
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


def generate_report(base_sha, final_sha):
    """Generate the import report."""
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    lines.append("# NEW_DECOR_ASSET_IMPORT_REPORT")
    lines.append("")
    lines.append(f"BASE_SHA = {base_sha}")
    lines.append(f"FINAL_SHA = {final_sha}")
    lines.append("")
    lines.append(f"SOURCE = {SOURCE_ROOT}")
    lines.append("")
    lines.append(f"扫描源图 = {stats.source_pngs}")
    lines.append(f"识别独立素材 = {stats.identifed_individual}")
    lines.append(f"正式导入 = {stats.imported}")
    lines.append(f"拒绝 = {stats.rejected}")
    lines.append(f"重复跳过 = {stats.duplicate_skipped}")
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
    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        f.write(report_text)

    print(f"Report written to {REPORT_PATH}")
    return report_text


def main():
    print("=" * 60)
    print("New Decoration Asset Import Pipeline")
    print("=" * 60)

    # Verify paths
    if not SOURCE_ROOT.exists():
        print(f"ERROR: Source directory not found: {SOURCE_ROOT}")
        sys.exit(1)
    if not CATALOG_PATH.exists():
        print(f"ERROR: Catalog not found: {CATALOG_PATH}")
        sys.exit(1)

    # Get base SHA
    import subprocess
    base_sha = subprocess.check_output(
        ['git', 'log', '-1', '--format=%H'],
        cwd=str(REPO_ROOT)
    ).decode().strip()
    print(f"Base SHA: {base_sha}")

    # Create temp dir for ZIP extraction
    temp_dir = tempfile.mkdtemp(prefix="decor_import_")
    print(f"Temp dir: {temp_dir}")

    try:
        # Discover source folders
        source_folders = sorted([
            d.name for d in SOURCE_ROOT.iterdir()
            if d.is_dir() and d.name in FOLDER_MAP
        ])
        print(f"Found {len(source_folders)} source folders: {source_folders}")

        # Process each folder
        all_new_entries = []
        for folder_name in source_folders:
            print(f"\n--- Processing: {folder_name} ---")
            entries = process_source_folder(folder_name, temp_dir)
            all_new_entries.extend(entries)
            print(f"  → {len(entries)} entries generated")

        print(f"\n{'=' * 60}")
        print(f"Total new entries: {len(all_new_entries)}")

        # Update catalog
        if all_new_entries:
            update_catalog(all_new_entries)

        # Get final SHA (will be same until commit)
        final_sha = base_sha

        # Generate report
        report = generate_report(base_sha, final_sha)
        print("\n" + report)

    finally:
        # Cleanup temp dir
        shutil.rmtree(temp_dir, ignore_errors=True)
        print(f"\nCleaned up temp dir: {temp_dir}")

    print("\nDone!")


if __name__ == '__main__':
    main()
