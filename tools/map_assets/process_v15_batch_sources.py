"""Local-only V1.5 batch source processor.

Copies batch source artwork, removes its keyed background by border-connected HSV
segmentation, cuts each declared invisible-grid cell, and emits transparent PNG
candidates on the declared editor canvas.  Outputs remain staging assets until
visual/connection QA promotes them into the formal map asset catalog.
"""
from __future__ import annotations

import json
import shutil
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


SOURCE_ROOT = Path(r"C:\Users\Administrator\Desktop\sucai\fangansucai")
PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = PROJECT_ROOT / "assets" / "raw_import" / "map_editor_batches_v1_5"
STAGING_ROOT = PROJECT_ROOT / "assets" / "art" / "maps" / "_staging" / "v1_5"
REPORT_PATH = PROJECT_ROOT / "docs" / "mafa_scene_editor" / "V1.5_Local_Asset_Processing_Report.json"


@dataclass(frozen=True)
class Batch:
    source: str
    batch_id: str
    title: str
    count: int
    grid: tuple[int, int]  # columns, rows
    canvas: tuple[int, int]
    role: str


def batch(source: str, ident: str, title: str, count: int, grid: tuple[int, int], canvas: tuple[int, int], role: str) -> Batch:
    return Batch(source, ident, title, count, grid, canvas, role)


# Exact source batches currently supplied by the user.  Count/grid comes from
# the V1.5 manifest and observed single-row ground batches are explicit.
BATCHES = [
    batch("a001", "A-001", "基础草地组_01", 8, (8, 1), (64, 32), "base_tile"),
    batch("a002", "A-002", "基础草地组_02", 8, (8, 1), (64, 32), "base_tile"),
    batch("a003", "A-003", "深草地组", 4, (4, 1), (64, 32), "base_tile"),
    batch("a004", "A-004", "泥地组_01", 6, (3, 2), (64, 32), "base_tile"),
    batch("a005", "A-005", "泥地组_02", 6, (3, 2), (64, 32), "base_tile"),
    batch("a006", "A-006", "土路组_01", 8, (4, 2), (64, 32), "road_tile"),
    batch("a007", "A-007", "土路组_02", 4, (2, 2), (64, 32), "road_tile"),
    batch("a008", "A-008", "石板路组_01", 8, (4, 2), (64, 32), "road_tile"),
    batch("a009", "A-009", "石板路组_02", 4, (2, 2), (64, 32), "road_tile"),
    batch("a010", "A-010", "水面组", 4, (2, 2), (64, 32), "base_tile"),
    batch("a011", "A-011", "水岸过渡组_01", 8, (4, 2), (64, 32), "transition_tile"),
    batch("a012", "A-012", "水岸过渡组_02", 8, (4, 2), (64, 32), "transition_tile"),
    batch("a013", "A-013", "石地组", 8, (4, 2), (64, 32), "base_tile"),
    batch("a014", "A-014", "裂石地组", 8, (4, 2), (64, 32), "base_tile"),
    batch("a015", "A-015", "矿区岩地组", 8, (4, 2), (64, 32), "base_tile"),
    batch("a022", "A-022", "地面裂缝污渍杂草覆盖层_01", 8, (4, 2), (64, 64), "overlay_detail"),
    batch("a023", "A-023", "地面覆盖层_02", 8, (4, 2), (64, 64), "overlay_detail"),
    batch("b001", "B-001", "普通树组_01", 6, (3, 2), (96, 128), "decoration"),
    batch("b002", "B-002", "普通树组_02", 6, (3, 2), (96, 128), "decoration"),
    batch("b003", "B-003", "枯树组", 4, (2, 2), (96, 128), "decoration"),
    batch("b004", "B-004", "小石头组", 6, (3, 2), (64, 64), "decoration"),
    batch("b005", "B-005", "小石头组补充", 2, (2, 1), (64, 64), "decoration"),
    batch("b006", "B-006", "中型岩石组", 6, (3, 2), (96, 128), "obstacle"),
    batch("b007", "B-007", "大型岩石组", 4, (2, 2), (128, 160), "obstacle"),
    batch("b008", "B-008", "栅栏组_01", 6, (3, 2), (96, 64), "terrain"),
    batch("b009", "B-009", "栅栏组_02", 2, (2, 1), (96, 64), "terrain"),
    batch("b010", "B-010", "野外小装饰组", 6, (3, 2), (64, 96), "decoration"),
    batch("b011", "B-011", "野外边界组", 6, (3, 2), (128, 160), "terrain"),
    batch("b012", "B-012", "野外入口组", 4, (2, 2), (192, 160), "terrain"),
]


def background_mask(bgr: np.ndarray) -> np.ndarray:
    """Return the high-value key colour, including background trapped in holes."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    h, w = hsv.shape[:2]
    edge = np.concatenate((hsv[:8].reshape(-1, 3), hsv[-8:].reshape(-1, 3), hsv[:, :8].reshape(-1, 3), hsv[:, -8:].reshape(-1, 3)))
    key_hue = int(np.median(edge[:, 0]))
    # Hue is cyclic in OpenCV's 0..179 representation.  Source images use a
    # very bright, fully saturated key.  Removing it globally (rather than only
    # at the border) is necessary for fence gaps and cave-door apertures.
    hue_distance = np.abs(hsv[:, :, 0].astype(np.int16) - key_hue)
    hue_distance = np.minimum(hue_distance, 180 - hue_distance)
    # Include anti-aliased key spill.  The V1.5 key-colour contract reserves
    # this hue for the background, so eliminating it is safer than retaining a
    # visible magenta/cyan fringe on a transparent game sprite.
    return (hue_distance <= 24) & (hsv[:, :, 1] >= 70) & (hsv[:, :, 2] >= 45)


def crop_cell(bgra: np.ndarray, columns: int, rows: int, index: int) -> np.ndarray:
    h, w = bgra.shape[:2]
    col, row = index % columns, index // columns
    x0, x1 = round(col * w / columns), round((col + 1) * w / columns)
    y0, y1 = round(row * h / rows), round((row + 1) * h / rows)
    return bgra[y0:y1, x0:x1].copy()


def tight_crop(bgra: np.ndarray, padding: int = 3) -> np.ndarray:
    alpha = bgra[:, :, 3]
    ys, xs = np.where(alpha > 8)
    if xs.size == 0:
        return bgra
    x0, x1 = max(0, xs.min() - padding), min(bgra.shape[1], xs.max() + padding + 1)
    y0, y1 = max(0, ys.min() - padding), min(bgra.shape[0], ys.max() + padding + 1)
    return bgra[y0:y1, x0:x1].copy()


def normalize_canvas(bgra: np.ndarray, canvas: tuple[int, int], role: str) -> np.ndarray:
    target_w, target_h = canvas
    cropped = tight_crop(bgra)
    h, w = cropped.shape[:2]
    if w <= 0 or h <= 0:
        return np.zeros((target_h, target_w, 4), np.uint8)
    # Ground tiles fill the logical canvas; props retain a 4% safety border and
    # rest on the bottom anchor, matching the editor's foot-tile convention.
    margin = 0.0 if role in {"base_tile", "road_tile", "transition_tile"} else 0.06
    max_w, max_h = max(1, round(target_w * (1 - margin * 2))), max(1, round(target_h * (1 - margin * 2)))
    scale = min(max_w / w, max_h / h)
    resized = cv2.resize(cropped, (max(1, round(w * scale)), max(1, round(h * scale))), interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC)
    output = np.zeros((target_h, target_w, 4), np.uint8)
    x = (target_w - resized.shape[1]) // 2
    y = (target_h - resized.shape[0]) // 2 if role in {"base_tile", "road_tile", "transition_tile", "overlay_detail"} else target_h - resized.shape[0] - max(1, round(target_h * margin))
    output[y:y + resized.shape[0], x:x + resized.shape[1]] = resized
    if role in {"base_tile", "road_tile", "transition_tile"}:
        mask = np.zeros((target_h, target_w), np.uint8)
        cv2.fillConvexPoly(mask, np.array([[target_w // 2, 0], [target_w - 1, target_h // 2], [target_w // 2, target_h - 1], [0, target_h // 2]], np.int32), 255)
        holes = (mask > 0) & (output[:, :, 3] == 0)
        if np.any(holes):
            output[:, :, :3] = cv2.inpaint(output[:, :, :3], holes.astype(np.uint8) * 255, 3, cv2.INPAINT_TELEA)
        output[:, :, 3] = mask
    return output


def editor_semantics(entry: Batch) -> tuple[list[int], list[int], str, str, str, bool]:
    if entry.role in {"base_tile", "road_tile", "transition_tile"}:
        return [1, 1], [entry.canvas[0] // 2, entry.canvas[1] // 2], "none", "ignore", "ground_base", False
    mapping = {
        "b001": ([2, 2], "preset", "block_player_and_monster", "object_base", True),
        "b002": ([2, 2], "preset", "block_player_and_monster", "object_base", True),
        "b003": ([2, 2], "preset", "block_player_and_monster", "object_base", True),
        "b004": ([1, 1], "preset", "block_player_and_monster", "object_base", False),
        "b005": ([1, 1], "preset", "block_player_and_monster", "object_base", False),
        "b006": ([2, 2], "preset", "block_player_and_monster", "object_base", True),
        "b007": ([3, 3], "preset", "block_player_and_monster", "object_base", True),
        "b008": ([2, 1], "terrain_stamp_generated", "block_player_and_monster", "terrain_base", True),
        "b009": ([2, 1], "terrain_stamp_generated", "block_player_and_monster", "terrain_base", True),
        "b010": ([1, 1], "none", "ignore", "object_base", False),
        "b011": ([3, 2], "terrain_stamp_generated", "block_player_and_monster", "terrain_base", True),
        "b012": ([3, 2], "terrain_stamp_generated", "block_player_and_monster", "terrain_base", True),
    }
    footprint, collision, navigation, layer, occlusion = mapping.get(entry.source, ([1, 1], "none", "ignore", "object_base", False))
    return footprint, [entry.canvas[0] // 2, entry.canvas[1] - 2], collision, navigation, layer, occlusion


def write_png(path: Path, image: np.ndarray) -> None:
    """Use imencode so Windows OpenCV never loses Unicode destination paths."""
    ok, encoded = cv2.imencode(".png", image)
    if not ok:
        raise RuntimeError(f"png_encode_failed:{path}")
    path.write_bytes(encoded.tobytes())


def process(entry: Batch) -> dict:
    source = SOURCE_ROOT / f"{entry.source}.png"
    if not source.exists():
        return {"batch_id": entry.batch_id, "status": "missing_source"}
    image = cv2.imread(str(source), cv2.IMREAD_COLOR)
    if image is None:
        return {"batch_id": entry.batch_id, "status": "unreadable_source"}
    if entry.grid[0] * entry.grid[1] != entry.count:
        return {"batch_id": entry.batch_id, "status": "invalid_grid"}
    stage_dir = STAGING_ROOT / entry.batch_id / entry.title
    raw_dir = RAW_ROOT / entry.batch_id / entry.title
    source_dir, rgba_dir, canvas_dir = stage_dir / "source", stage_dir / "rgba_native", stage_dir / "editor_canvas"
    for directory in [raw_dir, source_dir, rgba_dir, canvas_dir]:
        directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, raw_dir / source.name)
    shutil.copy2(source, source_dir / source.name)
    key_background = background_mask(image)
    alpha = np.where(key_background, 0, 255).astype(np.uint8)
    bgra = cv2.cvtColor(image, cv2.COLOR_BGR2BGRA)
    bgra[:, :, 3] = alpha
    assets = []
    footprint, anchor, collision, navigation, layer, occlusion = editor_semantics(entry)
    for index in range(entry.count):
        native = tight_crop(crop_cell(bgra, *entry.grid, index))
        canvas = normalize_canvas(native, entry.canvas, entry.role)
        asset_name = f"{entry.source}_{index + 1:02d}.png"
        native_path, canvas_path = rgba_dir / asset_name, canvas_dir / asset_name
        write_png(native_path, native)
        write_png(canvas_path, canvas)
        assets.append({
            "asset_id": f"staging.v1_5.{entry.source}_{index + 1:02d}", "file": asset_name,
            "source_cell": {"index": index + 1, "grid": list(entry.grid)}, "canvas_size": list(entry.canvas),
            "anchor_px": anchor, "footprint_tiles": footprint, "collision_policy": collision, "navigation_policy": navigation,
            "default_layer": layer, "occlusion": occlusion, "role": entry.role,
            "alpha_pixels": int(np.count_nonzero(canvas[:, :, 3])), "status": "staging_pending_visual_qa",
        })
    metadata = {"batch_id": entry.batch_id, "title": entry.title, "source_file": source.name, "expected_count": entry.count,
                "grid": list(entry.grid), "target_canvas_size": list(entry.canvas), "role": entry.role,
                "processing": "local_hsv_border_connected_key_removal", "assets": assets}
    (stage_dir / "batch_metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"batch_id": entry.batch_id, "status": "processed", "count": entry.count, "folder": str(stage_dir.relative_to(PROJECT_ROOT)).replace("\\", "/")}


def main() -> None:
    results = [process(entry) for entry in BATCHES]
    report = {"spec": "V1.5", "source_root": str(SOURCE_ROOT), "processed_batches": results,
              "processed_asset_count": sum(item.get("count", 0) for item in results),
              "status": "staging_only_requires_visual_and_connection_qa"}
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
