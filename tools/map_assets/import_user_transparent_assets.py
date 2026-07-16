"""Replace the editor palette with the user's already-cut transparent PNG tree."""
from __future__ import annotations

import hashlib
import json
import math
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(r"C:\Users\Administrator\Desktop\sucai")
DEST = ROOT / "assets/art/maps/_shared/user_palette"
DATA = ROOT / "assets/data/assets"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def slug(path: Path) -> str:
    return hashlib.sha1(path.as_posix().encode("utf-8")).hexdigest()[:16]


def semantics(parts: tuple[str, ...], width: int, height: int) -> dict:
    joined = "/".join(parts)
    is_ground = parts[0] == "地面"
    if is_ground:
        return dict(asset_type="ground_brush", object_class="ground", footprint=[1, 1], collision=[0, 0], policy="none", role="decoration")

    # Folder membership is authoritative. These values only describe logical
    # occupancy; they never move an asset to a Codex-created category.
    if "没有碰撞体积只是贴图" in joined:
        side = max(1, min(4, math.ceil(max(width / 128, height / 96))))
        fp, collision, policy, role, cls = [side, side], [0, 0], "none", "decoration", "visual_detail"
    elif "地面血渍" in joined:
        # Blood decals must remain a small ground detail, never a building-sized
        # image. Their logical visual size is capped to 1..4 integral tiles.
        side = max(1, min(4, math.ceil(max(width / 128, height / 96))))
        fp, collision, policy, role, cls = [side, side], [0, 0], "none", "decoration", "ground_decal"
    elif "纯美观装饰物" in joined:
        fp, collision, policy, role, cls = [1, 1], [0, 0], "none", "decoration", "visual_detail"
    elif "树木" in joined:
        fp, collision, policy, role, cls = [4, 6], [3, 3], "preset", "obstacle", "tree"
    elif "房子帐篷" in joined:
        fp, collision, policy, role, cls = [8, 8], [8, 8], "solid_footprint", "building", "building"
    elif "地图出入口" in joined:
        fp, collision, policy, role, cls = [8, 6], [0, 0], "none", "terrain", "map_entrance"
    elif "城墙" in joined:
        fp = [max(2, math.ceil(width / 64)), max(1, math.ceil(height / 64))]
        collision, policy, role, cls = fp.copy(), "solid_footprint", "terrain", "wall"
    elif "路障" in joined:
        fp = [max(1, math.ceil(width / 64)), max(1, math.ceil(height / 64))]
        collision, policy, role, cls = fp.copy(), "solid_footprint", "obstacle", "obstacle"
    elif "摊贩摊位" in joined:
        fp, collision, policy, role, cls = [4, 4], [4, 4], "solid_footprint", "building", "vendor_stall"
    elif "路灯" in joined:
        fp, collision, policy, role, cls = [2, 3], [1, 1], "preset", "obstacle", "street_lamp"
    else:
        fp = [max(1, math.ceil(width / 64)), max(1, math.ceil(height / 64))]
        collision, policy, role, cls = [0, 0], "none", "decoration", "decoration"
    return dict(asset_type="large_prop", object_class=cls, footprint=fp, collision=collision, policy=policy, role=role)


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing source: {SOURCE}")
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)

    assets = []
    for src in sorted(SOURCE.rglob("*.png"), key=lambda p: p.as_posix().casefold()):
        rel = src.relative_to(SOURCE)
        dst = DEST / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        with Image.open(src) as image:
            width, height = image.size
            if image.mode not in ("RGBA", "LA", "P") and "transparency" not in image.info:
                raise SystemExit(f"PNG has no transparency channel: {src}")
        sem = semantics(rel.parts, width, height)
        fp = sem["footprint"]
        # Keep the user's PNG byte-for-byte. Ground tiles are rendered into the
        # editor's 64x32 logical diamond instead of destructively resizing it.
        if sem["asset_type"] == "ground_brush":
            render_scale = min(64 / width, 32 / height)
        elif sem["object_class"] in ["ground_decal", "visual_detail"]:
            side = fp[0]
            render_scale = min((side * 64) / width, (side * 32) / height)
        else:
            render_scale = 1.0
        asset_id = f"user.{slug(rel.with_suffix(''))}"
        digest = sha256(dst)
        assets.append({
            "asset_id": asset_id, "display_name": src.stem,
            "asset_type": sem["asset_type"], "category": sem["object_class"], "object_class": sem["object_class"],
            "theme": "user_palette", "image": dst.relative_to(ROOT).as_posix(), "thumbnail": dst.relative_to(ROOT).as_posix(),
            "canvas_size": [width, height], "image_size": [width, height], "visible_bounds_px": [0, 0, width, height],
            "anchor_px": [width // 2, height // 2 if sem["asset_type"] == "ground_brush" else max(0, height - 1)],
            "placement_anchor_px": [width // 2, height // 2 if sem["asset_type"] == "ground_brush" else max(0, height - 1)],
            "anchor_tile": [0, 0], "anchor_mode": "tile_center" if sem["asset_type"] == "ground_brush" else "foot_tile",
            "footprint_tiles": fp, "visual_footprint_tiles": fp, "occupancy_footprint_tiles": fp,
            "base_footprint_tiles": fp, "collision_footprint_tiles": sem["collision"], "tile_size": [64, 32],
            "approved_scale": render_scale, "logical_scale_level": 0, "scale_approved": True, "anchor_approved": True,
            "default_layer": "ground_base" if sem["asset_type"] == "ground_brush" else "object_base",
            "default_object_role": sem["role"], "collision_policy": sem["policy"],
            "collision_profile_id": "none_visual" if sem["policy"] == "none" else "solid_logical_footprint",
            "navigation_policy": "ignore" if sem["policy"] == "none" else "block_player_and_monster",
            "occlusion": sem["policy"] != "none", "content_layer": "personal_expansion", "placeable": True,
            "calibration_status": "placeable", "palette_path": rel.parent.as_posix(),
            "source_external_path": str(src), "source_sha256": digest, "output_sha256": digest,
            "thumbnail_source_sha256": digest, "processing": "user_pre_cut_transparent_passthrough",
            "tags": ["user_source", *rel.parent.parts], "editable": True,
            "allows_edge_clipping": sem["object_class"] == "map_entrance",
            "semantic_role": "map_portal" if sem["object_class"] == "map_entrance" else "",
            "trigger_on_enter": sem["object_class"] == "map_entrance",
        })

    catalog = {"asset_schema_version": 2, "palette_source": str(SOURCE), "classification_policy": "source_folders_only", "assets": assets}
    text = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    (DATA / "map_asset_catalog.json").write_text(text, encoding="utf-8")
    (DATA / "map_direct_folder_asset_catalog.json").write_text(text, encoding="utf-8")
    print(f"USER_TRANSPARENT_PALETTE_PASS assets={len(assets)} folders={len({a['palette_path'] for a in assets})}")


if __name__ == "__main__":
    main()
