#!/usr/bin/env python3
"""Cache item-name to classic client Looks candidates from the catalog source pages."""

from __future__ import annotations

import json
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets/data/legend176_data.json"
OUTPUT = ROOT / "assets/data/equipment_web_looks_candidates.json"
LOOKS_RE = re.compile(rb'/files/items/(\d+)\.PNG', re.IGNORECASE)


def fetch(row: dict) -> dict:
    url = str(row.get("sourceUrl", ""))
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 MIR2-data-audit"})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            payload = response.read()
        match = LOOKS_RE.search(payload)
        if match:
            return {"name": row["name"], "looks": int(match.group(1)), "sourceUrl": url, "confidence": "B"}
        return {"name": row["name"], "sourceUrl": url, "error": "页面没有物品图片索引"}
    except Exception as exc:  # cache failures explicitly; never silently invent a mapping
        return {"name": row["name"], "sourceUrl": url, "error": str(exc)}


def main() -> None:
    rows = json.loads(DATA.read_text(encoding="utf-8")).get("items", [])
    results = []
    with ThreadPoolExecutor(max_workers=12) as pool:
        futures = [pool.submit(fetch, row) for row in rows if row.get("sourceUrl")]
        for future in as_completed(futures):
            results.append(future.result())
    results.sort(key=lambda row: str(row.get("name", "")))
    mapped = [row for row in results if "looks" in row]
    failed = [row for row in results if "looks" not in row]
    payload = {
        "schemaVersion": 1,
        "fetchedAt": date.today().isoformat(),
        "sourceRole": "逐件Looks网页候选；低于服务端StdItems，不能升级为官服精确数据",
        "mappedCount": len(mapped),
        "failedCount": len(failed),
        "items": mapped,
        "failures": failed,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"EQUIPMENT_LOOKS_CANDIDATES={len(mapped)} FAILURES={len(failed)}")


if __name__ == "__main__":
    main()
