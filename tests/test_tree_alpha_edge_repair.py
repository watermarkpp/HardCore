#!/usr/bin/env python3
"""Standalone contract test for the canonical tree alpha-edge repair."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/map_assets/repair_tree_alpha_edges.py"
SPEC = importlib.util.spec_from_file_location("repair_tree_alpha_edges", TOOL)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"unable to load {TOOL}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def main() -> int:
    targets, _ = MODULE.collect_targets(ROOT)
    assert len(targets) == 60
    assert sum(1 for t in targets if t["catalog_path"] == MODULE.MAIN_CATALOG_REL) == 16
    assert sum(1 for t in targets if t["catalog_path"] == MODULE.DEEP_CATALOG_REL) == 44
    assert not any("/_staging/" in str(t["asset"]["image"]) for t in targets)

    manifest = json.loads((ROOT / MODULE.MANIFEST_REL).read_text(encoding="utf-8"))
    assert manifest["runtime_publish_policy"] == "deferred_until_user_requests_final_map_publish"
    assert manifest["map_document_rewrite_required"] is False
    assert manifest["invariants"] == {
        "dimensions_preserved": True,
        "alpha_plane_preserved": True,
        "fully_opaque_rgb_preserved": True,
        "map_layout_preserved": True,
    }
    assert len(manifest["assets"]) == 60
    assert all(int(entry["changed_visible_edge_pixels"]) > 0 for entry in manifest["assets"])
    assert all(entry["input_sha256"] == entry["source_sha256"] for entry in manifest["assets"])
    assert all(entry["input_sha256"] != entry["output_sha256"] for entry in manifest["assets"])

    MODULE.check_repair(ROOT)
    print("TREE_ALPHA_EDGE_REPAIR_TEST_PASS assets=60 map_layout_rewrite=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
