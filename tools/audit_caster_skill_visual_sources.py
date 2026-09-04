#!/usr/bin/env python3
"""Audit every formal caster visual against the configured primary sources."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/caster_skill_visuals.json"
RAW_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
CLIENT_RULES = ROOT / "dev_art_sources/reference/original_gameofmir/MirClient"
SKILLS = ROOT / "assets/data/vanilla_176/skills_source_of_truth_v1.json"
UNIT_HALF = (32, 16)

# library, start, directions, frames, direction stride, milliseconds, playback,
# role, attachment, scale mode
EXPECTED = {
    "fireball": ("Magic.wil", 10, 16, 6, 10, 50, "loop", "projectile", "world_projectile", "fit_extent"),
    "repulsion_ring": ("Magic.wil", 900, 1, 10, 10, 60, "once", "self_area", "caster_actor", "source_pixels"),
    "temptation_light": ("Magic.wil", 1564, 1, 16, 10, 60, "once", "target_effect", "target_actor", "source_pixels"),
    "hellfire": ("Magic.wil", 930, 1, 6, 10, 50, "once", "line_effect", "world_anchor", "source_pixels"),
    "lightning": ("Magic2.wil", 10, 1, 6, 10, 50, "once", "target_effect", "world_anchor", "source_pixels"),
    "teleport": ("Magic.wil", 1590, 1, 10, 10, 30, "once", "self_effect", "world_anchor", "source_pixels"),
    "great_fireball": ("Magic.wil", 410, 16, 6, 10, 50, "loop", "projectile", "world_projectile", "fit_extent"),
    "exploding_flame": ("Magic.wil", 1660, 1, 20, 10, 80, "once", "area_effect", "world_anchor", "source_pixels"),
    "fire_wall": ("Magic.wil", 1630, 1, 6, 10, 40, "loop", "ground_effect", "world_anchor", "source_pixels"),
    "laser": ("Magic.wil", 970, 16, 6, 10, 50, "once", "line_effect", "caster_actor", "source_pixels"),
    "hell_lightning": ("Magic.wil", 1680, 1, 10, 10, 60, "once", "self_area", "caster_actor", "source_pixels"),
    "magic_shield": ("Magic.wil", 3880, 1, 10, 10, 60, "once", "self_effect", "caster_actor", "source_pixels"),
    "holy_word": ("Magic.wil", 3930, 1, 16, 10, 80, "once", "target_effect", "target_actor", "source_pixels"),
    "ice_storm": ("Magic.wil", 3850, 1, 20, 10, 80, "once", "area_effect", "world_anchor", "source_pixels"),
    "healing": ("Magic.wil", 370, 1, 10, 10, 80, "once", "target_effect", "target_actor", "source_pixels"),
    "poison": ("Magic.wil", 770, 1, 10, 10, 80, "once", "target_effect", "target_actor", "source_pixels"),
    "soul_fire_talisman": ("Magic.wil", 1160, 16, 3, 10, 50, "loop", "projectile", "world_projectile", "fit_extent"),
    "invisibility": ("Magic.wil", 1520, 1, 10, 10, 60, "once", "self_area", "caster_actor", "source_pixels"),
    "mass_invisibility": ("Magic.wil", 1540, 1, 10, 10, 50, "once", "area_effect", "world_anchor", "source_pixels"),
    "magic_defense": ("Magic.wil", 1320, 1, 16, 10, 50, "once", "area_effect", "world_anchor", "source_pixels"),
    "defense": ("Magic.wil", 1340, 1, 16, 10, 50, "once", "area_effect", "world_anchor", "source_pixels"),
    "revelation": ("Magic.wil", 3990, 1, 10, 10, 80, "once", "target_effect", "target_actor", "source_pixels"),
    "binding_circle": ("Magic.wil", 1380, 1, 10, 10, 60, "once", "area_effect", "world_anchor", "source_pixels"),
    "mass_healing": ("Magic.wil", 1800, 1, 10, 10, 80, "once", "area_effect", "world_anchor", "source_pixels"),
    "summon_skeleton": ("Mon3.wil", 0, 1, 4, 10, 200, "loop", "summon_actor_visual", "summon_actor", "source_pixels"),
    "summon_divine_beast": ("Mon18.wil", 350, 1, 4, 10, 160, "loop", "summon_actor_visual", "summon_actor", "source_pixels"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise AssertionError(message)


def verify_animation(
    asset_id: str,
    animation: dict,
    library_name: str,
    start: int,
    directions: int,
    frame_count: int,
    direction_stride: int,
    libraries: dict,
) -> int:
    if animation["direction_count"] != directions or animation["frame_count"] != frame_count:
        fail(f"{asset_id}: direction/frame count mismatch")
    sequences = animation["sequences"]
    if len(sequences) != directions:
        fail(f"{asset_id}: sequence count mismatch")
    data, palette, offsets, _info = libraries[library_name]
    checked = 0
    for source_slot, sequence in enumerate(sequences):
        expected_direction = round(source_slot * 16 / directions) % 16
        if sequence["source_direction_slot"] != source_slot:
            fail(f"{asset_id}: source direction slot order mismatch")
        if sequence["direction_index"] != expected_direction:
            fail(f"{asset_id}: canonical direction order mismatch")
        for frame_index, record in enumerate(sequence["frames"]):
            source_index = start + source_slot * direction_stride + frame_index
            if record["source_index"] != source_index:
                fail(f"{asset_id}: source index mismatch at {source_slot}/{frame_index}")
            source_image, sprite = decode_sprite(data, offsets[source_index], palette)
            png = ROOT / record["path"]
            if not png.is_file() or digest(png) != record["png_sha256"]:
                fail(f"{asset_id}: generated PNG hash mismatch at source {source_index}")
            with Image.open(png) as generated:
                if source_image.tobytes() != generated.convert("RGBA").tobytes():
                    fail(f"{asset_id}: generated pixels differ from primary WIL at {source_index}")
            expected_top_left = [sprite["x"] - UNIT_HALF[0], sprite["y"] - UNIT_HALF[1]]
            if record["top_left_from_world_anchor"] != expected_top_left:
                fail(f"{asset_id}: anchor offset mismatch at source {source_index}")
            if record["source_draw_offset"] != [sprite["x"], sprite["y"]]:
                fail(f"{asset_id}: source draw offset mismatch at source {source_index}")
            if record["pixel_size"] != [sprite["width"], sprite["height"]]:
                fail(f"{asset_id}: pixel size mismatch at source {source_index}")
            checked += 1
    return checked


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 4:
        fail("manifest schema is not v4")
    if manifest.get("renderContract") != "caster_skill_render.v2":
        fail("render contract mismatch")
    if manifest.get("primary_missing_evidence") or manifest.get("fallbacks_used"):
        fail("primary-only build unexpectedly records fallback")
    primary = manifest["primarySource"]
    if (
        primary["distribution_id"] != "client.classic_raw_complete"
        or primary["source_priority"]
        != {"lane": "client_assets", "tier": "primary", "order": 0, "weight": 100}
        or primary["custom_library_layout"] is not False
    ):
        fail("client asset primary identity/layout mismatch")

    source_text = (CLIENT_RULES / "clEvent.pas").read_text(encoding="latin-1")
    required_fire_tokens = [
        "{$IF CUSTOMLIBFILE = 1}",
        "FIREBURNBASE = 40;",
        "{$ELSE}",
        "FIREBURNBASE = 1630;",
        "FIREBURNBASE+((m_dwCurframe div 2) mod 6)",
    ]
    if not all(token in source_text for token in required_fire_tokens):
        fail("clEvent conditional fire-wall rule changed")

    for source in manifest["mappingSources"]:
        path = ROOT / source["workspace_path"]
        if source["distribution_id"] != "source.original_gameofmir.mirclient":
            fail("non-primary client rule source recorded")
        if digest(path) != source["sha256"]:
            fail(f"client rule source hash changed: {path}")

    skills_source = manifest["skillIdentitySource"]
    if (
        skills_source["distribution_id"]
        != "project.hardcore.mir2_176_skill_sot.v1.0.1"
        or skills_source["source_priority"]["lane"] != "skills"
        or skills_source["source_priority"]["tier"] != "primary"
        or digest(SKILLS) != skills_source["sha256"]
    ):
        fail("skills-lane primary identity/hash mismatch")
    skill_rows = {
        row["skill_id"]: row
        for row in json.loads(SKILLS.read_text(encoding="utf-8"))["skills"]
    }
    coverage = manifest["skillCoverage"]
    formal = {
        skill_id for skill_id, row in coverage.items()
        if row["status"] == "formal_primary_client_animation"
    }
    if len(formal) != 26 or coverage["taoist.spiritual_warfare"]["status"] != "no_runtime_visual":
        fail("formal/passive caster coverage mismatch")
    for skill_id, row in coverage.items():
        contract = row["skills_contract"]
        source_row = skill_rows[skill_id]
        if contract["target"] != source_row["target"]:
            fail(f"{skill_id}: target contract differs from skills primary")
        if contract["geometry"] != source_row["geometry"]:
            fail(f"{skill_id}: geometry contract differs from skills primary")
        if contract["timing"] != source_row["timing"]:
            fail(f"{skill_id}: timing contract differs from skills primary")

    libraries = {
        name: read_library(RAW_DATA / name)
        for name in {spec[0] for spec in EXPECTED.values()}
    }
    checked_frames = 0
    assets = manifest["assets"]
    if set(assets) != set(EXPECTED):
        fail("formal asset set differs from the 26 reviewed mappings")
    for asset_id, expected in EXPECTED.items():
        (
            library_name, start, directions, frames, stride, milliseconds,
            playback, role, attachment, scale_mode,
        ) = expected
        asset = assets[asset_id]
        animation = asset["animation"]
        if asset["original_path"] != f"Data/{library_name}":
            fail(f"{asset_id}: library mismatch")
        if digest(RAW_DATA / library_name) != asset["source_sha256"]:
            fail(f"{asset_id}: primary WIL hash mismatch")
        if (
            animation["frame_time_ms"] != milliseconds
            or animation["playback"] != playback
            or asset["role"] != role
            or asset["render"]["attachment_policy"] != attachment
            or asset["render"]["scale_mode"] != scale_mode
        ):
            fail(f"{asset_id}: timing/playback/role/render mismatch")
        checked_frames += verify_animation(
            asset_id, animation, library_name, start, directions, frames, stride, libraries
        )

    arrival = assets["teleport"]["animation_phases"]["arrival"]
    if arrival["frame_time_ms"] != 30 or arrival["render"]["attachment_policy"] != "caster_actor":
        fail("teleport arrival timing/attachment mismatch")
    checked_frames += verify_animation(
        "teleport_arrival", arrival, "Magic.wil", 1600, 1, 10, 10, libraries
    )
    fire_indices = [
        frame["source_index"]
        for sequence in assets["fire_wall"]["animation"]["sequences"]
        for frame in sequence["frames"]
    ]
    if fire_indices != list(range(1630, 1636)):
        fail("fire wall is not the ET_FIRE 1630..1635 family")
    skeleton_indices = [
        frame["source_index"]
        for sequence in assets["summon_skeleton"]["animation"]["sequences"]
        for frame in sequence["frames"]
    ]
    if skeleton_indices != [0, 1, 2, 3]:
        fail("skeleton stand loop includes sentinel frames")
    print(
        "CASTER_SKILL_PRIMARY_SOURCE_AUDIT_PASS "
        f"assets={len(assets)} formal_skills={len(formal)} "
        f"decoded_frames={checked_frames} fallbacks=0"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, ValueError) as error:
        print(f"CASTER_SKILL_PRIMARY_SOURCE_AUDIT_FAIL: {error}", file=sys.stderr)
        sys.exit(1)
