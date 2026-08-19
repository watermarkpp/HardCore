#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

from math import ceil
from typing import List, Sequence, Tuple

from PIL import Image


TILE_W = 64
TILE_H = 32
ALPHA_THRESHOLD = 10

GROUNDING_POLICY_ID = "bottom_contact_grounding_v1"
PLACEMENT_ANCHOR_POLICY_ID = "footprint_bottom_vertex_v1"

# 贴在地面上的东西不参与人物前后遮挡。
FLAT_CATEGORIES = {
    "地毯",
    "地面",
    "地面涂鸦",
}

# 竖立物允许的最大基础 footprint。
# 这里只是防止异常图片把 footprint 撑成几十格。
MAX_SIDE_BY_CATEGORY = {
    "烛台": 2,
    "旗帜": 2,
    "囚笼": 3,
    "雕塑": 4,
    "立柱": 3,
    "王座": 4,
    "树木": 6,
    "地图出入口": 6,
}


def clamp_int(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, int(value)))


def _rgba(image: Image.Image) -> Image.Image:
    if image.mode == "RGBA":
        return image
    return image.convert("RGBA")


def alpha_visible_bbox(
    image: Image.Image,
    threshold: int = ALPHA_THRESHOLD,
) -> Tuple[int, int, int, int]:
    """
    返回 alpha 可见区域 bbox:
    (x1, y1, x2, y2)

    x2 / y2 与 Pillow getbbox 相同，为 exclusive。
    """
    rgba = _rgba(image)
    alpha = rgba.getchannel("A")
    mask = alpha.point(
        lambda value: 255 if value >= threshold else 0
    )
    bbox = mask.getbbox()

    if bbox is None:
        return 0, 0, rgba.width, rgba.height

    return (
        int(bbox[0]),
        int(bbox[1]),
        int(bbox[2]),
        int(bbox[3]),
    )


def bottom_contact_bounds(
    image: Image.Image,
    threshold: int = ALPHA_THRESHOLD,
) -> List[int]:
    """
    只寻找真正接近图片最底部的"落地点"。

    关键原则：
    - 不使用整张图片高度。
    - 树冠高度不能变成地面 footprint。
    - 旗杆高度不能变成地面 footprint。
    - 雕塑高度不能变成地面 footprint。
    - 只看每一个 X 列最下面的 alpha 像素。
    - 再只保留靠近全图最低点的列。
    """
    rgba = _rgba(image)
    alpha = rgba.getchannel("A")
    pixels = alpha.load()

    x1, y1, x2, y2 = alpha_visible_bbox(rgba, threshold)

    visible_w = max(1, x2 - x1)
    visible_h = max(1, y2 - y1)

    global_bottom = max(y1, y2 - 1)

    # 第一轮只允许距离真正最低点 8~32 像素。
    tolerance = clamp_int(
        round(visible_h * 0.08),
        8,
        32,
    )

    bottom_by_x = {}

    for x in range(x1, x2):
        found_y = None

        for y in range(y2 - 1, y1 - 1, -1):
            if pixels[x, y] >= threshold:
                found_y = y
                break

        if found_y is not None:
            bottom_by_x[x] = found_y

    if not bottom_by_x:
        return [
            x1,
            max(y1, global_bottom - 7),
            visible_w,
            min(8, visible_h),
        ]

    def collect_near_bottom(limit: int):
        return [
            (x, y)
            for x, y in bottom_by_x.items()
            if y >= global_bottom - limit
        ]

    near = collect_near_bottom(tolerance)

    minimum_columns = max(
        2,
        int(round(visible_w * 0.03)),
    )

    # 如果最低点只是一个孤立抗锯齿像素，
    # 再放宽一次，但最大也只放到 48px。
    if len(near) < minimum_columns:
        tolerance = clamp_int(
            round(visible_h * 0.16),
            12,
            48,
        )
        near = collect_near_bottom(tolerance)

    if not near:
        near = list(bottom_by_x.items())

    min_x = min(item[0] for item in near)
    max_x = max(item[0] for item in near)
    min_y = min(item[1] for item in near)

    return [
        int(min_x),
        int(min_y),
        int(max_x - min_x + 1),
        int(global_bottom - min_y + 1),
    ]


def _tiles_for_pixels(
    pixels: float,
    tile_pixels: int,
) -> int:
    """
    允许少量抗锯齿/边缘溢出。

    例如：
    65px 不应该因为 1px 抗锯齿直接变成 2 格。
    """
    effective = max(1.0, float(pixels) - 6.0)

    return max(
        1,
        int(ceil(effective / float(tile_pixels))),
    )


def flat_ground_footprint(
    visible_w: int,
    visible_h: int,
    approved_scale: float = 1.0,
) -> List[int]:
    """
    地毯、地面涂鸦等本身就在地面上，
    所以可以使用其完整可见区域估算 footprint。
    """
    scale = max(0.0001, abs(float(approved_scale)))

    width_tiles = _tiles_for_pixels(
        visible_w * scale,
        TILE_W,
    )
    height_tiles = _tiles_for_pixels(
        visible_h * scale,
        TILE_H,
    )

    return [
        clamp_int(width_tiles, 1, 12),
        clamp_int(height_tiles, 1, 12),
    ]


def vertical_prop_footprint(
    category_cn: str,
    visible_w: int,
    visible_h: int,
    contact_bounds: Sequence[int],
    approved_scale: float = 1.0,
) -> List[int]:
    """
    树、旗帜、雕塑、柱子等：

    footprint 只由底部接地区域决定，
    绝对禁止再使用完整图片高度。

    普通竖立物：
    - 使用底部接触宽度决定基础 footprint。
    - 默认使用方形 footprint。

    横向倒木等极宽树木：
    - 如果图片明显横向，
      允许 footprint 变成长条。
    """
    scale = max(0.0001, abs(float(approved_scale)))

    contact_w = max(1, int(contact_bounds[2]))
    contact_h = max(1, int(contact_bounds[3]))

    width_tiles = _tiles_for_pixels(
        contact_w * scale,
        TILE_W,
    )

    max_side = int(
        MAX_SIDE_BY_CATEGORY.get(category_cn, 6)
    )

    width_tiles = clamp_int(
        width_tiles,
        1,
        max_side,
    )

    # 树木可能包含倒木。
    # 明显横向的树木不强制变成方形。
    if (
        category_cn == "树木"
        and visible_w >= visible_h * 1.45
    ):
        depth_tiles = _tiles_for_pixels(
            contact_h * scale,
            TILE_H,
        )

        depth_tiles = clamp_int(
            depth_tiles,
            1,
            min(3, width_tiles),
        )

        return [
            width_tiles,
            depth_tiles,
        ]

    return [
        width_tiles,
        width_tiles,
    ]


def category_occlusion(category_cn: str) -> bool:
    """
    是否进入人物 Y-sort 遮挡域。
    """
    if category_cn in FLAT_CATEGORIES:
        return False

    return True


def calibrate_asset_geometry(
    image: Image.Image,
    category_cn: str,
    approved_scale: float = 1.0,
) -> dict:
    """
    返回 catalog 使用的完整基础几何数据。
    """
    rgba = _rgba(image)

    x1, y1, x2, y2 = alpha_visible_bbox(rgba)

    visible_w = max(1, x2 - x1)
    visible_h = max(1, y2 - y1)

    anchor_x = int((x1 + x2) // 2)

    # 保持项目现有 foot_tile 约定：
    # anchor_px 保存可见内容底部位置。
    anchor_y = int(y2)

    anchor_px = [
        anchor_x,
        anchor_y,
    ]

    if category_cn in FLAT_CATEGORIES:
        contact_bounds = [
            int(x1),
            int(y1),
            int(visible_w),
            int(visible_h),
        ]

        footprint = flat_ground_footprint(
            visible_w,
            visible_h,
            approved_scale,
        )

        calibration_method = "flat_visible_ground_bounds"
    else:
        contact_bounds = bottom_contact_bounds(rgba)

        footprint = vertical_prop_footprint(
            category_cn,
            visible_w,
            visible_h,
            contact_bounds,
            approved_scale,
        )

        calibration_method = "bottom_contact_columns"

    return {
        "canvas_size": [
            int(rgba.width),
            int(rgba.height),
        ],
        "image_size": [
            int(rgba.width),
            int(rgba.height),
        ],
        "visible_bounds_px": [
            int(x1),
            int(y1),
            int(visible_w),
            int(visible_h),
        ],
        "ground_contact_bounds_px": [
            int(value)
            for value in contact_bounds
        ],
        "anchor_px": anchor_px.copy(),

        # raw catalog 继续保存 source foot anchor。
        # MapAssetPlacementAnchorPolicy 会生成 effective placement anchor。
        "placement_anchor_px": anchor_px.copy(),

        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",

        "footprint_tiles": footprint.copy(),
        "visual_footprint_tiles": footprint.copy(),
        "occupancy_footprint_tiles": footprint.copy(),
        "base_footprint_tiles": footprint.copy(),

        # 本次修复不擅自新增游戏碰撞。
        "collision_footprint_tiles": [0, 0],

        "tile_size": [
            TILE_W,
            TILE_H,
        ],

        "grounding_policy_id": GROUNDING_POLICY_ID,
        "grounding_calibration_method": calibration_method,
        "footprint_calibration_source":
            "new_decor_grounding_repair_v1",
    }


def placement_anchor_px(
    source_anchor_px: Sequence[float],
    footprint_tiles: Sequence[float],
    scale_xy: Sequence[float] = (1.0, 1.0),
) -> List[float]:
    """
    Python 版必须与：
    scripts/map_assets/map_asset_placement_anchor_policy.gd

    footprint_bottom_vertex_v1

    保持相同数学逻辑。
    """
    width = max(
        1.0,
        float(footprint_tiles[0]),
    )
    height = max(
        1.0,
        float(footprint_tiles[1]),
    )

    scale_x = max(
        0.0001,
        abs(float(scale_xy[0])),
    )
    scale_y = max(
        0.0001,
        abs(float(scale_xy[1])),
    )

    center_to_bottom_x = (
        (width - height)
        * 32.0
        * 0.5
    )

    center_to_bottom_y = (
        (width + height)
        * 16.0
        * 0.5
    )

    return [
        float(source_anchor_px[0])
        - center_to_bottom_x / scale_x,

        float(source_anchor_px[1])
        - center_to_bottom_y / scale_y,
    ]
