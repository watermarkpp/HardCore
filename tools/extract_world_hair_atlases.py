#!/usr/bin/env python3
"""Extract one complete male Hair.wil appearance into runtime action atlases.

Every output pixel and Hot coordinate comes directly from the matching
action/direction/frame record. No scaling, rotation, interpolation, or
synthetic frame generation is performed.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
HAIR_SOURCE = (
    ROOT
    / "dev_art_sources/reference/mir2_client_raw/Data/Hair.wil"
)
AUXILIARY_HAIR_SOURCE = (
    ROOT
    / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
)
OUTPUT_ROOT = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/runtime_hair_002"
)
POLICY_PATH = (
    ROOT
    / "assets/data/equipment_world_helmet_runtime_policy.json"
)
PREVIEW_PATH = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "male_hair_actions_8_direction_3x.png"
)
CANDIDATE_PREVIEW_PATH = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "classic_hair_candidate_blocks_3x.png"
)
SINGLE_CANDIDATE_PREVIEW_PATH = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "classic_hair_block_4_eight_directions_4x.png"
)
AUXILIARY_MALE_CANDIDATES_PATH = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "auxiliary_male_hair_candidates_front_4x.png"
)
AUXILIARY_MALE_CANDIDATES_BACK_PATH = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "auxiliary_male_hair_candidates_back_4x.png"
)
FULL_FRAME_PREVIEW_ROOT = (
    ROOT
    / "outputs/visual_acceptance/world_male_hair_no_helmet"
    / "block_4_full_frames"
)
BODY_ROOT = ROOT / "assets/art/items/client/world_wear/dress/male"

CONTRACT_ID = "equipment.world_helmet.runtime_visibility.v1"
CELL = (192, 160)
DRAW_ORIGIN = (64, 80)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
HAIR_APPEARANCE = 2
HAIR_GENDER_OFFSET = 0
HAIR_STRIDE = 600
HAIR_SOURCE_BLOCK = HAIR_APPEARANCE * 2 + HAIR_GENDER_OFFSET
HAIR_BASE_INDEX = HAIR_SOURCE_BLOCK * HAIR_STRIDE
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def rgba_sha256(image: Image.Image) -> str:
    return sha256_bytes(image.convert("RGBA").tobytes())


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def save_exact_atlas(path: Path, image: Image.Image) -> None:
    if path.exists():
        existing = Image.open(path).convert("RGBA")
        if existing.size == image.size and existing.tobytes() == image.tobytes():
            return
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False)


def extract_action(
    library: tuple,
    action_name: str,
    action_spec: dict,
) -> dict:
    data, palette, offsets, _info = library
    frame_count = int(action_spec["frames"])
    atlas = Image.new(
        "RGBA",
        (CELL[0] * frame_count, CELL[1] * len(DIRECTIONS)),
        (0, 0, 0, 0),
    )
    frames: list[dict] = []
    for direction_row, direction in enumerate(DIRECTIONS):
        for frame_index in range(frame_count):
            source_index = (
                HAIR_BASE_INDEX
                + int(action_spec["start"])
                + direction_row * 8
                + frame_index
            )
            source, metadata = decode_sprite(
                data,
                offsets[source_index],
                palette,
            )
            source = source.convert("RGBA")
            local_destination = (
                DRAW_ORIGIN[0] + int(metadata["x"]),
                DRAW_ORIGIN[1] + int(metadata["y"]),
            )
            if (
                local_destination[0] < 0
                or local_destination[1] < 0
                or local_destination[0] + source.width > CELL[0]
                or local_destination[1] + source.height > CELL[1]
            ):
                raise AssertionError(
                    "Hair.wil frame clips actor cell: "
                    f"{action_name}/{direction}/{frame_index}"
                )
            atlas.alpha_composite(
                source,
                (
                    frame_index * CELL[0] + local_destination[0],
                    direction_row * CELL[1] + local_destination[1],
                ),
            )
            cell = atlas.crop(
                (
                    frame_index * CELL[0],
                    direction_row * CELL[1],
                    (frame_index + 1) * CELL[0],
                    (direction_row + 1) * CELL[1],
                )
            )
            if cell.getchannel("A").getbbox() is None:
                raise AssertionError(
                    "Hair.wil frame is empty: "
                    f"{action_name}/{direction}/{frame_index}"
                )
            frames.append(
                {
                    "direction": direction,
                    "directionRow": direction_row,
                    "frame": frame_index,
                    "sourceIndex": source_index,
                    "hot": [
                        int(metadata["x"]),
                        int(metadata["y"]),
                    ],
                    "sourceSize": [source.width, source.height],
                    "sourceRgbaSha256": rgba_sha256(source),
                    "cellRgbaSha256": rgba_sha256(cell),
                }
            )
    target = OUTPUT_ROOT / f"hair_002_{action_name}.png"
    save_exact_atlas(target, atlas)
    return {
        "path": resource_path(target),
        "fileSha256": file_sha256(target),
        "atlasRgbaSha256": rgba_sha256(atlas),
        "cell": list(CELL),
        "footAnchor": list(DRAW_ORIGIN),
        "directions": len(DIRECTIONS),
        "framesPerDirection": frame_count,
        "missingFrames": [],
        "confidence": "primary_client_exact",
        "frames": frames,
    }


def preview_font(size: int) -> ImageFont.ImageFont:
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    if font_path.exists():
        return ImageFont.truetype(str(font_path), size)
    return ImageFont.load_default()


def save_runtime_preview() -> None:
    action_names = list(ACTIONS)
    sheet = Image.new(
        "RGBA",
        (180 + len(action_names) * 210, 80 + len(DIRECTIONS) * 260),
        (18, 21, 25, 255),
    )
    draw = ImageDraw.Draw(sheet)
    title_font = preview_font(30)
    label_font = preview_font(22)
    draw.text(
        (24, 18),
        "男性短发 block 4 · 主客户端完整帧 · 世界头盔隐藏",
        font=title_font,
        fill=(245, 245, 245, 255),
    )
    for action_column, action_name in enumerate(action_names):
        draw.text(
            (180 + action_column * 210 + 70, 48),
            action_name,
            font=label_font,
            fill=(200, 220, 255, 255),
        )
        body_atlas = Image.open(
            BODY_ROOT / f"dress_006_{action_name}.png"
        ).convert("RGBA")
        hair_atlas = Image.open(
            OUTPUT_ROOT / f"hair_002_{action_name}.png"
        ).convert("RGBA")
        for direction_row, direction in enumerate(DIRECTIONS):
            source_rect = (
                0,
                direction_row * CELL[1],
                CELL[0],
                (direction_row + 1) * CELL[1],
            )
            frame = body_atlas.crop(source_rect)
            frame.alpha_composite(hair_atlas.crop(source_rect))
            bbox = frame.getchannel("A").getbbox()
            if bbox is None:
                raise AssertionError(
                    f"preview frame is empty: {action_name}/{direction}"
                )
            actor = frame.crop(bbox)
            actor = actor.resize(
                (actor.width * 3, actor.height * 3),
                Image.Resampling.NEAREST,
            )
            tile_x = 180 + action_column * 210
            tile_y = 80 + direction_row * 260
            target_x = tile_x + (210 - actor.width) // 2
            target_y = tile_y + (235 - actor.height) // 2
            sheet.alpha_composite(actor, (target_x, target_y))
    for direction_row, direction in enumerate(DIRECTIONS):
        draw.text(
            (55, 80 + direction_row * 260 + 105),
            direction,
            font=label_font,
            fill=(255, 214, 140, 255),
        )
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(PREVIEW_PATH, format="PNG")


def save_candidate_preview(library: tuple) -> None:
    data, palette, offsets, _info = library
    candidates = [
        (2, "style1 / sex0"),
        (3, "style1 / sex1"),
        (4, "style2 / sex0"),
        (5, "style2 / sex1"),
    ]
    body_atlas = Image.open(BODY_ROOT / "dress_006_idle.png").convert(
        "RGBA"
    )
    sheet = Image.new(
        "RGBA",
        (180 + len(candidates) * 260, 80 + len(DIRECTIONS) * 260),
        (18, 21, 25, 255),
    )
    draw = ImageDraw.Draw(sheet)
    title_font = preview_font(30)
    label_font = preview_font(20)
    draw.text(
        (24, 18),
        "经典 Hair.wil 完整发型块视觉核对",
        font=title_font,
        fill=(245, 245, 245, 255),
    )
    for column, (source_block, label) in enumerate(candidates):
        draw.text(
            (180 + column * 260 + 45, 48),
            f"block {source_block} · {label}",
            font=label_font,
            fill=(200, 220, 255, 255),
        )
        for direction_row, direction in enumerate(DIRECTIONS):
            source_index = (
                source_block * HAIR_STRIDE + direction_row * 8
            )
            hair, metadata = decode_sprite(
                data,
                offsets[source_index],
                palette,
            )
            hair = hair.convert("RGBA")
            source_rect = (
                0,
                direction_row * CELL[1],
                CELL[0],
                (direction_row + 1) * CELL[1],
            )
            frame = body_atlas.crop(source_rect)
            frame.alpha_composite(
                hair,
                (
                    DRAW_ORIGIN[0] + int(metadata["x"]),
                    DRAW_ORIGIN[1] + int(metadata["y"]),
                ),
            )
            bbox = frame.getchannel("A").getbbox()
            if bbox is None:
                raise AssertionError(
                    f"candidate frame is empty: {source_block}/{direction}"
                )
            actor = frame.crop(bbox)
            actor = actor.resize(
                (actor.width * 3, actor.height * 3),
                Image.Resampling.NEAREST,
            )
            tile_x = 180 + column * 260
            tile_y = 80 + direction_row * 260
            sheet.alpha_composite(
                actor,
                (
                    tile_x + (260 - actor.width) // 2,
                    tile_y + (235 - actor.height) // 2,
                ),
            )
    for direction_row, direction in enumerate(DIRECTIONS):
        draw.text(
            (55, 80 + direction_row * 260 + 105),
            direction,
            font=label_font,
            fill=(255, 214, 140, 255),
        )
    CANDIDATE_PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(CANDIDATE_PREVIEW_PATH, format="PNG")


def save_single_candidate_preview(library: tuple) -> None:
    data, palette, offsets, _info = library
    source_block = 4
    body_atlas = Image.open(BODY_ROOT / "dress_006_idle.png").convert(
        "RGBA"
    )
    sheet = Image.new("RGBA", (1280, 760), (18, 21, 25, 255))
    draw = ImageDraw.Draw(sheet)
    title_font = preview_font(30)
    label_font = preview_font(24)
    draw.text(
        (28, 20),
        "男性短发候选 · 经典 Hair.wil block 4 · 八方向",
        font=title_font,
        fill=(245, 245, 245, 255),
    )
    for direction_row, direction in enumerate(DIRECTIONS):
        source_index = source_block * HAIR_STRIDE + direction_row * 8
        hair, metadata = decode_sprite(
            data,
            offsets[source_index],
            palette,
        )
        hair = hair.convert("RGBA")
        source_rect = (
            0,
            direction_row * CELL[1],
            CELL[0],
            (direction_row + 1) * CELL[1],
        )
        frame = body_atlas.crop(source_rect)
        frame.alpha_composite(
            hair,
            (
                DRAW_ORIGIN[0] + int(metadata["x"]),
                DRAW_ORIGIN[1] + int(metadata["y"]),
            ),
        )
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise AssertionError(
                f"single candidate frame is empty: {direction}"
            )
        actor = frame.crop(bbox)
        actor = actor.resize(
            (actor.width * 4, actor.height * 4),
            Image.Resampling.NEAREST,
        )
        column = direction_row % 4
        row = direction_row // 4
        tile_x = column * 320
        tile_y = 80 + row * 340
        sheet.alpha_composite(
            actor,
            (
                tile_x + (320 - actor.width) // 2,
                tile_y + (290 - actor.height) // 2,
            ),
        )
        draw.text(
            (tile_x + 142, tile_y + 292),
            direction,
            font=label_font,
            fill=(255, 214, 140, 255),
        )
    SINGLE_CANDIDATE_PREVIEW_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    sheet.convert("RGB").save(
        SINGLE_CANDIDATE_PREVIEW_PATH,
        format="PNG",
    )


def save_auxiliary_male_candidates_preview(
    direction_row: int,
    target_path: Path,
    direction_label: str,
) -> None:
    data, palette, offsets, info = read_library(AUXILIARY_HAIR_SOURCE)
    appearance_stride = 2224
    male_gender_offset = 0
    appearance_count = int(info["image_count"]) // appearance_stride
    body_atlas = Image.open(BODY_ROOT / "dress_006_idle.png").convert(
        "RGBA"
    )
    source_rect = (
        0,
        direction_row * CELL[1],
        CELL[0],
        (direction_row + 1) * CELL[1],
    )
    sheet = Image.new("RGBA", (1600, 860), (18, 21, 25, 255))
    draw = ImageDraw.Draw(sheet)
    title_font = preview_font(30)
    label_font = preview_font(24)
    draw.text(
        (28, 20),
        (
            "扩展完整客户端男性发型候选 · "
            f"{direction_label} · 原始像素 4x"
        ),
        font=title_font,
        fill=(245, 245, 245, 255),
    )
    for appearance in range(appearance_count):
        source_index = (
            appearance * appearance_stride
            + male_gender_offset
            + direction_row * 8
        )
        hair, metadata = decode_sprite(
            data,
            offsets[source_index],
            palette,
        )
        hair = hair.convert("RGBA")
        frame = body_atlas.crop(source_rect)
        frame.alpha_composite(
            hair,
            (
                DRAW_ORIGIN[0] + int(metadata["x"]),
                DRAW_ORIGIN[1] + int(metadata["y"]),
            ),
        )
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise AssertionError(
                f"auxiliary candidate is empty: {appearance}"
            )
        actor = frame.crop(bbox)
        actor = actor.resize(
            (actor.width * 4, actor.height * 4),
            Image.Resampling.NEAREST,
        )
        column = appearance % 5
        row = appearance // 5
        tile_x = column * 320
        tile_y = 90 + row * 380
        sheet.alpha_composite(
            actor,
            (
                tile_x + (320 - actor.width) // 2,
                tile_y + (315 - actor.height) // 2,
            ),
        )
        draw.text(
            (tile_x + 116, tile_y + 318),
            f"编号 {appearance}",
            font=label_font,
            fill=(255, 214, 140, 255),
        )
    target_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    sheet.convert("RGB").save(
        target_path,
        format="PNG",
    )


def save_full_frame_previews() -> None:
    title_font = preview_font(28)
    label_font = preview_font(20)
    FULL_FRAME_PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    for action_name, action_spec in ACTIONS.items():
        frame_count = int(action_spec["frames"])
        body_atlas = Image.open(
            BODY_ROOT / f"dress_006_{action_name}.png"
        ).convert("RGBA")
        hair_atlas = Image.open(
            OUTPUT_ROOT / f"hair_002_{action_name}.png"
        ).convert("RGBA")
        sheet = Image.new(
            "RGBA",
            (
                170 + frame_count * 210,
                78 + len(DIRECTIONS) * 235,
            ),
            (18, 21, 25, 255),
        )
        draw = ImageDraw.Draw(sheet)
        draw.text(
            (24, 16),
            f"block 4 · {action_name} · 全方向全帧",
            font=title_font,
            fill=(245, 245, 245, 255),
        )
        for frame_index in range(frame_count):
            draw.text(
                (170 + frame_index * 210 + 88, 48),
                str(frame_index),
                font=label_font,
                fill=(200, 220, 255, 255),
            )
        for direction_row, direction in enumerate(DIRECTIONS):
            draw.text(
                (54, 78 + direction_row * 235 + 98),
                direction,
                font=label_font,
                fill=(255, 214, 140, 255),
            )
            for frame_index in range(frame_count):
                source_rect = (
                    frame_index * CELL[0],
                    direction_row * CELL[1],
                    (frame_index + 1) * CELL[0],
                    (direction_row + 1) * CELL[1],
                )
                frame = body_atlas.crop(source_rect)
                frame.alpha_composite(hair_atlas.crop(source_rect))
                bbox = frame.getchannel("A").getbbox()
                if bbox is None:
                    raise AssertionError(
                        "full frame preview is empty: "
                        f"{action_name}/{direction}/{frame_index}"
                    )
                actor = frame.crop(bbox)
                actor = actor.resize(
                    (actor.width * 3, actor.height * 3),
                    Image.Resampling.NEAREST,
                )
                tile_x = 170 + frame_index * 210
                tile_y = 78 + direction_row * 235
                sheet.alpha_composite(
                    actor,
                    (
                        tile_x + (210 - actor.width) // 2,
                        tile_y + (215 - actor.height) // 2,
                    ),
                )
        sheet.convert("RGB").save(
            FULL_FRAME_PREVIEW_ROOT / f"block_4_{action_name}_3x.png",
            format="PNG",
        )


def main() -> None:
    library = read_library(HAIR_SOURCE)
    _data, _palette, _offsets, info = library
    maximum_index = (
        HAIR_BASE_INDEX
        + max(
            int(spec["start"]) + 7 * 8 + int(spec["frames"]) - 1
            for spec in ACTIONS.values()
        )
    )
    if int(info["image_count"]) <= maximum_index:
        raise AssertionError(
            "Hair.wil does not contain the complete selected appearance"
        )

    action_records = {
        action_name: extract_action(
            library,
            action_name,
            action_spec,
        )
        for action_name, action_spec in ACTIONS.items()
    }
    policy = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "scope": "runtime_world_character_head_only",
        "worldHelmet": {
            "visible": False,
            "frontLayerVisible": False,
            "backLayerVisible": False,
            "headOcclusionMaskEnabled": False,
            "calibrationAndGeneratedAssetsPreserved": True,
        },
        "preservedPresentationScopes": [
            "paper_doll",
            "inventory",
            "ground",
        ],
        "hairAppearance": {
            "sex": "male",
            "genderOffset": HAIR_GENDER_OFFSET,
            "appearance": HAIR_APPEARANCE,
            "appearanceStride": HAIR_STRIDE,
            "sourceBlock": HAIR_SOURCE_BLOCK,
            "directions": DIRECTIONS,
            "actions": action_records,
            "source": {
                "lane": "client_assets",
                "tier": "primary",
                "distribution": "client.classic_raw_complete",
                "path": resource_path(HAIR_SOURCE),
                "fileSha256": file_sha256(HAIR_SOURCE),
                "frameRule": (
                    "(hairFeature*2+gender)*600 + action_start "
                    "+ direction*8 + frame"
                ),
                "genderRuleSource": (
                    "original_gameofmir/MirClient/Actor.pas: "
                    "HUMANFRAME=600; m_btHair=m_btHair*2; "
                    "m_nHairOffset=HUMANFRAME*(m_btHair+m_btSex); "
                    "male m_btSex=0"
                ),
                "pixelPolicy": "same_frame_exact_rgba_and_hot",
                "resampled": False,
                "rotated": False,
                "syntheticFrames": False,
            },
            "pairedBodySource": {
                "lane": "client_assets",
                "tier": "primary",
                "distribution": "client.classic_raw_complete",
                "library": "Hum.wil",
                "path": resource_path(
                    ROOT
                    / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
                ),
                "fileSha256": file_sha256(
                    ROOT
                    / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
                ),
                "blockFrames": 600,
                "actionTable": ACTIONS,
                "runtimePreviewFeature": 6,
                "runtimePreviewRoot": resource_path(BODY_ROOT),
                "frameRule": (
                    "feature*600 + action_start "
                    "+ direction*8 + frame"
                ),
                "sameDistributionAndActionTable": True,
            },
        },
    }
    POLICY_PATH.write_text(
        json.dumps(policy, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    save_candidate_preview(library)
    save_single_candidate_preview(library)
    save_auxiliary_male_candidates_preview(
        4,
        AUXILIARY_MALE_CANDIDATES_PATH,
        "正面 S",
    )
    save_auxiliary_male_candidates_preview(
        0,
        AUXILIARY_MALE_CANDIDATES_BACK_PATH,
        "背面 N",
    )
    save_full_frame_previews()
    save_runtime_preview()
    print(
        "WORLD_HAIR_EXTRACT_PASS "
        f"appearance={HAIR_APPEARANCE} actions={len(ACTIONS)} "
        f"frames={sum(len(value['frames']) for value in action_records.values())} "
        "resampled=false synthetic=false"
    )


if __name__ == "__main__":
    main()
