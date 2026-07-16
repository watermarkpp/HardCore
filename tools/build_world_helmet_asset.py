#!/usr/bin/env python3
"""Build the mixed-source Black Iron Helmet world animation layer.

One complete client was scanned frame-by-frame and its paired runtime source
was audited.  The verified classic item exists as StateItem #344, but the 2013
runtime only draws Hair appearances and contains no matching worn Black Iron
Helmet layer.  StateItem #344 remains the verified equipment-window identity,
while all eight runtime directions come from the user's newly generated visual
family.  The source Hair animation is used only as a per-frame head-motion
anchor.  No Hair, unrelated Helmet, or old StateItem-derived world pixels are
copied into the generated result.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ICON = ROOT / "assets/art/characters/warrior/paper_doll/classic/layers/stateitem_00344.png"
REAR_DIRECTION_REFERENCE = ROOT / "dev_art_sources/reference/generated/black_iron_helmet/rear_n_ne_nw_transparent.png"
FRONT_SIDE_CONCEPT_REFERENCE = ROOT / "dev_art_sources/reference/generated/black_iron_helmet/front_side_direction_concept.png"
CANONICAL_DIRECTION_ROOT = ROOT / "dev_art_sources/reference/generated/black_iron_helmet/canonical_directions"
CANONICAL_DIRECTION_MANIFEST = CANONICAL_DIRECTION_ROOT / "manifest.json"
ANCHOR_SOURCE = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
SOURCE_CODE = ROOT / "dev_art_sources/reference/mir2opensource_2013_client/MirObjects/PlayerObject.cs"
FRAME_CODE = ROOT / "dev_art_sources/reference/mir2opensource_2013_client/MirObjects/Frames.cs"
COMPLETE_SCAN = ROOT / "outputs/resource_catalog/complete_client_frame_catalog/manifest.json"
CLIENT_HELMET_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/client_helmet_parameter_baseline.json"
OUTPUT = ROOT / "assets/art/characters/warrior/wear/helmet"
PROVENANCE = OUTPUT / "black_iron_helmet.source.json"
ANCHOR_APPEARANCE = 2
ANCHOR_STRIDE = 2224
CELL = (192, 160)
SOURCE_DRAW_ORIGIN = (64, 80)
RUNTIME_ENVELOPE_SCALE = 0.85 * 0.85
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_direction_variants(client_baseline: dict) -> list[Image.Image]:
    """Downsample all eight newly generated canonical views for world use."""
    labels = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
    variants: list[Image.Image] = []
    runtime_envelopes: dict = client_baseline.get("directionRuntimeMaxSize", {})
    for index, label in enumerate(labels):
        path = CANONICAL_DIRECTION_ROOT / f"{index}_{label}.png"
        image = Image.open(path).convert("RGBA")
        box = image.getchannel("A").getbbox()
        if not box:
            raise ValueError(f"Canonical Black Iron Helmet direction is empty: {label}")
        image = image.crop(box)
        direction = label.upper()
        envelope = runtime_envelopes.get(direction)
        if not isinstance(envelope, list) or len(envelope) != 2:
            raise ValueError(f"Missing real-client helmet envelope for {direction}")
        max_width, max_height = int(envelope[0]), int(envelope[1])
        # The first 85% pass was still visually oversized on the equipped
        # warrior. Apply the requested additional 15% reduction to that size.
        scale = min(max_width / image.width, max_height / image.height) * RUNTIME_ENVELOPE_SCALE
        target_width = max(1, round(image.width * scale))
        target_height = max(1, round(image.height * scale))
        # The approved E source is visibly narrower than real Helmet.wil E
        # rows. Fill the measured client envelope in this direction so idle E
        # and walk E do not look horizontally crushed.
        if direction == "E":
            target_width = max(1, round(max_width * RUNTIME_ENVELOPE_SCALE))
            target_height = max(1, round(max_height * RUNTIME_ENVELOPE_SCALE))
        image = image.resize((target_width, target_height), Image.Resampling.NEAREST)
        # Runtime pixel art uses a hard alpha edge.  This also guarantees that
        # no grey concept-sheet background survives the extraction process.
        alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
        image.putalpha(alpha)
        variants.append(image)
    return variants


def render_direction_reference(variants: list[Image.Image]) -> Path:
    labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    tile = (88, 92)
    sheet = Image.new("RGBA", (tile[0] * 8, 128), (14, 15, 18, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 6), "Black Iron Helmet: canonical newly generated 8-direction family", fill=(235, 235, 235, 255))
    for direction, variant in enumerate(variants):
        enlarged = variant.resize((variant.width * 3, variant.height * 3), Image.Resampling.NEAREST)
        x = direction * tile[0] + (tile[0] - enlarged.width) // 2
        sheet.alpha_composite(enlarged, (x, 31))
        draw.text((direction * tile[0] + 5, 108), labels[direction], fill=(255, 218, 84, 255))
    target = ROOT / "outputs/visual_acceptance/black_iron_helmet_directions.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def anchor_bbox(data: bytes, palette: list, offsets: list[int], index: int) -> tuple[int, int, int, int]:
    image, meta = decode_sprite(data, offsets[index], palette)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.alpha_composite(
        image.convert("RGBA"),
        (SOURCE_DRAW_ORIGIN[0] + int(meta["x"]), SOURCE_DRAW_ORIGIN[1] + int(meta["y"])),
    )
    box = cell.getchannel("A").getbbox()
    if not box:
        raise ValueError(f"Anchor source frame {index} is empty")
    return box


def build_action(
    data: bytes,
    palette: list,
    offsets: list[int],
    variants: list[Image.Image],
    action_name: str,
) -> dict:
    spec = ACTIONS[action_name]
    frame_count = int(spec["frames"])
    atlas = Image.new("RGBA", (CELL[0] * frame_count, CELL[1] * 8), (0, 0, 0, 0))
    frames: list[dict] = []
    for direction in range(8):
        for frame in range(frame_count):
            within_appearance = int(spec["start"]) + direction * 8 + frame
            index = ANCHOR_APPEARANCE * ANCHOR_STRIDE + within_appearance
            box = anchor_bbox(data, palette, offsets, index)
            helmet = variants[direction]
            pose_variant = "standing-direction"
            # South death frames 2/3 expose the crown as the body falls back.
            # A standing S helmet leaves the front eye slit upright on the
            # chest. Build a foreshortened crown from the approved N/back-top
            # geometry instead; do not rotate the standing front sprite.
            if action_name == "death" and direction == 4 and frame >= 2:
                crown_height = 8 if frame == 2 else 7
                helmet = variants[0].resize((variants[4].width, crown_height), Image.Resampling.NEAREST)
                pose_variant = "south-death-foreshortened-crown"
            rotated = False
            anchor_center_x = (box[0] + box[2]) // 2
            anchor_center_y = (box[1] + box[3]) // 2
            paste_x = frame * CELL[0] + anchor_center_x - helmet.width // 2
            paste_y_local = (
                anchor_center_y - helmet.height // 2
                if pose_variant == "south-death-foreshortened-crown"
                else box[1] - 3
            )
            paste_y = direction * CELL[1] + paste_y_local
            atlas.alpha_composite(helmet, (paste_x, paste_y))
            frames.append(
                {
                    "anchorSourceIndex": index,
                    "direction": direction,
                    "frame": frame,
                    "anchorOpaqueBox": list(box),
                    "paste": [paste_x - frame * CELL[0], paste_y - direction * CELL[1]],
                    "generatedSize": [helmet.width, helmet.height],
                    "rotatedForDeath": rotated,
                    "poseVariant": pose_variant,
                }
            )
    direction_signatures = [
        hashlib.sha256(
            atlas.crop((0, direction * CELL[1], atlas.width, (direction + 1) * CELL[1])).tobytes()
        ).hexdigest()
        for direction in range(8)
    ]
    if len(set(direction_signatures)) < 8:
        raise AssertionError(f"{action_name} does not contain eight distinct direction rows")
    target = OUTPUT / f"black_iron_helmet_{action_name}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(target)
    return {
        "path": f"res://{target.relative_to(ROOT).as_posix()}",
        "sha256": sha256(target),
        "cell": list(CELL),
        "directions": 8,
        "framesPerDirection": frame_count,
        "frames": frames,
        "directionSignatures": direction_signatures,
    }


def main() -> None:
    for required in (
        REFERENCE_ICON,
        REAR_DIRECTION_REFERENCE,
        FRONT_SIDE_CONCEPT_REFERENCE,
        CANONICAL_DIRECTION_MANIFEST,
        CLIENT_HELMET_BASELINE,
        ANCHOR_SOURCE,
        SOURCE_CODE,
        FRAME_CODE,
        COMPLETE_SCAN,
    ):
        if not required.exists():
            raise FileNotFoundError(f"Missing Black Iron Helmet evidence: {required}")
    scan = json.loads(COMPLETE_SCAN.read_text(encoding="utf-8"))
    client_helmet_baseline = json.loads(CLIENT_HELMET_BASELINE.read_text(encoding="utf-8"))
    if scan.get("libraryCount") != 122 or scan.get("indexedFramesScanned") != 962251:
        raise AssertionError("Complete-client scan is not complete")
    variants = build_direction_variants(client_helmet_baseline)
    direction_reference = render_direction_reference(variants)
    data, palette, offsets, info = read_library(ANCHOR_SOURCE)
    actions = {
        name: build_action(data, palette, offsets, variants, name)
        for name in ACTIONS
    }
    payload = {
        "schemaVersion": 6,
        "item": "Black Iron Helmet / 黑铁头盔",
        "classification": "project-generated presentation asset based on verified classic evidence",
        "referenceIcon": f"res://{REFERENCE_ICON.relative_to(ROOT).as_posix()}",
        "referenceIconSha256": sha256(REFERENCE_ICON),
        "referenceIconImage": 344,
        "approvedDirectionReferences": {
            "rearNNeNw": f"res://{REAR_DIRECTION_REFERENCE.relative_to(ROOT).as_posix()}",
            "rearNNeNwSha256": sha256(REAR_DIRECTION_REFERENCE),
            "frontSideConcept": f"res://{FRONT_SIDE_CONCEPT_REFERENCE.relative_to(ROOT).as_posix()}",
            "frontSideConceptSha256": sha256(FRONT_SIDE_CONCEPT_REFERENCE),
            "canonicalManifest": f"res://{CANONICAL_DIRECTION_MANIFEST.relative_to(ROOT).as_posix()}",
            "canonicalManifestSha256": sha256(CANONICAL_DIRECTION_MANIFEST),
            "acceptedRowMapping": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
        },
        "anchorLibrary": f"res://{ANCHOR_SOURCE.relative_to(ROOT).as_posix()}",
        "anchorLibraryImageCount": int(info["image_count"]),
        "anchorAppearance": ANCHOR_APPEARANCE,
        "anchorStride": ANCHOR_STRIDE,
        "anchorUsage": "position/motion only; no anchor-source pixels copied",
        "completeClientScan": f"res://{COMPLETE_SCAN.relative_to(ROOT).as_posix()}",
        "completeClientCoverage": {
            "libraries": scan["libraryCount"],
            "indexedFrames": scan["indexedFramesScanned"],
            "validFrames": scan["validFrames"],
        },
        "clientHelmetParameterBaseline": {
            "path": f"res://{CLIENT_HELMET_BASELINE.relative_to(ROOT).as_posix()}",
            "sha256": sha256(CLIENT_HELMET_BASELINE),
            "directionRuntimeMaxSize": client_helmet_baseline["directionRuntimeMaxSize"],
            "deathCanonicalRotate90Degrees": client_helmet_baseline["deathFinal"]["canonicalSpriteRotate90Degrees"],
        },
        "sourceEvidence": {
            "runtimeHeadLibrary": f"res://{SOURCE_CODE.relative_to(ROOT).as_posix()}",
            "runtimeFinding": "DrawHead uses HairLibrary; no equipped-helmet mapping exists in the paired runtime.",
            "actionFrames": f"res://{FRAME_CODE.relative_to(ROOT).as_posix()}",
            "rejectedHairLook2": "Narrow hair strip; visually rejected and used only as a motion anchor.",
            "rejectedHelmetWil": "Six horned/open-face families; none matches StateItem #344.",
        },
        "generation": {
            "equipmentIcon": "Verified StateItem #344 remains the equipment-window icon and unique identity evidence; its old derived world pixels are not used.",
            "runtimeDirections": "All eight runtime views come from the newly generated canonical direction family assembled from the user-supplied concept images.",
            "rearDirections": "N/NE/NW come from the user-approved magenta-background rear sheet.",
            "frontAndSideDirections": "E/SE/S/SW/W come from visual panels 2/3/4/6/7 of the supplied nine-panel concept; incorrect labels and duplicate panels are ignored.",
            "authorship": "Project-generated extension; not claimed as an original client world frame.",
            "aiGenerated": True,
            "aiPixelsLimitedTo": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
            "oldDerivedStateItemWorldPixelsUsed": False,
            "scalePolicy": "Fit each direction at 72.25% of the p75 width/height envelope measured from all six real client Helmet.wil appearances: two successive 15% reductions (0.85 * 0.85).",
            "runtimeEnvelopeScale": RUNTIME_ENVELOPE_SCALE,
            "deathPosePolicy": "Follow the per-frame client head anchor; South death frames 2/3 use a foreshortened crown derived from the approved Black Iron N/back-top geometry instead of a standing front sprite or whole-sprite 90-degree rotation.",
        },
        "directionReference": f"res://{direction_reference.relative_to(ROOT).as_posix()}",
        "actions": actions,
        "policy": "Complete-client evidence first; generated art is explicitly separated from original client assets.",
    }
    PROVENANCE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BLACK_IRON_HELMET_GENERATED_PASS "
        "runtime_reference=canonical_generated_8_directions actions=5 directions=8 old_stateitem_world_pixels=0 anchor_pixels_copied=0"
    )


if __name__ == "__main__":
    main()
