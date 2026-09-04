#!/usr/bin/env python3
"""Build the user-approved item 236 helmet without touching other helmets.

This is intentionally a single-target builder.  The approved 4x2 sheet is
kept byte-for-byte as provenance, then a transparent world sheet, six physical
world atlases, a face-window paper-doll layer, and opaque inventory/ground
icons are derived from it.  No other visual identity can be selected.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from copy import deepcopy
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
APPROVED_EXTERNAL = Path(
    r"C:\Users\Administrator\Downloads"
    r"\ChatGPT Image 2026年7月27日 17_18_23.png"
)
APPROVED_SHA256 = (
    "b676e30dbb335c55df10ac89aac4636f5a7b557cbd978f0edfd8a419c12afa14"
)
APPROVED_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "god_magic_helmet_approved_20260727.png"
)
WORLD_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "god_magic_helmet_8dir.png"
)
RECIPE_PATH = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
WORLD_CONTRACT = ROOT / "assets/data/equipment_male_world_helmet.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
HEAD_PATCH_CONTRACT = (
    ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
)
HEAD_PATCH = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00236_head.png"
)
HEAD_ERASE_MASK = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00236_erase_mask.png"
)
PROJECT_ICON_DIR = (
    ROOT / "assets/art/items/client/project_redesign/helmet/god_magic"
)
INVENTORY_ICON = PROJECT_ICON_DIR / "item_00236_inventory.png"
GROUND_ICON = PROJECT_ICON_DIR / "item_00236_ground.png"
ACCEPTANCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/acceptance"
    / "god_magic_direction_mapping.png"
)
PREVIEW = (
    ROOT / "outputs/helmet_236/god_magic_236_processed_8dir_preview.png"
)
PRESENTATION_PREVIEW = (
    ROOT / "outputs/helmet_236/god_magic_236_paper_inventory_ground_preview.png"
)
REPORT = ROOT / "outputs/helmet_236/god_magic_236_validation_report.json"

IDENTITY_ID = "god_magic"
ITEM_ID = 236
SOURCE_INDEX = 101
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
SOURCE_SLOT_DIRECTION_ORDER = DIRECTIONS
CANONICAL_ROW_SOURCE_SLOTS = list(range(8))
SOURCE_SIZE = (1774, 887)
SOURCE_X_BOUNDS = [0, 444, 887, 1331, 1774]
SOURCE_Y_BOUNDS = [0, 444, 887]
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

# Face openings are punched only in the wearable/paper-doll variants.  Gold,
# red-gem and highlighted metal pixels are retained, so the apertures expose
# the player's original face without deleting the decorative cage/trim.
FACE_WINDOWS: dict[str, list[list[list[int]]]] = {}

# Rebuild directly from the approved 1774x887 source while reducing only the
# world-worn content by another 10%.  This is not a resize of the prior
# runtime art: atlas cells remain 192x160 and runtime scale stays 1.
WORLD_HEIGHT = {
    "N": 17,
    "NE": 17,
    "E": 16,
    "SE": 17,
    "S": 17,
    "SW": 17,
    "W": 16,
    "NW": 17,
}
WORLD_SCALE_RATIO = 0.47
RELATIVE_TO_PREVIOUS_SCALE = 0.90
PAPER_CANVAS_SIZE = (32, 41)
PAPER_CONTENT_ENVELOPE = (20, 24)


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
    return sheet.crop(slot_box(slot))


def slot_box(slot: int) -> tuple[int, int, int, int]:
    column = slot % 4
    row = slot // 4
    return (
        SOURCE_X_BOUNDS[column],
        SOURCE_Y_BOUNDS[row],
        SOURCE_X_BOUNDS[column + 1],
        SOURCE_Y_BOUNDS[row + 1],
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


def clean_lanczos_matte_edge(image: Image.Image) -> Image.Image:
    output = image.convert("RGBA")
    pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha <= 3:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            if (
                green >= 180
                and green >= red + 70
                and green >= blue + 70
            ):
                pixels[x, y] = (0, 0, 0, 0)
                continue
            if green > max(red, blue) + 28:
                green = max(red, blue) + 12
            pixels[x, y] = (red, green, blue, alpha)
    return output


def resize_to_height(image: Image.Image, height: int) -> Image.Image:
    width = max(1, round(image.width * height / image.height))
    return clean_lanczos_matte_edge(
        image.resize((width, height), Image.Resampling.LANCZOS)
    )


def fit_inside(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    resized = clean_lanczos_matte_edge(
        image.resize(target, Image.Resampling.LANCZOS)
    )
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.alpha_composite(
        resized,
        ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2),
    )
    return output


def fit_inside_envelope(
    image: Image.Image,
    canvas_size: tuple[int, int],
    content_envelope: tuple[int, int],
) -> Image.Image:
    fitted = fit_inside(image, content_envelope)
    used = fitted.getchannel("A").getbbox()
    if used is None:
        raise ValueError("empty fitted helmet image")
    fitted = fitted.crop(used)
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
        raise FileNotFoundError(f"approved item 236 source missing: {APPROVED_EXTERNAL}")
    actual_sha = file_sha256(APPROVED_EXTERNAL)
    if actual_sha != APPROVED_SHA256:
        raise ValueError(
            "approved item 236 source SHA changed: "
            f"{actual_sha} != {APPROVED_SHA256}"
        )
    approved = Image.open(APPROVED_EXTERNAL).convert("RGBA")
    if approved.size != SOURCE_SIZE:
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
        base = green_screen_alpha(crop_slot(approved, slot))
        opaque_no_face[direction] = crop_alpha(base)
        with_face_window = punch_face_window(base, direction)
        wearable[direction] = crop_alpha(with_face_window)
        slot_bounds = slot_box(slot)
        world_sheet.alpha_composite(
            with_face_window,
            (slot_bounds[0], slot_bounds[1]),
        )
    WORLD_SOURCE.parent.mkdir(parents=True, exist_ok=True)
    world_sheet.save(WORLD_SOURCE, format="PNG", optimize=False)
    return opaque_no_face, wearable, {
        direction: resize_to_height(wearable[direction], WORLD_HEIGHT[direction])
        for direction in DIRECTIONS
    }


def build_acceptance_sheet(
    wearable: dict[str, Image.Image],
) -> dict:
    canvas = Image.new("RGBA", (8 * 128, 176), (15, 17, 21, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (8, 7),
        "god_magic / item 236 approved canonical source mapping",
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
            "god_magic_helmet"
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
            "resizeFilter": "lanczos_original_source_to_final_integer_pixels",
            "worldScaleRatio": WORLD_SCALE_RATIO,
            "relativeToPreviousScale": RELATIVE_TO_PREVIOUS_SCALE,
            "singlePassDownsampleFromApprovedSource": True,
            "runtimeScale": 1,
            "facePolicy": FACE_POLICY[direction],
            "hairPolicy": "hide",
            "blackClothVeilRetained": True,
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
        "approvedBlackClothVeilRetained": True,
        "worldScaleRatio": WORLD_SCALE_RATIO,
        "relativeToPreviousScale": RELATIVE_TO_PREVIOUS_SCALE,
        "bakeResizeFilter": "lanczos",
        "singlePassDownsampleFromApprovedSource": True,
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
    paper = fit_inside_envelope(
        wearable["S"],
        PAPER_CANVAS_SIZE,
        PAPER_CONTENT_ENVELOPE,
    )
    erase = Image.new("RGBA", paper.size, (255, 255, 255, 0))
    erase.putalpha(
        paper.getchannel("A").point(lambda alpha: 255 if alpha > 0 else 0)
    )
    HEAD_PATCH.parent.mkdir(parents=True, exist_ok=True)
    paper.save(HEAD_PATCH, format="PNG", optimize=False)
    erase.save(HEAD_ERASE_MASK, format="PNG", optimize=False)

    # Inventory and ground derivatives deliberately use the opaque S face
    # interior; these are item icons, not wearable face windows.
    inventory = fit_inside(opaque_no_face["S"], (36, 35))
    ground = fit_inside(opaque_no_face["S"], (16, 17))
    PROJECT_ICON_DIR.mkdir(parents=True, exist_ok=True)
    inventory.save(INVENTORY_ICON, format="PNG", optimize=False)
    ground.save(GROUND_ICON, format="PNG", optimize=False)

    paper_record = {
        "contractId": "equipment.paper_doll.classic_flattened_head_patch.v1",
        "itemId": ITEM_ID,
        "itemName": "法神头盔",
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
        "eraseMaskPolicy": "clear_exact_approved_S_silhouette",
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
            if key != "法神头盔"
        },
    }


def non_target_file_hashes() -> dict[str, str]:
    roots = [
        ROOT / "assets/art/items/client/world_wear/helmet/male",
        ROOT / "assets/art/characters/warrior/wear/helmet",
        ROOT / "assets/art/items/client/paper_doll/classic_flattened_head",
        ROOT / "assets/art/items/client/project_redesign/helmet",
    ]
    result: dict[str, str] = {}
    for root in roots:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if "god_magic" in relative or "item_00236_" in relative:
                continue
            result[relative] = file_sha256(path)
    return result


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
                "god_magic_helmet"
            ),
            "mattePolicy": "pure_green_remove_and_despill_v1",
            "approvedBlackClothVeilPolicy": "retain_exact_subject_pixels",
            "faceAperturePolicy": FACE_POLICY,
            "faceApertureShape": FACE_APERTURE_SHAPE,
            "paperDollSourceDirection": "S",
            "paperDollFaceWindow": "none_opaque_black_mask",
            "paperDollEraseMask": "clear_exact_approved_S_silhouette",
            "inventorySourceDirection": "S",
            "inventoryFaceWindow": "opaque_black_mask_interior",
            "groundSourceDirection": "S",
            "groundFaceWindow": "opaque_black_mask_interior",
            "calibrationResizeFilter": (
                "lanczos_downsample_nearest_runtime_v1"
            ),
            "calibrationBaseScalePercent": 47,
            "relativeToPreviousScalePercent": 90,
            "singlePassDownsampleFromApprovedSource": True,
            "runtimeScale": 1,
            "textureFilter": "nearest",
            "userOverrideAuthorization": (
                "direct use of the explicitly supplied replacement sheet"
            ),
        }
    text = RECIPE_PATH.read_text(encoding="utf-8")
    marker = f'"identityId": "{IDENTITY_ID}"'
    identities_at = text.find('"identities": [')
    marker_at = text.find(marker, identities_at)
    if marker_at < 0:
        raise ValueError("god_magic recipe object is missing")
    object_start = text.rfind("{", 0, marker_at)
    if object_start < 0:
        raise ValueError("god_magic recipe object start is missing")
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
        raise ValueError("god_magic recipe object end is missing")
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
            "text-preserving god_magic recipe update failed: "
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
            "explicit item-236 visual override; no StateItem runtime pixels"
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
        "source": "approved item-236 S-direction",
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
        "itemName": "法神头盔",
        "flattenedHeadPatch": paper_record,
    }
    head["runtimeMappings"]["法神头盔"] = deepcopy(paper_record)
    write_json(HEAD_PATCH_CONTRACT, head)


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
    erase = Image.open(HEAD_ERASE_MASK).convert("RGBA")
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
    if world_source.size != SOURCE_SIZE:
        raise AssertionError("processed source grid size changed")
    source_signatures = []
    opaque_black_cloth_evidence = {}
    for slot, direction in enumerate(DIRECTIONS):
        cell = crop_slot(world_source, slot)
        source_signatures.append(rgba_sha256(cell))
        bounds = cell.getchannel("A").getbbox()
        if bounds is None:
            raise AssertionError(f"{direction} processed subject is empty")
        point = [
            (bounds[0] + bounds[2]) // 2,
            round(bounds[1] + 0.70 * (bounds[3] - bounds[1])),
        ]
        alpha = cell.getpixel(tuple(point))[3]
        if alpha == 0:
            raise AssertionError(
                f"{direction} approved black cloth veil was opened at {point}"
            )
        opaque_black_cloth_evidence[direction] = {
            "alphaBounds": list(bounds),
            "point": point,
            "alpha": alpha,
            "allOpaque": True,
        }
    if len(set(source_signatures)) != 8:
        raise AssertionError("item 236 source directions are not unique")
    if any(
        pixel[1] >= 245 and pixel[0] <= 12 and pixel[2] <= 12 and pixel[3] > 0
        for pixel in world_source.get_flattened_data()
    ):
        raise AssertionError("processed source retained pure green matte")

    paper = Image.open(HEAD_PATCH).convert("RGBA")
    erase = Image.open(HEAD_ERASE_MASK).convert("RGBA")
    inventory = Image.open(INVENTORY_ICON).convert("RGBA")
    ground = Image.open(GROUND_ICON).convert("RGBA")
    if inventory.getchannel("A").getbbox() is None:
        raise AssertionError("inventory icon is empty")
    if ground.getchannel("A").getbbox() is None:
        raise AssertionError("ground icon is empty")
    if erase.getchannel("A").getbbox() is None:
        raise AssertionError("paper-doll erase mask is empty")
    erase_corners = [
        erase.getpixel((0, 0))[3],
        erase.getpixel((erase.width - 1, 0))[3],
        erase.getpixel((0, erase.height - 1))[3],
        erase.getpixel((erase.width - 1, erase.height - 1))[3],
    ]
    if any(alpha != 0 for alpha in erase_corners):
        raise AssertionError("paper-doll erase mask outer corner is opaque")
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
    world = load_json(WORLD_CONTRACT)
    identity = world["visualIdentities"][IDENTITY_ID]
    if identity["sourceSlotDirectionOrder"] != DIRECTIONS:
        raise AssertionError("item 236 source direction order changed")
    if identity["canonicalRowSourceSlots"] != list(range(8)):
        raise AssertionError("item 236 canonical mapping changed")
    if identity["faceAperturePolicy"] != FACE_POLICY:
        raise AssertionError("item 236 face policy changed")
    if any(
        identity["directionCutouts"][direction]["facePolicy"] != "closed"
        for direction in DIRECTIONS
    ):
        raise AssertionError("a direction exposes a forbidden face aperture")
    if any(
        int(record["runtimeScale"]) != 1
        for record in identity["directionCutouts"].values()
    ):
        raise AssertionError("item 236 introduced runtime scaling")
    generated_sizes = {
        direction: identity["directionCutouts"][direction]["generatedSize"]
        for direction in DIRECTIONS
    }
    if any(
        size[1] != WORLD_HEIGHT[direction]
        for direction, size in generated_sizes.items()
    ):
        raise AssertionError("item 236 world bake height left default envelope")
    if max(size[0] for size in generated_sizes.values()) > 14:
        raise AssertionError("item 236 world bake width exceeds default envelope")
    paper_bounds = paper.getchannel("A").getbbox()
    if paper_bounds is None:
        raise AssertionError("paper-doll helmet is empty")
    paper_content_size = [
        paper_bounds[2] - paper_bounds[0],
        paper_bounds[3] - paper_bounds[1],
    ]
    if (
        paper_content_size[0] > PAPER_CONTENT_ENVELOPE[0]
        or paper_content_size[1] > PAPER_CONTENT_ENVELOPE[1]
    ):
        raise AssertionError("paper-doll helmet exceeds default content envelope")
    for action_name, spec in ACTION_SPECS.items():
        action = identity["actions"][action_name]
        atlas_path = ROOT / action["path"].removeprefix("res://")
        atlas = Image.open(atlas_path).convert("RGBA")
        if atlas.size != (CELL[0] * spec["frames"], CELL[1] * 8):
            raise AssertionError(f"{action_name} atlas size changed")
        if file_sha256(atlas_path) != action["fileSha256"]:
            raise AssertionError(f"{action_name} atlas SHA changed")
    return {
        "contractId": "equipment.world_helmet.god_magic_236.redesign.v1",
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
        "paperDollEraseMaskHasTransparentAndOpaquePixels": True,
        "paperDollEraseMaskCornerAlpha": erase_corners,
        "inventoryFaceWindowOpaque": True,
        "groundFaceWindowOpaque": True,
        "approvedBlackClothVeilRetained": True,
        "worldScaleRatio": WORLD_SCALE_RATIO,
        "relativeToPreviousScale": RELATIVE_TO_PREVIOUS_SCALE,
        "worldBakeSource": resource_path(APPROVED_SOURCE),
        "singlePassDownsampleFromApprovedSource": True,
        "bakeResizeFilter": "lanczos",
        "postResizeMatteEdgePolicy": "clear_alpha_lte_3_and_green_despill",
        "worldGeneratedSizes": generated_sizes,
        "worldMaximumSize": [
            max(size[0] for size in generated_sizes.values()),
            max(size[1] for size in generated_sizes.values()),
        ],
        "atlasCellResolutionPreserved": list(CELL),
        "paperDollContentEnvelope": list(PAPER_CONTENT_ENVELOPE),
        "paperDollContentSize": paper_content_size,
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "preview": resource_path(PREVIEW),
        "paperInventoryGroundPreview": resource_path(PRESENTATION_PREVIEW),
        "presentationFaceCenterAlphaEvidence": presentation_face_alpha,
        "opaqueBlackClothVeilEvidence": opaque_black_cloth_evidence,
    }


def build() -> dict:
    non_target_semantic_before = semantic_non_target_snapshot()
    non_target_files_before = non_target_file_hashes()
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
    build_preview(wearable, opaque_no_face)
    if semantic_non_target_snapshot() != non_target_semantic_before:
        raise AssertionError("single-target build changed non-236 contract data")
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
            "single-target build changed frozen non-236 files: "
            + ", ".join(changed)
        )
    report = validate_outputs()
    report["frozenNon236FileCount"] = len(non_target_files_before)
    report["frozenNon236FilesUnchanged"] = True
    report["non236ContractDataUnchanged"] = True
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
        "GOD_MAGIC_HELMET_236_PASS "
        f"item={report['itemId']} identity={report['identityId']} "
        "directions=8 face_windows=false all_masks_opaque=true "
        "non236_unchanged=true"
    )


if __name__ == "__main__":
    main()
