#!/usr/bin/env python3
"""Cache a small, rejected-for-baseline cross-check from a public modern MIR2 database.

This deliberately does not write legend176_data.json. The source contains modern
Crystal fields and is useful only for confirming names/timing candidates.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/data/bich_public_database_crosscheck.json"
REPOSITORY = "angelk727/Mir2ServerDatabases"
RAW_ROOT = f"https://raw.githubusercontent.com/{REPOSITORY}/main/Exports"
URLS = {
    "maps": f"{RAW_ROOT}/1_%E5%9C%B0%E5%9B%BE%E6%95%B0%E6%8D%AE.txt",
    "monsters": f"{RAW_ROOT}/3_%E6%80%AA%E7%89%A9%E6%95%B0%E6%8D%AE.csv",
    "spawns": f"{RAW_ROOT}/6_%E5%88%B7%E6%80%AA%E6%95%B0%E6%8D%AE.txt",
}
TARGET_MONSTERS = {
    "稻草人", "钉耙猫", "半兽人", "森林雪人", "食人花", "骷髅", "掷斧骷髅",
    "骷髅战士", "骷髅战将", "骷髅精灵", "僵尸1", "尸王", "洞蛆", "蝎子", "山洞蝙蝠",
}
TARGET_MAPS = {"0", "D001", "D002", "D003", "D011", "D012", "Q004"}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "legend176-data-audit/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def integer(value: str) -> int:
    try:
        return int(float(value or 0))
    except ValueError:
        return 0


def main() -> None:
    raw = {name: fetch(url) for name, url in URLS.items()}
    commit = json.loads(fetch(f"https://api.github.com/repos/{REPOSITORY}/commits/main").decode("utf-8"))["sha"]
    monster_rows = csv.DictReader(io.StringIO(raw["monsters"].decode("utf-8-sig")))
    monsters = []
    for row in monster_rows:
        if row.get("MonsterName") not in TARGET_MONSTERS:
            continue
        monsters.append({
            "name": row["MonsterName"],
            "image": row.get("MonsterImage", ""),
            "ai": integer(row.get("MonsterAI", "0")),
            "level": integer(row.get("MonsterLevel", "0")),
            "attackIntervalMs": integer(row.get("MonsterAttackSpeed", "0")),
            "moveIntervalMs": integer(row.get("MonsterMoveSpeed", "0")),
            "experience": integer(row.get("MonsterExperience", "0")),
            "hp": integer(row.get("StatHP", "0")),
            "defense": [integer(row.get("StatMinAC", "0")), integer(row.get("StatMaxAC", "0"))],
            "magicDefense": [integer(row.get("StatMinMAC", "0")), integer(row.get("StatMaxMAC", "0"))],
            "attack": [integer(row.get("StatMinDC", "0")), integer(row.get("StatMaxDC", "0"))],
        })
    spawns = []
    for line in raw["spawns"].decode("utf-8-sig").splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 7 or parts[0] not in TARGET_MAPS or parts[3] not in TARGET_MONSTERS:
            continue
        spawns.append({
            "mapCode": parts[0], "x": integer(parts[1]), "y": integer(parts[2]),
            "monsterName": parts[3], "range": integer(parts[4]), "count": integer(parts[5]),
            "respawnMinutes": integer(parts[6]),
        })
    maps = []
    for line in raw["maps"].decode("utf-8-sig").splitlines():
        match = re.match(r"^\[([^\s\]]+)\s+([^\]]+)\]", line.strip())
        if match and match.group(1) in TARGET_MAPS:
            maps.append({"mapCode": match.group(1), "name": match.group(2)})
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "repository": f"https://github.com/{REPOSITORY}",
        "commit": commit,
        "sourceFiles": {
            name: {"url": URLS[name], "sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}
            for name, content in raw.items()
        },
        "classification": {
            "versionTag": "1.76后期追加内容",
            "availabilityDefault": False,
            "confidence": "B",
            "baselineDecision": "拒绝覆盖2003基准",
            "reason": "数据含刺客、坐骑、暴击、现代Crystal字段，且地图0名为飞天县；仅同名怪物攻击/移动间隔可作交叉验证。",
        },
        "summary": {"monsterMatches": len(monsters), "mapMatches": len(maps), "spawnMatches": len(spawns)},
        "maps": maps,
        "monsters": sorted(monsters, key=lambda row: row["name"]),
        "spawns": spawns,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), **payload["summary"], "commit": commit}, ensure_ascii=False))


if __name__ == "__main__":
    main()
