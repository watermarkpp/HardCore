#!/usr/bin/env python3
"""Build the tracked merchant catalog from primary Crystal NPC scripts.

Trade's trailing integer is a pack count, not stock.  Duplicate lines are kept
as distinct offers because the primary scripts use them for pack choices.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIMARY = ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa"
NPC_ROOT = PRIMARY / "Envir/NPCs"
ITEM_CATALOG = ROOT / "assets/data/service_item_catalog.json"
EQUIPMENT_ATTRIBUTE_MASTER = ROOT / "assets/data/equipment_attribute_master.json"
BOOK_SHOP_POLICY = ROOT / "assets/data/official_book_shop_policy_v1.json"
OUTPUT = ROOT / "assets/data/merchant_catalog_v1.json"

RUNTIME_MERCHANTS = {
    "general": ("npc.4.001", "merchant.server.crystal.cjlaaa.33", "BichonProvince/BichonWall/Grocery-0.txt"),
    "starter_gear": ("npc.4.002", "merchant.server.crystal.cjlaaa.46", "BichonProvince/BichonWall/Blacksmith-0103.txt"),
    "books": ("npc.4.003", "merchant.server.crystal.cjlaaa.45", "BichonProvince/BichonWall/BookStore-0104.txt"),
    "medicine": ("npc.expansion.bich_pharmacist", "merchant.server.crystal.cjlaaa.29", "BichonProvince/BichonWall/Potion-0108.txt"),
}

# Explicit gameplay overrides requested by the project owner.  The primary
# [Trade] lines remain recorded in excludedOffers so the runtime catalog stays
# auditable instead of pretending the source NPC script contained our subset.
EXCLUDED_OFFER_NAMES = {
    "general": {"蜡烛", "火把", "护身符"},
    # These are private-server potion extensions.  The official shop keeps
    # only the small/medium/large health and mana potions, each as a single
    # bottle offer and a 20-bottle purchase option.
    "medicine": {
        "金疮药(特大)",
        "魔法药(特大)",
        "超级金疮药",
        "超级魔法药",
    },
}

# The primary blacksmith script contains these legacy bow lines, but the
# project item/runtime catalog does not support them as buyable gameplay
# instances. Keep them in excludedOffers for source auditability while
# removing them from the live starter_gear stock.  The parser below also
# rejects any other equipment reference missing from the project-owned
# equipment_attribute_master, which covers private-server additions such as
# 虎牙刀/暴虎刀/音速刀 without relying on names alone.
EXCLUDED_OFFER_NAMES["starter_gear"] = {
    "WoodenBow",
    "EbonyBow",
    "ShortBow",
    "BoneBow",
    "CompoundBow",
}

MEDICINE_ALLOWED_NAMES = {
    "金疮药(小量)",
    "魔法药(小量)",
    "金疮药(中量)",
    "魔法药(中量)",
    "金疮药(大量)",
    "魔法药(大量)",
}
MEDICINE_ALLOWED_PACK_COUNTS = {1, 20}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sections(text: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    active = ""
    for raw in text.splitlines():
        line = raw.strip()
        match = re.fullmatch(r"\[([^]]+)\]", line)
        if match:
            active = match.group(1).lower()
            result.setdefault(active, [])
        elif active and line and not line.startswith(";"):
            result[active].append(line)
    return result


def section_line_entries(text: str, section_name: str) -> list[dict]:
    """Return source ordinals and physical lines for one audited section."""
    result: list[dict] = []
    active = ""
    for source_line, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        match = re.fullmatch(r"\[([^]]+)\]", line)
        if match:
            active = match.group(1).lower()
        elif active == section_name.lower() and line and not line.startswith(";"):
            result.append({
                "value": line,
                "sourceOrdinal": len(result) + 1,
                "sourceLine": source_line,
            })
    return result


def _require_evidence_hash(record: dict) -> Path:
    path = ROOT / str(record.get("path", ""))
    if not path.is_file():
        raise ValueError(f"book-shop evidence missing: {path}")
    expected = str(record.get("sha256", "")).lower()
    actual = sha256_file(path)
    if not expected or actual != expected:
        raise ValueError(f"book-shop evidence hash drift: {path} expected {expected}, got {actual}")
    return path


def load_book_shop_policy() -> dict:
    policy = json.loads(BOOK_SHOP_POLICY.read_text(encoding="utf-8-sig"))
    if policy.get("contractId") != "gameplay.official_book_shop.v1":
        raise ValueError("unsupported official book-shop policy contract")

    _require_evidence_hash(policy["sourcePriorityPolicy"])
    skill_master_path = _require_evidence_hash(policy["formalVanillaSkillMaster"])
    candidate_record = policy["primaryCandidateTrade"]
    candidate_path = _require_evidence_hash(candidate_record)
    candidate_entries = section_line_entries(candidate_path.read_text(encoding="utf-8-sig"), "trade")
    candidate_names = [entry["value"] for entry in candidate_entries]
    if len(candidate_names) != int(candidate_record.get("tradeLineCount", -1)):
        raise ValueError("BookStore-0104 trade-line count drift")

    original_audit = policy["originalGameofmirMerchantDataAudit"]
    original_root = ROOT / str(original_audit.get("searchRoot", ""))
    unexpected_original_data = [
        path
        for pattern in original_audit.get("searchedPatterns", [])
        for path in original_root.glob(str(pattern))
        if path.is_file()
    ]
    if unexpected_original_data:
        raise ValueError(
            "original_gameofmir merchant data is no longer missing; audit it before regenerating: "
            + ", ".join(path.as_posix() for path in unexpected_original_data[:5])
        )
    for reference in original_audit.get("engineReferences", []):
        _require_evidence_hash(reference)

    conservative_name_sets: list[set[str]] = []
    conservative_paths: list[str] = []
    for record in policy.get("conservativeShopEvidence", []):
        path = _require_evidence_hash(record)
        conservative_paths.append(path.relative_to(ROOT).as_posix())
        conservative_name_sets.append(set(sections(path.read_text(encoding="utf-8-sig")).get("trade", [])))
    if not conservative_name_sets:
        raise ValueError("official book-shop policy has no conservative shop evidence")

    skill_master = json.loads(skill_master_path.read_text(encoding="utf-8-sig"))
    formal_skills = {
        str(record.get("display_name", "")): record
        for record in skill_master.get("skills", [])
        if str(record.get("display_name", ""))
    }
    live_names = list(policy.get("officialShopLive", []))
    computed_live = [
        name
        for name in candidate_names
        if name in formal_skills and all(name in names for names in conservative_name_sets)
    ]
    if live_names != computed_live:
        raise ValueError(f"official_shop_live policy drift: expected {computed_live}, got {live_names}")

    advanced_records = list(policy.get("officialAdvancedDropOnly", []))
    advanced_names = [str(record.get("name", "")) for record in advanced_records]
    expected_advanced = [name for name in candidate_names if name in formal_skills and name not in live_names]
    if advanced_names != expected_advanced:
        raise ValueError(f"official_advanced_drop_only policy drift: expected {expected_advanced}, got {advanced_names}")
    for record in advanced_records:
        evidence = record.get("dropEvidence", {})
        path = _require_evidence_hash(evidence)
        source_line = int(evidence.get("sourceLine", 0))
        lines = path.read_text(encoding="utf-8-sig").splitlines()
        if source_line < 1 or source_line > len(lines) or lines[source_line - 1].strip() != evidence.get("rawLine"):
            raise ValueError(f"drop evidence line drift for {record.get('name', '')}: {path}:{source_line}")
        if str(evidence.get("rawLine", "")).split(maxsplit=1)[-1] != str(record.get("name", "")):
            raise ValueError(f"drop evidence item mismatch for {record.get('name', '')}")

    private_names = list(policy.get("privateExtensionExcluded", []))
    expected_private = [name for name in candidate_names if name not in formal_skills]
    if private_names != expected_private:
        raise ValueError(f"private_extension_excluded policy drift: expected {expected_private}, got {private_names}")
    unresolved_names = list(policy.get("unresolvedFailClosed", []))
    classified = live_names + advanced_names + private_names + unresolved_names
    if (
        len(classified) != len(set(classified))
        or len(classified) != len(candidate_names)
        or set(classified) != set(candidate_names)
    ):
        raise ValueError("book-shop classifications must account for all source lines once and in source order")

    classification_by_name: dict[str, dict] = {}
    for name in live_names:
        skill = formal_skills[name]
        classification_by_name[name] = {
            "classification": "official_shop_live",
            "policyId": policy["policyId"],
            "formalSkillId": skill["skill_id"],
            "membershipStatus": skill["membership_status"],
            "conservativeShopPaths": conservative_paths,
        }
    for record in advanced_records:
        name = str(record["name"])
        skill = formal_skills[name]
        classification_by_name[name] = {
            "classification": "official_advanced_drop_only",
            "policyId": policy["policyId"],
            "formalSkillId": skill["skill_id"],
            "membershipStatus": skill["membership_status"],
            "absentFromConservativeShopPaths": conservative_paths,
            "dropEvidence": record["dropEvidence"],
        }
    for name in private_names:
        classification_by_name[name] = {
            "classification": "private_extension_excluded",
            "policyId": policy["policyId"],
            "formalSkillMasterPath": skill_master_path.relative_to(ROOT).as_posix(),
            "formalSkillMasterMembership": "missing",
        }
    for name in unresolved_names:
        classification_by_name[name] = {
            "classification": "unresolved_fail_closed",
            "policyId": policy["policyId"],
        }
    return {
        "policy": policy,
        "candidatePath": candidate_path,
        "candidateEntries": candidate_entries,
        "classificationByName": classification_by_name,
    }


def item_index() -> dict[str, dict]:
    source = json.loads(ITEM_CATALOG.read_text(encoding="utf-8-sig"))
    records = list(source.get("runtimeItems", []))
    records += list(source.get("runtimeSpecials", {}).values())
    records += list(source.get("serviceEquipmentReference", []))
    by_name: dict[str, dict] = {}
    for record in records:
        for name in (record.get("name"), record.get("serviceName")):
            if name and name not in by_name:
                by_name[name] = record
    return by_name


def equipment_master_names() -> set[str]:
    """Return the project-owned equipment names used as the live whitelist."""
    source = json.loads(EQUIPMENT_ATTRIBUTE_MASTER.read_text(encoding="utf-8-sig"))
    names: set[str] = set()
    for record in source.get("records", []):
        if not isinstance(record, dict):
            continue
        name = str(record.get("name", "")).strip()
        if name:
            names.add(name)
    if not names:
        raise ValueError("equipment_attribute_master has no usable project equipment records")
    return names


def parse_offer(
    line: str,
    by_name: dict[str, dict],
    offer_index: int,
    source_ordinal: int = 0,
    source_line: int = 0,
) -> dict:
    item_name = line
    pack_count = 1
    match = re.fullmatch(r"(.+?)\s+(\d+)", line)
    if match and match.group(1) in by_name:
        item_name = match.group(1)
        pack_count = int(match.group(2))
    record = by_name.get(item_name, {})
    offer = {
        "offerIndex": offer_index,
        "offerId": f"offer:{offer_index}:{int(record.get('serviceIndex', -1))}:{pack_count}",
        "tradeLine": line,
        "itemName": item_name,
        "itemKey": f"service:{int(record.get('serviceIndex', -1))}" if record else "",
        "serviceIndex": int(record.get("serviceIndex", -1)),
        "packCount": pack_count,
        "supply": "unlimited_static_trade",
        "resolved": bool(record),
    }
    if source_ordinal > 0:
        offer["sourceOrdinal"] = source_ordinal
    if source_line > 0:
        offer["sourceLine"] = source_line
    return offer


def parse_merchant(
    stock_key: str,
    npc_id: str,
    merchant_id: str,
    relative: str,
    by_name: dict[str, dict],
    equipment_names: set[str],
    book_shop_policy: dict,
) -> dict:
    path = NPC_ROOT / relative
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig")
    parsed = sections(text)
    if stock_key == "books":
        expected_path = book_shop_policy["candidatePath"]
        if path != expected_path:
            raise ValueError(f"book-shop policy source mismatch: {path} != {expected_path}")
        source_offers = [
            parse_offer(
                entry["value"],
                by_name,
                index,
                int(entry["sourceOrdinal"]),
                int(entry["sourceLine"]),
            )
            for index, entry in enumerate(book_shop_policy["candidateEntries"])
        ]
    else:
        source_offers = [parse_offer(line, by_name, index) for index, line in enumerate(parsed.get("trade", []))]
    excluded_offers: list[dict] = []
    offers: list[dict] = []
    excluded_names = EXCLUDED_OFFER_NAMES.get(stock_key, set())
    project_excluded_names = set(excluded_names)
    for offer in source_offers:
        exclusion_reason = ""
        classification_evidence: dict = {}
        if stock_key == "books":
            classification_evidence = dict(book_shop_policy["classificationByName"].get(offer["itemName"], {}))
            classification = str(classification_evidence.get("classification", "unresolved_fail_closed"))
            offer["catalogClassification"] = classification
            if classification != "official_shop_live":
                exclusion_reason = classification
        elif offer["itemName"] in excluded_names:
            if stock_key == "starter_gear":
                exclusion_reason = "project_owner_removed_unsupported_legacy_bow_offer"
            elif stock_key == "general":
                exclusion_reason = "project_owner_removed_unrelated_general_goods"
            else:
                exclusion_reason = "project_owner_removed_private_server_potion_tier"
        elif stock_key == "starter_gear" and (
            not bool(offer["resolved"])
            or offer["itemName"] not in equipment_names
        ):
            exclusion_reason = (
                "project_owner_removed_noncanonical_equipment_missing_equipment_attribute_master"
            )
        elif stock_key == "medicine" and offer["itemName"] not in MEDICINE_ALLOWED_NAMES:
            exclusion_reason = "project_owner_removed_private_server_potion_tier"
        elif stock_key == "medicine" and int(offer["packCount"]) not in MEDICINE_ALLOWED_PACK_COUNTS:
            exclusion_reason = "project_medicine_pack_size_not_in_allowed_options"
        if exclusion_reason:
            excluded = dict(offer)
            excluded["exclusionReason"] = exclusion_reason
            if stock_key == "books":
                excluded["exclusionEvidence"] = classification_evidence
            excluded_offers.append(excluded)
            project_excluded_names.add(str(offer["itemName"]))
        else:
            if stock_key == "books":
                offer["classificationEvidence"] = classification_evidence
            offers.append(offer)
    project_overrides = {
        "excludedItemNames": sorted(project_excluded_names),
        "singleUnitOffersOnly": False,
        "allowedPackCounts": sorted(MEDICINE_ALLOWED_PACK_COUNTS) if stock_key == "medicine" else [1],
        "officialEquipmentEvidence": {
            "path": EQUIPMENT_ATTRIBUTE_MASTER.relative_to(ROOT).as_posix(),
            "recordCount": len(equipment_names),
            "matchingPolicy": "starter_gear_equipment_name_must_exist_in_equipment_attribute_master",
        } if stock_key == "starter_gear" else {},
    }
    if stock_key == "books":
        project_overrides["officialBookShopPolicy"] = {
            "contractId": book_shop_policy["policy"]["contractId"],
            "policyId": book_shop_policy["policy"]["policyId"],
            "path": BOOK_SHOP_POLICY.relative_to(ROOT).as_posix(),
            "classificationCounts": {
                "official_shop_live": len(book_shop_policy["policy"]["officialShopLive"]),
                "official_advanced_drop_only": len(book_shop_policy["policy"]["officialAdvancedDropOnly"]),
                "private_extension_excluded": len(book_shop_policy["policy"]["privateExtensionExcluded"]),
                "unresolved_fail_closed": len(book_shop_policy["policy"]["unresolvedFailClosed"]),
            },
        }
    return {
        "stockKey": stock_key,
        "npcId": npc_id,
        "merchantId": merchant_id,
        "source": {
            "distribution": "server.crystal.cjlaaa",
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "sections": ["Types", "Trade"],
        },
        "types": [int(value) for value in parsed.get("types", []) if value.isdigit()],
        "merchantRateBps": 10000,
        "stockMarkupBps": 11000,
        "pricingEvidence": {
            "merchantRate": {
                "valueBps": 10000,
                "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjNpc.pas:m_nPriceRate_default_100",
                "npcOverride": "absent_in_source_script",
            },
            "stockMarkup": {
                "valueBps": 11000,
                "source": "dev_art_sources/reference/original_gameofmir/M2Server/ObjNpc.pas:CheckItemPrice_first_trade_offer",
            },
            "types": "source_script_[Types]",
            "repairCapability": "source_script_@Repair_route",
        },
        "supportsRepair": bool(re.search(r"(?:\[@Repair\]|/@Repair\b)", text, re.IGNORECASE)),
        "offers": offers,
        "excludedOffers": excluded_offers,
        "projectOverrides": project_overrides,
        "unresolvedTradeLines": [offer["tradeLine"] for offer in source_offers if not offer["resolved"]],
    }


def discover_standard_merchants() -> list[dict]:
    discovered: list[dict] = []
    for path in sorted(NPC_ROOT.rglob("*.txt"), key=lambda value: value.as_posix().lower()):
        raw = path.read_bytes()
        try:
            parsed = sections(raw.decode("utf-8-sig"))
        except UnicodeDecodeError:
            continue
        if not parsed.get("trade"):
            continue
        discovered.append({
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "types": [int(value) for value in parsed.get("types", []) if value.isdigit()],
            "tradeLineCount": len(parsed["trade"]),
        })
    return discovered


def build_payload() -> dict:
    by_name = item_index()
    equipment_names = equipment_master_names()
    book_shop_policy = load_book_shop_policy()
    merchants = {
        stock_key: parse_merchant(
            stock_key,
            npc_id,
            merchant_id,
            relative,
            by_name,
            equipment_names,
            book_shop_policy,
        )
        for stock_key, (npc_id, merchant_id, relative) in RUNTIME_MERCHANTS.items()
    }
    required_exact = {
        "general": "随机传送卷",
        "starter_gear": "木剑",
        "books": "基本剑术",
        "medicine": "金疮药(小量)",
    }
    for stock_key, expected in required_exact.items():
        actual = merchants[stock_key]["offers"][0]["itemName"]
        if actual != expected:
            raise ValueError(f"merchant encoding/name drift: {stock_key} expected {expected!r}, got {actual!r}")
    potion_path = NPC_ROOT / "BichonProvince/BichonWall/Potion-0108.txt"
    potion_trade = sections(potion_path.read_text(encoding="utf-8-sig"))["trade"]
    if potion_trade[-4:] != ["超级金疮药", "超级金疮药 20", "超级魔法药", "超级金疮药 20"]:
        raise ValueError("known primary Potion-0108 duplicate changed; audit before regenerating catalog")
    payload = {
        "schemaVersion": 1,
        "contractId": "gameplay.merchant_catalog.v1",
        "sourceDistribution": "server.crystal.cjlaaa",
        "tradeSemantics": {
            "trailingInteger": "pack_count",
            "duplicateLines": "preserve_as_distinct_offers",
            "supply": "unlimited_static_trade",
            "projectOverrides": "excludedOffers_preserve_primary_evidence",
        },
        "merchants": merchants,
        "discoveredStandardMerchants": discover_standard_merchants(),
        "knownPrimaryAnomalies": [{
            "path": "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa/Envir/NPCs/BichonProvince/BichonWall/Potion-0108.txt",
            "rule": "preserve_duplicate_trade_lines_verbatim",
            "note": "Primary repeats 超级金疮药 20 where a different item may have been intended; no correction is inferred.",
        }],
    }
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify output without writing")
    args = parser.parse_args()
    payload = build_payload()
    serialized = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != serialized:
            raise SystemExit("merchant catalog drift detected; run generator without --check")
        print(f"merchant catalog check passed: {OUTPUT}")
        return
    OUTPUT.write_text(serialized, encoding="utf-8")
    print(f"wrote {OUTPUT} with {len(payload['merchants'])} runtime merchants and {len(payload['discoveredStandardMerchants'])} discovered scripts")


if __name__ == "__main__":
    main()
