#!/usr/bin/env python3
"""Build the evidence-calibrated Black Iron Helmet world animation layer.

One complete client was scanned frame-by-frame and its paired runtime source
was audited.  The verified classic item exists as StateItem #344, but the 2013
runtime only draws Hair appearances and contains no matching worn Black Iron
Helmet layer.  StateItem #344 remains the verified equipment-window identity,
while the approved redesign is reconstructed as one complete procedural helmet
and rendered by Godot's orthographic 3D pipeline.  The source Hair animation is
used only as a per-frame head-motion anchor.  Death uses a 32-cell pose table
calibrated from the matching body direction/frame, Hair anchor and six authored
Helmet.wil appearances.  No Hair, unrelated Helmet, or old StateItem-derived
world pixels are copied into the generated result.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ICON = ROOT / "assets/art/characters/warrior/paper_doll/classic/layers/stateitem_00344.png"
APPROVED_CONCEPT = ROOT / "outputs/visual_acceptance/black_iron_helmet_approved_concept_20260717.png"
GODOT_RENDER_ROOT = ROOT / "outputs/visual_acceptance/black_iron_helmet_3d"
GODOT_RENDER_MANIFEST = GODOT_RENDER_ROOT / "manifest.json"
DEATH_POSE_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
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
RUNTIME_ENVELOPE_SCALE = 1.0
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
    """Downsample the eight Godot-rendered views to real-client envelopes."""
    labels = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
    variants: list[Image.Image] = []
    runtime_envelopes: dict = client_baseline.get("directionRuntimeMaxSize", {})
    runtime_opaque_pixels: dict = client_baseline.get("directionRuntimeOpaquePixels", {})
    for index, label in enumerate(labels):
        path = GODOT_RENDER_ROOT / f"standing_{label}.png"
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
        target_opaque = int(runtime_opaque_pixels.get(direction, 0))
        if target_opaque <= 0:
            raise ValueError(f"Missing real-client opaque-pixel baseline for {direction}")
        source_opaque = sum(image.getchannel("A").histogram()[128:])
        envelope_scale = min(max_width / image.width, max_height / image.height) * RUNTIME_ENVELOPE_SCALE
        area_scale = math.sqrt(target_opaque / max(1, source_opaque))
        scale = min(envelope_scale, area_scale)
        target_width = max(1, round(image.width * scale))
        target_height = max(1, round(image.height * scale))
        image = image.resize((target_width, target_height), Image.Resampling.NEAREST)
        # Runtime pixel art uses a hard alpha edge.  This also guarantees that
        # no grey concept-sheet background survives the extraction process.
        alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
        image.putalpha(alpha)
        variants.append(image)
    return variants


def load_death_variants() -> list[list[Image.Image]]:
    labels = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
    variants: list[list[Image.Image]] = []
    for label in labels:
        row: list[Image.Image] = []
        for frame in range(4):
            path = GODOT_RENDER_ROOT / f"death_{label}_f{frame}.png"
            image = Image.open(path).convert("RGBA")
            if image.getchannel("A").getbbox() is None:
                raise ValueError(f"Godot death pose is empty: {label} F{frame}")
            row.append(image)
        variants.append(row)
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
    death_variants: list[list[Image.Image]],
    death_pose_records: dict[tuple[int, int], dict],
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
            pose_record: dict | None = None
            if action_name == "death":
                helmet = death_variants[direction][frame]
                pose_record = death_pose_records[(direction, frame)]
                pose_variant = "godot-orthographic-complete-helmet"
            rotated = False
            anchor_center_x = (box[0] + box[2]) // 2
            anchor_center_y = (box[1] + box[3]) // 2
            if pose_record is not None:
                hair_centroid = pose_record["hairAnchorCentroid"]
                anchor_center_x = round(float(hair_centroid[0]))
                anchor_center_y = round(float(hair_centroid[1]))
            paste_x = frame * CELL[0] + anchor_center_x - helmet.width // 2
            paste_y_local = anchor_center_y - helmet.height // 2 if pose_record is not None else box[1] - 3
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
        APPROVED_CONCEPT,
        GODOT_RENDER_MANIFEST,
        DEATH_POSE_BASELINE,
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
    death_pose_baseline = json.loads(DEATH_POSE_BASELINE.read_text(encoding="utf-8"))
    godot_render_manifest = json.loads(GODOT_RENDER_MANIFEST.read_text(encoding="utf-8"))
    if scan.get("libraryCount") != 122 or scan.get("indexedFramesScanned") != 962251:
        raise AssertionError("Complete-client scan is not complete")
    variants = build_direction_variants(client_helmet_baseline)
    death_variants = load_death_variants()
    death_pose_records = {
        (int(record["directionRow"]), int(record["frame"])): record
        for record in death_pose_baseline.get("records", [])
    }
    if len(death_pose_records) != 32 or len(godot_render_manifest.get("records", [])) != 32:
        raise AssertionError("Godot death pipeline does not contain the complete 8x4 mapping")
    direction_reference = render_direction_reference(variants)
    data, palette, offsets, info = read_library(ANCHOR_SOURCE)
    actions = {
        name: build_action(data, palette, offsets, variants, death_variants, death_pose_records, name)
        for name in ACTIONS
    }
    payload = {
        "schemaVersion": 7,
        "item": "Black Iron Helmet / 黑铁头盔",
        "classification": "project-generated presentation asset based on verified classic evidence",
        "referenceIcon": f"res://{REFERENCE_ICON.relative_to(ROOT).as_posix()}",
        "referenceIconSha256": sha256(REFERENCE_ICON),
        "referenceIconImage": 344,
        "approvedDirectionReferences": {
            "approvedConcept": f"res://{APPROVED_CONCEPT.relative_to(ROOT).as_posix()}",
            "approvedConceptSha256": sha256(APPROVED_CONCEPT),
            "godotRenderer": "res://tools/render_black_iron_helmet_3d.gd",
            "godotRendererSha256": sha256(ROOT / "tools/render_black_iron_helmet_3d.gd"),
            "godotRenderManifest": f"res://{GODOT_RENDER_MANIFEST.relative_to(ROOT).as_posix()}",
            "godotRenderManifestSha256": sha256(GODOT_RENDER_MANIFEST),
            "acceptedRowMapping": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
        },
        "anchorLibrary": f"res://{ANCHOR_SOURCE.relative_to(ROOT).as_posix()}",
        "anchorLibraryImageCount": int(info["image_count"]),
        "anchorAppearance": ANCHOR_APPEARANCE,
        "anchorStride": ANCHOR_STRIDE,
        "anchorUsage": "same-cell position/motion and death-facing calibration only; no anchor-source pixels copied",
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
            "directionRuntimeOpaquePixels": client_helmet_baseline["directionRuntimeOpaquePixels"],
            "deathCanonicalRotate90Degrees": client_helmet_baseline["deathFinal"]["canonicalSpriteRotate90Degrees"],
        },
        "deathPoseBaseline": {
            "path": f"res://{DEATH_POSE_BASELINE.relative_to(ROOT).as_posix()}",
            "sha256": sha256(DEATH_POSE_BASELINE),
            "records": len(death_pose_records),
            "mappingRule": death_pose_baseline["mappingRule"],
            "rendererPolicy": death_pose_baseline["rendererPolicy"],
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
            "runtimeDirections": "All eight runtime views are orthographic Godot renders of one complete procedural helmet geometry based on the user-approved redesign.",
            "deathDirections": "Every N/NE/E/SE/S/SW/W/NW x F0/F1/F2/F3 cell is independently rendered from the same-row same-frame evidence record.",
            "authorship": "Project-generated extension; not claimed as an original client world frame.",
            "aiGenerated": True,
            "aiConceptUsed": True,
            "aiPixelsLimitedTo": [],
            "runtimePixelGenerator": "Godot 4.7 orthographic 3D renderer; no image-generation pixels are copied into the runtime atlases.",
            "oldDerivedStateItemWorldPixelsUsed": False,
            "scalePolicy": "Fit each direction within the p75 width/height envelope and cap opaque visual mass at the same-direction client median; no arbitrary global reduction.",
            "runtimeEnvelopeScale": RUNTIME_ENVELOPE_SCALE,
            "deathPosePolicy": "Use the exact same direction row and frame column in warrior_death.png and Hair.wil; invert that head vector through the documented Godot orthographic camera, render the complete helmet geometry, then centre it on the same-cell Hair anchor.",
        },
        "directionReference": f"res://{direction_reference.relative_to(ROOT).as_posix()}",
        "actions": actions,
        "policy": "Complete-client evidence first; generated art is explicitly separated from original client assets.",
    }
    PROVENANCE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BLACK_IRON_HELMET_GENERATED_PASS "
        "runtime_reference=godot_orthographic_complete_geometry actions=5 directions=8 death_pose_records=32 old_stateitem_world_pixels=0 anchor_pixels_copied=0"
    )


if __name__ == "__main__":
    main()
