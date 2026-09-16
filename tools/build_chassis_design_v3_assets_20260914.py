# -*- coding: utf-8 -*-
"""Build HardCore HUD bottom-chassis v3 candidate assets from user art.

The user art (2172x724 PNG, transparent background) comes with the slot wells
ALREADY cut to alpha holes ("我开好的槽"):
  - two large circular resource wells (health / mana)
  - four square item quick-slot wells
  - one wide thin experience-bar slot at the bottom center

This tool measures the enclosed alpha holes of each candidate, classifies them
(2 orbs + 4 item slots + 1 experience slot), copies the art unchanged into
assets/ui/gothic_hud/v3/runtime/, writes geometry evidence as JSON, and draws
annotated debug overlays. Runtime mapping matches hud.gd
`_chassis_source_to_local` aspect-fit into the 820x273 chassis rect.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INPUT_DIR = ROOT / "outputs" / "chassis_design_20260914"
OUT_RUNTIME_DIR = ROOT / "assets" / "ui" / "gothic_hud" / "v3" / "runtime"
OUT_GEOMETRY = ROOT / "assets" / "ui" / "gothic_hud" / "v3" / "gothic_hud_frame_geometry_v3.json"

SOURCE_SIZE = (2172, 724)
ALPHA_HOLE_THRESHOLD = 200
MIN_HOLE_AREA = 400
ORB_AREA_RANGE = (35000, 60000)
ORB_BBOX_RANGE = (200, 280)
SLOT_BBOX_RANGE = (110, 200)
SLOT_X_RANGE = (560.0, 1620.0)
SLOT_Y_RANGE = (280.0, 540.0)
PLAQUE_MIN_WIDTH = 600
ORB_LIQUID_RADIUS_RATIO = 0.49  # must match hud_resource_orb.gd
DISPLAY_SIZE = (820.0, 273.0)   # must match GameHUD.HUD_CHASSIS_SIZE

DESIGNS = [
    ("v3_dragon", "魔龙", INPUT_DIR / "candidate_1_dragon.png"),
    ("v3_lion", "雄狮", INPUT_DIR / "candidate_2_lion.png"),
    ("v3_winged_lion", "飞狮", INPUT_DIR / "candidate_3_winged_lion.png"),
    ("v3_demon", "恶魔", INPUT_DIR / "candidate_4_demon.png"),
]


def label_components(mask: np.ndarray) -> list[dict]:
    visited = np.zeros_like(mask, dtype=bool)
    height, width = mask.shape
    components: list[dict] = []
    for sy, sx in zip(*np.nonzero(mask)):
        if visited[sy, sx]:
            continue
        queue = deque([(sy, sx)])
        visited[sy, sx] = True
        members: list[tuple[int, int]] = []
        while queue:
            y, x = queue.popleft()
            members.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))
        ys = np.array([m[0] for m in members], dtype=np.int64)
        xs = np.array([m[1] for m in members], dtype=np.int64)
        min_x, min_y = int(xs.min()), int(ys.min())
        box_w, box_h = int(xs.max()) - min_x + 1, int(ys.max()) - min_y + 1
        touches_border = min_x == 0 or min_y == 0 or min_x + box_w == width or min_y + box_h == height
        components.append(
            {
                "area": len(members),
                "bbox": [min_x, min_y, box_w, box_h],
                "touches_border": touches_border,
            }
        )
    return components


def measure(path: Path) -> dict:
    img = Image.open(path).convert("RGBA")
    if img.size != SOURCE_SIZE:
        raise ValueError(f"{path.name}: unexpected size {img.size}, expected {SOURCE_SIZE}")
    alpha = np.array(img)[:, :, 3]
    holes = [
        c
        for c in label_components(alpha < ALPHA_HOLE_THRESHOLD)
        if not c["touches_border"] and c["area"] >= MIN_HOLE_AREA
    ]

    orbs = [c for c in holes if ORB_AREA_RANGE[0] <= c["area"] <= ORB_AREA_RANGE[1]
            and ORB_BBOX_RANGE[0] <= c["bbox"][2] <= ORB_BBOX_RANGE[1]
            and ORB_BBOX_RANGE[0] <= c["bbox"][3] <= ORB_BBOX_RANGE[1]]
    orbs.sort(key=lambda c: c["bbox"][0])
    if len(orbs) != 2:
        raise ValueError(f"{path.name}: expected 2 orb holes, found {len(orbs)}")

    slots = [
        c
        for c in holes
        if SLOT_BBOX_RANGE[0] <= c["bbox"][2] <= SLOT_BBOX_RANGE[1]
        and SLOT_BBOX_RANGE[0] <= c["bbox"][3] <= SLOT_BBOX_RANGE[1]
        and SLOT_X_RANGE[0] <= c["bbox"][0] + c["bbox"][2] / 2.0 <= SLOT_X_RANGE[1]
        and SLOT_Y_RANGE[0] <= c["bbox"][1] + c["bbox"][3] / 2.0 <= SLOT_Y_RANGE[1]
    ]
    slots.sort(key=lambda c: c["bbox"][0])
    if len(slots) != 4:
        raise ValueError(f"{path.name}: expected 4 item slot holes, found {len(slots)}")

    plaques = [c for c in holes if c["bbox"][2] >= PLAQUE_MIN_WIDTH and c["bbox"][1] > 500]
    if len(plaques) != 1:
        raise ValueError(f"{path.name}: expected 1 experience slot hole, found {len(plaques)}")
    plaque = plaques[0]

    scale = min(DISPLAY_SIZE[0] / SOURCE_SIZE[0], DISPLAY_SIZE[1] / SOURCE_SIZE[1])
    origin_x = (DISPLAY_SIZE[0] - SOURCE_SIZE[0] * scale) / 2.0
    origin_y = (DISPLAY_SIZE[1] - SOURCE_SIZE[1] * scale) / 2.0

    def center_of(bbox: list[int]) -> tuple[float, float]:
        return (bbox[0] + bbox[2] / 2.0, bbox[1] + bbox[3] / 2.0)

    def to_display(point: tuple[float, float]) -> list[float]:
        return [round(origin_x + point[0] * scale, 3), round(origin_y + point[1] * scale, 3)]

    orb_left, orb_right = orbs
    orb_diameter_display = round(min(orb_left["bbox"][2], orb_left["bbox"][3]) * scale)

    slot_centers = [center_of(slot["bbox"]) for slot in slots]
    slot_fill_size = [
        round(slots[0]["bbox"][2] * scale),
        round(slots[0]["bbox"][3] * scale),
    ]
    plaque_bbox = plaque["bbox"]
    # bar rect: inset 3 source px inside the experience slot hole
    xp_rect_display = [
        round(origin_x + (plaque_bbox[0] + 3) * scale, 3),
        round(origin_y + (plaque_bbox[1] + 3) * scale, 3),
        round((plaque_bbox[2] - 6) * scale, 3),
        round((plaque_bbox[3] - 6) * scale, 3),
    ]

    # center peak: topmost opaque pixel within the central crown band
    opaque = alpha >= ALPHA_HOLE_THRESHOLD
    band = opaque[0:400, 1000:1180]
    ys, xs = np.nonzero(band)
    if len(ys) == 0:
        raise ValueError(f"{path.name}: no opaque pixels in central crown band")
    peak_y = int(ys.min())
    peak_x = int(round(1000 + float(xs[ys <= peak_y + 2].mean())))

    return {
        "orb_left": orb_left["bbox"],
        "orb_right": orb_right["bbox"],
        "slots": [slot["bbox"] for slot in slots],
        "plaque": plaque_bbox,
        "peak": [peak_x, peak_y],
        "scale": scale,
        "origin": [origin_x, origin_y],
        "to_display": to_display,
        "orb_diameter_display": orb_diameter_display,
        "slot_centers": slot_centers,
        "slot_fill_size": slot_fill_size,
        "xp_rect_display": xp_rect_display,
    }


def build_design(design_id: str, display_name: str, path: Path) -> dict:
    measured = measure(path)
    to_display = measured["to_display"]
    scale = measured["scale"]
    img = Image.open(path).convert("RGBA")

    orb_left_c = center_of_bbox(measured["orb_left"])
    orb_right_c = center_of_bbox(measured["orb_right"])
    asymmetry = abs(orb_left_c[0] - (SOURCE_SIZE[0] - orb_right_c[0]))

    # debug overlay
    debug = img.copy()
    draw = ImageDraw.Draw(debug)
    for bbox in (measured["orb_left"], measured["orb_right"]):
        x, y, w, h = bbox
        draw.ellipse([x, y, x + w, y + h], outline=(0, 255, 0, 255), width=4)
    for bbox in measured["slots"]:
        x, y, w, h = bbox
        draw.rectangle([x, y, x + w, y + h], outline=(0, 200, 255, 255), width=4)
    x, y, w, h = measured["plaque"]
    draw.rectangle([x, y, x + w, y + h], outline=(255, 80, 80, 255), width=4)
    draw.point(measured["peak"], fill=(255, 255, 0, 255))
    debug.save(INPUT_DIR / f"debug_{design_id}.png")

    out_path = OUT_RUNTIME_DIR / f"bottom_chassis_{design_id}.png"
    img.save(out_path)

    geometry = {
        "id": design_id,
        "display_name": display_name,
        "texture_path": f"res://assets/ui/gothic_hud/v3/runtime/bottom_chassis_{design_id}.png",
        "source_size": list(SOURCE_SIZE),
        "display_size": list(DISPLAY_SIZE),
        "source_to_display_scale": round(scale, 6),
        "render_origin": [round(v, 3) for v in measured["origin"]],
        "health_orb": {
            "hole_bbox_source": measured["orb_left"],
            "center_source": [round(v, 1) for v in orb_left_c],
            "center_display": to_display(orb_left_c),
            "orb_display_size": measured["orb_diameter_display"],
        },
        "mana_orb": {
            "hole_bbox_source": measured["orb_right"],
            "center_source": [round(v, 1) for v in orb_right_c],
            "center_display": to_display(orb_right_c),
            "orb_display_size": measured["orb_diameter_display"],
        },
        "orb_symmetry_error_source_px": round(asymmetry, 1),
        "item_slots": [
            {
                "index": index + 1,
                "hole_bbox_source": bbox,
                "center_source": [round(v, 1) for v in measured["slot_centers"][index]],
                "center_display": to_display(measured["slot_centers"][index]),
            }
            for index, bbox in enumerate(measured["slots"])
        ],
        "item_slot_fill_display_size": measured["slot_fill_size"],
        "experience_slot": {
            "hole_bbox_source": measured["plaque"],
            "center_source": [round(v, 1) for v in center_of_bbox(measured["plaque"])],
            "bar_rect_display": measured["xp_rect_display"],
        },
        "center_peak_source": measured["peak"],
    }
    print(
        f"{design_id}: orbL={orb_left_c} orbR={orb_right_c} sym_err={asymmetry:.1f}px "
        f"slots={[tuple(round(v,1) for v in c) for c in measured['slot_centers']]} "
        f"plaque={measured['plaque']} peak={measured['peak']} "
        f"orb_disp={measured['orb_diameter_display']} fill_disp={measured['slot_fill_size']} "
        f"xp_disp={measured['xp_rect_display']}"
    )
    return geometry


def center_of_bbox(bbox: list[int]) -> tuple[float, float]:
    return (bbox[0] + bbox[2] / 2.0, bbox[1] + bbox[3] / 2.0)


def main() -> int:
    OUT_RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    designs = {}
    for design_id, display_name, path in DESIGNS:
        if not path.exists():
            raise FileNotFoundError(path)
        designs[design_id] = build_design(design_id, display_name, path)
    document = {
        "contract": "hardcore.hud.bottom_chassis.v3.geometry.v1",
        "note": (
            "User-authored 2172x724 candidate frames with pre-cut alpha slot wells. "
            "Art is copied unchanged; geometry is measured from the enclosed alpha "
            "holes (2 resource orbs, 4 item quick slots, 1 experience bar slot). "
            "Runtime maps source pixels through the same aspect-fit as v2."
        ),
        "orb_liquid_radius_ratio": ORB_LIQUID_RADIUS_RATIO,
        "designs": designs,
    }
    OUT_GEOMETRY.write_text(json.dumps(document, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"geometry: {OUT_GEOMETRY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
