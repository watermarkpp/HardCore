"""Compile the display-only exact-ID palette; never modify gameplay tiers."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "assets/data/ui/item_name_rarity_policy_v2.json"
OUTPUT = ROOT / "assets/data/ui/item_name_rarity_v1.json"


def source_hash(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def build():
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    source = ROOT / policy["membership_source"]
    records = json.loads(source.read_text(encoding="utf-8"))["records"]
    equipment_source = ROOT / policy["equipment_membership_source"]
    equipment = json.loads(equipment_source.read_text(encoding="utf-8"))["records"]
    tier_ids = {row["canonical_item_id"] for row in records}
    records += [{"canonical_item_id": row["itemId"], "canonical_name": row["name"], "tier": "UNCLASSIFIED"}
                for row in equipment if row["itemId"] not in tier_ids]
    records.sort(key=lambda row: row["canonical_item_id"])
    result = {}
    for row in records:
        key = str(row["canonical_item_id"])
        if key in result:
            raise ValueError(f"Duplicate item ID {key}")
        tier = row["tier"]
        style = policy["exact_id_overrides"].get(key, policy["tier_styles"].get(tier, "default"))
        if style not in policy["palette"]:
            raise ValueError(f"Unknown palette entry {style}")
        result[key] = {"canonical_name": row["canonical_name"], "source_tier": tier, "name_style": style}
    missing = set(policy["exact_id_overrides"]) - result.keys()
    if missing:
        raise ValueError(f"Unknown override IDs {sorted(missing)}")
    output = {
        "schema_version": 1, "contract_id": "ui.item_name.rarity.v1",
        "scope": "name_color_in_ui_ground_and_pickup_no_gameplay_mutation",
        "membership_source": policy["membership_source"],
        "hash_encoding": "utf8_lf",
        "membership_source_sha256": source_hash(source),
        "equipment_membership_source": policy["equipment_membership_source"],
        "equipment_membership_source_sha256": source_hash(equipment_source),
        "presentation_policy": POLICY.relative_to(ROOT).as_posix(),
        "presentation_policy_sha256": source_hash(POLICY),
        "palette": policy["palette"], "records": result,
    }
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ITEM_NAME_RARITY_BUILD_PASS records={len(result)}")


if __name__ == "__main__":
    build()
