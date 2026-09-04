#!/usr/bin/env python3
"""Build the exact-ID Monster.DB combat authority for the canonical catalog.

The local 1.76 Paradox Monster.DB is the project's highest-priority raw combat
source (priority A).  Its rows are bound to canonical monster_ids by exact GBK
name against the 21CQ identity namespace (``vanilla_176/monsters.json``) and
cross-checked field-by-field; no base-name, suffix, alias, or substring
inference participates.  Rows that cannot be bound exactly are omitted and
remain fail-closed.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

ART_SPEC = importlib.util.spec_from_file_location(
    "build_complete_monster_client_art", ROOT / "tools" / "build_complete_monster_client_art.py"
)
assert ART_SPEC is not None and ART_SPEC.loader is not None
ART = importlib.util.module_from_spec(ART_SPEC)
ART_SPEC.loader.exec_module(ART)

VANILLA_PATH = ROOT / "assets" / "data" / "vanilla_176" / "monsters.json"
OUTPUT_PATH = ROOT / "assets" / "data" / "canonical_monster_combat_source_v1.json"

# Canonical id -> Monster.DB Name override for the small set where the 21CQ
# visible name differs from the raw DB name but the identity is explicit.
DB_NAME_OVERRIDES = dict(ART.DB_NAME_OVERRIDES)

FIELD_MAP = {
    "Lvl": "level",
    "Exp": "exp",
    "HP": "hp",
    "AC": "defense",
    "MAC": "magic_defense",
    "DC": "attack_min",
    "DCMAX": "attack_max",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    rows, meta = ART.read_monster_db()
    db_by_name: dict[str, list[int]] = {}
    for index, row in enumerate(rows):
        db_by_name.setdefault(row["Name"], []).append(index)

    vanilla = json.loads(VANILLA_PATH.read_text(encoding="utf-8"))["records"]
    records: dict[str, dict[str, Any]] = {}
    bound = 0
    cross_verified = 0
    unbound: list[dict[str, Any]] = []

    for vr in vanilla:
        mid = int(vr["monsterId"])
        name = str(vr["name"])
        db_name = DB_NAME_OVERRIDES.get(mid, name)
        hits = db_by_name.get(db_name)
        if not hits:
            unbound.append({"monster_id": mid, "name": name})
            continue
        row = rows[hits[0]]
        db_vals = tuple(int(row[f]) for f in ("Lvl", "Exp", "HP", "AC", "MAC", "DC", "DCMAX"))
        v_vals = tuple(int(vr.get(k, 0)) for k in ("level", "exp", "hp", "defense", "magicDefense", "attackMin", "attackMax"))
        cross_ok = db_vals == v_vals
        record = {
            "monster_id": mid,
            "source_name": row["Name"],
            "level": int(row["Lvl"]),
            "exp": int(row["Exp"]),
            "hp": int(row["HP"]),
            "defense": int(row["AC"]),
            "magic_defense": int(row["MAC"]),
            "attack_min": int(row["DC"]),
            "attack_max": int(row["DCMAX"]),
            "ai_code": int(row["Race"]),
            "view_range": int(row["CoolEye"]),
            "image": int(row["RaceImg"]),
            "appearance": int(row["Appr"]),
            "undead": int(row["Undead"]),
            "attack_interval_ms": int(row["ATTACK_SPD"]),
            "move_interval_ms": int(row["WALK_SPD"]),
            "hit": int(row["HIT"]),
            "speed": int(row["SPEED"]),
            "cross_verified_21cq": cross_ok,
            "binding": "exact_name" if db_name == name else "explicit_override",
        }
        records[str(mid)] = record
        bound += 1
        if cross_ok:
            cross_verified += 1

    payload = {
        "schema_version": 1,
        "identity_key": "monster_id",
        "source": meta["path"],
        "source_sha256": meta["sha256"],
        "distribution": "source.original_gameofmir.monster_db_176",
        "tier": "primary",
        "resolution_policy": "exact_id_name_binding + 21cq_cross_verify; no suffix/alias/substring inference",
        "binding": {
            "bound_count": bound,
            "cross_verified_21cq_count": cross_verified,
            "unbound": unbound,
        },
        "records_by_monster_id": records,
    }
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MONSTER_COMBAT_SOURCE_BUILD_PASS bound={bound} cross_verified={cross_verified} unbound={len(unbound)}")
    print(f"output={OUTPUT_PATH}")


if __name__ == "__main__":
    main()
