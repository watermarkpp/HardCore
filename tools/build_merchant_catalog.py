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
}
SINGLE_UNIT_STOCK_KEYS = {"medicine"}

# The primary blacksmith script contains these legacy bow lines, but the
# project item/runtime catalog does not support them as buyable gameplay
# instances. Keep them in excludedOffers for source auditability while
# removing them from the live starter_gear stock.
EXCLUDED_OFFER_NAMES["starter_gear"] = {
    "WoodenBow",
    "EbonyBow",
    "ShortBow",
    "BoneBow",
    "CompoundBow",
}


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


def parse_offer(line: str, by_name: dict[str, dict], offer_index: int) -> dict:
    item_name = line
    pack_count = 1
    match = re.fullmatch(r"(.+?)\s+(\d+)", line)
    if match and match.group(1) in by_name:
        item_name = match.group(1)
        pack_count = int(match.group(2))
    record = by_name.get(item_name, {})
    return {
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


def parse_merchant(stock_key: str, npc_id: str, merchant_id: str, relative: str, by_name: dict[str, dict]) -> dict:
    path = NPC_ROOT / relative
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig")
    parsed = sections(text)
    source_offers = [parse_offer(line, by_name, index) for index, line in enumerate(parsed.get("trade", []))]
    excluded_offers: list[dict] = []
    offers: list[dict] = []
    excluded_names = EXCLUDED_OFFER_NAMES.get(stock_key, set())
    for offer in source_offers:
        exclusion_reason = ""
        if offer["itemName"] in excluded_names:
            exclusion_reason = (
                "project_owner_removed_unsupported_legacy_bow_offer"
                if stock_key == "starter_gear"
                else "project_owner_removed_unrelated_general_goods"
            )
        elif stock_key in SINGLE_UNIT_STOCK_KEYS and int(offer["packCount"]) != 1:
            exclusion_reason = "project_stackable_consumables_use_single_unit_offers"
        if exclusion_reason:
            excluded = dict(offer)
            excluded["exclusionReason"] = exclusion_reason
            excluded_offers.append(excluded)
        else:
            offers.append(offer)
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
        "projectOverrides": {
            "excludedItemNames": sorted(excluded_names),
            "singleUnitOffersOnly": stock_key in SINGLE_UNIT_STOCK_KEYS,
        },
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
    merchants = {
        stock_key: parse_merchant(stock_key, npc_id, merchant_id, relative, by_name)
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
