#!/usr/bin/env python3
"""Build exact wizard/taoist animation frames and icons from primary client WILs."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
CLIENT_SOURCE = ROOT / "dev_art_sources/reference/original_gameofmir/MirClient"
OUTPUT = ROOT / "assets/data/caster_skill_visuals.json"
PROFESSION_GROWTH = ROOT / "assets/data/vanilla_176/profession_growth.json"
SKILL_SOURCE = ROOT / "assets/data/vanilla_176/skills_source_of_truth_v1.json"
FRAME_ROOT = ROOT / "assets/art/characters/caster_skill_frames"
ICON_SIZE = 96
CLASSIC_UNIT_HALF = (32, 16)


@dataclass(frozen=True)
class AnimationSpec:
    library: str
    start: int
    frame_count: int
    skill_ids: tuple[str, ...]
    role: str
    frame_time_ms: int
    mapping_rule: str
    directions: int = 1
    direction_stride: int = 10
    playback: str = "once"
    mapping_confidence: str = "A"


SPECS = {
    # Wizard. Direction 0 is up; directions increase clockwise, exactly as
    # MirClient.ClFunc.GetFlyDirection16.
    "fireball": AnimationSpec(
        "Magic.wil", 10, 6, ("wizard.fireball",), "projectile", 50,
        "EffectBase[1]=0 + FLYBASE=10 + Dir16*10; TMagicEff frame=MG_FLY=6",
        directions=16, playback="loop",
    ),
    "repulsion_ring": AnimationSpec(
        "Magic.wil", 900, 10, ("wizard.repulsion_ring",), "self_area", 60,
        "EffectType=mtFireWind has no detached TMagicEff; Actor draws EffectBase[6]=900 "
        "with DEFSPELLFRAME=10 and HA.ActSpell.ftime=60",
    ),
    "temptation_light": AnimationSpec(
        "Magic.wil", 1564, 16, ("wizard.temptation_light",), "target_effect", 60,
        "PlayScn.NewMagic effect 18 sets MagExplosionBase=1564, NextFrameTime=60, "
        "ExplosionFrame=16",
    ),
    "hellfire": AnimationSpec(
        "Magic.wil", 930, 6, ("wizard.hellfire",), "line_effect", 50,
        "PlayScn mtFireGun constructs TFireGunEffect at 930; FIREGUNFRAME=6, "
        "NextFrameTime=50",
    ),
    "lightning": AnimationSpec(
        "Magic2.wil", 10, 6, ("wizard.lightning",), "target_effect", 50,
        "PlayScn mtThunder constructs Magic2 TThuderEffect at 10 and sets "
        "ExplosionFrame=6; inherited NextFrameTime=50",
    ),
    "teleport": AnimationSpec(
        "Magic.wil", 1590, 10, ("wizard.teleport",), "self_effect", 30,
        "Actor.pas SM_SPACEMOVE_HIDE2 constructs TScrollHideEffect(1590, 10); "
        "magiceff.pas TMapEffect fixes NextFrameTime=30",
    ),
    "great_fireball": AnimationSpec(
        "Magic.wil", 410, 6, ("wizard.great_fireball",), "projectile", 50,
        "EffectBase[3]=400 + FLYBASE=10 + Dir16*10; TMagicEff frame=MG_FLY=6",
        directions=16, playback="loop",
    ),
    "exploding_flame": AnimationSpec(
        "Magic.wil", 1660, 20, ("wizard.exploding_flame",), "area_effect", 80,
        "PlayScn.NewMagic effect 21 sets MagExplosionBase=1660, NextFrameTime=80, "
        "ExplosionFrame=20",
    ),
    "fire_wall": AnimationSpec(
        "Magic.wil", 1630, 6, ("wizard.fire_wall",), "ground_effect", 40,
        "clEvent.pas ET_FIRE in the non-CUSTOMLIBFILE branch uses g_WMagicImages "
        "FIREBURNBASE=1630 + ((m_dwCurframe div 2) mod 6). The primary "
        "client.classic_raw_complete Data/Magic.wil distribution is that non-custom "
        "library layout. Run advances m_dwCurframe every 20 ms, so visible frames are 40 ms. "
        "EffectBase[20]=1620 is only the caster body ring and is not the ground fire.",
        playback="loop",
    ),
    "laser": AnimationSpec(
        "Magic.wil", 970, 6, ("wizard.laser",), "line_effect", 50,
        "PlayScn mtLightingThunder constructs TLightingThunder at 970; DrawEff uses "
        "970 + Dir16*10 + curframe while curframe<6",
        directions=16,
    ),
    "hell_lightning": AnimationSpec(
        "Magic.wil", 1680, 10, ("wizard.hell_lightning",), "self_area", 60,
        "EffectType=mtFireWind has no detached TMagicEff; Actor draws EffectBase[22]=1680 "
        "with DEFSPELLFRAME=10 and HA.ActSpell.ftime=60",
    ),
    "magic_shield": AnimationSpec(
        "Magic.wil", 3880, 10, ("wizard.magic_shield",), "self_effect", 60,
        "EffectType=mtFireWind has no detached TMagicEff; Actor draws EffectBase[29]=3880 "
        "with DEFSPELLFRAME=10 and HA.ActSpell.ftime=60",
    ),
    "holy_word": AnimationSpec(
        "Magic.wil", 3930, 16, ("wizard.holy_word",), "target_effect", 80,
        "PlayScn.NewMagic effect 30 sets MagExplosionBase=3930, NextFrameTime=80, "
        "ExplosionFrame=16",
    ),
    "ice_storm": AnimationSpec(
        "Magic.wil", 3850, 20, ("wizard.ice_storm",), "area_effect", 80,
        "PlayScn.NewMagic effect 31 sets MagExplosionBase=3850, NextFrameTime=80, "
        "ExplosionFrame=20",
    ),
    # Taoist.
    "healing": AnimationSpec(
        "Magic.wil", 370, 10, ("taoist.healing",), "target_effect", 80,
        "EffectType=mtExplosion; TMagicEff default MagExplosionBase is "
        "EffectBase[2]=200 + EXPLOSIONBASE=170; PlayScn default NextFrameTime=80",
    ),
    "poison": AnimationSpec(
        "Magic.wil", 770, 10, ("taoist.poison",), "target_effect", 80,
        "EffectType=mtExplosion; TMagicEff default MagExplosionBase is "
        "EffectBase[4]=600 + EXPLOSIONBASE=170; PlayScn default NextFrameTime=80",
    ),
    "soul_fire_talisman": AnimationSpec(
        "Magic.wil", 1160, 3, ("taoist.soul_fire_talisman",), "projectile", 50,
        "PlayScn mtExploBujauk constructs TExploBujaukEffect at 1160; DrawEff uses "
        "1160 + Dir16*10 + curframe; constructor frame=3, NextFrameTime=50",
        directions=16, playback="loop",
    ),
    "invisibility": AnimationSpec(
        "Magic.wil", 1520, 10, ("taoist.invisibility",), "self_area", 60,
        "EffectType=mtFireWind has no detached TMagicEff; Actor draws EffectBase[16]=1520 "
        "with DEFSPELLFRAME=10 and HA.ActSpell.ftime=60",
    ),
    "mass_invisibility": AnimationSpec(
        "Magic.wil", 1540, 10, ("taoist.mass_invisibility",), "area_effect", 50,
        "PlayScn mtExploBujauk effect 17 sets MagExplosionBase=1540; "
        "TExploBujaukEffect inherits MG_EXPLOSION=10 and NextFrameTime=50",
    ),
    "magic_defense": AnimationSpec(
        "Magic.wil", 1320, 16, ("taoist.magic_defense",), "area_effect", 50,
        "TBujaukGroundEffect magic 11 draws 1160 + 16*10 + curframe; "
        "PlayScn sets ExplosionFrame=16 and constructor NextFrameTime=50",
    ),
    "defense": AnimationSpec(
        "Magic.wil", 1340, 16, ("taoist.defense",), "area_effect", 50,
        "TBujaukGroundEffect magic 12 draws 1160 + 18*10 + curframe; "
        "PlayScn sets ExplosionFrame=16 and constructor NextFrameTime=50",
    ),
    "revelation": AnimationSpec(
        "Magic.wil", 3990, 10, ("taoist.revelation",), "target_effect", 80,
        "PlayScn.NewMagic effect 26 sets MagExplosionBase=3990, NextFrameTime=80, "
        "ExplosionFrame=10",
    ),
    "binding_circle": AnimationSpec(
        "Magic.wil", 1380, 10, ("taoist.entrapment",), "area_effect", 60,
        "EffectBase[14]=1380 is the primary ground-nail family; Actor draws its "
        "DEFSPELLFRAME=10 at HA.ActSpell.ftime=60. PlayScn mtKyulKai detached "
        "constructor is explicitly disabled, so no lower-priority runtime is invented.",
        mapping_confidence="B",
    ),
    "mass_healing": AnimationSpec(
        "Magic.wil", 1800, 10, ("taoist.mass_healing",), "area_effect", 80,
        "PlayScn.NewMagic effect 27 sets MagExplosionBase=1800, NextFrameTime=80, "
        "ExplosionFrame=10",
    ),
    "summon_skeleton": AnimationSpec(
        "Mon3.wil", 0, 4, ("taoist.summon_skeleton",), "summon_actor_visual", 200,
        "Actor.aGetMonImg appearance 20 selects Mon3; Actor.MA20 ActStand starts at 0, "
        "has 4 visible frames, skips 6 sentinel slots, and uses ftime=200. "
        "Indices 4..9 are not animation frames.",
        playback="loop",
    ),
    "summon_divine_beast": AnimationSpec(
        "Mon18.wil", 350, 4, ("taoist.summon_divine_beast",), "summon_actor_visual", 160,
        "Actor/AxeMon divine-beast classes select Mon18; standing block starts at 350. "
        "SummonActor owns the full state animation; this exact family supplies the skill icon.",
        playback="loop", mapping_confidence="B",
    ),
}

NO_VISUAL_SKILLS = {
    "taoist.spiritual_warfare": {
        "status": "no_runtime_visual",
        "reason": "Passive accuracy skill; the primary server/client emit no cast event.",
        "source_original_path": "M2Server/Magic.pas",
    },
}

TELEPORT_ARRIVAL_SPEC = AnimationSpec(
    "Magic.wil",
    1600,
    10,
    ("wizard.teleport",),
    "self_effect",
    30,
    "Actor.pas SM_SPACEMOVE_SHOW2 constructs TCharEffect(1600, 10); "
    "magiceff.pas TCharEffect fixes NextFrameTime=30 and follows the arriving actor",
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def icon_metrics(image: Image.Image) -> dict[str, float | int]:
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    opaque_pixels = sum(histogram[1:])
    alpha_sum = sum(value * count for value, count in enumerate(histogram))
    bbox = alpha.getbbox()
    bbox_area = 0 if bbox is None else (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    luminances = [
        0.2126 * red + 0.7152 * green + 0.0722 * blue
        for red, green, blue, pixel_alpha in image.get_flattened_data()
        if pixel_alpha > 0
    ]
    mean_luma = sum(luminances) / len(luminances) if luminances else 0.0
    variance = (
        sum((value - mean_luma) ** 2 for value in luminances) / len(luminances)
        if luminances
        else 0.0
    )
    return {
        "opaque_pixels": opaque_pixels,
        "alpha_sum": alpha_sum,
        "bbox_area": bbox_area,
        "occupancy": opaque_pixels / max(1, bbox_area),
        "mean_luma": mean_luma,
        "luminance_stddev": math.sqrt(variance),
    }


def _visible_alpha_samples(
    image: Image.Image,
    top_left_from_world_anchor: list[int] | list[float],
) -> list[tuple[float, float, float]]:
    """Return visible pixel centres in source world-anchor coordinates."""
    alpha = image.getchannel("A")
    origin_x = float(top_left_from_world_anchor[0])
    origin_y = float(top_left_from_world_anchor[1])
    result: list[tuple[float, float, float]] = []
    for y in range(image.height):
        for x in range(image.width):
            alpha_value = alpha.getpixel((x, y))
            if alpha_value <= 0:
                continue
            result.append((
                origin_x + x + 0.5,
                origin_y + y + 0.5,
                float(alpha_value) / 255.0,
            ))
    return result


def _principal_visible_axis(
    samples: list[tuple[float, float, float]],
    fallback_axis: tuple[float, float],
) -> tuple[float, float]:
    """Measure the alpha-weighted major axis and retain the intended direction."""
    total_weight = sum(sample[2] for sample in samples)
    if total_weight <= 0.0:
        return fallback_axis
    mean_x = sum(x * weight for x, _y, weight in samples) / total_weight
    mean_y = sum(y * weight for _x, y, weight in samples) / total_weight
    covariance_xx = sum(
        weight * (x - mean_x) * (x - mean_x) for x, _y, weight in samples
    ) / total_weight
    covariance_xy = sum(
        weight * (x - mean_x) * (y - mean_y) for x, y, weight in samples
    ) / total_weight
    covariance_yy = sum(
        weight * (y - mean_y) * (y - mean_y) for _x, y, weight in samples
    ) / total_weight
    angle = 0.5 * math.atan2(
        2.0 * covariance_xy,
        covariance_xx - covariance_yy,
    )
    axis = (math.cos(angle), math.sin(angle))
    if axis[0] * fallback_axis[0] + axis[1] * fallback_axis[1] < 0.0:
        axis = (-axis[0], -axis[1])
    return axis


def _visible_projection_metadata(
    samples: list[tuple[float, float, float]],
    source_axis: tuple[float, float],
) -> dict[str, object]:
    cross_axis = (-source_axis[1], source_axis[0])
    axis_projections = [
        x * source_axis[0] + y * source_axis[1] for x, y, _weight in samples
    ]
    cross_projections = [
        x * cross_axis[0] + y * cross_axis[1] for x, y, _weight in samples
    ]
    if not axis_projections or not cross_projections:
        return {
            "visible_axis_local": [source_axis[0], source_axis[1]],
            "visible_axis_start_pixels": 0.0,
            "visible_axis_extent_pixels": 1.0,
            "visible_cross_center_pixels": 0.0,
            "visible_cross_extent_pixels": 1.0,
        }
    axis_pixel_support = abs(source_axis[0]) + abs(source_axis[1])
    cross_pixel_support = abs(cross_axis[0]) + abs(cross_axis[1])
    axis_minimum = min(axis_projections) - axis_pixel_support * 0.5
    axis_maximum = max(axis_projections) + axis_pixel_support * 0.5
    cross_minimum = min(cross_projections) - cross_pixel_support * 0.5
    cross_maximum = max(cross_projections) + cross_pixel_support * 0.5
    return {
        "visible_axis_local": [round(source_axis[0], 9), round(source_axis[1], 9)],
        "visible_axis_start_pixels": round(axis_minimum, 6),
        "visible_axis_extent_pixels": round(axis_maximum - axis_minimum, 6),
        "visible_cross_center_pixels": round(
            (cross_minimum + cross_maximum) * 0.5, 6
        ),
        "visible_cross_extent_pixels": round(cross_maximum - cross_minimum, 6),
    }


def annotate_laser_sequence_presentation(sequence: dict[str, object]) -> None:
    """Attach reproducible source-art calibration without regenerating geometry."""
    direction_index = int(sequence.get("direction_index", 0))
    angle = direction_index * math.tau / 16.0
    fallback_axis = (math.sin(angle), -math.cos(angle))
    aggregate_samples: list[tuple[float, float, float]] = []
    frame_samples: list[list[tuple[float, float, float]]] = []
    frames = sequence.get("frames", [])
    if not isinstance(frames, list):
        return
    for frame in frames:
        if not isinstance(frame, dict):
            frame_samples.append([])
            continue
        image = Image.open(ROOT / str(frame["path"])).convert("RGBA")
        samples = _visible_alpha_samples(
            image,
            frame.get("top_left_from_world_anchor", [0, 0]),
        )
        frame_samples.append(samples)
        aggregate_samples.extend(samples)
    sequence_axis = _principal_visible_axis(aggregate_samples, fallback_axis)
    sequence["source_axis_local"] = [
        round(sequence_axis[0], 9),
        round(sequence_axis[1], 9),
    ]
    for frame, samples in zip(frames, frame_samples):
        if not isinstance(frame, dict):
            continue
        frame_axis = _principal_visible_axis(samples, sequence_axis)
        frame.update(_visible_projection_metadata(samples, frame_axis))


def icon_score(
    metrics: dict[str, float | int],
    maximum_opaque: int,
    maximum_bbox_area: int,
    source_index: int,
) -> tuple[int, int]:
    opaque_ratio = float(metrics["opaque_pixels"]) / max(1, maximum_opaque)
    bbox_ratio = float(metrics["bbox_area"]) / max(1, maximum_bbox_area)
    occupancy = min(1.0, float(metrics["occupancy"]))
    luma_contrast = min(1.0, float(metrics["luminance_stddev"]) / 96.0)
    # Prefer a readable mid/high luminance effect without rewarding blown-out
    # solid white frames. The bounded term peaks near 62% luma.
    bounded_mean_luma = max(0.0, 1.0 - abs(float(metrics["mean_luma"]) / 255.0 - 0.62) / 0.62)
    readability = (
        opaque_ratio * 0.35
        + bbox_ratio * 0.25
        + occupancy * 0.15
        + luma_contrast * 0.15
        + bounded_mean_luma * 0.10
    )
    return (round(readability * 1_000_000), -source_index)


def save_icon(frame: Image.Image, output: Path) -> None:
    alpha_bbox = frame.getchannel("A").getbbox()
    crop = frame.crop(alpha_bbox) if alpha_bbox is not None else frame
    maximum = ICON_SIZE - 12
    scale = min(maximum / max(1, crop.width), maximum / max(1, crop.height))
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    resized = crop.resize(size, Image.Resampling.NEAREST)
    icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    icon.alpha_composite(resized, ((ICON_SIZE - size[0]) // 2, (ICON_SIZE - size[1]) // 2))
    output.parent.mkdir(parents=True, exist_ok=True)
    icon.save(output)


def render_policy(asset_id: str, role: str) -> dict[str, object]:
    if role == "projectile":
        attachment = "world_projectile"
        scale_mode = "fit_extent"
        fit_extent = 34.0
    elif role == "target_effect":
        attachment = "target_actor"
        scale_mode = "source_pixels"
        fit_extent = 0.0
    elif role in {"self_effect", "self_area", "line_effect"}:
        attachment = "caster_actor"
        scale_mode = "source_pixels"
        fit_extent = 0.0
    elif role == "summon_actor_visual":
        attachment = "summon_actor"
        scale_mode = "source_pixels"
        fit_extent = 0.0
    else:
        attachment = "world_anchor"
        scale_mode = "source_pixels"
        fit_extent = 0.0
    # These effects are sampled or emitted into the map rather than continuously
    # following an actor. Teleport's arrival phase overrides this below.
    if asset_id in {"lightning", "hellfire", "teleport"}:
        attachment = "world_anchor"
    result: dict[str, object] = {
        "contract": "caster_skill_render.v2",
        "scale_mode": scale_mode,
        "source_scale": 1.0,
        "fit_extent": fit_extent,
        "anchor_policy": "top_left_from_world_anchor",
        "attachment_policy": attachment,
        "playback_strategy": "firegun_trail" if asset_id == "hellfire" else "frame_sequence",
        "pixel_snap": True,
    }
    if asset_id == "lightning":
        # Magic2's primary six-frame sky strike is almost 1000 px tall, while
        # its lateral branches/glow reach 316 px. Preserve every source pixel
        # and the original vertical reach, but present the strike with a
        # narrower horizontal axis around its world anchor. This is a runtime
        # presentation transform only; source frames and combat geometry stay
        # byte-identical.
        result.update(
            {
                "presentation_contract": "skills.wizard.lightning.slender_axis.v1",
                "source_scale_x": 0.62,
                "source_scale_y": 1.0,
            }
        )
    if asset_id == "magic_shield":
        # The exact primary Magic.wil bounds are x=-42..27 relative to the
        # actor footpoint: their horizontal centre is -7.5. Rebase only that
        # proven half-pixel centre error while retaining the source vertical
        # baseline, then render behind the player body at the same sort row.
        result.update(
            {
                "presentation_contract": (
                    "skills.wizard.magic_shield.primary_actor_footpoint_centered_behind_body.v1"
                ),
                "anchor_rebase_pixels": [7.5, 0.0],
                "attachment_draw_order": "behind_attached_actor_same_footpoint",
            }
        )
    if asset_id == "hellfire":
        result.update(
            {
                "trajectory_contract": "mirclient.tfireguneffect.v1",
                "trajectory_length_tiles": 5,
                "trajectory_step_ms": 50,
                "trajectory_dominant_axis_pixels_per_second": 500.0 / 0.9,
                "trail_frame_count": 6,
            }
        )
    if asset_id == "laser":
        result.update(
            {
                "geometry_alignment_contract": "skills.caster.geometry_visual_alignment.v1",
                "axis_fit_contract": "skills.caster.line_visual.frame_alpha_cross_affine.v3",
                "fit_mode": "sequence_longitudinal_and_per_frame_alpha_cross_extent",
                "visual_cross_extent_contract": "sqrt_iso_cell_screen_area_direction_invariant",
                "movement_lock_to_primary_visual": True,
            }
        )
    return result


def decode_phase(
    asset_id: str,
    phase_id: str,
    spec: AnimationSpec,
    library: tuple,
) -> dict[str, object]:
    data, palette, offsets, _library_info = library
    sequences = []
    native_left = native_top = 2**31 - 1
    native_right = native_bottom = -(2**31)
    for source_slot in range(spec.directions):
        frames = []
        canonical_direction = round(source_slot * 16 / spec.directions) % 16
        for frame_index in range(spec.frame_count):
            source_index = spec.start + source_slot * spec.direction_stride + frame_index
            if source_index >= len(offsets):
                raise RuntimeError(
                    f"{asset_id}:{phase_id} source index {source_index} is outside {spec.library}"
                )
            image, sprite = decode_sprite(data, offsets[source_index], palette)
            frame_path = (
                FRAME_ROOT
                / f"{asset_id}_{phase_id}"
                / f"direction_{source_slot:02d}"
                / f"frame_{frame_index:02d}.png"
            )
            frame_path.parent.mkdir(parents=True, exist_ok=True)
            image.save(frame_path)
            top_left = [sprite["x"] - CLASSIC_UNIT_HALF[0], sprite["y"] - CLASSIC_UNIT_HALF[1]]
            native_left = min(native_left, top_left[0])
            native_top = min(native_top, top_left[1])
            native_right = max(native_right, top_left[0] + sprite["width"])
            native_bottom = max(native_bottom, top_left[1] + sprite["height"])
            frames.append(
                {
                    "frame_index": frame_index,
                    "source_index": source_index,
                    "source_offset": sprite["offset"],
                    "source_draw_offset": [sprite["x"], sprite["y"]],
                    "top_left_from_world_anchor": top_left,
                    "pixel_size": [sprite["width"], sprite["height"]],
                    "path": rel(frame_path),
                    "png_sha256": digest(frame_path),
                }
            )
        sequences.append(
            {
                "source_direction_slot": source_slot,
                "direction_index": canonical_direction,
                "frames": frames,
            }
        )
    return {
        "contract": "caster_skill_animation.v1",
        "phase_id": phase_id,
        "frame_time_ms": spec.frame_time_ms,
        "frame_count": spec.frame_count,
        "direction_count": spec.directions,
        "direction_order": "canonical16: 0=up, 4=right, 8=down, 12=left; clockwise",
        "source_direction_slot_order": [
            int(sequence["direction_index"]) for sequence in sequences
        ],
        "playback": spec.playback,
        "native_bounds": [native_left, native_top, native_right, native_bottom],
        "native_extent": [native_right - native_left, native_bottom - native_top],
        "sequences": sequences,
        "mapping_rule": spec.mapping_rule,
        "distribution_id": "client.classic_raw_complete",
        "source_priority": {
            "lane": "client_assets",
            "tier": "primary",
            "order": 0,
            "weight": 100,
        },
        "original_path": f"Data/{spec.library}",
        "source_sha256": digest(DATA / spec.library),
    }


def main() -> None:
    if FRAME_ROOT.exists():
        shutil.rmtree(FRAME_ROOT)
    libraries: dict[str, tuple] = {}
    assets: dict[str, dict] = {}
    skill_coverage: dict[str, dict] = {}

    for asset_id, spec in SPECS.items():
        library_path = DATA / spec.library
        if spec.library not in libraries:
            libraries[spec.library] = read_library(library_path)
        data, palette, offsets, library_info = libraries[spec.library]
        sequences = []
        candidate_frames = []
        native_left = native_top = 2**31 - 1
        native_right = native_bottom = -(2**31)

        for direction_index in range(spec.directions):
            frames = []
            canonical_direction = round(direction_index * 16 / spec.directions) % 16
            for frame_index in range(spec.frame_count):
                source_index = spec.start + direction_index * spec.direction_stride + frame_index
                if source_index >= len(offsets):
                    raise RuntimeError(f"{asset_id} source index {source_index} is outside {spec.library}")
                image, sprite = decode_sprite(data, offsets[source_index], palette)
                frame_path = FRAME_ROOT / asset_id / f"direction_{direction_index:02d}" / f"frame_{frame_index:02d}.png"
                frame_path.parent.mkdir(parents=True, exist_ok=True)
                image.save(frame_path)
                top_left = [sprite["x"] - CLASSIC_UNIT_HALF[0], sprite["y"] - CLASSIC_UNIT_HALF[1]]
                native_left = min(native_left, top_left[0])
                native_top = min(native_top, top_left[1])
                native_right = max(native_right, top_left[0] + sprite["width"])
                native_bottom = max(native_bottom, top_left[1] + sprite["height"])
                record = {
                    "frame_index": frame_index,
                    "source_index": source_index,
                    "source_offset": sprite["offset"],
                    "source_draw_offset": [sprite["x"], sprite["y"]],
                    "top_left_from_world_anchor": top_left,
                    "pixel_size": [sprite["width"], sprite["height"]],
                    "path": rel(frame_path),
                    "png_sha256": digest(frame_path),
                }
                frames.append(record)
                candidate_frames.append((image, record, icon_metrics(image)))
            sequence = {
                "source_direction_slot": direction_index,
                "direction_index": canonical_direction,
                "frames": frames,
            }
            if asset_id == "laser":
                annotate_laser_sequence_presentation(sequence)
            sequences.append(sequence)

        maximum_opaque = max(int(candidate[2]["opaque_pixels"]) for candidate in candidate_frames)
        maximum_bbox_area = max(int(candidate[2]["bbox_area"]) for candidate in candidate_frames)
        eligible_candidates = []
        for image, record, metrics in candidate_frames:
            if int(metrics["opaque_pixels"]) <= 0:
                continue
            endpoint = int(record["frame_index"]) in (0, spec.frame_count - 1)
            weak_endpoint = (
                endpoint
                and int(metrics["opaque_pixels"]) < maximum_opaque * 0.45
                and int(metrics["bbox_area"]) < maximum_bbox_area * 0.45
            )
            if not weak_endpoint:
                eligible_candidates.append((image, record, metrics))
        if not eligible_candidates:
            raise RuntimeError(f"{asset_id} has no non-empty icon candidates")
        best_image, best_record, best_metrics = max(
            eligible_candidates,
            key=lambda candidate: icon_score(
                candidate[2],
                maximum_opaque,
                maximum_bbox_area,
                int(candidate[1]["source_index"]),
            ),
        )
        best_score = icon_score(
            best_metrics,
            maximum_opaque,
            maximum_bbox_area,
            int(best_record["source_index"]),
        )
        profession = "wizard" if spec.skill_ids[0].startswith("wizard.") else "taoist"
        icon_path = ROOT / f"assets/art/characters/{profession}/skill_icons/{asset_id}.png"
        save_icon(best_image, icon_path)
        representative_path = ROOT / f"assets/art/characters/{profession}/effects/{asset_id}.png"
        representative_path.parent.mkdir(parents=True, exist_ok=True)
        best_image.save(representative_path)

        animation = {
            "contract": "caster_skill_animation.v1",
            "frame_time_ms": spec.frame_time_ms,
            "frame_count": spec.frame_count,
            "direction_count": spec.directions,
            "direction_order": "canonical16: 0=up, 4=right, 8=down, 12=left; clockwise",
            "source_direction_slot_order": [
                int(sequence["direction_index"]) for sequence in sequences
            ],
            "playback": spec.playback,
            "native_bounds": [native_left, native_top, native_right, native_bottom],
            "native_extent": [native_right - native_left, native_bottom - native_top],
            "sequences": sequences,
        }
        assets[asset_id] = {
            "skill_ids": list(spec.skill_ids),
            "role": spec.role,
            "path": rel(representative_path),
            "icon": {
                "path": rel(icon_path),
                "pixel_size": [ICON_SIZE, ICON_SIZE],
                "selected_source_index": best_record["source_index"],
                "selected_direction_index": next(
                    sequence["direction_index"]
                    for sequence in sequences
                    if best_record in sequence["frames"]
                ),
                "selected_frame_index": best_record["frame_index"],
                "selection_rule": "nonempty; weak endpoint filter at 0.45 asset maxima; max(0.35 opaque_ratio + 0.25 bbox_ratio + 0.15 occupancy + 0.15 luminance_stddev + 0.10 bounded_mean_luma); tie=min source_index",
                "selection_score": list(best_score),
                "selection_metrics": {
                    **best_metrics,
                    "asset_maximum_opaque_pixels": maximum_opaque,
                    "asset_maximum_bbox_area": maximum_bbox_area,
                    "endpoint_filter_ratio": 0.45,
                },
                "transform": "alpha_bbox_crop -> nearest_neighbor_fit_84x84 -> transparent_96x96_center",
                "derived_only_from_animation_frame": True,
            },
            "animation": animation,
            "render": render_policy(asset_id, spec.role),
            "distribution_id": "client.classic_raw_complete",
            "source_priority": {"lane": "client_assets", "tier": "primary", "order": 0, "weight": 100},
            "original_path": f"Data/{spec.library}",
            "source_sha256": digest(library_path),
            "library_image_count": library_info["image_count"],
            "mapping_rule": spec.mapping_rule,
            "mapping_confidence": spec.mapping_confidence,
            "pixel_confidence": "A",
            "derived_status": "ready",
        }
        for skill_id in spec.skill_ids:
            if skill_id in skill_coverage:
                raise RuntimeError(f"duplicate visual coverage for {skill_id}")
            skill_coverage[skill_id] = {
                "status": "formal_primary_client_animation",
                "asset_id": asset_id,
                "role": spec.role,
                "path": rel(representative_path),
                "icon_path": rel(icon_path),
                "derived_status": "ready",
            }

    teleport_arrival = decode_phase(
        "teleport",
        "arrival",
        TELEPORT_ARRIVAL_SPEC,
        libraries[TELEPORT_ARRIVAL_SPEC.library],
    )
    teleport_arrival["render"] = {
        **render_policy("teleport", "self_effect"),
        "attachment_policy": "caster_actor",
    }
    assets["teleport"]["animation"]["phase_id"] = "departure"
    assets["teleport"]["animation_phases"] = {
        "departure": assets["teleport"]["animation"],
        "arrival": teleport_arrival,
    }
    assets["teleport"]["phase_contract"] = "mirclient.space_move.hide_show2.v1"

    skill_coverage.update(NO_VISUAL_SKILLS)
    growth = json.loads(PROFESSION_GROWTH.read_text(encoding="utf-8"))
    expected = {
        skill_id
        for skill_id in growth["skillCatalog"]
        if skill_id.startswith("wizard.") or skill_id.startswith("taoist.")
    }
    if set(skill_coverage) != expected:
        raise RuntimeError(
            f"caster visual coverage mismatch missing={sorted(expected - set(skill_coverage))} "
            f"extra={sorted(set(skill_coverage) - expected)}"
        )

    skill_source = json.loads(SKILL_SOURCE.read_text(encoding="utf-8"))
    skill_rows = {
        row["skill_id"]: row
        for row in skill_source["skills"]
        if row["skill_id"] in skill_coverage
    }
    if set(skill_rows) != set(skill_coverage):
        raise RuntimeError("skills-lane source does not cover every caster visual identity")
    for skill_id, coverage in skill_coverage.items():
        row = skill_rows[skill_id]
        coverage["skills_contract"] = {
            "contract_id": "skills.mir2_176.vanilla_33.v1.0.1",
            "distribution_id": "project.hardcore.mir2_176_skill_sot.v1.0.1",
            "source_priority": {
                "lane": "skills",
                "tier": "primary",
                "order": 0,
                "weight": 100,
            },
            "activation": row.get("activation"),
            "target": row.get("target"),
            "geometry": row.get("geometry"),
            "timing": row.get("timing"),
        }

    source_files = [
        CLIENT_SOURCE / "magiceff.pas",
        CLIENT_SOURCE / "PlayScn.pas",
        CLIENT_SOURCE / "Actor.pas",
        CLIENT_SOURCE / "AxeMon.pas",
        CLIENT_SOURCE / "ClFunc.pas",
        CLIENT_SOURCE / "clEvent.pas",
    ]
    payload = {
        "schemaVersion": 4,
        "generator": "tools/build_caster_client_art.py exact primary-WIL animation decoder",
        "target_gender": "male_only",
        "sourcePolicy": "primary client pixels/rules only; no auxiliary fallback",
        "animationContract": "caster_skill_animation.v1",
        "renderContract": "caster_skill_render.v2",
        "iconPolicy": "active skill icons are deterministic transforms of one selected exact animation frame",
        "primarySource": {
            "distribution_id": "client.classic_raw_complete",
            "source_priority": {"lane": "client_assets", "tier": "primary", "order": 0, "weight": 100},
            "original_root": "Data",
            "custom_library_layout": False,
            "custom_library_evidence": (
                "client.classic_raw_complete/Data/Magic.wil matches the non-CUSTOMLIBFILE "
                "g_WMagicImages index layout; clEvent.pas FIREBURNBASE=1630 applies"
            ),
        },
        "skillIdentitySource": {
            "distribution_id": "project.hardcore.mir2_176_skill_sot.v1.0.1",
            "source_priority": {
                "lane": "skills",
                "tier": "primary",
                "order": 0,
                "weight": 100,
            },
            "contract_id": "skills.mir2_176.vanilla_33.v1.0.1",
            "original_path": "assets/data/vanilla_176/skills_source_of_truth_v1.json",
            "sha256": digest(SKILL_SOURCE),
        },
        "mappingSources": [
            {
                "distribution_id": "source.original_gameofmir.mirclient",
                "source_priority": {"lane": "client_rules", "tier": "primary", "order": 0, "weight": 100},
                "original_path": str(path.relative_to(CLIENT_SOURCE.parent)).replace("\\", "/"),
                "workspace_path": rel(path),
                "sha256": digest(path),
            }
            for path in source_files
        ],
        "primary_missing_evidence": [],
        "generated_candidates_retained": [],
        "fallbacks_used": [],
        "skillCoverage": {skill_id: skill_coverage[skill_id] for skill_id in sorted(skill_coverage)},
        "assets": assets,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"CASTER_CLIENT_ANIMATION_BUILT={len(assets)} "
        f"active_skills={len(skill_coverage) - len(NO_VISUAL_SKILLS)} fallbacks=0"
    )


if __name__ == "__main__":
    main()
