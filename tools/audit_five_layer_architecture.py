#!/usr/bin/env python3
"""Fail when the formal five-layer manifests or dependency contracts drift."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYER_DIR = ROOT / "assets/data/layers"
EXPECTED = {
    "vanilla_core": "vanilla_core.json",
    "expansion_layer": "expansion_layer.json",
    "rule_systems": "rule_systems.json",
    "presentation_layer": "presentation_layer.json",
    "runtime_services": "runtime_services.json",
}


def resource_exists(path: str) -> bool:
    return path.startswith("res://") and (ROOT / path.removeprefix("res://")).exists()


errors: list[str] = []
manifests: dict[str, dict] = {}
for layer_id, filename in EXPECTED.items():
    path = LAYER_DIR / filename
    if not path.exists():
        errors.append(f"missing manifest: {filename}")
        continue
    data = json.loads(path.read_text(encoding="utf-8"))
    manifests[layer_id] = data
    if data.get("layer") != layer_id:
        errors.append(f"wrong layer id: {filename}")

vanilla = manifests.get("vanilla_core", {})
if vanilla.get("defaultEnabled") is not True or vanilla.get("immutableSource") is not True:
    errors.append("vanilla core must be enabled and immutable")
for dataset_id, path in vanilla.get("datasets", {}).items():
    if not resource_exists(path):
        errors.append(f"missing vanilla dataset {dataset_id}: {path}")

for package in manifests.get("expansion_layer", {}).get("packages", []):
    if package.get("defaultEnabled") is not False:
        errors.append(f"expansion must default off: {package.get('id')}")
    if package.get("mergePolicy") not in {"add_only", "explicit_override"}:
        errors.append(f"unsafe merge policy: {package.get('id')}")
    if package.get("data") and not resource_exists(package["data"]):
        errors.append(f"missing expansion data: {package['data']}")

for system_id, path in manifests.get("rule_systems", {}).get("systems", {}).items():
    if not resource_exists(path):
        errors.append(f"missing rule system {system_id}: {path}")

for schema_id, path in manifests.get("rule_systems", {}).get("schemas", {}).items():
    if not resource_exists(path):
        errors.append(f"missing rule schema {schema_id}: {path}")

runtime_snapshot = ROOT / "assets/data/runtime/merged_game_database.json"
if not runtime_snapshot.exists():
    errors.append("missing merged runtime database snapshot")
else:
    snapshot = json.loads(runtime_snapshot.read_text(encoding="utf-8"))
    if snapshot.get("mergeOrder") != ["vanilla_core", "expansion_layer", "user_override"]:
        errors.append("wrong runtime merge order")

for required in ["map_content.json", "spawn_rules.json", "npcs.json", "map_connections.json", "regional_drops.json", "profession_growth.json"]:
    path = ROOT / "assets/data/vanilla_176" / required
    if not path.exists():
        errors.append(f"missing migrated vanilla table: {required}")
    elif json.loads(path.read_text(encoding="utf-8")).get("layer") != "vanilla_core":
        errors.append(f"wrong migrated layer: {required}")

for visual_script in [ROOT / "scripts/player_visual.gd", ROOT / "scripts/monster_visual.gd"]:
    source = visual_script.read_text(encoding="utf-8")
    if 'preload("res://assets/art' in source or 'preload("res://assets/audio' in source:
        errors.append(f"presentation path leaked into logic: {visual_script.name}")

region_source = (ROOT / "scripts/region_content.gd").read_text(encoding="utf-8")
if "return WorldContent.map_content(map_id)" not in region_source:
    errors.append("RegionContent runtime is not delegated to WorldContent")

profession_source = (ROOT / "scripts/profession_rules.gd").read_text(encoding="utf-8")
if 'vanilla_dataset("professionGrowth")' not in profession_source:
    errors.append("ProfessionRules runtime is not data driven")

for required in [
    "scripts/layers/rules/modifier_effect_runtime.gd",
    "scripts/layers/rules/boss_mechanic_registry.gd",
    "scripts/layers/runtime/game_mode_service.gd",
    "assets/data/rules/boss_skill_library.json",
    "assets/data/game_modes.json",
]:
    if not (ROOT / required).exists():
        errors.append(f"missing architecture final resource: {required}")

modes = json.loads((ROOT / "assets/data/game_modes.json").read_text(encoding="utf-8"))
if set(modes.get("modes", {})) != {"classic_176", "enhanced_loot", "modded_expansion"}:
    errors.append("classic/enhanced/modded modes are incomplete")

save_source = (ROOT / "scripts/player_state.gd").read_text(encoding="utf-8")
for marker in ["content_packages", "content_schema_version", "game_mode_id"]:
    if marker not in save_source:
        errors.append(f"save compatibility marker missing: {marker}")

if errors:
    raise SystemExit("FIVE_LAYER_AUDIT_FAIL\n" + "\n".join(errors))
print(json.dumps({"status": "PASS", "layers": list(EXPECTED), "errors": 0}, ensure_ascii=False))
