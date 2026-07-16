#!/usr/bin/env python3
"""Build immutable Vanilla tables and a traceable merged runtime snapshot."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/legend176_data.json"
VANILLA = ROOT / "assets/data/vanilla_176"
RUNTIME = ROOT / "assets/data/runtime"

TABLES = {
    "maps": "maps.json", "monsters": "monsters.json", "bosses": "bosses.json",
    "items": "items.json", "skills": "skills.json", "drops": "drops.json", "tasks": "quests.json",
}

EXPERIENCE = {
    1: 100, 2: 200, 3: 300, 4: 400, 5: 600, 6: 900, 7: 1200, 8: 1700, 9: 2500,
    10: 6000, 11: 8000, 12: 10000, 13: 15000, 14: 30000, 15: 40000, 16: 50000,
    17: 70000, 18: 100000, 19: 120000, 20: 140000, 21: 250000, 22: 300000,
}


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def tagged(record: dict) -> dict:
    result = dict(record)
    result.setdefault("contentLayer", "vanilla_core")
    result.setdefault("source", "vanilla_176")
    result.setdefault("confidence", "A" if record.get("source") else "B")
    result["editable"] = False
    return result


source = json.loads(SOURCE.read_text(encoding="utf-8"))
snapshot: dict[str, object] = {
    "schemaVersion": 1,
    "mergeOrder": ["vanilla_core", "expansion_layer", "user_override"],
    "activeExpansions": [],
    "source": "five_layer_build",
}
for key, filename in TABLES.items():
    rows = [tagged(row) for row in source.get(key, [])]
    write(VANILLA / filename, {"schemaVersion": 1, "layer": "vanilla_core", "table": key, "records": rows})
    snapshot[key] = rows

write(VANILLA / "exp_table.json", {
    "schemaVersion": 1, "layer": "vanilla_core", "source": "verified_1_to_22",
    "confidence": "A", "editable": False,
    "records": [{"level": level, "requiredExperience": value} for level, value in EXPERIENCE.items()],
})
for name, table in {
    "spawn_rules.json": "spawn_rules", "npcs.json": "npcs", "map_connections.json": "map_connections",
    "profession_growth.json": "profession_growth",
}.items():
    target = VANILLA / name
    if target.exists():
        continue
    write(target, {
        "schemaVersion": 1, "layer": "vanilla_core", "table": table, "records": [],
        "migrationStatus": "legacy_adapter", "legacyOwner": "scripts/region_content.gd" if table != "profession_growth" else "scripts/profession_rules.gd",
        "policy": "迁移完成前由只读兼容适配器提供；禁止扩展层写入本文件。",
    })

write(RUNTIME / "merged_game_database.json", snapshot)
print(json.dumps({"vanillaTables": len(TABLES) + 5, "runtimeCounts": {key: len(snapshot[key]) for key in TABLES}}, ensure_ascii=False))
