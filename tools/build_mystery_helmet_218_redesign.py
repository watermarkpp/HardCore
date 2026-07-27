#!/usr/bin/env python3
"""Build the user-authorized item 218 non-world visual family.

The generated chroma-key sources are the sole design authority for this
exception. Other equipment records and assets are never rewritten.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = (
    ROOT
    / "assets/art/items/client/source/user_authorized_redesign"
    / "mystery_helmet_218"
)
INVENTORY_PATH = ROOT / "assets/art/items/client/inventory/111.png"
EQUIPPED_PATH = ROOT / "assets/art/items/client/equipped/111.png"
GROUND_PATH = ROOT / "assets/art/items/client/ground/111.png"
HEAD_PATH = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00218_head.png"
)
MASK_PATH = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00218_erase_mask.png"
)
HEAD_MANIFEST = ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"

ITEM_ID = "218"
ITEM_NAME = "神秘头盔"
SOURCE_INDEX = 111
HEAD_CENTER_X = 86
HEAD_TOP_Y = 21


def rgba_sha(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def chroma_cutout(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, _opacity = pixels[x, y]
            chroma_distance = max(
                abs(red - 0),
                abs(green - 255),
                abs(blue - 0),
            )
            if chroma_distance <= 16:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            opacity = 255
            if chroma_distance < 96:
                opacity = round(255 * (chroma_distance - 16) / 80)
            non_green = max(red, blue)
            green = min(green, non_green + 8)
            if opacity <= 6:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (red, green, blue, opacity)
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError(f"empty chroma-key source: {path}")
    return image.crop(box)


def fit(source: Image.Image, maximum_size: tuple[int, int]) -> Image.Image:
    scale = min(
        maximum_size[0] / source.width,
        maximum_size[1] / source.height,
    )
    size = (
        max(1, round(source.width * scale)),
        max(1, round(source.height * scale)),
    )
    result = source.resize(size, Image.Resampling.LANCZOS)
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, opacity = pixels[x, y]
            if opacity <= 8:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (red, green, blue, opacity)
    return result


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def padded_canvas(
    source: Image.Image,
    size: tuple[int, int],
    position: tuple[int, int],
) -> Image.Image:
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    result.alpha_composite(source, position)
    return result


def build_assets() -> dict[str, Image.Image]:
    paper = chroma_cutout(SOURCE_DIR / "paper_doll_front_green.png")
    inventory = chroma_cutout(
        SOURCE_DIR / "inventory_three_quarter_green.png"
    )
    ground = chroma_cutout(SOURCE_DIR / "ground_drop_green.png")

    head_subject = fit(paper, (44, 44))
    head = padded_canvas(
        head_subject,
        (48, 48),
        (
            (48 - head_subject.width) // 2,
            1,
        ),
    )
    equipped = head.copy()
    inventory_icon = fit(inventory, (40, 40))
    ground_icon = fit(ground, (24, 18))
    erase_mask = Image.new("RGBA", head.size, (255, 255, 255, 0))
    erase_mask.putalpha(
        head.getchannel("A").point(lambda alpha: 255 if alpha > 0 else 0)
    )

    save(head, HEAD_PATH)
    save(erase_mask, MASK_PATH)
    save(equipped, EQUIPPED_PATH)
    save(inventory_icon, INVENTORY_PATH)
    save(ground_icon, GROUND_PATH)
    return {
        "head": head,
        "mask": erase_mask,
        "equipped": equipped,
        "inventory": inventory_icon,
        "ground": ground_icon,
    }


def update_head_manifest(images: dict[str, Image.Image]) -> None:
    manifest = json.loads(HEAD_MANIFEST.read_text(encoding="utf-8"))
    source_policy = manifest["sourcePolicy"]
    source_policy["aiGeneratedAssets"] = 1
    source_policy["userAuthorizedRedesignExceptions"] = {
        ITEM_ID: {
            "itemId": 218,
            "itemName": ITEM_NAME,
            "tier": "user_authorized_redesign",
            "originalClientAppearanceRequired": False,
            "sourceDirectory": (
                "res://assets/art/items/client/source/"
                "user_authorized_redesign/mystery_helmet_218"
            ),
        }
    }
    manifest["compositionPolicy"]["userAuthorizedRedrawExceptions"] = [
        218
    ]
    head = images["head"]
    mask = images["mask"]
    draw_offset = [
        HEAD_CENTER_X - head.width // 2,
        HEAD_TOP_Y,
    ]
    source_path = (
        "res://assets/art/items/client/source/user_authorized_redesign/"
        "mystery_helmet_218/paper_doll_front_green.png"
    )
    source_disk = SOURCE_DIR / "paper_doll_front_green.png"
    record = {
        "contractId": manifest["contractId"],
        "itemId": 218,
        "itemName": ITEM_NAME,
        "slot": "头盔",
        "source": "user_authorized_redesign",
        "sourceIndex": SOURCE_INDEX,
        "sourceRecordPath": source_path,
        "sourceRecordRgbaSha256": rgba_sha(
            Image.open(source_disk).convert("RGBA")
        ),
        "sourceFileSha256": file_sha(source_disk),
        "path": (
            "res://assets/art/items/client/paper_doll/"
            "classic_flattened_head/item_00218_head.png"
        ),
        "eraseMaskPath": (
            "res://assets/art/items/client/paper_doll/"
            "classic_flattened_head/item_00218_erase_mask.png"
        ),
        "drawOffset": draw_offset,
        "size": list(head.size),
        "rgbaSha256": rgba_sha(head),
        "eraseMaskRgbaSha256": rgba_sha(mask),
        "drawOrder": [
            "male_head_anatomy",
            "male_hair",
            "helmet",
        ],
        "subjectEvidence": {
            "method": "user_authorized_chroma_key_redesign.v1",
            "designIdentity": "mystery_japanese_kabuto_218",
            "subjectOpaquePixels": sum(
                1
                for opacity in head.getchannel("A").get_flattened_data()
                if opacity > 0
            ),
            "originalClientAppearanceRequired": False,
        },
        "headOnlyEvidence": {
            "headBox": [76, 40, 98, 68],
            "shoulderStartY": 65,
            "neckXRange": [80, 92],
            "bottomLeftAlpha": 0,
            "bottomRightAlpha": 0,
        },
    }
    manifest["itemsById"][ITEM_ID]["flattenedHeadPatch"] = record
    manifest["runtimeMappings"][ITEM_NAME] = record
    write_json(HEAD_MANIFEST, manifest)


def icon_record(
    path: str,
    image: Image.Image,
    source_name: str,
    source_path: Path,
) -> dict:
    return {
        "path": path,
        "library": "user_authorized_redesign",
        "index": SOURCE_INDEX,
        "size": list(image.size),
        "drawOffset": [0, 0],
        "confidence": "user_authorized_exact",
        "designIdentity": "mystery_japanese_kabuto_218",
        "sourcePath": (
            "res://"
            + source_path.relative_to(ROOT).as_posix()
        ),
        "sourceFileSha256": file_sha(source_path),
        "sourceRole": source_name,
    }


def update_visual_catalog(images: dict[str, Image.Image]) -> None:
    catalog = json.loads(VISUAL_CATALOG.read_text(encoding="utf-8"))
    item = catalog["itemsById"][ITEM_ID]
    inventory_source = SOURCE_DIR / "inventory_three_quarter_green.png"
    paper_source = SOURCE_DIR / "paper_doll_front_green.png"
    ground_source = SOURCE_DIR / "ground_drop_green.png"
    item["icons"] = {
        "inventory": icon_record(
            "res://assets/art/items/client/inventory/111.png",
            images["inventory"],
            "backpack_inventory",
            inventory_source,
        ),
        "equippedSlot": icon_record(
            "res://assets/art/items/client/equipped/111.png",
            images["equipped"],
            "paper_doll_equipped",
            paper_source,
        ),
        "ground": icon_record(
            "res://assets/art/items/client/ground/111.png",
            images["ground"],
            "ground_drop",
            ground_source,
        ),
    }
    item["paperDoll"] = {
        "status": "user_authorized_redesign",
        "slot": "头盔",
        "gender": "通用",
        "sourceIndex": SOURCE_INDEX,
        "path": "res://assets/art/items/client/equipped/111.png",
        "drawOffset": [
            HEAD_CENTER_X - images["equipped"].width // 2,
            HEAD_TOP_Y,
        ],
        "size": list(images["equipped"].size),
        "source": "user_authorized_redesign",
        "mappingConfidence": "user_authorized_exact",
        "designIdentity": "mystery_japanese_kabuto_218",
    }
    write_json(VISUAL_CATALOG, catalog)


def main() -> None:
    images = build_assets()
    update_head_manifest(images)
    update_visual_catalog(images)
    print(
        "BUILD_MYSTERY_HELMET_218_REDESIGN_PASS "
        f"inventory={images['inventory'].size} "
        f"paper={images['head'].size} "
        f"ground={images['ground'].size}"
    )


if __name__ == "__main__":
    main()
