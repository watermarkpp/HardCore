#!/usr/bin/env python3
"""Single-target builder for the user-supplied item 240 helmet."""

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
DOWNLOADS = Path(r"C:\Users\Administrator\Downloads")
APPROVED_EXTERNAL_GLOB = "*18_50_11.png"
APPROVED_SHA256 = "a5e474da3c081ad2f5dd0926bd9dd1358e4179737e6b8d5614a77cf7b2ba9e8e"
SOURCE_SIZE = (1448, 1086)
SOURCE_X_BOUNDS = [0, 362, 724, 1086, 1448]
SOURCE_Y_BOUNDS = [0, 543, 1086]

IDENTITY_ID = "heavenly_taoist"
ITEM_ID = 240
ITEM_NAME = "天尊头盔"
SOURCE_INDEX = 102
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ACTION_SPECS = {
    "idle": {"frames": 4},
    "walk": {"frames": 6},
    "attack": {"frames": 6},
    "cast": {"frames": 6},
    "hit": {"frames": 3},
    "death": {"frames": 4},
}
CELL = (192, 160)
FOOT_ANCHOR = (64, 80)
PAPER_CANVAS = (32, 41)
PAPER_ENVELOPE = (20, 24)

APPROVED_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_helmet_approved_20260727.png"
)
WORLD_SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_helmet_8dir.png"
)
WORLD_PREFIX = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male"
    / "heavenly_taoist_helmet"
)
ACCEPTANCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/acceptance"
    / "heavenly_taoist_direction_mapping.png"
)
HEAD_PATCH = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00240_head.png"
)
HEAD_ERASE_MASK = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00240_erase_mask.png"
)
ICON_DIR = ROOT / "assets/art/items/client/project_redesign/helmet/heavenly_taoist"
INVENTORY_ICON = ICON_DIR / "item_00240_inventory.png"
GROUND_ICON = ICON_DIR / "item_00240_ground.png"

RECIPE_PATH = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
WORLD_CONTRACT = ROOT / "assets/data/equipment_male_world_helmet.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
HEAD_PATCH_CONTRACT = ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
HELMET_V2_CONTRACT = ROOT / "assets/data/equipment_helmet_visual_v2.json"

OUTPUT_ROOT = ROOT / "outputs/helmet_240"
SOURCE_PREVIEW = OUTPUT_ROOT / "heavenly_taoist_240_processed_8dir_preview.png"
PRESENTATION_PREVIEW = (
    OUTPUT_ROOT / "heavenly_taoist_240_paper_inventory_ground_preview.png"
)
REPORT = OUTPUT_ROOT / "heavenly_taoist_240_validation_report.json"

# These are the formal runtime envelopes from the primary male client baseline.
WORLD_ENVELOPES = {
    "N": (13, 16),
    "NE": (18, 18),
    "E": (15, 20),
    "SE": (16, 23),
    "S": (14, 21),
    "SW": (16, 23),
    "W": (16, 20),
    "NW": (16, 17),
}
FACE_POLICY = {
    "N": "closed",
    "NE": "closed",
    "E": "open_crown",
    "SE": "open_crown",
    "S": "open_crown",
    "SW": "open_crown",
    "W": "open_crown",
    "NW": "closed",
}
OPENING_VISIBILITY = {
    "N": "none",
    "NE": "none",
    "E": "partial",
    "SE": "partial",
    "S": "full",
    "SW": "partial",
    "W": "partial",
    "NW": "none",
}

# Polygons are local to one 362x543 source cell.  Only dark pixels inside
# these conservative openings are cleared, preserving all gold trim.
FACE_WINDOWS = {
    "E": [[[160, 365], [217, 361], [224, 442], [174, 451], [157, 419]]],
    "SE": [[[62, 319], [117, 319], [124, 416], [92, 450], [61, 445]]],
    "S": [[[123, 286], [239, 286], [237, 418], [126, 417]]],
    "SW": [[[199, 280], [291, 283], [290, 416], [233, 416], [198, 390]]],
    "W": [[[260, 286], [305, 286], [303, 415], [273, 417], [259, 390]]],
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
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


def approved_external() -> Path:
    matches = sorted(DOWNLOADS.glob(APPROVED_EXTERNAL_GLOB))
    exact = [path for path in matches if file_sha256(path) == APPROVED_SHA256]
    if len(exact) != 1:
        raise FileNotFoundError(
            f"expected one approved item-240 source, found {len(exact)}"
        )
    return exact[0]


def slot_box(slot: int) -> tuple[int, int, int, int]:
    column = slot % 4
    row = slot // 4
    return (
        SOURCE_X_BOUNDS[column],
        SOURCE_Y_BOUNDS[row],
        SOURCE_X_BOUNDS[column + 1],
        SOURCE_Y_BOUNDS[row + 1],
    )


def crop_slot(sheet: Image.Image, slot: int) -> Image.Image:
    return sheet.crop(slot_box(slot))


def crop_alpha(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("derived helmet image is empty")
    return image.crop(box)


def magenta_screen_alpha(image: Image.Image) -> Image.Image:
    """Remove the generated magenta matte while retaining red/green jewels."""
    output = image.convert("RGBA")
    width, height = output.size
    pixels = output.load()

    for y in range(height):
        for x in range(width):
            red, green, blue, _ = pixels[x, y]
            if (
                red >= 120
                and blue >= 120
                and min(red, blue) >= green + 35
                and abs(red - blue) <= 105
            ):
                pixels[x, y] = (0, 0, 0, 0)
    # Peel the anti-aliased matte fringe from the new transparent boundary.
    # This is adjacency-limited, so the enclosed red jewel is never selected.
    for _ in range(6):
        clear: list[tuple[int, int]] = []
        for y in range(height):
            for x in range(width):
                red, green, blue, alpha = pixels[x, y]
                if alpha == 0:
                    continue
                touches_transparency = any(
                    0 <= x + dx < width
                    and 0 <= y + dy < height
                    and pixels[x + dx, y + dy][3] == 0
                    for dx, dy in (
                        (-1, -1), (0, -1), (1, -1),
                        (-1, 0), (1, 0),
                        (-1, 1), (0, 1), (1, 1),
                    )
                )
                if (
                    touches_transparency
                    and red >= 40
                    and blue >= 40
                    and min(red, blue) >= green + 15
                    and abs(red - blue) <= 140
                ):
                    clear.append((x, y))
        if not clear:
            break
        for x, y in clear:
            pixels[x, y] = (0, 0, 0, 0)
    return output


def punch_face_window(image: Image.Image, direction: str) -> Image.Image:
    output = image.copy()
    polygons = FACE_WINDOWS.get(direction, [])
    if not polygons:
        return output
    mask = Image.new("L", output.size, 0)
    draw = ImageDraw.Draw(mask)
    for polygon in polygons:
        draw.polygon([tuple(point) for point in polygon], fill=255)
    pixels = output.load()
    selected = mask.load()
    for y in range(output.height):
        for x in range(output.width):
            if selected[x, y] == 0:
                continue
            red, green, blue, alpha = pixels[x, y]
            if alpha and max(red, green, blue) < 112:
                pixels[x, y] = (0, 0, 0, 0)
    return output


def premultiplied_resize(
    image: Image.Image,
    size: tuple[int, int],
) -> Image.Image:
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
            if alpha <= 3:
                target_pixels[x, y] = (0, 0, 0, 0)
                continue
            target_pixels[x, y] = (
                min(255, round(red * 255 / alpha)),
                min(255, round(green * 255 / alpha)),
                min(255, round(blue * 255 / alpha)),
                alpha,
            )
    return crop_alpha(output)


def fit_inside(image: Image.Image, envelope: tuple[int, int]) -> Image.Image:
    scale = min(envelope[0] / image.width, envelope[1] / image.height)
    target = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    return premultiplied_resize(image, target)


def fit_on_canvas(
    image: Image.Image,
    canvas: tuple[int, int],
    envelope: tuple[int, int],
) -> Image.Image:
    fitted = fit_inside(image, envelope)
    output = Image.new("RGBA", canvas, (0, 0, 0, 0))
    output.alpha_composite(
        fitted,
        ((canvas[0] - fitted.width) // 2, (canvas[1] - fitted.height) // 2),
    )
    return output


def build_sources() -> tuple[dict[str, Image.Image], dict[str, Image.Image]]:
    external = approved_external()
    approved = Image.open(external).convert("RGBA")
    if approved.size != SOURCE_SIZE:
        raise ValueError(f"approved source size changed: {approved.size}")
    APPROVED_SOURCE.parent.mkdir(parents=True, exist_ok=True)
    if not APPROVED_SOURCE.exists() or file_sha256(APPROVED_SOURCE) != APPROVED_SHA256:
        shutil.copyfile(external, APPROVED_SOURCE)

    opaque: dict[str, Image.Image] = {}
    wearable: dict[str, Image.Image] = {}
    processed = Image.new("RGBA", SOURCE_SIZE, (0, 0, 0, 0))
    for slot, direction in enumerate(DIRECTIONS):
        base = magenta_screen_alpha(crop_slot(approved, slot))
        opaque[direction] = crop_alpha(base)
        opened = punch_face_window(base, direction)
        wearable[direction] = crop_alpha(opened)
        bounds = slot_box(slot)
        processed.alpha_composite(opened, (bounds[0], bounds[1]))
    processed.save(WORLD_SOURCE, format="PNG", optimize=False)
    return opaque, wearable


def build_acceptance(wearable: dict[str, Image.Image]) -> dict:
    canvas = Image.new("RGBA", (1024, 176), (15, 17, 21, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (8, 7),
        "heavenly_taoist / item 240 canonical source mapping",
        fill=(238, 238, 238, 255),
    )
    for slot, direction in enumerate(DIRECTIONS):
        preview = fit_on_canvas(wearable[direction], (96, 96), (92, 92))
        canvas.alpha_composite(preview, (slot * 128 + 16, 31))
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
        "canonicalRowSourceSlots": list(range(8)),
        "classificationStatus": "accepted_manual_visual_classification",
        "classificationEvidence": (
            "user supplied the complete canonical 4x2 sheet: "
            "top N,NE,E,SE and bottom S,SW,W,NW"
        ),
    }


def load_world_builder():
    sys.path.insert(0, str(ROOT / "tools"))
    import build_male_world_helmet_assets as builder

    return builder


def build_world(
    wearable: dict[str, Image.Image],
) -> tuple[dict, dict]:
    builder = load_world_builder()
    baseline = builder.load_json(builder.CLIENT_BASELINE)
    anchors = builder.pose_anchor_map(baseline)
    hair_library = builder.read_library(builder.HAIR_SOURCE)
    variants = {
        direction: fit_inside(wearable[direction], WORLD_ENVELOPES[direction])
        for direction in DIRECTIONS
    }
    recipe = {
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "concept": resource_path(WORLD_SOURCE),
        "sourceGrid": [4, 2],
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": list(range(8)),
        "outputPrefix": resource_path(WORLD_PREFIX),
        "matteTolerance": 0,
    }
    records: dict[str, dict] = {}
    for slot, direction in enumerate(DIRECTIONS):
        variant = variants[direction]
        cutout = wearable[direction]
        records[direction] = {
            "sourceSlot": slot,
            "sourceDirection": direction,
            "sourceCutoutSize": list(cutout.size),
            "sourceCutoutRgbaSha256": rgba_sha256(cutout),
            "generatedSize": list(variant.size),
            "generatedRgbaSha256": rgba_sha256(variant),
            "effectiveOpaquePixels": round(
                builder.effective_opaque_pixels(variant), 4
            ),
            "clientMedianEnvelope": list(WORLD_ENVELOPES[direction]),
            "clientMedianOpaquePixels": round(
                float(baseline["directionRuntimeOpaquePixels"][direction]), 4
            ),
            "resizeFilter": "premultiplied_alpha_lanczos_high_res_single_pass",
            "singlePassDownsampleFromApprovedSource": True,
            "runtimeScale": 1,
            "facePolicy": FACE_POLICY[direction],
            "hairPolicy": "keep",
        }
    actions = {
        action: builder.build_generated_action(
            recipe,
            variants,
            records,
            anchors,
            hair_library,
            action,
        )
        for action in ACTION_SPECS
    }
    identity = {
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "sex": "male",
        "concept": resource_path(WORLD_SOURCE),
        "conceptFileSha256": file_sha256(WORLD_SOURCE),
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
        "approvedSourceExpectedSha256": APPROVED_SHA256,
        "sourceGrid": [4, 2],
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": list(range(8)),
        "directionAcceptance": build_acceptance(wearable),
        "directionCutouts": records,
        "faceAperturePolicy": FACE_POLICY,
        "faceApertureShape": {
            direction: ("polygon_dark_only" if direction in FACE_WINDOWS else "none")
            for direction in DIRECTIONS
        },
        "faceAperturePixelPolicy": (
            "clear only dark source pixels inside conservative front/side "
            "opening polygons; preserve all gold trim and jewels"
        ),
        "hairPolicy": "keep",
        "worldSizingPolicy": "primary_client_direction_envelope_fit_v1",
        "worldDirectionEnvelopes": {
            key: list(value) for key, value in WORLD_ENVELOPES.items()
        },
        "sourceBakePolicy": "approved_high_res_single_pass",
        "offlineDownsampleFilter": "premultiplied_alpha_lanczos",
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "integerPlacementCompatible": True,
        "stateItemPixelsUsed": False,
        "hairPixelsUsed": False,
        "actions": actions,
    }
    return identity, builder.appearance_for_identity(identity)


def build_paper_and_icons(
    opaque: dict[str, Image.Image],
    wearable: dict[str, Image.Image],
) -> tuple[dict, dict, dict]:
    paper = fit_on_canvas(wearable["S"], PAPER_CANVAS, PAPER_ENVELOPE)
    erase = Image.new("RGBA", PAPER_CANVAS, (255, 255, 255, 0))
    erase.putalpha(paper.getchannel("A").point(lambda alpha: 255 if alpha else 0))
    HEAD_PATCH.parent.mkdir(parents=True, exist_ok=True)
    paper.save(HEAD_PATCH, format="PNG", optimize=False)
    erase.save(HEAD_ERASE_MASK, format="PNG", optimize=False)

    inventory = fit_on_canvas(opaque["S"], (36, 35), (32, 33))
    ground = fit_on_canvas(opaque["S"], (16, 17), (15, 16))
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    inventory.save(INVENTORY_ICON, format="PNG", optimize=False)
    ground.save(GROUND_ICON, format="PNG", optimize=False)

    common_evidence = {
        "method": "user_supplied_source_S_direction_single_pass_v1",
        "approvedSourcePath": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
    }
    paper_record = {
        "contractId": "equipment.paper_doll.classic_flattened_head_patch.v1",
        "itemId": ITEM_ID,
        "itemName": ITEM_NAME,
        "slot": "头盔",
        "source": "user_approved_project_redesign",
        "sourceIndex": SOURCE_INDEX,
        "sourceRecordPath": resource_path(APPROVED_SOURCE),
        "sourceRecordRgbaSha256": APPROVED_SHA256,
        "sourceDirection": "S",
        "path": resource_path(HEAD_PATCH),
        "eraseMaskPath": resource_path(HEAD_ERASE_MASK),
        "drawOffset": [73, 27],
        "size": list(PAPER_CANVAS),
        "rgbaSha256": rgba_sha256(paper),
        "eraseMaskRgbaSha256": rgba_sha256(erase),
        "drawOrder": ["male_head_anatomy", "male_hair", "helmet"],
        "faceWindowPolicy": "open_source_face_aperture",
        "eraseMaskPolicy": "clear_helmet_silhouette_but_preserve_face_window",
        "facePixelsBaked": False,
        "hairPixelsBaked": False,
        "subjectEvidence": common_evidence,
        "headOnlyEvidence": {
            "bottomLeftAlpha": paper.getpixel((0, paper.height - 1))[3],
            "bottomRightAlpha": paper.getpixel((paper.width - 1, paper.height - 1))[3],
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
        "faceAperture": "opaque_dark_interior_for_item_icon",
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
        "faceAperture": "opaque_dark_interior_for_item_icon",
        "fileSha256": file_sha256(GROUND_ICON),
        "rgbaSha256": rgba_sha256(ground),
    }
    return paper_record, inventory_record, ground_record


def replace_named_object(
    path: Path,
    marker: str,
    replacement: dict,
    *,
    start_marker: str = "",
) -> None:
    text = path.read_text(encoding="utf-8")
    search_from = text.find(start_marker) if start_marker else 0
    marker_at = text.find(marker, search_from)
    if marker_at < 0:
        raise ValueError(f"marker {marker!r} missing from {path}")
    object_start = text.rfind("{", 0, marker_at)
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
        raise ValueError(f"unterminated target object in {path}")
    indent = len(text[text.rfind("\n", 0, object_start) + 1 : object_start])
    serialized = json.dumps(replacement, ensure_ascii=False, indent=2)
    serialized = "\n".join(
        (" " * indent + line if line else line)
        for line in serialized.splitlines()
    ).lstrip()
    path.write_text(text[:object_start] + serialized + text[object_end:], encoding="utf-8")


def update_recipe() -> None:
    replacement = {
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "concept": resource_path(WORLD_SOURCE),
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
        "approvedSourceExternalEvidence": str(approved_external()),
        "approvedSourceGrid": [4, 2],
        "sourceGrid": [4, 2],
        "directionClassificationStatus": "accepted_manual_visual_classification",
        "directionClassificationEvidence": (
            "user supplied the exact canonical sheet; top N,NE,E,SE and "
            "bottom S,SW,W,NW"
        ),
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": list(range(8)),
        "outputPrefix": resource_path(WORLD_PREFIX),
        "mattePolicy": "generated_magenta_remove_v1",
        "faceAperturePolicy": FACE_POLICY,
        "faceApertureShape": {
            direction: ("polygon_dark_only" if direction in FACE_WINDOWS else "none")
            for direction in DIRECTIONS
        },
        "paperDollSourceDirection": "S",
        "paperDollFaceWindow": "open_source_face_aperture",
        "paperDollEraseMask": "clear_helmet_silhouette_preserve_face",
        "inventorySourceDirection": "S",
        "inventoryFaceWindow": "opaque_dark_interior",
        "groundSourceDirection": "S",
        "groundFaceWindow": "opaque_dark_interior",
        "worldSizingPolicy": "primary_client_direction_envelope_fit_v1",
        "worldDirectionEnvelopes": {
            key: list(value) for key, value in WORLD_ENVELOPES.items()
        },
        "paperDollCanvasSize": list(PAPER_CANVAS),
        "paperDollContentEnvelope": list(PAPER_ENVELOPE),
        "singlePassDownsampleFromApprovedSource": True,
        "offlineDownsampleFilter": "premultiplied_alpha_lanczos",
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "userOverrideAuthorization": "direct use of user-supplied replacement sheet",
    }
    replace_named_object(
        RECIPE_PATH,
        f'"identityId": "{IDENTITY_ID}"',
        replacement,
        start_marker='"identities": [',
    )


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
    item = world["itemsById"][str(ITEM_ID)]
    item["maleAppearance"] = deepcopy(appearance)
    item["status"] = "user_approved_project_redesign"
    item["identityEvidence"] = {
        "library": "user-supplied approved project source",
        "sourceIndex": SOURCE_INDEX,
        "usage": "explicit item-240 visual override; no StateItem runtime pixels",
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
        "size": list(PAPER_CANVAS),
        "drawOffset": [73, 27],
        "confidence": "user_approved_exact_design",
        "sourceDirection": "S",
        "faceAperture": "open_source_face_aperture",
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
        "size": list(PAPER_CANVAS),
        "source": "approved item-240 S-direction",
        "mappingConfidence": "user_approved_exact",
        "faceWindow": "open_source_face_aperture",
    }
    item["worldWear"] = {
        "status": "user_approved_project_redesign",
        "contractId": "equipment.world_helmet.male.extension.v1",
        "identityId": IDENTITY_ID,
        "sourceIndex": SOURCE_INDEX,
        "helmetAppearance": deepcopy(appearance),
        "reason": (
            "user supplied exact canonical eight-direction source; "
            "front and side face openings expose the original player face"
        ),
    }
    write_json(VISUAL_CATALOG, catalog)

    head = load_json(HEAD_PATCH_CONTRACT)
    head["itemsById"][str(ITEM_ID)] = {
        "itemId": ITEM_ID,
        "itemName": ITEM_NAME,
        "flattenedHeadPatch": paper_record,
    }
    head["runtimeMappings"][ITEM_NAME] = deepcopy(paper_record)
    write_json(HEAD_PATCH_CONTRACT, head)


def update_v2(identity: dict) -> None:
    data = load_json(HELMET_V2_CONTRACT)
    asset = data["visualAssets"][IDENTITY_ID]
    asset["source"]["lane"] = "helmet_world_visuals"
    asset["source"]["tier"] = "primary"
    asset["source"]["distribution"] = "user.supplied"
    asset["source"]["manifest"] = resource_path(WORLD_CONTRACT)
    asset["source"]["sourceSlotDirectionOrder"] = DIRECTIONS
    asset["source"]["approvedSource"] = resource_path(APPROVED_SOURCE)
    asset["source"]["approvedSourceFileSha256"] = APPROVED_SHA256
    asset["source"]["pixelPolicy"] = "user_approved_exact_runtime_atlas"
    for action, record in asset["source"]["actions"].items():
        record["sha256"] = identity["actions"][action]["fileSha256"]
    asset["source_direction_map"] = {
        direction: index for index, direction in enumerate(DIRECTIONS)
    }
    for index, direction in enumerate(DIRECTIONS):
        record = asset["directions"][direction]
        record["source_direction"] = direction
        record["source_row"] = index
        record["source_slot_id"] = f"slot_{index}"
        record["face_policy"] = FACE_POLICY[direction]
        record["hair_policy"] = "keep"
        record["openingVisibility"] = OPENING_VISIBILITY[direction]
        record["runtime_scale"] = [1, 1]
        record["flip_h"] = False
        for action in ACTION_SPECS:
            frames = [
                frame
                for frame in identity["actions"][action]["frames"]
                if frame["direction"] == direction
            ]
            pivots = [
                [round(value) for value in frame["helmetAnchorCentroid"]]
                for frame in frames
            ]
            if len(pivots) != ACTION_SPECS[action]["frames"]:
                raise AssertionError(f"{direction}/{action} pivot count changed")
            record["pivotByActionFrame"][action] = pivots
        record["pivot"] = record["pivotByActionFrame"]["idle"][0]
    replace_named_object(
        HELMET_V2_CONTRACT,
        f'"visual_asset_id": "{IDENTITY_ID}"',
        asset,
        start_marker='"visualAssets": {',
    )


def semantic_non_target_snapshot() -> dict:
    recipes = load_json(RECIPE_PATH)
    world = load_json(WORLD_CONTRACT)
    catalog = load_json(VISUAL_CATALOG)
    head = load_json(HEAD_PATCH_CONTRACT)
    v2 = load_json(HELMET_V2_CONTRACT)
    return {
        "recipeItems": [x for x in recipes["items"] if int(x["itemId"]) != ITEM_ID],
        "recipeIdentities": [
            x for x in recipes["identities"] if x["identityId"] != IDENTITY_ID
        ],
        "worldIdentities": {
            key: value
            for key, value in world["visualIdentities"].items()
            if key != IDENTITY_ID
        },
        "worldItems": {
            key: value for key, value in world["itemsById"].items() if key != str(ITEM_ID)
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
            if key != ITEM_NAME
        },
        "v2Assets": {
            key: value
            for key, value in v2["visualAssets"].items()
            if key != IDENTITY_ID
        },
        "v2ItemRefs": {
            key: value
            for key, value in v2["itemVisualAssetRefs"].items()
            if key != str(ITEM_ID)
        },
    }


def non_target_file_hashes() -> dict[str, str]:
    roots = [
        ROOT / "assets/art/items/client/world_wear/helmet/male",
        ROOT / "assets/art/items/client/paper_doll/classic_flattened_head",
        ROOT / "assets/art/items/client/project_redesign/helmet",
        ROOT / "assets/generated/helmet_v2",
    ]
    result: dict[str, str] = {}
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if IDENTITY_ID in relative or "item_00240_" in relative:
                continue
            result[relative] = file_sha256(path)
    return result


def build_previews(
    opaque: dict[str, Image.Image],
    wearable: dict[str, Image.Image],
) -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1024, 600), (35, 37, 41, 255))
    draw = ImageDraw.Draw(canvas)
    for index, direction in enumerate(DIRECTIONS):
        preview = fit_on_canvas(wearable[direction], (224, 240), (210, 228))
        x = (index % 4) * 256 + 16
        y = (index // 4) * 300 + 16
        canvas.alpha_composite(preview, (x, y))
        draw.text(
            (x + 4, y + 250),
            f"{direction} / {FACE_POLICY[direction]}",
            fill=(245, 220, 140, 255),
        )
    canvas.save(SOURCE_PREVIEW, format="PNG", optimize=False)

    paper = Image.open(HEAD_PATCH).convert("RGBA")
    inventory = Image.open(INVENTORY_ICON).convert("RGBA")
    ground = Image.open(GROUND_ICON).convert("RGBA")
    presentation = Image.new("RGBA", (768, 320), (36, 38, 42, 255))
    draw = ImageDraw.Draw(presentation)
    panels = [
        ("paper doll / open face", paper, 7),
        ("inventory / dark interior", inventory, 6),
        ("ground / dark interior", ground, 11),
    ]
    for index, (label, source, scale) in enumerate(panels):
        left = index * 256
        draw.rectangle(
            (left + 8, 8, left + 248, 312),
            fill=(57, 60, 66, 255),
            outline=(180, 180, 180, 255),
        )
        if index == 0:
            draw.ellipse(
                (left + 91, 76, left + 165, 202),
                fill=(222, 172, 124, 255),
            )
        enlarged = source.resize(
            (source.width * scale, source.height * scale),
            Image.Resampling.NEAREST,
        )
        presentation.alpha_composite(
            enlarged,
            (left + (256 - enlarged.width) // 2, 32 + (236 - enlarged.height) // 2),
        )
        draw.text((left + 14, 284), label, fill=(245, 220, 140, 255))
    presentation.save(PRESENTATION_PREVIEW, format="PNG", optimize=False)


def validate() -> dict:
    if file_sha256(APPROVED_SOURCE) != APPROVED_SHA256:
        raise AssertionError("approved source is not byte-exact")
    source = Image.open(WORLD_SOURCE).convert("RGBA")
    if source.size != SOURCE_SIZE:
        raise AssertionError("processed source size changed")
    signatures = []
    for slot, direction in enumerate(DIRECTIONS):
        cutout = crop_slot(source, slot)
        if cutout.getchannel("A").getbbox() is None:
            raise AssertionError(f"{direction} source slot is empty")
        signatures.append(rgba_sha256(cutout))
    if len(set(signatures)) != 8:
        raise AssertionError("source directions are not unique")
    if any(
        red >= 245 and blue >= 245 and green <= 20 and alpha > 0
        for red, green, blue, alpha in source.get_flattened_data()
    ):
        raise AssertionError("processed source retained pure magenta")

    world = load_json(WORLD_CONTRACT)
    identity = world["visualIdentities"][IDENTITY_ID]
    sizes = {
        direction: identity["directionCutouts"][direction]["generatedSize"]
        for direction in DIRECTIONS
    }
    for direction, size in sizes.items():
        envelope = WORLD_ENVELOPES[direction]
        if size[0] > envelope[0] or size[1] > envelope[1]:
            raise AssertionError(f"{direction} exceeds formal world envelope")
    for action, spec in ACTION_SPECS.items():
        record = identity["actions"][action]
        atlas_path = ROOT / record["path"].removeprefix("res://")
        atlas = Image.open(atlas_path).convert("RGBA")
        if atlas.size != (CELL[0] * spec["frames"], CELL[1] * 8):
            raise AssertionError(f"{action} atlas resolution changed")
        if file_sha256(atlas_path) != record["fileSha256"]:
            raise AssertionError(f"{action} atlas hash mismatch")

    paper = Image.open(HEAD_PATCH).convert("RGBA")
    inventory = Image.open(INVENTORY_ICON).convert("RGBA")
    ground = Image.open(GROUND_ICON).convert("RGBA")
    paper_box = paper.getchannel("A").getbbox()
    if paper_box is None:
        raise AssertionError("paper doll is empty")
    paper_size = [paper_box[2] - paper_box[0], paper_box[3] - paper_box[1]]
    if paper_size[0] > PAPER_ENVELOPE[0] or paper_size[1] > PAPER_ENVELOPE[1]:
        raise AssertionError("paper doll exceeds formal envelope")
    if paper.getpixel((16, 25))[3] != 0:
        raise AssertionError("paper-doll face opening is not transparent")
    if inventory.getchannel("A").getbbox() is None or ground.getchannel("A").getbbox() is None:
        raise AssertionError("inventory or ground icon is empty")

    v2 = load_json(HELMET_V2_CONTRACT)["visualAssets"][IDENTITY_ID]
    expected_map = {direction: index for index, direction in enumerate(DIRECTIONS)}
    if v2["source_direction_map"] != expected_map:
        raise AssertionError("v2 canonical source mapping changed")
    for action in ACTION_SPECS:
        if v2["source"]["actions"][action]["sha256"] != identity["actions"][action]["fileSha256"]:
            raise AssertionError(f"v2 {action} hash is stale")
    return {
        "contractId": "equipment.world_helmet.heavenly_taoist_240.redesign.v1",
        "itemId": ITEM_ID,
        "identityId": IDENTITY_ID,
        "approvedSource": resource_path(APPROVED_SOURCE),
        "approvedSourceFileSha256": APPROVED_SHA256,
        "processedSource": resource_path(WORLD_SOURCE),
        "processedSourceFileSha256": file_sha256(WORLD_SOURCE),
        "sourceSlotDirectionOrder": DIRECTIONS,
        "canonicalRowSourceSlots": list(range(8)),
        "uniqueDirectionRgbaSha256": signatures,
        "faceAperturePolicy": FACE_POLICY,
        "worldDirectionEnvelopes": {
            key: list(value) for key, value in WORLD_ENVELOPES.items()
        },
        "worldGeneratedSizes": sizes,
        "atlasCellResolutionPreserved": list(CELL),
        "paperDollCanvas": list(PAPER_CANVAS),
        "paperDollContentEnvelope": list(PAPER_ENVELOPE),
        "paperDollContentSize": paper_size,
        "paperDollFaceWindowTransparent": True,
        "inventoryIconSize": list(inventory.size),
        "groundIconSize": list(ground.size),
        "singlePassDownsampleFromApprovedSource": True,
        "runtimeScale": 1,
        "textureFilter": "nearest",
        "sourcePreview": resource_path(SOURCE_PREVIEW),
        "paperInventoryGroundPreview": resource_path(PRESENTATION_PREVIEW),
    }


def build() -> dict:
    semantic_before = semantic_non_target_snapshot()
    files_before = non_target_file_hashes()
    opaque, wearable = build_sources()
    update_recipe()
    identity, appearance = build_world(wearable)
    paper, inventory, ground = build_paper_and_icons(opaque, wearable)
    update_contracts(identity, appearance, paper, inventory, ground)
    update_v2(identity)
    build_previews(opaque, wearable)
    if semantic_non_target_snapshot() != semantic_before:
        raise AssertionError("single-target build changed non-240 contract data")
    files_after = non_target_file_hashes()
    if files_after != files_before:
        changed = sorted(
            path
            for path in set(files_before) | set(files_after)
            if files_before.get(path) != files_after.get(path)
        )
        raise AssertionError(
            "single-target build changed frozen non-240 files: " + ", ".join(changed)
        )
    report = validate()
    report["frozenNon240FileCount"] = len(files_before)
    report["frozenNon240FilesUnchanged"] = True
    report["non240ContractDataUnchanged"] = True
    report["singleTargetBuild"] = {
        "acceptedIdentity": IDENTITY_ID,
        "acceptedItemId": ITEM_ID,
        "otherIdentitiesRejected": True,
    }
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
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
        raise SystemExit(f"single-target builder accepts only {IDENTITY_ID!r}")
    if args.item_id is not None and args.item_id != ITEM_ID:
        raise SystemExit(f"single-target builder accepts only item {ITEM_ID}")
    report = validate() if args.validate_only else build()
    print(
        "HEAVENLY_TAOIST_HELMET_240_PASS "
        f"item={report['itemId']} identity={report['identityId']} "
        "directions=8 world_paper_inventory_ground=true non240_unchanged=true"
    )


if __name__ == "__main__":
    main()
