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

SPECS = {
    "fireball": ("Magic.wil", 10, "assets/art/characters/wizard/effects/arcane_projectile.png", ["wizard.fireball"], "projectile", "EffectBase[1]=0; fly frame base+10"),
    "great_fireball": ("Magic.wil", 410, "assets/art/characters/wizard/effects/great_fireball.png", ["wizard.great_fireball"], "projectile", "EffectBase[3]=400; fly frame base+10"),
    "lightning": ("Magic2.wil", 20, "assets/art/characters/wizard/effects/lightning.png", ["wizard.lightning"], "projectile", "GetEffectBase effect 9 selects Magic2; EffectBase[9]=20"),
    "exploding_flame": ("Magic.wil", 1660, "assets/art/characters/wizard/effects/area_burst.png", ["wizard.exploding_flame"], "area_effect", "PlayScn.NewMagic effect 21 explosion base 1660"),
    "fire_wall": ("Magic.wil", 1620, "assets/art/characters/wizard/effects/fire_wall.png", ["wizard.fire_wall"], "ground_effect", "EffectBase[20]=1620"),
    "ice_storm": ("Magic.wil", 3850, "assets/art/characters/wizard/effects/ice_storm.png", ["wizard.ice_storm"], "area_effect", "PlayScn.NewMagic effect 31 explosion base 3850"),
    "soul_fire_talisman": ("Magic.wil", 1160, "assets/art/characters/taoist/effects/soul_fire_talisman.png", ["taoist.soul_fire_talisman"], "projectile", "PlayScn.NewMagic mtExploBujauk constructor base 1160"),
    "binding_circle": ("Magic.wil", 1380, "assets/art/characters/taoist/effects/binding_circle.png", ["taoist.entrapment"], "area_effect", "EffectBase[14]=1380, ground nail/entrapment family"),
    "summon_skeleton": ("Mon3.wil", 0, "assets/art/characters/taoist/effects/summon_skeleton.png", ["taoist.summon_skeleton"], "summon", "Actor.aGetMonImg appearance 20 selects Mon3; skeleton manifest block base 0"),
    "summon_divine_beast": ("Mon18.wil", 350, "assets/art/characters/taoist/effects/summon_divine_beast.png", ["taoist.summon_divine_beast"], "summon", "PlayScn race 54/55 + Actor/AxeMon divine beast classes select Mon18; standing block 350"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    libraries: dict[str, tuple] = {}
    assets: dict[str, dict] = {}
    for asset_id, (library_name, index, relative_output, skill_ids, role, mapping_rule) in SPECS.items():
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
            "mapping_confidence": "A" if not asset_id.startswith("summon_") else "B",
            "pixel_confidence": "A",
        }
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
        "assets": assets,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CASTER_CLIENT_ART_BUILT={len(assets)} generated_fallbacks=0")


if __name__ == "__main__":
    main()
