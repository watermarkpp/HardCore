#!/usr/bin/env python3
"""Extract verified client item sprites and emit a data-driven equipment art map."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
OUTPUT = ROOT / "assets/art/items/client"
MANIFEST = ROOT / "assets/data/equipment_client_art_sources.json"
LOOKS_CACHE = ROOT / "assets/data/equipment_web_looks_candidates.json"
STD_ITEMS = ROOT / "assets/data/equipment_stditems_176.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


# The first classic weapon sequence and visually unique pick/axe entries can be
# cross-checked directly in the client libraries.  Since StdItems.Looks is absent,
# every name-to-index row remains B confidence and is never labelled service exact.
NAME_TO_LOOKS = {
    "木剑": 30,
    "匕首": 31,
    "乌木剑": 32,
    "青铜剑": 33,
    "短剑": 34,
    "铁剑": 35,
    "青铜斧": 40,
    "炼狱": 41,
    "鹤嘴锄": 50,
    "裁决之杖": 58,
}

LIBRARIES = {
    "inventoryIcon": ("Items.wil", "inventory"),
    "equippedIcon": ("stateitem.wil", "equipped"),
    "groundIcon": ("DnItems.wil", "ground"),
}


def extract_index(library_name: str, folder: str, index: int) -> dict:
    source = CLIENT_DATA / library_name
    data, palette, offsets, info = read_library(source)
    image, meta = decode_sprite(data, offsets[index], palette)
    target_dir = OUTPUT / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{index:03d}.png"
    image.save(target)
    return {
        "path": f"res://assets/art/items/client/{folder}/{index:03d}.png",
        "library": f"dev_art_sources/reference/mir2_client_raw/Data/{library_name}",
        "index": index,
        "sourceOffset": meta["offset"],
        "size": [meta["width"], meta["height"]],
        "drawOffset": [meta["x"], meta["y"]],
        "libraryVersion": info["version"],
        "confidence": "A",
    }


def main() -> None:
    name_to_looks = dict(NAME_TO_LOOKS)
    mapping_sources = {name: "客户端图像序列与外观复核；待StdItems.Looks逐件升级" for name in NAME_TO_LOOKS}
    mapping_confidence = {name: "B" for name in NAME_TO_LOOKS}
    if LOOKS_CACHE.exists():
        cache = json.loads(LOOKS_CACHE.read_text(encoding="utf-8"))
        for row in cache.get("items", []):
            name = str(row.get("name", ""))
            if name and isinstance(row.get("looks"), int):
                name_to_looks[name] = int(row["looks"])
                mapping_sources[name] = str(row.get("sourceUrl", "逐件资料页图片索引"))
                mapping_confidence[name] = "B"
    std_items = json.loads(STD_ITEMS.read_text(encoding="utf-8"))
    for row in std_items.get("records", []):
        name = str(row.get("Name", ""))
        if name in name_to_looks:
            name_to_looks[name] = int(row["Looks"])
            mapping_sources[name] = "community.mylgd.mir2server.176 StdItems.DB@3952c536"
            mapping_confidence[name] = "A"
    mappings = {}
    failures = []
    for name, looks in name_to_looks.items():
        art = {
            "looks": looks,
            "mappingSource": mapping_sources[name],
            "mappingConfidence": mapping_confidence.get(name, "B"),
        }
        try:
            for field, (library, folder) in LIBRARIES.items():
                art[field] = extract_index(library, folder, looks)
        except (ValueError, IndexError) as exc:
            failures.append({"name": name, "looks": looks, "error": str(exc)})
            continue
        mappings[name] = art
    payload = {
        "schemaVersion": 1,
        "baseline": "2003官服1.76基准优先",
        "clientLibraries": {
            field: f"dev_art_sources/reference/mir2_client_raw/Data/{library}"
            for field, (library, _folder) in LIBRARIES.items()
        },
        "runtimeMappings": mappings,
        "unresolvedMappings": failures,
        "wearableMappingSchema": {
            "weaponAppearance": "Weapon.wil角色武器Shape；见warrior_wear_sources schema 3",
            "dressAppearance": "Hum.wil角色衣服Shape；见warrior_wear_sources schema 3",
        },
        "policy": "库、索引和像素为客户端A源；172件名称到Looks对锁定社区1.76发行版为A，缺名3件保留网页候选B且不冒充官服原库。",
        "missing": std_items.get("missingVanillaRecords", []),
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"EQUIPMENT_CLIENT_ART={MANIFEST}")
    print(f"EQUIPMENT_RUNTIME_MAPPINGS={len(mappings)}")


if __name__ == "__main__":
    main()
