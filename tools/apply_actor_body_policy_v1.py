"""Apply actor_body_policy_v1 to the checked-in canonical monster catalog.

HC-BODY-2TIER-1P5-V1 bounded build step. The canonical generator
(build_canonical_monster_catalog.py) carries the same body_profile logic for
future full rebuilds, but a pre-existing checked-in source drift
(special_normal authority expects canonical_monster_classification_v1.json
sha256 BD7D..., the checked-in file hashes to FD7F... under the same lf_text
contract; identical on the main tree) blocks a full regeneration. This script
performs the additive body_profile bake on the current catalog without
touching any other field, and fails closed on any mismatch.

Usage: python tools/apply_actor_body_policy_v1.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
BODY_POLICY_PATH = ROOT / "assets/data/actor_body_policy_v1.json"


def lf_text_sha256(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    return hashlib.sha256(
        text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    ).hexdigest()


def main() -> None:
    policy = json.loads(BODY_POLICY_PATH.read_text(encoding="utf-8"))
    policy_sha = lf_text_sha256(BODY_POLICY_PATH)
    tiers = policy["tier_radii"]
    large_px = float(tiers["large"]["screen_radius_px"])
    small_px = float(tiers["small"]["screen_radius_px"])
    max_ground_gu = float(policy["invariants"]["max_body_ground_radius_gu"])
    iso_denominator = 32.0 * math.sqrt(2.0)
    named_large_ids = {
        int(item)
        for rule in policy.get("assignment_rules", [])
        if rule.get("rule_id") == "named_large_elite_family"
        for item in rule.get("monster_ids", [])
    }

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entries = catalog.get("entries", [])
    if not isinstance(entries, list) or not entries:
        raise RuntimeError("canonical catalog has no entries to stamp")
    if catalog.get("entries_by_id") is None:
        raise RuntimeError("canonical catalog is missing entries_by_id")

    counts = {"large": 0, "small": 0}
    table_rows = []
    for entry in entries:
        monster_id = int(entry["monster_id"])
        classification = str(entry.get("classification", ""))
        if classification == "boss":
            tier, rule_id = "large", "boss_large_body"
        elif monster_id in named_large_ids:
            tier, rule_id = "large", "named_large_elite_family"
        else:
            tier, rule_id = "small", "default_small"
        screen_radius_px = large_px if tier == "large" else small_px
        ground_radius_gu = screen_radius_px / iso_denominator
        if not (0.0 < ground_radius_gu <= max_ground_gu):
            raise RuntimeError(
                f"monster_id={monster_id} tier={tier} radius {ground_radius_gu} "
                f"violates the {max_ground_gu} GU bound"
            )
        profile = {
            "policy_id": str(policy["policy_id"]),
            "contract_id": str(policy["contract_id"]),
            "policy_sha256": policy_sha,
            "tier": tier,
            "assignment_rule": rule_id,
            "screen_radius_px": screen_radius_px,
            "ground_radius_gu": ground_radius_gu,
        }
        combat = entry.get("combat")
        if not isinstance(combat, dict):
            raise RuntimeError(f"monster_id={monster_id} has no combat section")
        if "body_profile" in combat:
            raise RuntimeError(
                f"monster_id={monster_id} already carries a body_profile; "
                "refusing to double-stamp"
            )
        combat["body_profile"] = profile
        by_id_entry = catalog.get("entries_by_id", {}).get(str(monster_id))
        if isinstance(by_id_entry, dict):
            by_id_combat = by_id_entry.get("combat")
            if not isinstance(by_id_combat, dict):
                raise RuntimeError(
                    f"entries_by_id[{monster_id}] has no combat section"
                )
            if "body_profile" in by_id_combat:
                raise RuntimeError(
                    f"entries_by_id[{monster_id}] already carries a body_profile"
                )
            by_id_combat["body_profile"] = profile
        counts[tier] += 1
        table_rows.append(
            {
                "monster_id": monster_id,
                "canonical_name": entry.get("canonical_name", ""),
                "classification": classification,
                "tier": tier,
                "assignment_rule": rule_id,
                "screen_radius_px": screen_radius_px,
                "ground_radius_gu": ground_radius_gu,
            }
        )

    # The by-id index was stamped alongside the entry list; verify both.
    for key, entry in catalog.get("entries_by_id", {}).items():
        combat = entry.get("combat", {})
        if "body_profile" not in combat:
            raise RuntimeError(f"entries_by_id[{key}] did not receive a body_profile")

    rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    CATALOG_PATH.write_text(rendered, encoding="utf-8", newline="\n")

    table = {
        "deliverable": "HC-BODY-2TIER-1P5-V1 per-ID body tier table (first deliverable)",
        "policy_id": policy["policy_id"],
        "policy_sha256": policy_sha,
        "catalog_path": "assets/data/runtime/canonical_monster_catalog.json",
        "summary": {
            "total": len(table_rows),
            "large": counts["large"],
            "small": counts["small"],
            "large_rule_counts": {
                "boss_large_body": sum(
                    1 for row in table_rows if row["assignment_rule"] == "boss_large_body"
                ),
                "named_large_elite_family": sum(
                    1 for row in table_rows if row["assignment_rule"] == "named_large_elite_family"
                ),
            },
            "note": "large_elite families are exactly the HC-BODY-2TIER-1P5-V1 section 5.2 named families; elites are not bulk-upgraded",
        },
        "rows": table_rows,
    }
    table_path = ROOT / "docs/monster_combat_r1/body_tier_table.json"
    table_path.parent.mkdir(parents=True, exist_ok=True)
    table_path.write_text(
        json.dumps(table, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(
        f"stamped {len(table_rows)} entries: "
        f"large={counts['large']} small={counts['small']}; table -> {table_path}"
    )


if __name__ == "__main__":
    main()
