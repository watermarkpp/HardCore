"""Promote V1.5 batches that have passed structural/editor semantic review."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "assets" / "art" / "maps" / "_staging" / "v1_5"
FORMAL = ROOT / "assets" / "art" / "maps" / "_shared" / "v1_5"
OUTPUT = ROOT / "assets" / "data" / "assets" / "map_v15_batch_asset_catalog.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def terrain_type(batch: str) -> str:
    return {
        "A-001": "grass", "A-002": "grass", "A-003": "deep_grass", "A-004": "mud", "A-005": "mud",
        "A-006": "dirt_road", "A-007": "dirt_road", "A-008": "paved_road", "A-009": "paved_road",
        "A-010": "water", "A-011": "grass_to_water", "A-012": "grass_to_water", "A-013": "stone",
        "A-014": "cracked_stone", "A-015": "mine_rock",
    }.get(batch, "bich_outdoor")


def main() -> None:
    assets = []
    for metadata_path in sorted(STAGING.rglob("batch_metadata.json")):
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        batch = metadata["batch_id"]
        source_sha = sha(metadata_path.parent / "source" / metadata["source_file"])
        for item in metadata["assets"]:
            src = metadata_path.parent / "editor_canvas" / item["file"]
            destination = FORMAL / batch / item["file"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, destination)
            with Image.open(destination) as image:
                alpha = image.getchannel("A")
                box = alpha.getbbox() or (0, 0, 0, 0)
                canvas = list(image.size)
            role = item["role"]
            is_ground = role in {"base_tile", "road_tile", "transition_tile"}
            is_overlay = role == "overlay_detail"
            is_terrain = item["default_layer"] == "terrain_base"
            asset_type = "ground_brush" if is_ground else "terrain_stamp" if is_overlay or is_terrain else "large_prop"
            default_role = "terrain" if is_terrain else "obstacle" if item["collision_policy"] != "none" else "decoration"
            relative = destination.relative_to(ROOT).as_posix()
            record = {
                "asset_id": item["asset_id"].replace("staging.", ""), "display_name": f"{batch} {item['source_cell']['index']:02d}",
                "asset_type": asset_type, "category": "ground" if is_ground else "terrain" if is_terrain else "overlay" if is_overlay else "prop",
                "theme": "ancient_gothic", "image": relative, "thumbnail": relative, "canvas_size": canvas, "image_size": canvas,
                "visible_bounds_px": [box[0], box[1], box[2] - box[0], box[3] - box[1]], "anchor_px": item["anchor_px"],
                "anchor_tile": [0, 0], "anchor_mode": "tile_center" if is_ground else "foot_tile", "footprint_tiles": item["footprint_tiles"],
                "tile_size": [64, 32], "default_layer": item["default_layer"], "default_object_role": default_role,
                "collision_policy": item["collision_policy"], "navigation_policy": item["navigation_policy"], "occlusion": item["occlusion"],
                "content_layer": "personal_expansion", "placeable": True, "calibration_status": "placeable",
                "tags": ["v1_5", batch.lower(), role, "ancient_gothic"], "source_sha256": source_sha, "output_sha256": sha(destination),
                "thumbnail_source_sha256": sha(destination), "raw_import_path": f"assets/raw_import/map_editor_batches_v1_5/{batch}/{metadata['title']}/{metadata['source_file']}",
                "processing": "v1_5_local_key_remove_cell_cut_canvas_semantic_audit",
            }
            if is_ground:
                record.update({"logical_bounds_px": [0, 0, canvas[0], canvas[1]], "ground_brush_role": role, "terrain_type": terrain_type(batch), "paintable": True, "diamond_inner_coverage": 1.0})
            assets.append(record)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"asset_schema_version": 2, "assets": assets}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"promoted_v1_5_assets={len(assets)}")


if __name__ == "__main__":
    main()
