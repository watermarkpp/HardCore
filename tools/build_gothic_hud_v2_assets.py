from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from ui_frame_geometry_opencv import analyze_frame


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dev_art_sources" / "ui" / "gothic_hud_v2" / "round_frame_prototypes" / "alpha" / "round_frame_b.png"
OUTPUT_ROOT = ROOT / "assets" / "ui" / "gothic_preview" / "frames"
ROUND_RUNTIME = OUTPUT_ROOT / "round_action_frame_runtime_v2.png"
CHASSIS_RUNTIME = OUTPUT_ROOT / "bottom_hud_chassis_runtime_v1.png"
SQUARE_RUNTIME = OUTPUT_ROOT / "gothic_slot_frame_runtime_v1.png"
GEOMETRY_OUTPUT = OUTPUT_ROOT / "gothic_hud_frame_geometry_v2.json"


def _visible_bbox(image: Image.Image, threshold: int = 12) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise RuntimeError("round frame prototype has no visible alpha")
    return bbox


def build_round_runtime() -> None:
    image = Image.open(SOURCE).convert("RGBA")
    source_geometry = analyze_frame(SOURCE)
    main_hole = source_geometry["enclosedTransparentRegions"][0]
    center_x, center_y = main_hole["inscribedCircle"]["center"]
    left, top, right, bottom = _visible_bbox(image)
    half_extent = int(max(center_x - left, right - center_x, center_y - top, bottom - center_y))
    crop_box = (center_x - half_extent, center_y - half_extent, center_x + half_extent, center_y + half_extent)
    crop = image.crop(crop_box).resize((128, 128), Image.Resampling.LANCZOS)
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    crop.save(ROUND_RUNTIME, optimize=True)


def main() -> None:
    build_round_runtime()
    round_geometry = analyze_frame(ROUND_RUNTIME)
    chassis_geometry = analyze_frame(CHASSIS_RUNTIME)
    square_geometry = analyze_frame(SQUARE_RUNTIME)
    chassis_holes = chassis_geometry["enclosedTransparentRegions"][:2]
    chassis_holes.sort(key=lambda region: region["inscribedCircle"]["center"][0])
    payload = {
        "taskId": "UI-GOTHIC-PREVIEW-1",
        "engine": "OpenCV connectedComponentsWithStats + precise L2 distanceTransform",
        "selection": {
            "chosenPrototype": "round_frame_b",
            "reason": "highest main-hole contour circularity and selection score among A/B/C"
        },
        "bottomChassis": {
            "path": "res://assets/ui/gothic_preview/frames/bottom_hud_chassis_runtime_v1.png",
            "size": chassis_geometry["size"],
            "healthHole": chassis_holes[0]["inscribedCircle"],
            "manaHole": chassis_holes[1]["inscribedCircle"]
        },
        "squareSlotFrame": {
            "path": "res://assets/ui/gothic_preview/frames/gothic_slot_frame_runtime_v1.png",
            "size": square_geometry["size"],
            "hole": square_geometry["enclosedTransparentRegions"][0]
        },
        "roundActionFrame": {
            "path": "res://assets/ui/gothic_preview/frames/round_action_frame_runtime_v2.png",
            "size": round_geometry["size"],
            "hole": round_geometry["enclosedTransparentRegions"][0]
        }
    }
    GEOMETRY_OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"ROUND_ACTION_FRAME={ROUND_RUNTIME}")
    print(f"GOTHIC_HUD_GEOMETRY={GEOMETRY_OUTPUT}")


if __name__ == "__main__":
    main()
