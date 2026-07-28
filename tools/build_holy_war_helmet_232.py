#!/usr/bin/env python3
"""Build the user-approved item 232 helmet without touching other helmets.

This is intentionally a single-target builder.  The approved 4x2 sheet is
kept byte-for-byte as provenance, then a transparent world sheet, six physical
world atlases, an opaque paper-doll layer, and opaque inventory/ground icons
are derived from it.  No other visual identity can be selected.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from copy import deepcopy
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
APPROVED_EXTERNAL = Path(
    r"C:\Users\Administrator\.codex\generated_images"
    r"\019f9cf3-2388-76c3-925a-c98a9cdbb355"
    r"\call_GKJo7DbapyE1Tz43MbMNAYIp.png"
)
APPROVED_SHA256 = (
    "93307c79e0d5d697d269eec3ba2c318385be96130026e1dbe1b67779437b583b"
)
APPROVED_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "holy_war_helmet_approved_20260727.png"
)
WORLD_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "holy_war_helmet_8dir.png"
)
RECIPE_PATH = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
WORLD_CONTRACT = ROOT / "assets/data/equipment_male_world_helmet.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
HEAD_PATCH_CONTRACT = (
    ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
)
HELMET_V2_CONTRACT = ROOT / "assets/data/equipment_helmet_visual_v2.json"
HELMET_V2_OVERRIDES = (
    ROOT / "assets/data/equipment_helmet_visual_v2_overrides.json"
)
GENERATED_HELMET_V2_ROOT = ROOT / "assets/generated/helmet_v2"
HEAD_SOCKET_CONTRACT = ROOT / "assets/data/player_head_socket_db.json"
HEAD_PATCH = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00232_head.png"
)
HEAD_ERASE_MASK = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00232_erase_mask.png"
)
PROJECT_ICON_DIR = (
    ROOT / "assets/art/items/client/project_redesign/helmet/holy_war"
)
INVENTORY_ICON = PROJECT_ICON_DIR / "item_00232_inventory.png"
GROUND_ICON = PROJECT_ICON_DIR / "item_00232_ground.png"
ACCEPTANCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/acceptance"
    / "holy_war_direction_mapping.png"
)
PREVIEW = (
    ROOT / "outputs/helmet_232/holy_war_232_processed_8dir_preview.png"
)
PRESENTATION_PREVIEW = (
    ROOT / "outputs/helmet_232/holy_war_232_paper_inventory_ground_preview.png"
)
REPORT = ROOT / "outputs/helmet_232/holy_war_232_validation_report.json"
WORN_PREVIEW_1X = (
    ROOT / "outputs/helmet_232/holy_war_232_worn_idle_8dir_1x.png"
)
WORN_PREVIEW_8X = (
    ROOT / "outputs/helmet_232/holy_war_232_worn_idle_8dir_8x.png"
)

IDENTITY_ID = "holy_war"
ITEM_ID = 232
SOURCE_INDEX = 104
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
SOURCE_SLOT_DIRECTION_ORDER = DIRECTIONS
CANONICAL_ROW_SOURCE_SLOTS = list(range(8))
FACE_POLICY = {
    "N": "closed",
    "NE": "closed",
    "E": "closed",
    "SE": "closed",
    "S": "closed",
    "SW": "closed",
    "W": "closed",
    "NW": "closed",
}
FACE_APERTURE_SHAPE = {
    "N": "none",
    "NE": "none",
    "E": "none",
    "SE": "none",
    "S": "none",
    "SW": "none",
    "W": "none",
    "NW": "none",
}
ACTION_SPECS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
CELL = (192, 160)
FOOT_ANCHOR = (64, 80)

# The generated concept has black fur beneath the gold helmet rim.  These
# per-slot polygons remove only that accidental neck/fur area.  Coordinates
# are local to one 384x512 source slot.
FUR_POLYGONS = {
    "N": [[54, 405], [330, 405], [360, 512], [20, 512]],
    "NE": [[54, 418], [304, 410], [322, 512], [35, 512]],
    "E": [[112, 379], [327, 379], [356, 512], [88, 512]],
    "SE": [[34, 418], [300, 407], [320, 512], [15, 512]],
    "S": [[68, 414], [316, 414], [350, 512], [34, 512]],
    "SW": [[63, 414], [313, 406], [350, 512], [30, 512]],
    "W": [[24, 382], [252, 382], [300, 512], [8, 512]],
    "NW": [[62, 386], [321, 386], [354, 512], [28, 512]],
}

# Face openings are punched only in the wearable/paper-doll variants.  Gold,
# red-gem and highlighted metal pixels are retained, so the apertures expose
# the player's original face without deleting the decorative cage/trim.
FACE_WINDOWS: dict[str, list[list[list[int]]]] = {}

# These are the user-approved final per-direction pixel heights.  Every
# runtime/paper/icon derivative is produced directly from the 1536x1024
# approved sheet in one alpha-safe high-quality downsample.  Width alone is
# compressed to 80% so the horned design keeps its height without using the
# horns as the helmet-body diameter.
WORLD_HEIGHT = {
    "N": 23,
    "NE": 21,
    "E": 20,
    "SE": 22,
    "S": 23,
    "SW": 22,
    "W": 22,
    "NW": 23,
}
HORIZONTAL_DIAMETER_SCALE = 0.8
PAPER_CANVAS_SIZE = (32, 41)
PAPER_CONTENT_HEIGHT = 29
FROZEN_V2_SOURCE_DIRECTION_MAP = {
    "N": 0,
    "NE": 7,
    "E": 3,
    "SE": 6,
    "S": 4,
    "SW": 5,
    "W": 2,
    "NW": 1,
}
SOURCE_VARIANT_HEIGHT = {
    DIRECTIONS[source_row]: WORLD_HEIGHT[target_direction]
    for target_direction, source_row in FROZEN_V2_SOURCE_DIRECTION_MAP.items()
}
PREVIOUS_TARGET_BBOX_SIZE = {
    "N": [21, 23],
    "NE": [16, 21],
    "E": [15, 20],
    "SE": [17, 22],
    "S": [19, 23],
    "SW": [16, 22],
    "W": [15, 22],
    "NW": [17, 23],
}
EXPECTED_TARGET_BBOX_SIZE = {
    direction: [
        round(PREVIOUS_TARGET_BBOX_SIZE[direction][0] * 0.8),
        PREVIOUS_TARGET_BBOX_SIZE[direction][1],
    ]
    for direction in DIRECTIONS
}
SOURCE_VARIANT_SIZE = {
    DIRECTIONS[source_row]: EXPECTED_TARGET_BBOX_SIZE[target_direction]
    for target_direction, source_row in FROZEN_V2_SOURCE_DIRECTION_MAP.items()
}
OPAQUE_FACE_ROI_POINTS = {
    "N": [[192, 330]],
    "NE": [[180, 320]],
    "E": [[84, 276]],
    "SE": [[217, 293]],
    "S": [[155, 290], [223, 289]],
    "SW": [[133, 291]],
    "W": [[280, 275]],
    "NW": [[200, 320]],
}
CLOSED_SHELL_ROI_POINTS = {
    "N": [[192, 330]],
    "NE": [[180, 320]],
    "NW": [[200, 320]],
}
FUR_VALIDATION_RECTS = {
    "N": [120, 448, 270, 510],
    "NE": [110, 450, 270, 510],
    "E": [125, 452, 320, 510],
    "SE": [70, 455, 255, 510],
    "S": [140, 452, 245, 510],
    "SW": [120, 455, 275, 510],
    "W": [100, 438, 245, 510],
    "NW": [100, 425, 280, 510],
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def resource_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def opaque_pixels(image: Image.Image) -> int:
    return sum(
        alpha > 0 for alpha in image.getchannel("A").get_flattened_data()
    )


def crop_slot(sheet: Image.Image, slot: int) -> Image.Image:
    column = slot % 4
    row = slot // 4
    return sheet.crop(
        (column * 384, row * 512, (column + 1) * 384, (row + 1) * 512)
    )


def green_screen_alpha(image: Image.Image) -> Image.Image:
    output = image.convert("RGBA")
    pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            red, green, blue, alpha = pixels[x, y]
            if (
                alpha == 0
                or (
                    green >= 180
                    and green >= red + 70
                    and green >= blue + 70
                )
            ):
                pixels[x, y] = (0, 0, 0, 0)
                continue
            # Remove residual green spill without changing opaque design hues.
            if green > max(red, blue) + 28:
                green = max(red, blue) + 12
            pixels[x, y] = (red, green, blue, alpha)
    return output


def apply_polygon_clear(
    image: Image.Image,
    polygons: list[list[list[int]]],
    *,
    dark_only: bool,
) -> Image.Image:
    output = image.copy()
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    for polygon in polygons:
        draw.polygon([tuple(point) for point in polygon], fill=255)
    source = output.load()
    selected = mask.load()
    for y in range(output.height):
        for x in range(output.width):
            if selected[x, y] == 0:
                continue
            red, green, blue, alpha = source[x, y]
            if alpha == 0:
                continue
            if dark_only:
                # Preserve gold trim, red gems and strong reflected highlights.
                if max(red, green, blue) >= 112:
                    continue
            source[x, y] = (0, 0, 0, 0)
    return output


def trim_fur(image: Image.Image, direction: str) -> Image.Image:
    return apply_polygon_clear(
        image,
        [FUR_POLYGONS[direction]],
        dark_only=False,
    )


def punch_face_window(image: Image.Image, direction: str) -> Image.Image:
    if direction not in FACE_WINDOWS:
        return image.copy()
    return apply_polygon_clear(
        image,
        FACE_WINDOWS[direction],
        dark_only=True,
    )


def crop_alpha(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("empty derived helmet image")
    return image.crop(box)


def premultiplied_lanczos_resize(
    image: Image.Image,
    size: tuple[int, int],
) -> Image.Image:
    """Resize transparent art once without bleeding matte RGB into its edge."""
    source = image.convert("RGBA")
    alpha = source.getchannel("A")
    red, green, blue, _ = source.split()
    premultiplied = Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    ).resize(size, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    source_pixels = premultiplied.load()
    target_pixels = output.load()
    for y in range(size[1]):
        for x in range(size[0]):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha <= 1:
                target_pixels[x, y] = (0, 0, 0, 0)
                continue
            target_pixels[x, y] = (
                min(255, round(red * 255 / alpha)),
                min(255, round(green * 255 / alpha)),
                min(255, round(blue * 255 / alpha)),
                alpha,
            )
    return crop_alpha(output)


def resize_to_height(
    image: Image.Image,
    height: int,
    horizontal_scale: float = HORIZONTAL_DIAMETER_SCALE,
) -> Image.Image:
    natural_width = image.width * height / image.height
    width = max(1, round(natural_width * horizontal_scale))
    return premultiplied_lanczos_resize(image, (width, height))


def fit_inside(
    image: Image.Image,
    size: tuple[int, int],
    horizontal_scale: float = HORIZONTAL_DIAMETER_SCALE,
) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (
        max(1, round(image.width * scale * horizontal_scale)),
        max(1, round(image.height * scale)),
    )
    resized = premultiplied_lanczos_resize(image, target)
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.alpha_composite(
        resized,
        ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2),
    )
    return output


def fit_height_on_canvas(
    image: Image.Image,
    canvas_size: tuple[int, int],
    content_height: int,
) -> Image.Image:
    fitted = resize_to_height(image, content_height)
    if fitted.width > canvas_size[0] or fitted.height > canvas_size[1]:
        raise ValueError(
            f"fitted helmet {fitted.size} exceeds canvas {canvas_size}"
        )
    output = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    output.alpha_composite(
        fitted,
        (
            (canvas_size[0] - fitted.width) // 2,
            (canvas_size[1] - fitted.height) // 2,
        ),
    )
    return output


def build_processed_sources() -> tuple[
    dict[str, Image.Image],
    dict[str, Image.Image],
    dict[str, Image.Image],
]:
    if not APPROVED_EXTERNAL.exists():
        raise FileNotFoundError(f"approved item 232 source missing: {APPROVED_EXTERNAL}")
    actual_sha = file_sha256(APPROVED_EXTERNAL)
    if actual_sha != APPROVED_SHA256:
        raise ValueError(
            "approved item 232 source SHA changed: "
            f"{actual_sha} != {APPROVED_SHA256}"
        )
    approved = Image.open(APPROVED_EXTERNAL).convert("RGBA")
    if approved.size != (1536, 1024):
        raise ValueError(f"approved sheet size changed: {approved.size}")
    APPROVED_SOURCE.parent.mkdir(parents=True, exist_ok=True)
    if (
        not APPROVED_SOURCE.exists()
        or file_sha256(APPROVED_SOURCE) != APPROVED_SHA256
    ):
        shutil.copyfile(APPROVED_EXTERNAL, APPROVED_SOURCE)

    opaque_no_face: dict[str, Image.Image] = {}
    wearable: dict[str, Image.Image] = {}
    world_sheet = Image.new("RGBA", approved.size, (0, 0, 0, 0))
    for slot, direction in enumerate(SOURCE_SLOT_DIRECTION_ORDER):
        base = trim_fur(green_screen_alpha(crop_slot(approved, slot)), direction)
        opaque_no_face[direction] = crop_alpha(base)
        with_face_window = punch_face_window(base, direction)
        wearable[direction] = crop_alpha(with_face_window)
        world_sheet.alpha_composite(
            with_face_window,
            ((slot % 4) * 384, (slot // 4) * 512),
        )
    WORLD_SOURCE.parent.mkdir(parents=True, exist_ok=True)
    world_sheet.save(WORLD_SOURCE, format="PNG", optimize=False)
    return opaque_no_face, wearable, {
        direction: premultiplied_lanczos_resize(
            wearable[direction],
            tuple(SOURCE_VARIANT_SIZE[direction]),
        )
        for direction in DIRECTIONS
    }


def build_acceptance_sheet(
    wearable: dict[str, Image.Image],
) -> dict:
    canvas = Image.new("RGBA", (8 * 128, 176), (15, 17, 21, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (8, 7),
        "holy_war / item 232 approved canonical source mapping",
        fill=(238, 238, 238, 255),
    )
    for slot, direction in enumerate(DIRECTIONS):
        cutout = wearable[direction]
        preview = fit_inside(cutout, (96, 96))
        x = slot * 128 + 16
        canvas.alpha_composite(preview, (x, 31))
        draw.text(
            (slot * 128 + 7, 134),
            f"S{slot} -> {direction}",
            fill=(255, 214, 87, 255),
        )
        draw.text(
            (slot * 128 + 7, 152),
            FACE_POLICY[direction],
            fill=(183, 211, 255, 255),
        )
    ACCEPTANCE.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(ACCEPTANCE, format="PNG", optimize=False)
    return {
        "path": resource_path(ACCEPTANCE),
        "fileSha256": file_sha256(ACCEPTANCE),
        "sourceGrid": [4, 2],
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": CANONICAL_ROW_SOURCE_SLOTS,
        "classificationStatus": "accepted_manual_visual_classification",
        "classificationEvidence": (
            "user approved the complete 4x2 sheet; source slots are explicitly "
            "top N,NE,E,SE and bottom S,SW,W,NW"
        ),
    }


def load_world_builder():
    sys.path.insert(0, str(ROOT / "tools"))
    import build_male_world_helmet_assets as world_builder

    return world_builder


def build_world_identity(
    variants: dict[str, Image.Image],
    wearable: dict[str, Image.Image],
) -> tuple[dict, dict]:
    builder = load_world_builder()
    baseline = builder.load_json(builder.CLIENT_BASELINE)
    anchors = builder.pose_anchor_map(baseline)
    hair_library = builder.read_library(builder.HAIR_SOURCE)
    recipe = {
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "concept": resource_path(WORLD_SOURCE),
        "sourceGrid": [4, 2],
        "directionClassificationStatus": (
            "accepted_manual_visual_classification"
        ),
        "directionClassificationEvidence": (
            "user-approved canonical grid: top N,NE,E,SE; "
            "bottom S,SW,W,NW"
        ),
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": CANONICAL_ROW_SOURCE_SLOTS,
        "outputPrefix": (
            "res://assets/art/items/client/world_wear/helmet/male/"
            "holy_war_helmet"
        ),
        "matteTolerance": 0,
    }
    acceptance = build_acceptance_sheet(wearable)
    records: dict[str, dict] = {}
    for source_slot, direction in enumerate(DIRECTIONS):
        variant = variants[direction]
        cutout = wearable[direction]
        records[direction] = {
            "sourceSlot": source_slot,
            "sourceDirection": direction,
            "sourceCutoutSize": list(cutout.size),
            "sourceCutoutRgbaSha256": rgba_sha256(cutout),
            "generatedSize": list(variant.size),
            "generatedRgbaSha256": rgba_sha256(variant),
            "effectiveOpaquePixels": round(
                builder.effective_opaque_pixels(variant), 4
            ),
            "clientMedianEnvelope": list(
                baseline["directionRuntimeTargetSize"][direction]
            ),
            "clientMedianOpaquePixels": round(
                float(baseline["directionRuntimeOpaquePixels"][direction]), 4
            ),
            "resizeFilter": (
                "premultiplied_alpha_lanczos_high_res_single_pass"
            ),
            "sourceBakePolicy": "approved_high_res_single_pass",
            "horizontalDiameterScale": HORIZONTAL_DIAMETER_SCALE,
            "runtimeScale": 1,
            "facePolicy": FACE_POLICY[direction],
            "hairPolicy": "hide",
            "furOrNeckPixelsRetained": False,
        }
    actions = {
        action_name: builder.build_generated_action(
            recipe,
            variants,
            records,
            anchors,
            hair_library,
            action_name,
        )
        for action_name in ACTION_SPECS
    }
    identity = {
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "sex": "male",
        "concept": resource_path(WORLD_SOURCE),
        "conceptFileSha256": file_sha256(WORLD_SOURCE),
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": file_sha256(APPROVED_SOURCE),
        "approvedSourceExpectedSha256": APPROVED_SHA256,
        "sourceGrid": [4, 2],
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": CANONICAL_ROW_SOURCE_SLOTS,
        "directionAcceptance": acceptance,
        "directionCutouts": records,
        "faceAperturePolicy": FACE_POLICY,
        "faceApertureShape": FACE_APERTURE_SHAPE,
        "faceAperturePixelPolicy": (
            "no face aperture in any direction; approved opaque black mask, "
            "mouth, chin, cheek guards and lower gold lattice all remain"
        ),
        "hairPolicy": "hide",
        "generatedFurOrNeckPixelsRetained": False,
        "worldSizingPolicy": (
            "approved_high_res_single_pass_horizontal_diameter_v1"
        ),
        "sourceBakePolicy": "approved_high_res_single_pass",
        "horizontalDiameterScale": HORIZONTAL_DIAMETER_SCALE,
        "offlineDownsampleFilter": "premultiplied_alpha_lanczos",
        "worldDirectionHeights": WORLD_HEIGHT,
        "sourceRowDirectionHeights": SOURCE_VARIANT_HEIGHT,
        "sourceRowDirectionSizes": SOURCE_VARIANT_SIZE,
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "integerPlacementCompatible": True,
        "stateItemPixelsUsed": False,
        "hairPixelsUsed": False,
        "actions": actions,
    }
    return identity, builder.appearance_for_identity(identity)


def build_paper_doll_and_icons(
    opaque_no_face: dict[str, Image.Image],
    wearable: dict[str, Image.Image],
) -> tuple[dict, dict, dict]:
    # Paper doll uses the opaque S design.  The approved black face mask is
    # part of the helmet and must not be cut out.  No base-image erase pass is
    # needed because the opaque helmet layer covers the head itself.
    paper = fit_height_on_canvas(
        wearable["S"],
        PAPER_CANVAS_SIZE,
        PAPER_CONTENT_HEIGHT,
    )
    erase = Image.new("RGBA", paper.size, (0, 0, 0, 0))
    HEAD_PATCH.parent.mkdir(parents=True, exist_ok=True)
    paper.save(HEAD_PATCH, format="PNG", optimize=False)
    erase.save(HEAD_ERASE_MASK, format="PNG", optimize=False)

    # Inventory and ground derivatives deliberately use the opaque S face
    # interior; these are item icons, not wearable face windows.
    inventory = fit_height_on_canvas(opaque_no_face["S"], (36, 35), 35)
    ground = fit_height_on_canvas(opaque_no_face["S"], (16, 17), 17)
    PROJECT_ICON_DIR.mkdir(parents=True, exist_ok=True)
    inventory.save(INVENTORY_ICON, format="PNG", optimize=False)
    ground.save(GROUND_ICON, format="PNG", optimize=False)

    paper_record = {
        "contractId": "equipment.paper_doll.classic_flattened_head_patch.v1",
        "itemId": ITEM_ID,
        "itemName": "圣战头盔",
        "slot": "头盔",
        "source": "user_approved_project_redesign",
        "sourceIndex": SOURCE_INDEX,
        "sourceRecordPath": resource_path(APPROVED_SOURCE),
        "sourceRecordRgbaSha256": APPROVED_SHA256,
        "sourceDirection": "S",
        "path": resource_path(HEAD_PATCH),
        "eraseMaskPath": resource_path(HEAD_ERASE_MASK),
        "drawOffset": [73, 27],
        "size": list(paper.size),
        "rgbaSha256": rgba_sha256(paper),
        "eraseMaskRgbaSha256": rgba_sha256(erase),
        "drawOrder": ["male_head_anatomy", "male_hair", "helmet"],
        "faceWindowPolicy": "none; preserve approved opaque black face mask",
        "eraseMaskPolicy": "no_cutout_all_transparent",
        "facePixelsBaked": False,
        "hairPixelsBaked": False,
        "subjectEvidence": {
            "method": "approved_source_S_direction_face_aperture_v1",
            "approvedSourcePath": resource_path(APPROVED_SOURCE),
            "approvedSourceFileSha256": APPROVED_SHA256,
        },
        "headOnlyEvidence": {
            "bottomLeftAlpha": paper.getpixel((0, paper.height - 1))[3],
            "bottomRightAlpha": paper.getpixel(
                (paper.width - 1, paper.height - 1)
            )[3],
        },
    }
    inventory_record = {
        "path": resource_path(INVENTORY_ICON),
        "library": "project.user_approved_redesign",
        "index": ITEM_ID,
        "size": list(inventory.size),
        "drawOffset": [0, 0],
        "confidence": "user_approved_exact_design",
        "sourceDirection": "S",
        "faceAperture": "opaque_black_mask_interior",
        "fileSha256": file_sha256(INVENTORY_ICON),
        "rgbaSha256": rgba_sha256(inventory),
    }
    ground_record = {
        "path": resource_path(GROUND_ICON),
        "library": "project.user_approved_redesign",
        "index": ITEM_ID,
        "size": list(ground.size),
        "drawOffset": [0, 0],
        "confidence": "user_approved_exact_design",
        "sourceDirection": "S",
        "faceAperture": "opaque_black_mask_interior",
        "fileSha256": file_sha256(GROUND_ICON),
        "rgbaSha256": rgba_sha256(ground),
    }
    return paper_record, inventory_record, ground_record


def semantic_non_target_snapshot() -> dict:
    recipes = load_json(RECIPE_PATH)
    world = load_json(WORLD_CONTRACT)
    catalog = load_json(VISUAL_CATALOG)
    head = load_json(HEAD_PATCH_CONTRACT)
    return {
        "recipeItems": [
            item for item in recipes["items"] if int(item["itemId"]) != ITEM_ID
        ],
        "recipeIdentities": [
            identity
            for identity in recipes["identities"]
            if str(identity["identityId"]) != IDENTITY_ID
        ],
        "worldIdentities": {
            key: value
            for key, value in world["visualIdentities"].items()
            if key != IDENTITY_ID
        },
        "worldItems": {
            key: value
            for key, value in world["itemsById"].items()
            if key != str(ITEM_ID)
        },
        "worldRuntime": {
            key: value
            for key, value in world["runtimeMappingsByItemId"].items()
            if key != str(ITEM_ID)
        },
        "catalogItems": {
            key: value
            for key, value in catalog["itemsById"].items()
            if key != str(ITEM_ID)
        },
        "headItems": {
            key: value
            for key, value in head["itemsById"].items()
            if key != str(ITEM_ID)
        },
        "headRuntime": {
            key: value
            for key, value in head["runtimeMappings"].items()
            if key != "圣战头盔"
        },
    }


def non_target_file_hashes() -> dict[str, str]:
    roots = [
        ROOT / "assets/art/items/client/world_wear/helmet/male",
        ROOT / "assets/art/characters/warrior/wear/helmet",
    ]
    result: dict[str, str] = {}
    for root in roots:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if "holy_war" in relative:
                continue
            result[relative] = file_sha256(path)
    return result


def file_tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(ROOT).as_posix(): file_sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def alpha_sprite_metrics(image: Image.Image) -> dict:
    alpha = image.convert("RGBA").getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("cannot measure an empty helmet sprite")
    cropped = alpha.crop(bbox)
    values = list(cropped.get_flattened_data())
    opaque_pixels = sum(value > 0 for value in values)
    solid_pixels = sum(value == 255 for value in values)
    semitransparent_pixels = sum(0 < value < 255 for value in values)
    lower_start = max(0, cropped.height // 2)
    row_spans: list[tuple[int, int]] = []
    for y in range(lower_start, cropped.height):
        xs = [x for x in range(cropped.width) if cropped.getpixel((x, y)) > 0]
        if xs:
            row_spans.append((min(xs), max(xs) + 1))
    if not row_spans:
        raise ValueError("helmet lower shell has no measurable alpha")
    sorted_widths = sorted(right - left for left, right in row_spans)
    body_width = sorted_widths[len(sorted_widths) // 2]
    sorted_centers = sorted((left + right) / 2 for left, right in row_spans)
    body_center = sorted_centers[len(sorted_centers) // 2]
    body_left = round(bbox[0] + body_center - body_width / 2)
    body_bbox = [
        body_left,
        bbox[1] + lower_start,
        body_left + body_width,
        bbox[3],
    ]
    transparent_rgb_leaks = 0
    rgba = image.convert("RGBA")
    for red, green, blue, pixel_alpha in rgba.get_flattened_data():
        if pixel_alpha == 0 and (red != 0 or green != 0 or blue != 0):
            transparent_rgb_leaks += 1
    bbox_area = cropped.width * cropped.height
    return {
        "totalBbox": list(bbox),
        "totalBboxSize": [cropped.width, cropped.height],
        "bodyCoreBbox": body_bbox,
        "bodyCoreWidth": body_width,
        "effectivePixelDensity": round(opaque_pixels / bbox_area, 4),
        "solidPixelDensity": round(solid_pixels / bbox_area, 4),
        "semiTransparentEdgePixels": semitransparent_pixels,
        "semiTransparentEdgeRatio": round(
            semitransparent_pixels / max(1, opaque_pixels),
            4,
        ),
        "transparentRgbLeakPixels": transparent_rgb_leaks,
        "playerHeadReferenceWidth": 9,
        "bodyToPlayerHeadWidthRatio": round(body_width / 9, 4),
    }


def runtime_idle_sprite(
    asset: dict,
    direction: str,
) -> Image.Image:
    record = asset["directions"][direction]
    path = record.get("texturesByAction", {}).get("idle")
    if path is None:
        path = record.get("texture")
    if not isinstance(path, str):
        raise ValueError(f"missing idle texture for {direction}")
    atlas = Image.open(ROOT / path.removeprefix("res://")).convert("RGBA")
    source_row = int(record["source_row"])
    return atlas.crop(
        (
            0,
            source_row * CELL[1],
            CELL[0],
            (source_row + 1) * CELL[1],
        )
    )


def paper_doll_occupancy(item_id: int) -> dict:
    path = (
        ROOT
        / "assets/art/items/client/paper_doll/classic_flattened_head"
        / f"item_{item_id:05d}_head.png"
    )
    if not path.exists():
        return {"available": False}
    image = Image.open(path).convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return {"available": True, "empty": True}
    bbox_size = [bbox[2] - bbox[0], bbox[3] - bbox[1]]
    return {
        "available": True,
        "canvasSize": list(image.size),
        "contentBbox": list(bbox),
        "contentBboxSize": bbox_size,
        "widthOccupancy": round(bbox_size[0] / image.width, 4),
        "heightOccupancy": round(bbox_size[1] / image.height, 4),
    }


def reference_pixel_parameter_audit() -> dict:
    contract = load_json(HELMET_V2_CONTRACT)
    items = [146, 147, 149, 150, 151, ITEM_ID]
    audit: dict[str, dict] = {}
    accepted_body_widths: list[int] = []
    for item_id in items:
        asset_id = contract["itemVisualAssetRefs"][str(item_id)]
        asset = contract["visualAssets"][asset_id]
        directions = {
            direction: alpha_sprite_metrics(
                runtime_idle_sprite(asset, direction)
            )
            for direction in DIRECTIONS
        }
        if item_id in {146, 147, 149, 151}:
            accepted_body_widths.extend(
                record["bodyCoreWidth"] for record in directions.values()
            )
        audit[str(item_id)] = {
            "visualAssetId": asset_id,
            "directionMetrics": directions,
            "paperDollOccupancy": paper_doll_occupancy(item_id),
            "readOnlyReference": item_id != ITEM_ID,
            "bodyCorePolicy": (
                "median alpha span across lower half; for item150 this "
                "intentionally excludes the upper decorative horns"
            ),
        }
    accepted_range = [
        min(accepted_body_widths),
        max(accepted_body_widths),
    ]
    target_widths = [
        record["bodyCoreWidth"]
        for record in audit[str(ITEM_ID)]["directionMetrics"].values()
    ]
    target_bbox_audit: dict[str, dict] = {}
    for direction, record in audit[str(ITEM_ID)]["directionMetrics"].items():
        actual_size = record["totalBboxSize"]
        previous_size = PREVIOUS_TARGET_BBOX_SIZE[direction]
        expected_size = EXPECTED_TARGET_BBOX_SIZE[direction]
        if actual_size[1] != previous_size[1]:
            raise AssertionError(
                f"item 232 {direction} target-semantic height changed: "
                f"{actual_size[1]} != {previous_size[1]}"
            )
        if abs(actual_size[0] - expected_size[0]) > 1:
            raise AssertionError(
                f"item 232 {direction} target-semantic width is not 0.8x: "
                f"{actual_size[0]} vs expected {expected_size[0]}"
            )
        target_bbox_audit[direction] = {
            "previousTargetSemanticBboxSize": previous_size,
            "expectedTargetSemanticBboxSizeAt0_8": expected_size,
            "actualTargetSemanticBboxSize": actual_size,
            "actualWidthRatio": round(
                actual_size[0] / previous_size[0],
                4,
            ),
            "heightUnchanged": True,
            "sourceRow": FROZEN_V2_SOURCE_DIRECTION_MAP[direction],
        }
    if min(target_widths) < accepted_range[0] - 1:
        raise AssertionError(
            "item 232 body diameter is narrower than accepted helmet range"
        )
    armored_shell_allowance = 2
    if max(target_widths) > accepted_range[1] + armored_shell_allowance:
        raise AssertionError(
            "item 232 body diameter remains wider than accepted helmet range"
        )
    if any(
        record["transparentRgbLeakPixels"] != 0
        for record in audit[str(ITEM_ID)]["directionMetrics"].values()
    ):
        raise AssertionError("item 232 contains RGB color in fully transparent pixels")
    return {
        "referenceItemIds": [146, 147, 149, 151],
        "hornedReferenceItemId": 150,
        "acceptedBodyCoreWidthRange": accepted_range,
        "armoredShellDecorationAllowancePx": armored_shell_allowance,
        "acceptedBodyCoreWidthRangeWithArmoredShellAllowance": [
            accepted_range[0] - 1,
            accepted_range[1] + armored_shell_allowance,
        ],
        "targetBodyCoreWidthRange": [min(target_widths), max(target_widths)],
        "playerHeadWidthBasisPx": 9,
        "targetSemanticOldToNewBbox": target_bbox_audit,
        "items": audit,
    }


def update_recipe() -> None:
    replacement = {
            "identityId": IDENTITY_ID,
            "sourceIndex": SOURCE_INDEX,
            "concept": resource_path(WORLD_SOURCE),
            "approvedSource": resource_path(APPROVED_SOURCE),
            "approvedSourceFileSha256": APPROVED_SHA256,
            "approvedSourceExternalEvidence": str(APPROVED_EXTERNAL),
            "approvedSourceGrid": [4, 2],
            "sourceGrid": [4, 2],
            "directionClassificationStatus": (
                "accepted_manual_visual_classification"
            ),
            "directionClassificationEvidence": (
                "user approved this exact sheet; top N,NE,E,SE and "
                "bottom S,SW,W,NW"
            ),
            "sourceSlotDirectionOrder": DIRECTIONS,
            "canonicalRowSourceSlots": CANONICAL_ROW_SOURCE_SLOTS,
            "outputPrefix": (
                "res://assets/art/items/client/world_wear/helmet/male/"
                "holy_war_helmet"
            ),
            "mattePolicy": "pure_green_remove_and_despill_v1",
            "generatedNeckFurPolicy": "remove",
            "faceAperturePolicy": FACE_POLICY,
            "faceApertureShape": FACE_APERTURE_SHAPE,
            "paperDollSourceDirection": "S",
            "paperDollFaceWindow": "none_opaque_black_mask",
            "paperDollEraseMask": "no_cutout_all_transparent",
            "inventorySourceDirection": "S",
            "inventoryFaceWindow": "opaque_black_mask_interior",
            "groundSourceDirection": "S",
            "groundFaceWindow": "opaque_black_mask_interior",
            "worldSizingPolicy": (
                "approved_high_res_single_pass_horizontal_diameter_v1"
            ),
            "sourceBakePolicy": "approved_high_res_single_pass",
            "horizontalDiameterScale": HORIZONTAL_DIAMETER_SCALE,
            "offlineDownsampleFilter": "premultiplied_alpha_lanczos",
            "worldDirectionHeights": WORLD_HEIGHT,
            "sourceRowDirectionHeights": SOURCE_VARIANT_HEIGHT,
            "sourceRowDirectionSizes": SOURCE_VARIANT_SIZE,
            "paperDollCanvasSize": list(PAPER_CANVAS_SIZE),
            "paperDollContentHeight": PAPER_CONTENT_HEIGHT,
            "runtimeScale": 1,
            "textureFilter": "nearest",
            "userOverrideAuthorization": (
                "direct use of the explicitly approved generated design"
            ),
        }
    text = RECIPE_PATH.read_text(encoding="utf-8")
    marker = f'"identityId": "{IDENTITY_ID}"'
    identities_at = text.find('"identities": [')
    marker_at = text.find(marker, identities_at)
    if marker_at < 0:
        raise ValueError("holy_war recipe object is missing")
    object_start = text.rfind("{", 0, marker_at)
    if object_start < 0:
        raise ValueError("holy_war recipe object start is missing")
    depth = 0
    in_string = False
    escaped = False
    object_end = -1
    for index in range(object_start, len(text)):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                object_end = index + 1
                break
    if object_end < 0:
        raise ValueError("holy_war recipe object end is missing")
    serialized = json.dumps(replacement, ensure_ascii=False, indent=2)
    serialized = "\n".join(
        ("    " + line if line else line) for line in serialized.splitlines()
    ).lstrip()
    updated = text[:object_start] + serialized + text[object_end:]
    parsed = json.loads(updated)
    target = next(
        value
        for value in parsed["identities"]
        if value["identityId"] == IDENTITY_ID
    )
    if target != replacement:
        raise AssertionError(
            "text-preserving holy_war recipe update failed: "
            f"target={target!r} replacement={replacement!r}"
        )
    RECIPE_PATH.write_text(updated, encoding="utf-8")


def update_contracts(
    identity: dict,
    appearance: dict,
    paper_record: dict,
    inventory_record: dict,
    ground_record: dict,
) -> None:
    world = load_json(WORLD_CONTRACT)
    world["recipeFileSha256"] = file_sha256(RECIPE_PATH)
    world["visualIdentities"][IDENTITY_ID] = identity
    world["itemsById"][str(ITEM_ID)]["maleAppearance"] = deepcopy(appearance)
    world["itemsById"][str(ITEM_ID)]["status"] = (
        "user_approved_project_redesign"
    )
    world["itemsById"][str(ITEM_ID)]["identityEvidence"] = {
        "library": "user-approved project source",
        "sourceIndex": SOURCE_INDEX,
        "usage": (
            "explicit item-232 visual override; no StateItem runtime pixels"
        ),
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
        "stateItemPixelsUsed": False,
    }
    world["runtimeMappingsByItemId"][str(ITEM_ID)] = {
        "helmetAppearance": deepcopy(appearance)
    }
    write_json(WORLD_CONTRACT, world)

    catalog = load_json(VISUAL_CATALOG)
    item = catalog["itemsById"][str(ITEM_ID)]
    item["icons"]["inventory"] = inventory_record
    item["icons"]["ground"] = ground_record
    item["icons"]["equippedSlot"] = {
        "path": resource_path(HEAD_PATCH),
        "library": "project.user_approved_redesign",
        "index": ITEM_ID,
        "size": list(Image.open(HEAD_PATCH).size),
        "drawOffset": [73, 27],
        "confidence": "user_approved_exact_design",
        "sourceDirection": "S",
        "faceAperture": "none_opaque_black_mask",
        "fileSha256": file_sha256(HEAD_PATCH),
    }
    item["paperDoll"] = {
        "status": "user_approved_project_redesign",
        "slot": "头盔",
        "gender": "通用",
        "sourceIndex": SOURCE_INDEX,
        "path": resource_path(HEAD_PATCH),
        "drawOffset": [73, 27],
        "rawDrawOffset": [73, 27],
        "size": list(Image.open(HEAD_PATCH).size),
        "source": "approved item-232 S-direction",
        "mappingConfidence": "user_approved_exact",
        "faceWindow": "none_opaque_black_mask",
    }
    item["worldWear"] = {
        "status": "user_approved_project_redesign",
        "contractId": "equipment.world_helmet.male.extension.v1",
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "helmetAppearance": deepcopy(appearance),
        "reason": (
            "user approved exact eight-direction source; the original opaque "
            "black face mask is preserved without any cutout"
        ),
    }
    write_json(VISUAL_CATALOG, catalog)

    head = load_json(HEAD_PATCH_CONTRACT)
    head["itemsById"][str(ITEM_ID)] = {
        "itemId": ITEM_ID,
        "itemName": "圣战头盔",
        "flattenedHeadPatch": paper_record,
    }
    head["runtimeMappings"]["圣战头盔"] = deepcopy(paper_record)
    write_json(HEAD_PATCH_CONTRACT, head)


def holy_war_v2_frozen_snapshot() -> dict:
    data = load_json(HELMET_V2_CONTRACT)
    asset = deepcopy(data["visualAssets"][IDENTITY_ID])
    for action in asset["source"]["actions"].values():
        action.pop("sha256", None)
    return asset


def update_v2_action_hashes(identity: dict) -> None:
    text = HELMET_V2_CONTRACT.read_text(encoding="utf-8")
    data = json.loads(text)
    asset = data["visualAssets"][IDENTITY_ID]
    if asset["source_direction_map"] != FROZEN_V2_SOURCE_DIRECTION_MAP:
        raise AssertionError("item 232 user source-direction mapping changed")
    for direction, source_row in FROZEN_V2_SOURCE_DIRECTION_MAP.items():
        record = asset["directions"][direction]
        if int(record["source_row"]) != source_row:
            raise AssertionError(
                f"item 232 {direction} source row changed before SHA update"
            )
    for action_name in ACTION_SPECS:
        old_sha = str(asset["source"]["actions"][action_name]["sha256"])
        new_sha = str(identity["actions"][action_name]["fileSha256"])
        old_token = f'"sha256": "{old_sha}"'
        new_token = f'"sha256": "{new_sha}"'
        if text.count(old_token) != 1:
            raise AssertionError(
                f"item 232 {action_name} old action SHA is not unique"
            )
        text = text.replace(old_token, new_token, 1)
    HELMET_V2_CONTRACT.write_text(text, encoding="utf-8")


def build_worn_previews() -> None:
    v2 = load_json(HELMET_V2_CONTRACT)
    asset = v2["visualAssets"][IDENTITY_ID]
    sockets = load_json(HEAD_SOCKET_CONTRACT)["playerVisuals"][
        asset["player_visual_id"]
    ]["actions"]["idle"]["directions"]
    body_path = (
        ROOT
        / "assets/art/items/client/world_wear/dress/male"
        / "dress_002_idle.png"
    )
    body = Image.open(body_path).convert("RGBA")
    helmet = Image.open(
        ROOT
        / asset["source"]["actions"]["idle"]["path"].removeprefix("res://")
    ).convert("RGBA")
    frames: dict[str, Image.Image] = {}
    for target_row, direction in enumerate(DIRECTIONS):
        source_row = int(asset["source_direction_map"][direction])
        body_cell = body.crop((0, target_row * CELL[1], CELL[0], (target_row + 1) * CELL[1]))
        helmet_cell = helmet.crop(
            (0, source_row * CELL[1], CELL[0], (source_row + 1) * CELL[1])
        )
        record = asset["directions"][direction]
        pivot = record["pivotByActionFrame"]["idle"][0]
        socket = sockets[direction][0]["head_socket"]
        nudge = record["nudge"]
        destination = (
            int(socket[0]) - int(pivot[0]) + int(nudge[0]),
            int(socket[1]) - int(pivot[1]) + int(nudge[1]),
        )
        body_cell.alpha_composite(helmet_cell, destination)
        frames[direction] = body_cell

    WORN_PREVIEW_1X.parent.mkdir(parents=True, exist_ok=True)
    one_x = Image.new("RGBA", (CELL[0] * 8, CELL[1] + 20), (18, 20, 24, 255))
    one_draw = ImageDraw.Draw(one_x)
    for index, direction in enumerate(DIRECTIONS):
        one_x.alpha_composite(frames[direction], (index * CELL[0], 0))
        one_draw.text((index * CELL[0] + 4, CELL[1] + 2), direction, fill=(255, 224, 120, 255))
    one_x.save(WORN_PREVIEW_1X, format="PNG", optimize=False)

    zoom_source = (40, 40)
    zoom = 8
    tile = (zoom_source[0] * zoom, zoom_source[1] * zoom + 24)
    eight_x = Image.new("RGBA", (tile[0] * 4, tile[1] * 2), (18, 20, 24, 255))
    eight_draw = ImageDraw.Draw(eight_x)
    for index, direction in enumerate(DIRECTIONS):
        socket = sockets[direction][0]["head_socket"]
        crop = frames[direction].crop(
            (
                int(socket[0]) - zoom_source[0] // 2,
                int(socket[1]) - zoom_source[1] // 2,
                int(socket[0]) + zoom_source[0] // 2,
                int(socket[1]) + zoom_source[1] // 2,
            )
        ).resize((tile[0], zoom_source[1] * zoom), Image.Resampling.NEAREST)
        x = (index % 4) * tile[0]
        y = (index // 4) * tile[1]
        eight_x.alpha_composite(crop, (x, y))
        eight_draw.text((x + 6, y + zoom_source[1] * zoom + 3), direction, fill=(255, 224, 120, 255))
    eight_x.save(WORN_PREVIEW_8X, format="PNG", optimize=False)


def build_preview(
    wearable: dict[str, Image.Image],
    opaque_no_face: dict[str, Image.Image],
) -> None:
    tile = (256, 300)
    canvas = Image.new("RGBA", (tile[0] * 4, tile[1] * 2))
    background = ImageDraw.Draw(canvas)
    for y in range(0, canvas.height, 16):
        for x in range(0, canvas.width, 16):
            shade = 42 if (x // 16 + y // 16) % 2 == 0 else 88
            background.rectangle(
                (x, y, x + 15, y + 15),
                fill=(shade, shade, shade, 255),
            )
    draw = ImageDraw.Draw(canvas)
    for index, direction in enumerate(DIRECTIONS):
        preview = fit_inside(wearable[direction], (210, 240))
        x = (index % 4) * tile[0] + (tile[0] - preview.width) // 2
        y = (index // 4) * tile[1] + 18
        canvas.alpha_composite(preview, (x, y))
        draw.text(
            ((index % 4) * tile[0] + 10, (index // 4) * tile[1] + 274),
            f"{direction}  face={FACE_POLICY[direction]}",
            fill=(245, 220, 140, 255),
        )
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW, format="PNG", optimize=False)

    paper = Image.open(HEAD_PATCH).convert("RGBA")
    inventory = Image.open(INVENTORY_ICON).convert("RGBA")
    ground = Image.open(GROUND_ICON).convert("RGBA")
    presentation = Image.new("RGBA", (768, 320), (36, 38, 42, 255))
    presentation_draw = ImageDraw.Draw(presentation)
    panels = [
        ("paper doll: opaque black mask / no cutout", paper, 8, True),
        ("inventory: opaque black mask", inventory, 6, False),
        ("ground: opaque black mask", ground, 10, False),
    ]
    for index, (label, source, scale, show_skin) in enumerate(panels):
        left = index * 256
        presentation_draw.rectangle(
            (left + 8, 8, left + 248, 312),
            fill=(57, 60, 66, 255),
            outline=(180, 180, 180, 255),
        )
        if show_skin:
            presentation_draw.ellipse(
                (left + 91, 88, left + 165, 202),
                fill=(222, 172, 124, 255),
            )
        enlarged = source.resize(
            (source.width * scale, source.height * scale),
            Image.Resampling.NEAREST,
        )
        presentation.alpha_composite(
            enlarged,
            (
                left + (256 - enlarged.width) // 2,
                36 + (236 - enlarged.height) // 2,
            ),
        )
        presentation_draw.text(
            (left + 14, 284),
            label,
            fill=(245, 220, 140, 255),
        )
    presentation.save(
        PRESENTATION_PREVIEW,
        format="PNG",
        optimize=False,
    )


def validate_outputs() -> dict:
    approved = Image.open(APPROVED_SOURCE).convert("RGBA")
    world_source = Image.open(WORLD_SOURCE).convert("RGBA")
    if file_sha256(APPROVED_SOURCE) != APPROVED_SHA256:
        raise AssertionError("committed approved source is not byte-exact")
    if world_source.size != (1536, 1024):
        raise AssertionError("processed source grid size changed")
    source_signatures = []
    opaque_face_roi = {}
    closed_shell_roi = {}
    fur_clearance = {}
    for slot, direction in enumerate(DIRECTIONS):
        cell = crop_slot(world_source, slot)
        source_signatures.append(rgba_sha256(cell))
        samples = [
            cell.getpixel(tuple(point))[3]
            for point in OPAQUE_FACE_ROI_POINTS[direction]
        ]
        if any(alpha == 0 for alpha in samples):
            raise AssertionError(
                f"{direction} approved black face-mask ROI was opened: "
                f"{samples}"
            )
        opaque_face_roi[direction] = {
            "points": OPAQUE_FACE_ROI_POINTS[direction],
            "alpha": samples,
            "allOpaque": True,
        }
        if direction in CLOSED_SHELL_ROI_POINTS:
            samples = [
                cell.getpixel(tuple(point))[3]
                for point in CLOSED_SHELL_ROI_POINTS[direction]
            ]
            if any(alpha == 0 for alpha in samples):
                raise AssertionError(
                    f"{direction} rear shell ROI was opened: {samples}"
                )
            closed_shell_roi[direction] = {
                "points": CLOSED_SHELL_ROI_POINTS[direction],
                "alpha": samples,
                "allOpaque": True,
            }
        rectangle = FUR_VALIDATION_RECTS[direction]
        fur_roi = cell.crop(tuple(rectangle))
        retained = opaque_pixels(fur_roi)
        if retained != 0:
            raise AssertionError(
                f"{direction} retained {retained} opaque pixels in the "
                "forbidden neck/fur ROI"
            )
        fur_clearance[direction] = {
            "rect": rectangle,
            "opaquePixels": retained,
            "clear": True,
        }
    if len(set(source_signatures)) != 8:
        raise AssertionError("item 232 source directions are not unique")
    if any(
        pixel[1] >= 245 and pixel[0] <= 12 and pixel[2] <= 12 and pixel[3] > 0
        for pixel in world_source.get_flattened_data()
    ):
        raise AssertionError("processed source retained pure green matte")

    paper = Image.open(HEAD_PATCH).convert("RGBA")
    inventory = Image.open(INVENTORY_ICON).convert("RGBA")
    ground = Image.open(GROUND_ICON).convert("RGBA")
    if inventory.getchannel("A").getbbox() is None:
        raise AssertionError("inventory icon is empty")
    if ground.getchannel("A").getbbox() is None:
        raise AssertionError("ground icon is empty")
    presentation_face_alpha = {
        "paperDoll": {
            "point": [16, 28],
            "alpha": paper.getpixel((16, 28))[3],
            "expected": "opaque",
        },
        "inventory": {
            "point": [18, 24],
            "alpha": inventory.getpixel((18, 24))[3],
            "expected": "opaque",
        },
        "ground": {
            "point": [8, 12],
            "alpha": ground.getpixel((8, 12))[3],
            "expected": "opaque",
        },
    }
    if presentation_face_alpha["paperDoll"]["alpha"] == 0:
        raise AssertionError("paper-doll black face mask was cut out")
    if presentation_face_alpha["inventory"]["alpha"] == 0:
        raise AssertionError("inventory face center was made transparent")
    if presentation_face_alpha["ground"]["alpha"] == 0:
        raise AssertionError("ground face center was made transparent")
    paper_bbox = paper.getchannel("A").getbbox()
    if paper_bbox is None:
        raise AssertionError("paper-doll helmet is empty")
    paper_content_size = [
        paper_bbox[2] - paper_bbox[0],
        paper_bbox[3] - paper_bbox[1],
    ]
    if paper_content_size[1] != PAPER_CONTENT_HEIGHT:
        raise AssertionError(
            "paper-doll helmet height changed: "
            f"{paper_content_size[1]} != {PAPER_CONTENT_HEIGHT}"
        )
    world = load_json(WORLD_CONTRACT)
    identity = world["visualIdentities"][IDENTITY_ID]
    if identity["sourceSlotDirectionOrder"] != DIRECTIONS:
        raise AssertionError("item 232 source direction order changed")
    if identity["canonicalRowSourceSlots"] != list(range(8)):
        raise AssertionError("item 232 canonical mapping changed")
    if identity["faceAperturePolicy"] != FACE_POLICY:
        raise AssertionError("item 232 face policy changed")
    if any(
        identity["directionCutouts"][direction]["facePolicy"] != "closed"
        for direction in DIRECTIONS
    ):
        raise AssertionError("a direction exposes a forbidden face aperture")
    if any(
        int(record["runtimeScale"]) != 1
        for record in identity["directionCutouts"].values()
    ):
        raise AssertionError("item 232 introduced runtime scaling")
    for direction in DIRECTIONS:
        record = identity["directionCutouts"][direction]
        if record["generatedSize"] != SOURCE_VARIANT_SIZE[direction]:
            raise AssertionError(
                f"item 232 source row {direction} size is not normalized"
            )
        if record["resizeFilter"] != (
            "premultiplied_alpha_lanczos_high_res_single_pass"
        ):
            raise AssertionError(
                f"item 232 {direction} was not baked directly from high-res"
            )
        if float(record["horizontalDiameterScale"]) != (
            HORIZONTAL_DIAMETER_SCALE
        ):
            raise AssertionError(
                f"item 232 {direction} horizontal scale contract changed"
            )
    v2_asset = load_json(HELMET_V2_CONTRACT)["visualAssets"][IDENTITY_ID]
    if v2_asset["source_direction_map"] != FROZEN_V2_SOURCE_DIRECTION_MAP:
        raise AssertionError("item 232 saved source-direction mapping changed")
    for direction, source_row in FROZEN_V2_SOURCE_DIRECTION_MAP.items():
        record = v2_asset["directions"][direction]
        if int(record["source_row"]) != source_row:
            raise AssertionError(f"item 232 {direction} saved row changed")
        if record["runtime_scale"] != [1, 1]:
            raise AssertionError(f"item 232 {direction} runtime scale changed")
    for action_name, spec in ACTION_SPECS.items():
        action = identity["actions"][action_name]
        atlas_path = ROOT / action["path"].removeprefix("res://")
        atlas = Image.open(atlas_path).convert("RGBA")
        if atlas.size != (CELL[0] * spec["frames"], CELL[1] * 8):
            raise AssertionError(f"{action_name} atlas size changed")
        if file_sha256(atlas_path) != action["fileSha256"]:
            raise AssertionError(f"{action_name} atlas SHA changed")
        if (
            v2_asset["source"]["actions"][action_name]["sha256"]
            != action["fileSha256"]
        ):
            raise AssertionError(f"{action_name} v2 action SHA is stale")
    if not WORN_PREVIEW_1X.exists() or not WORN_PREVIEW_8X.exists():
        raise AssertionError("worn eight-direction previews are missing")
    pixel_parameter_audit = reference_pixel_parameter_audit()
    return {
        "contractId": "equipment.world_helmet.holy_war_232.redesign.v1",
        "itemId": ITEM_ID,
        "identityId": IDENTITY_ID,
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
        "processedSource": resource_path(WORLD_SOURCE),
        "processedSourceFileSha256": file_sha256(WORLD_SOURCE),
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": list(range(8)),
        "uniqueDirectionRgbaSha256": source_signatures,
        "faceAperturePolicy": FACE_POLICY,
        "faceApertureShape": FACE_APERTURE_SHAPE,
        "allDirectionsFaceMaskClosed": DIRECTIONS,
        "wearableFaceWindowTransparent": False,
        "paperDollFaceWindowTransparent": False,
        "paperDollEraseMaskAllTransparent": True,
        "inventoryFaceWindowOpaque": True,
        "groundFaceWindowOpaque": True,
        "generatedFurOrNeckPixelsRetained": False,
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "offlineBakeFilter": "premultiplied_alpha_lanczos",
        "sourceBakePolicy": "approved_high_res_single_pass",
        "horizontalDiameterScale": HORIZONTAL_DIAMETER_SCALE,
        "worldSizingAudit": {
            "bakePolicy": "approved_high_res_single_pass",
            "approvedSourceSize": [1536, 1024],
            "approvedSourceSha256": APPROVED_SHA256,
            "offlineDownsampleFilter": "premultiplied_alpha_lanczos",
            "horizontalDiameterScale": HORIZONTAL_DIAMETER_SCALE,
            "heightsUnchanged": True,
            "playerHairHeadWidthMedian": 9,
            "worldDirectionHeights": WORLD_HEIGHT,
            "sourceRowDirectionHeights": SOURCE_VARIANT_HEIGHT,
            "sourceRowDirectionSizes": SOURCE_VARIANT_SIZE,
            "paperDollCanvasSize": list(PAPER_CANVAS_SIZE),
            "paperDollContentSize": paper_content_size,
            "paperDollContentHeight": PAPER_CONTENT_HEIGHT,
            "sizingBasis": (
                "helmet_body_diameter; decorative horns may exceed body core"
            ),
        },
        "acceptedHelmetPixelParameterAudit": pixel_parameter_audit,
        "preview": resource_path(PREVIEW),
        "paperInventoryGroundPreview": resource_path(PRESENTATION_PREVIEW),
        "wornIdle8Direction1xPreview": resource_path(WORN_PREVIEW_1X),
        "wornIdle8Direction8xPreview": resource_path(WORN_PREVIEW_8X),
        "presentationFaceCenterAlphaEvidence": presentation_face_alpha,
        "opaqueFaceMaskRoiEvidence": opaque_face_roi,
        "closedRearShellRoiEvidence": closed_shell_roi,
        "furClearanceRoiEvidence": fur_clearance,
    }


def build() -> dict:
    non_target_semantic_before = semantic_non_target_snapshot()
    non_target_files_before = non_target_file_hashes()
    generated_helmet_v2_before = file_tree_hashes(GENERATED_HELMET_V2_ROOT)
    helmet_v2_overrides_before = file_sha256(HELMET_V2_OVERRIDES)
    frozen_v2_before = holy_war_v2_frozen_snapshot()
    opaque_no_face, wearable, variants = build_processed_sources()
    update_recipe()
    identity, appearance = build_world_identity(variants, wearable)
    paper_record, inventory_record, ground_record = build_paper_doll_and_icons(
        opaque_no_face,
        wearable,
    )
    update_contracts(
        identity,
        appearance,
        paper_record,
        inventory_record,
        ground_record,
    )
    update_v2_action_hashes(identity)
    if holy_war_v2_frozen_snapshot() != frozen_v2_before:
        raise AssertionError(
            "item 232 mapping, pivots, nudges or policies changed"
        )
    build_preview(wearable, opaque_no_face)
    build_worn_previews()
    if semantic_non_target_snapshot() != non_target_semantic_before:
        raise AssertionError("single-target build changed non-232 contract data")
    generated_helmet_v2_after = file_tree_hashes(GENERATED_HELMET_V2_ROOT)
    if generated_helmet_v2_after != generated_helmet_v2_before:
        raise AssertionError(
            "single-target build changed assets/generated/helmet_v2"
        )
    helmet_v2_overrides_after = file_sha256(HELMET_V2_OVERRIDES)
    if helmet_v2_overrides_after != helmet_v2_overrides_before:
        raise AssertionError(
            "single-target build changed helmet calibration overrides"
        )
    non_target_files_after = non_target_file_hashes()
    if non_target_files_after != non_target_files_before:
        changed = sorted(
            set(non_target_files_before) | set(non_target_files_after)
        )
        changed = [
            path
            for path in changed
            if non_target_files_before.get(path) != non_target_files_after.get(path)
        ]
        raise AssertionError(
            "single-target build changed frozen non-232 files: "
            + ", ".join(changed)
        )
    report = validate_outputs()
    report["frozenNon232FileCount"] = len(non_target_files_before)
    report["frozenNon232FilesUnchanged"] = True
    report["non232ContractDataUnchanged"] = True
    report["generatedHelmetV2FrozenFileCount"] = len(
        generated_helmet_v2_before
    )
    report["generatedHelmetV2FilesUnchanged"] = True
    report["helmetV2OverridesSha256Before"] = helmet_v2_overrides_before
    report["helmetV2OverridesSha256After"] = helmet_v2_overrides_after
    report["helmetV2OverridesUnchanged"] = True
    report["singleTargetBuild"] = {
        "acceptedIdentity": IDENTITY_ID,
        "acceptedItemId": ITEM_ID,
        "otherIdentitiesRejected": True,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    write_json(REPORT, report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--identity")
    group.add_argument("--item-id", type=int)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if args.identity is not None and args.identity != IDENTITY_ID:
        raise SystemExit(
            f"single-target builder rejects identity {args.identity!r}; "
            f"only {IDENTITY_ID!r} is legal"
        )
    if args.item_id is not None and args.item_id != ITEM_ID:
        raise SystemExit(
            f"single-target builder rejects item {args.item_id}; "
            f"only {ITEM_ID} is legal"
        )
    if args.validate_only:
        report = validate_outputs()
    else:
        report = build()
    print(
        "HOLY_WAR_HELMET_232_PASS "
        f"item={report['itemId']} identity={report['identityId']} "
        "directions=8 face_windows=false all_masks_opaque=true "
        "non232_unchanged=true"
    )


if __name__ == "__main__":
    main()
