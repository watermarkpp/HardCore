#!/usr/bin/env python3
"""Build self-contained male wizard/taoist profession packages from traced project data."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS_PATH = ROOT / "assets/data/vanilla_176/skills.json"
GROWTH_PATH = ROOT / "assets/data/vanilla_176/profession_growth.json"
RULES_PATH = ROOT / "assets/data/vanilla_176/profession_combat_rules.json"
VISUALS_PATH = ROOT / "assets/data/caster_skill_visuals.json"
OUTPUT_DIR = ROOT / "assets/data/vanilla_176/profession_packages"

PROFESSIONS = {
    "wizard": {
        "display_name": "法师",
        "package_id": "profession.package.wizard.v1",
        "growth_formula": {
            "formula_id": "wizard.server_setup.hp_mp.v1",
            "max_hp": "14 + round(((level / hp_divisor + hp_rate) * level))",
            "max_mp": "13 + round((level / 5 + 2) * 2.2 * level)",
            "hp_divisor": 15.0,
            "hp_rate": 1.8,
            "attack_min": 1,
            "attack_max": 3,
            "source": "Server.MirDB/Setup/LevelValueOfWizardHP+LevelValueOfWizardHPRate",
        },
    },
    "taoist": {
        "display_name": "道士",
        "package_id": "profession.package.taoist.v1",
        "growth_formula": {
            "formula_id": "taoist.server_setup.hp_mp.v1",
            "max_hp": "14 + round(((level / hp_divisor + hp_rate) * level))",
            "max_mp": "13 + round(((level / mp_divisor) * 2.2 * level))",
            "hp_divisor": 6.0,
            "hp_rate": 2.5,
            "mp_divisor": 8.0,
            "attack_min": 1,
            "attack_max": 4,
            "source": "Server.MirDB/Setup/LevelValueOfTaosHP+LevelValueOfTaosHPRate+LevelValueOfTaosMP",
        },
    },
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    skills_data = read_json(SKILLS_PATH)
    growth = read_json(GROWTH_PATH)
    rules = read_json(RULES_PATH)
    visuals = read_json(VISUALS_PATH)
    source_files = {
        "skills": {
            "path": "assets/data/vanilla_176/skills.json",
            "sha256": sha256(SKILLS_PATH),
        },
        "growth": {
            "path": "assets/data/vanilla_176/profession_growth.json",
            "sha256": sha256(GROWTH_PATH),
        },
        "combat_rules": {
            "path": "assets/data/vanilla_176/profession_combat_rules.json",
            "sha256": sha256(RULES_PATH),
        },
        "visuals": {
            "path": "assets/data/caster_skill_visuals.json",
            "sha256": sha256(VISUALS_PATH),
        },
    }
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    total_skills = 0
    package_index = []
    for profession_id, definition in PROFESSIONS.items():
        rows = [
            row
            for row in skills_data["records"]
            if row.get("profession_id") == profession_id
        ]
        grouped: dict[str, list[dict]] = {}
        for row in rows:
            grouped.setdefault(row["skill_id"], []).append(row)
        package_skills = {}
        for skill_id in sorted(grouped):
            level_rows = sorted(grouped[skill_id], key=lambda row: row["skillLevel"])
            if [row["skillLevel"] for row in level_rows] != [0, 1, 2, 3]:
                raise ValueError(f"{skill_id} does not contain levels 0-3")
            display_name = level_rows[0]["display_name"]
            combat_profile = growth["skillProfiles"][display_name]
            action_profile = dict(
                growth["castDefaults"][combat_profile.get("cast_type", "projectile")]
            )
            action_profile.update(combat_profile)
            coverage = visuals["skillCoverage"].get(skill_id, {})
            asset_id = coverage.get("asset_id", "")
            visual_profile = dict(coverage)
            if asset_id:
                visual_profile.update(visuals["assets"][asset_id])
                visual_profile["asset_id"] = asset_id
            package_skills[skill_id] = {
                "skill_id": skill_id,
                "profession_id": profession_id,
                "display_name": display_name,
                "levels": [
                    {
                        key: row.get(key)
                        for key in (
                            "skillLevel",
                            "requiredCharacterLevel",
                            "trainingPoints",
                            "manaCost",
                            "delay",
                            "effect",
                            "source_trace",
                            "service_candidate",
                        )
                    }
                    for row in level_rows
                ],
                "combat_profile": combat_profile,
                "action_profile": action_profile,
                "combat_rule": rules[profession_id]["skills"][skill_id],
                "visual_profile": visual_profile,
            }
        total_skills += len(package_skills)
        package = {
            "schemaVersion": 1,
            "package_id": definition["package_id"],
            "profession_id": profession_id,
            "display_name": definition["display_name"],
            "gender_policy": "male_only",
            "character_creation": {
                "allowed_genders": ["male"],
                "initial_skill_ids": [],
                "learning_mode": "skill_book_then_usage_training",
            },
            "growth": {
                "runtime_formula": definition["growth_formula"],
                "legacy_candidate": growth["baseStats"][definition["display_name"]],
                "source_priority": {
                    "lane": "server_rules",
                    "tier": "primary",
                    "order": 0,
                    "weight": 100,
                },
            },
            "runtime": {
                "package_contract": "caster_profession_package.v1",
                "state_contract": "caster_profession_state.v1",
                "cast_contract": "caster_skill_execution.v1",
                "cooldown_policy": "client_action_profile_selected; server candidate retained per level",
                "resource_policy": "mana plus explicit taoist material costs",
                "training_policy": {
                    "points_per_accepted_cast": 1,
                    "status": "project_adapter_C_candidate",
                    "reason": "MagicInfo supplies level thresholds but the recovered source set does not expose a separate per-cast increment",
                },
            },
            "skills": package_skills,
            "source_files": source_files,
            "source_policy": {
                "stable_ids": "authoritative",
                "display_names": "Chinese display aliases only",
                "magic_info": "server.crystal.cjlaaa B/C candidate retained per level",
                "visuals": "primary client pixels only; generated fallback forbidden",
            },
        }
        output_path = OUTPUT_DIR / f"{profession_id}.json"
        output_path.write_text(
            json.dumps(package, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        package_index.append(
            {
                "package_id": definition["package_id"],
                "profession_id": profession_id,
                "display_name": definition["display_name"],
                "gender_policy": "male_only",
                "resource_path": f"res://assets/data/vanilla_176/profession_packages/{profession_id}.json",
                "skill_count": len(package_skills),
            }
        )
    (OUTPUT_DIR / "index.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "registration_contract": "caster_profession_registration.v1",
                "packages": package_index,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"CASTER_PROFESSION_PACKAGES_BUILT=2 skills={total_skills}")


if __name__ == "__main__":
    main()
