#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import json
import subprocess
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]

CATALOG_REL = "assets/data/assets/map_asset_catalog.json"
CATALOG_PATH = REPO / CATALOG_REL

PRE_IMPORT_BASE = "cf4ceb344d7a612104347917c1e32ef0392eeff6"
IMPORT_COMMIT = "c4d260866935132b95a4a2498fe322acf7050e17"

REPORT_PATH = (
    REPO
    / "docs"
    / "mafa_scene_editor"
    / "new_decor_occlusion_risk_report.md"
)


def read_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_catalog_at(commit: str):
    raw = subprocess.check_output(
        ["git", "show", f"{commit}:{CATALOG_REL}"],
        cwd=str(REPO),
    )
    return json.loads(raw.decode("utf-8"))


def asset_map(catalog: dict):
    return {
        str(asset.get("asset_id", "")): asset
        for asset in catalog.get("assets", [])
    }


def new_batch_ids():
    pre = asset_map(load_catalog_at(PRE_IMPORT_BASE))
    imported = asset_map(load_catalog_at(IMPORT_COMMIT))
    return set(imported) - set(pre)


def category_of(asset: dict) -> str:
    path = str(asset.get("palette_path", ""))
    if "/" not in path:
        return ""
    return path.rsplit("/", 1)[-1]


def main():
    current = read_json(CATALOG_PATH)
    assets = asset_map(current)
    batch_ids = new_batch_ids()

    target_ids = sorted(
        aid for aid in batch_ids if aid in assets
    )

    risk_rows = []

    for aid in target_ids:
        asset = assets[aid]

        if not bool(asset.get("occlusion", False)):
            continue

        fp = asset.get("footprint_tiles", [1, 1])
        if not isinstance(fp, list) or len(fp) != 2:
            continue

        gcb = asset.get("ground_contact_bounds_px", [0, 0, 0, 0])
        if not isinstance(gcb, list) or len(gcb) != 4:
            continue

        category = category_of(asset)

        fp_w = int(fp[0])
        fp_h = int(fp[1])

        contact_w = int(gcb[2])
        contact_h = int(gcb[3])

        if contact_h <= 0:
            continue

        pixel_ratio = contact_w / max(1.0, float(contact_h))
        tile_rect = fp_w != fp_h

        # 方形优先类别（烛台、雕塑、立柱）设计上就是方形 footprint，
        # 宽底座不影响遮挡正确性，跳过审查。
        if category in {"烛台", "雕塑", "立柱"}:
            continue

        # 小 footprint（≤2）在小尺寸下方形不影响遮挡切换，
        # 只有大 footprint 的方形化才会造成可见的遮挡问题。
        if fp_w <= 2 and fp_h <= 2:
            continue

        # 重点审查：
        # 底部接地区域明显横向拉长，但最终 footprint 仍为正方形
        if pixel_ratio >= 1.8 and not tile_rect:
            risk_rows.append({
                "asset_id": aid,
                "category": category,
                "footprint": fp,
                "ground_contact_bounds_px": gcb,
                "pixel_ratio": round(pixel_ratio, 2),
            })

    lines = []
    lines.append("# New Decor Occlusion Risk Report")
    lines.append("")
    lines.append(f"TARGET_ASSETS = {len(target_ids)}")
    lines.append(f"RISK_COUNT = {len(risk_rows)}")
    lines.append("")
    lines.append("| asset_id | category | footprint | ground_contact_bounds_px | pixel_ratio |")
    lines.append("|---|---|---|---|---:|")

    for row in risk_rows:
        lines.append(
            f"| {row['asset_id']} | {row['category']} | "
            f"{row['footprint']} | {row['ground_contact_bounds_px']} | "
            f"{row['pixel_ratio']} |"
        )

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"TARGET_ASSETS={len(target_ids)}")
    print(f"RISK_COUNT={len(risk_rows)}")
    print(f"WROTE_REPORT={REPORT_PATH}")

    if risk_rows:
        print("OCCLUSION_RISK_AUDIT=FOUND_RISKS")
    else:
        print("OCCLUSION_RISK_AUDIT=PASS")


if __name__ == "__main__":
    main()
