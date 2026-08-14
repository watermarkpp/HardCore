#!/usr/bin/env python3
"""Contract test for decorations_1 non-tree alpha-edge repair."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/map_assets/repair_decoration_alpha_edges.py"
SPEC = importlib.util.spec_from_file_location("repair_decoration_alpha_edges", TOOL)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"unable to load {TOOL}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def main() -> int:
    images, catalogs, refs = MODULE.collect_scope(ROOT)
    assert len(images) == 234
    assert sum(len(items) for items in refs.values()) == 346
    assert MODULE.TREE_ROOT_REL not in {parent for image in images for parent in image.parents}
    assert MODULE.EXPECTED_GROUP_COUNTS == {
        "barricades": 8,
        "carpets": 6,
        "corpses_visual_only": 36,
        "ground_graffiti": 16,
        "houses_and_tents": 24,
        "map_entrances": 72,
        "pillars": 24,
        "small_decorations_visual_only": 24,
        "street_lamps": 4,
        "thrones": 12,
        "vendor_stalls": 8,
    }
    tree_refs, _ = MODULE.tree_direct_refs(ROOT, catalogs)
    assert len(tree_refs) == 16

    manifest = json.loads((ROOT / MODULE.MANIFEST_REL).read_text(encoding="utf-8"))
    assert manifest["asset_count"] == 234
    assert manifest["catalog_reference_count"] == 346
    assert manifest["map_document_rewrite_required"] is False
    assert manifest["runtime_publish_policy"] == "deferred_until_user_requests_final_map_publish"
    assert manifest["aligned_tree_direct_folder_record_count"] == 16
    assert len(manifest["assets"]) == 234
    assert all(int(entry["changed_visible_edge_pixels"]) > 0 for entry in manifest["assets"])
    assert all(entry["input_sha256"] != entry["output_sha256"] for entry in manifest["assets"])

    MODULE.check_repair(ROOT)
    print(
        "DECORATION_ALPHA_EDGE_REPAIR_TEST_PASS assets=234 catalog_refs=346 "
        "map_layout_rewrite=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
