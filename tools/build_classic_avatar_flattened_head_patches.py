#!/usr/bin/env python3
"""Build original-client flattened male head patches for classic avatars.

The player UI must not paint complete StateItem rectangles because those
records contain restoration pixels from the opaque equipment page.  Instead
this builder reproduces the original draw order on a transparent male head:

    Prguse #376 male anatomy -> Prguse #442 hair -> StateItem helmet

It then exports only the finished head/helmet region plus an erase mask.  The
result contains the original face, hair and complete helmet silhouette, but
never the equipment-page background, slots, naked chest, or shoulders.
"""

from __future__ import annotations

import hashlib
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PRIMARY_ROOT = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
PRGUSE = PRIMARY_ROOT / "Prguse.wil"
STATE_ITEM = PRIMARY_ROOT / "StateItem.wil"
SOURCE_POLICY = ROOT / "assets/data/source_priority_policy.json"
ORIGINAL_STAGE = (
    ROOT / "assets/data/equipment_original_client_paper_doll_stage.json"
)
ANATOMY = (
    ROOT
    / "assets/art/characters/warrior/paper_doll/classic"
    / "base_male_00376_anatomy.png"
)
HAIR = (
    ROOT
    / "assets/art/characters/warrior/paper_doll/classic"
    / "hair_male_00442.png"
)
LEGACY_SUBJECT_DIR = (
    ROOT / "assets/art/characters/warrior/paper_doll/classic/layers"
)
OUTPUT_DIR = (
    ROOT / "assets/art/items/client/paper_doll/classic_flattened_head"
)
OUTPUT_MANIFEST = (
    ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
)

CONTRACT_ID = "equipment.paper_doll.classic_flattened_head_patch.v1"
ITEM_IDS = (146, 147, 148, 149, 150, 151, 218, 224, 228, 232, 236, 240)
# Black Iron is the only record whose complete dark silhouette shares enough
# exact page-palette values to be damaged by the generic primary difference.
SUBJECT_MASK_RECORDS = {344}
BASE_STAGE_POSITION = (38, 52)
HAIR_STAGE_POSITION = (80, 44)
HEAD_BOX = (76, 40, 98, 68)
SHOULDER_START_Y = 65
NECK_X_RANGE = (80, 92)

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def resource_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def primary_distribution(policy: dict) -> dict:
    primary = policy["lanes"]["client_assets"]["sources"][0]
    if (
        primary.get("tier") != "primary"
        or primary.get("distribution") != "client.classic_raw_complete"
    ):
        raise ValueError("client_assets primary distribution changed")
    return primary


def page_background_palette(
    base: Image.Image, anatomy: Image.Image
) -> set[tuple[int, int, int, int]]:
    return {
        base.getpixel((x, y))
        for y in range(base.height)
        for x in range(base.width)
        if anatomy.getpixel((x, y))[3] == 0
    }


def connected_exact_background_subject(
    source: Image.Image,
    base: Image.Image,
    background_palette: set[tuple[int, int, int, int]],
    position: tuple[int, int],
) -> tuple[Image.Image, dict]:
    """Remove certified page background while preserving source RGB."""
    source = source.convert("RGBA")
    exact: set[tuple[int, int]] = set()
    candidates: set[tuple[int, int]] = set()
    for y in range(source.height):
        for x in range(source.width):
            pixel = source.getpixel((x, y))
            if pixel[3] == 0:
                continue
            base_x = position[0] + x
            base_y = position[1] + y
            if (
                0 <= base_x < base.width
                and 0 <= base_y < base.height
                and pixel == base.getpixel((base_x, base_y))
            ):
                exact.add((x, y))
            if pixel in background_palette:
                candidates.add((x, y))
    removed = set(exact)
    queue = deque(exact)
    while queue:
        x, y = queue.popleft()
        for offset_y in (-1, 0, 1):
            for offset_x in (-1, 0, 1):
                neighbour = (x + offset_x, y + offset_y)
                if neighbour in candidates and neighbour not in removed:
                    removed.add(neighbour)
                    queue.append(neighbour)
    output = source.copy()
    for x, y in removed:
        red, green, blue, _alpha = output.getpixel((x, y))
        output.putpixel((x, y), (red, green, blue, 0))
    foreground = sum(pixel[3] > 0 for pixel in output.getdata())
    if foreground <= 0:
        raise ValueError("helmet subject extraction removed all foreground")
    return output, {
        "method": "primary_exact_palette_connected_difference.v1",
        "exactCoordinateSeedPixels": len(exact),
        "paletteCandidatePixels": len(candidates),
        "removedBackgroundPixels": len(removed),
        "subjectOpaquePixels": foreground,
    }


def verified_subject_mask(
    source: Image.Image,
    source_index: int,
    base: Image.Image,
    background_palette: set[tuple[int, int, int, int]],
    position: tuple[int, int],
) -> tuple[Image.Image, dict]:
    if source_index not in SUBJECT_MASK_RECORDS:
        return connected_exact_background_subject(
            source, base, background_palette, position
        )
    mask_path = LEGACY_SUBJECT_DIR / f"stateitem_{source_index:05d}.png"
    mask = Image.open(mask_path).convert("RGBA")
    if mask.size != source.size:
        raise ValueError(f"StateItem {source_index} subject-mask size mismatch")
    kept: set[tuple[int, int]] = set()
    output = source.copy()
    removed = 0
    for y in range(source.height):
        for x in range(source.width):
            before = source.getpixel((x, y))
            if mask.getpixel((x, y))[3] > 0:
                if mask.getpixel((x, y)) != before:
                    raise ValueError(
                        f"StateItem {source_index} subject mask rewrote pixels"
                    )
                kept.add((x, y))
                continue
            if before[3] > 0:
                removed += 1
            output.putpixel((x, y), (*before[:3], 0))
    remaining = set(kept)
    components = 0
    while remaining:
        components += 1
        queue = deque([remaining.pop()])
        while queue:
            x, y = queue.popleft()
            for offset_y in (-1, 0, 1):
                for offset_x in (-1, 0, 1):
                    neighbour = (x + offset_x, y + offset_y)
                    if neighbour in remaining:
                        remaining.remove(neighbour)
                        queue.append(neighbour)
    if components != 1:
        raise ValueError(
            f"StateItem {source_index} subject mask is not one component"
        )
    return output, {
        "method": "primary_stateitem_complete_subject_protection.v1",
        "subjectMaskPath": resource_path(mask_path),
        "subjectMaskFileSha256": file_sha256(mask_path),
        "subjectComponents": components,
        "removedBackgroundPixels": removed,
        "subjectOpaquePixels": len(kept),
    }


def male_head_anatomy(anatomy: Image.Image) -> Image.Image:
    output = anatomy.copy()
    for y in range(output.height):
        for x in range(output.width):
            keep = (
                HEAD_BOX[0] <= x < HEAD_BOX[2]
                and HEAD_BOX[1] <= y < HEAD_BOX[3]
            )
            if y >= SHOULDER_START_Y:
                keep = keep and NECK_X_RANGE[0] <= x <= NECK_X_RANGE[1]
            if not keep:
                red, green, blue, _alpha = output.getpixel((x, y))
                output.putpixel((x, y), (red, green, blue, 0))
    return output


def union_box(
    position: tuple[int, int], size: tuple[int, int]
) -> tuple[int, int, int, int]:
    return (
        min(HEAD_BOX[0], position[0]),
        min(HEAD_BOX[1], position[1]),
        max(HEAD_BOX[2], position[0] + size[0]),
        max(HEAD_BOX[3], position[1] + size[1]),
    )


def erase_mask(patch: Image.Image) -> Image.Image:
    output = Image.new("RGBA", patch.size)
    for y in range(patch.height):
        for x in range(patch.width):
            if patch.getpixel((x, y))[3] > 0:
                output.putpixel((x, y), (255, 255, 255, 255))
    return output


def main() -> None:
    policy = load_json(SOURCE_POLICY)
    primary = primary_distribution(policy)
    original = load_json(ORIGINAL_STAGE)
    if original.get("contractId") != "equipment.paper_doll.original_client_stage.v1":
        raise ValueError("original paper-doll stage contract changed")

    prguse_data, prguse_palette, prguse_offsets, _ = read_library(PRGUSE)
    state_data, state_palette, state_offsets, _ = read_library(STATE_ITEM)
    base, base_meta = decode_sprite(
        prguse_data, prguse_offsets[376], prguse_palette
    )
    base = base.convert("RGBA")
    decoded_hair, hair_meta = decode_sprite(
        prguse_data, prguse_offsets[442], prguse_palette
    )
    decoded_hair = decoded_hair.convert("RGBA")
    anatomy = Image.open(ANATOMY).convert("RGBA")
    hair = Image.open(HAIR).convert("RGBA")
    if rgba_sha256(decoded_hair) != rgba_sha256(hair):
        raise ValueError("Prguse #442 hair differs from primary")
    head_anatomy = male_head_anatomy(anatomy)
    background_palette = page_background_palette(base, anatomy)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    items: dict[str, dict] = {}
    runtime_mappings: dict[str, dict] = {}
    visual_hashes: dict[int, str] = {}
    for item_id in ITEM_IDS:
        item = original["itemsById"][str(item_id)]
        record = item["originalClientPaperDoll"]
        source_index = int(record["sourceIndex"])
        source, metadata = decode_sprite(
            state_data, state_offsets[source_index], state_palette
        )
        source = source.convert("RGBA")
        if rgba_sha256(source) != record["rgbaSha256"]:
            raise ValueError(f"StateItem {source_index} primary hash mismatch")
        if [int(metadata["x"]), int(metadata["y"])] != [
            int(record["hotX"]),
            int(record["hotY"]),
        ]:
            raise ValueError(f"StateItem {source_index} coordinate mismatch")
        position = (
            int(record["stagePosition"][0]) - BASE_STAGE_POSITION[0],
            int(record["stagePosition"][1]) - BASE_STAGE_POSITION[1],
        )
        subject, subject_evidence = verified_subject_mask(
            source, source_index, base, background_palette, position
        )

        composition = Image.new("RGBA", base.size)
        composition.alpha_composite(head_anatomy)
        composition.alpha_composite(hair, HAIR_STAGE_POSITION)
        composition.alpha_composite(subject, position)
        crop_box = union_box(position, source.size)
        patch = composition.crop(crop_box)
        mask = erase_mask(patch)
        if patch.getbbox() is None:
            raise ValueError(f"item {item_id} flattened head patch is empty")
        if patch.getpixel((0, patch.height - 1))[3] != 0:
            raise ValueError(f"item {item_id} retained bottom-left shoulder")
        if patch.getpixel((patch.width - 1, patch.height - 1))[3] != 0:
            raise ValueError(f"item {item_id} retained bottom-right shoulder")

        patch_path = OUTPUT_DIR / f"item_{item_id:05d}_head.png"
        mask_path = OUTPUT_DIR / f"item_{item_id:05d}_erase_mask.png"
        patch.save(patch_path)
        mask.save(mask_path)
        visual_hashes.setdefault(source_index, rgba_sha256(patch))
        flattened = {
            "contractId": CONTRACT_ID,
            "itemId": item_id,
            "itemName": item["itemName"],
            "slot": "头盔",
            "source": "StateItem.wil",
            "sourceIndex": source_index,
            "sourceRecordPath": record["path"],
            "sourceRecordRgbaSha256": record["rgbaSha256"],
            "path": resource_path(patch_path),
            "eraseMaskPath": resource_path(mask_path),
            "drawOffset": [crop_box[0], crop_box[1]],
            "size": list(patch.size),
            "rgbaSha256": rgba_sha256(patch),
            "eraseMaskRgbaSha256": rgba_sha256(mask),
            "drawOrder": ["male_head_anatomy", "male_hair", "helmet"],
            "subjectEvidence": subject_evidence,
            "headOnlyEvidence": {
                "headBox": list(HEAD_BOX),
                "shoulderStartY": SHOULDER_START_Y,
                "neckXRange": list(NECK_X_RANGE),
                "bottomLeftAlpha": patch.getpixel(
                    (0, patch.height - 1)
                )[3],
                "bottomRightAlpha": patch.getpixel(
                    (patch.width - 1, patch.height - 1)
                )[3],
            },
        }
        items[str(item_id)] = {
            "itemId": item_id,
            "itemName": item["itemName"],
            "flattenedHeadPatch": flattened,
        }
        runtime_mappings[item["itemName"]] = flattened

    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "sex": "male",
        "presentationMode": "classic_avatar",
        "sourcePolicy": {
            "lane": "client_assets",
            "tier": "primary",
            "distribution": primary["distribution"],
            "rootPrefix": primary["rootPrefix"],
            "fallbackUsed": False,
            "aiGeneratedAssets": 0,
            "prgusePath": str(PRGUSE.relative_to(ROOT)).replace("\\", "/"),
            "prguseFileSha256": file_sha256(PRGUSE),
            "stateItemPath": str(STATE_ITEM.relative_to(ROOT)).replace("\\", "/"),
            "stateItemFileSha256": file_sha256(STATE_ITEM),
            "anatomyPath": resource_path(ANATOMY),
            "anatomyFileSha256": file_sha256(ANATOMY),
            "hairPath": resource_path(HAIR),
            "hairFileSha256": file_sha256(HAIR),
            "baseSourceIndex": 376,
            "baseRgbaSha256": rgba_sha256(base),
            "baseHotX": int(base_meta["x"]),
            "baseHotY": int(base_meta["y"]),
            "hairSourceIndex": 442,
            "hairRgbaSha256": rgba_sha256(decoded_hair),
            "hairHotX": int(hair_meta["x"]),
            "hairHotY": int(hair_meta["y"]),
        },
        "compositionPolicy": {
            "id": "original_client_final_head_only.v1",
            "drawOrder": [
                "Prguse#376 male head anatomy",
                "Prguse#442 male hair",
                "StateItem helmet",
            ],
            "headBox": list(HEAD_BOX),
            "shoulderStartY": SHOULDER_START_Y,
            "neckXRange": list(NECK_X_RANGE),
            "cropRule": "union(primary StateItem rectangle, male head box)",
            "bottomCornerAlphaRequired": 0,
            "fullEquipmentPageForbidden": True,
            "redrawAllowed": False,
            "auxiliarySourceAllowed": False,
        },
        "coverage": {
            "formalMaleHelmetItems": len(items),
            "uniqueStateItemRecords": len(visual_hashes),
            "itemIds": list(ITEM_IDS),
            "officialTestHelmetItemIds": [148, 149, 150, 151, 232, 236, 240],
            "femaleAssetsGenerated": 0,
        },
        "itemsById": items,
        "runtimeMappings": runtime_mappings,
    }
    OUTPUT_MANIFEST.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "CLASSIC_AVATAR_FLATTENED_HEAD_PATCHES_BUILD_PASS "
        f"items={len(items)} records={len(visual_hashes)} fallback=false ai=0"
    )


if __name__ == "__main__":
    main()
