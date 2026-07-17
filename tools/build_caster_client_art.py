#!/usr/bin/env python3
"""Extract exact caster/summon pixels from the primary classic client WILs."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
CLIENT_SOURCE = ROOT / "dev_art_sources/reference/original_gameofmir/MirClient"
OUTPUT = ROOT / "assets/data/caster_skill_visuals.json"
PROFESSION_GROWTH = ROOT / "assets/data/vanilla_176/profession_growth.json"

SPECS = {
    "fireball": ("Magic.wil", 10, "assets/art/characters/wizard/effects/arcane_projectile.png", ["wizard.fireball"], "projectile", "EffectBase effect 1 base 0 + FLYBASE 10", "A"),
    "repulsion_ring": ("Magic.wil", 900, "assets/art/characters/wizard/effects/repulsion_ring.png", ["wizard.repulsion_ring"], "self_area", "EffectBase effect 6 explicitly labels repulsion ring at 900", "A"),
    "temptation_light": ("Magic.wil", 1564, "assets/art/characters/wizard/effects/temptation_light.png", ["wizard.temptation_light"], "target_effect", "PlayScn.NewMagic effect 18 overrides explosion base to 1564", "A"),
    "hellfire": ("Magic.wil", 930, "assets/art/characters/wizard/effects/hellfire.png", ["wizard.hellfire"], "line_effect", "PlayScn.NewMagic mtFireGun constructs TFireGunEffect at base 930", "A"),
    "lightning": ("Magic2.wil", 10, "assets/art/characters/wizard/effects/lightning.png", ["wizard.lightning"], "target_effect", "PlayScn.NewMagic mtThunder explicitly constructs Magic2 TThuderEffect at 10", "A"),
    "teleport": ("Magic.wil", 1590, "assets/art/characters/wizard/effects/teleport.png", ["wizard.teleport"], "self_effect", "EffectBase effect 19 explicitly labels teleport at 1590", "A"),
    "great_fireball": ("Magic.wil", 410, "assets/art/characters/wizard/effects/great_fireball.png", ["wizard.great_fireball"], "projectile", "EffectBase effect 3 base 400 + FLYBASE 10", "A"),
    "exploding_flame": ("Magic.wil", 1660, "assets/art/characters/wizard/effects/area_burst.png", ["wizard.exploding_flame"], "area_effect", "PlayScn.NewMagic effect 21 explosion base 1660", "A"),
    "fire_wall": ("Magic.wil", 1620, "assets/art/characters/wizard/effects/fire_wall.png", ["wizard.fire_wall"], "ground_effect", "EffectBase effect 20 explicitly labels fire wall at 1620", "A"),
    "laser": ("Magic.wil", 970, "assets/art/characters/wizard/effects/laser.png", ["wizard.laser"], "line_effect", "PlayScn.NewMagic mtLightingThunder explicitly constructs TLightingThunder at 970", "A"),
    "hell_lightning": ("Magic.wil", 1680, "assets/art/characters/wizard/effects/hell_lightning.png", ["wizard.hell_lightning"], "self_area", "EffectBase effect 22 explicitly labels hell lightning at 1680", "A"),
    "magic_shield": ("Magic.wil", 3880, "assets/art/characters/wizard/effects/magic_shield.png", ["wizard.magic_shield"], "self_effect", "EffectBase effect 29 explicitly labels magic shield at 3880", "A"),
    "holy_word": ("Magic.wil", 3930, "assets/art/characters/wizard/effects/holy_word.png", ["wizard.holy_word"], "target_effect", "PlayScn.NewMagic effect 30 explosion base 3930", "A"),
    "ice_storm": ("Magic.wil", 3850, "assets/art/characters/wizard/effects/ice_storm.png", ["wizard.ice_storm"], "area_effect", "PlayScn.NewMagic effect 31 explosion base 3850", "A"),
    "healing": ("Magic.wil", 200, "assets/art/characters/taoist/effects/healing.png", ["taoist.healing"], "target_effect", "EffectBase effect 2 explicitly labels healing at 200", "A"),
    "poison": ("Magic.wil", 600, "assets/art/characters/taoist/effects/poison.png", ["taoist.poison"], "target_effect", "EffectBase effect 4 explicitly labels poison at 600", "A"),
    "soul_fire_talisman": ("Magic.wil", 1160, "assets/art/characters/taoist/effects/soul_fire_talisman.png", ["taoist.soul_fire_talisman"], "projectile", "PlayScn.NewMagic mtExploBujauk constructor base 1160", "A"),
    "summon_skeleton": ("Mon3.wil", 0, "assets/art/characters/taoist/effects/summon_skeleton.png", ["taoist.summon_skeleton"], "summon", "Actor.aGetMonImg appearance 20 selects Mon3; skeleton manifest block base 0", "B"),
    "invisibility": ("Magic.wil", 1520, "assets/art/characters/taoist/effects/invisibility.png", ["taoist.invisibility", "taoist.mass_invisibility"], "self_area", "EffectBase effect 16 explicitly labels invisibility; group variant reuses the same primary family", "B"),
    "magic_defense": ("Magic.wil", 1320, "assets/art/characters/taoist/effects/magic_defense.png", ["taoist.magic_defense"], "area_effect", "TBujaukGroundEffect magic number 11 uses base 1160 + 16*10", "A"),
    "defense": ("Magic.wil", 1340, "assets/art/characters/taoist/effects/defense.png", ["taoist.defense"], "area_effect", "TBujaukGroundEffect magic number 12 uses base 1160 + 18*10", "A"),
    "revelation": ("Magic.wil", 3990, "assets/art/characters/taoist/effects/revelation.png", ["taoist.revelation"], "target_effect", "PlayScn.NewMagic effect 26 explosion base 3990", "A"),
    "binding_circle": ("Magic.wil", 1380, "assets/art/characters/taoist/effects/binding_circle.png", ["taoist.entrapment"], "area_effect", "EffectBase effect 14 explicitly labels ground nail/entrapment at 1380", "A"),
    "mass_healing": ("Magic.wil", 1800, "assets/art/characters/taoist/effects/mass_healing.png", ["taoist.mass_healing"], "area_effect", "PlayScn.NewMagic effect 27 explosion base 1800", "A"),
    "summon_divine_beast": ("Mon18.wil", 350, "assets/art/characters/taoist/effects/summon_divine_beast.png", ["taoist.summon_divine_beast"], "summon", "PlayScn race 54/55 + Actor/AxeMon divine beast classes select Mon18; standing block 350", "B"),
}

NO_VISUAL_SKILLS = {
    "taoist.spiritual_warfare": {
        "status": "no_runtime_visual",
        "reason": "Passive accuracy skill; no cast event is emitted by the classic runtime.",
        "source_original_path": "M2Server/Magic.pas",
    },
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    libraries: dict[str, tuple] = {}
    assets: dict[str, dict] = {}
    skill_coverage: dict[str, dict] = {}
    for asset_id, (library_name, index, relative_output, skill_ids, role, mapping_rule, mapping_confidence) in SPECS.items():
        library_path = DATA / library_name
        if library_name not in libraries:
            libraries[library_name] = read_library(library_path)
        data, palette, offsets, library_info = libraries[library_name]
        image, sprite = decode_sprite(data, offsets[index], palette)
        output_path = ROOT / relative_output
        output_path.parent.mkdir(parents=True, exist_ok=True)
        image.save(output_path)
        assets[asset_id] = {
            "skill_ids": skill_ids,
            "role": role,
            "path": relative_output,
            "distribution_id": "client.classic_raw_complete",
            "source_priority": {"lane": "client_assets", "tier": "primary", "order": 0, "weight": 100},
            "original_path": f"Data/{library_name}",
            "source_sha256": digest(library_path),
            "source_index": index,
            "source_offset": sprite["offset"],
            "source_draw_offset": [sprite["x"], sprite["y"]],
            "pixel_size": [sprite["width"], sprite["height"]],
            "library_image_count": library_info["image_count"],
            "mapping_rule": mapping_rule,
            "mapping_confidence": mapping_confidence,
            "pixel_confidence": "A",
        }
        for skill_id in skill_ids:
            if skill_id in skill_coverage:
                raise RuntimeError(f"duplicate visual coverage for {skill_id}")
            skill_coverage[skill_id] = {
                "status": "formal_primary_client_pixel",
                "asset_id": asset_id,
                "role": role,
                "path": relative_output,
            }
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
    source_files = [CLIENT_SOURCE / "magiceff.pas", CLIENT_SOURCE / "PlayScn.pas", CLIENT_SOURCE / "Actor.pas", CLIENT_SOURCE / "AxeMon.pas"]
    payload = {
        "schemaVersion": 2,
        "generator": "tools/build_caster_client_art.py exact WIL decoder",
        "target_gender": "male_only",
        "sourcePolicy": "primary client pixels only; generated fallback requires per-asset primary-missing evidence",
        "primarySource": {
            "distribution_id": "client.classic_raw_complete",
            "source_priority": {"lane": "client_assets", "tier": "primary", "order": 0, "weight": 100},
            "original_root": "Data",
        },
        "mappingSources": [
            {
                "distribution_id": "source.original_gameofmir.mirclient",
                "source_priority": {"lane": "client_rules", "tier": "primary", "order": 0, "weight": 100},
                "original_path": str(path.relative_to(CLIENT_SOURCE.parent)).replace("\\", "/"),
                "workspace_path": str(path.relative_to(ROOT)).replace("\\", "/"),
                "sha256": digest(path),
            }
            for path in source_files
        ],
        "primary_missing_evidence": [],
        "generated_candidates_retained": [],
        "skillCoverage": {skill_id: skill_coverage[skill_id] for skill_id in sorted(skill_coverage)},
        "assets": assets,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CASTER_CLIENT_ART_BUILT={len(assets)} generated_fallbacks=0")


if __name__ == "__main__":
    main()
