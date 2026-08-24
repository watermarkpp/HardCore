import hashlib
import hashlib
import json
from collections import Counter
from pathlib import Path
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
FAMILY_ID = "chiyue_valley_rock_wall_u0"
ASSET_PREFIX = "chiyue_valley_wall_"
ART_ROOT = ROOT / "assets/art/maps/_shared/walls/chiyue_valley/chiyue_valley_rock_wall_u0"
SOURCE_ROOT = ROOT / "assets/art/maps/_shared/walls/chiyue_valley/source"
ASSET_CATALOG = ROOT / "assets/data/assets/map_chiyue_valley_wall_asset_catalog.json"
MODULE_CATALOG = ROOT / "assets/data/assets/wall_module_catalog.json"
FAMILY_CATALOG = ROOT / "assets/data/assets/wall_family_catalog.json"
PROVENANCE = SOURCE_ROOT / "chiyue_valley_wall_source_provenance.json"
PREVIEW = SOURCE_ROOT / "chiyue_valley_wall_pack_contact_sheet.png"
LEGACY_SOURCES = {
    SOURCE_ROOT / "chiyue_valley_wall_front_source.png",
    SOURCE_ROOT / "chiyue_valley_wall_cap_source.png",
}
FRONT_OUTPUT_IDS = {
    "exec-a16c2c00-468a-45e3-a09e-35e7b6b63dda.png",
}
CAP_OUTPUT_ID = "exec-394b3c43-bf78-40ad-9aaa-d97b8e17af26.png"
CAP_TRACKED_SHA256 = {
    1: "9c37b54db921d9b2f62c493a0804eec9da28b14de0e6030f1a0dcd6eea86f4da",
    2: "2ed6a11fc5c075e5a029ad0c654be73ccef6b2d0623e1604810063813d279b2b",
    3: "d35843ec670a1e60babd4ea20be654f3e4a0a0f83b3c4e828316175fb75a71d5",
    4: "893891428d08d6a09b399042b7ef1697e64a651f86fa88541e6ced8ac7ed38cc",
}
EXPECTED_BOUNDS = {
    ("iso_x", 1): [32, 8, 63, 191],
    ("iso_x", 2): [32, 8, 95, 207],
    ("iso_x", 3): [32, 8, 127, 223],
    ("iso_x", 4): [32, 8, 159, 239],
    ("iso_y", 1): [1, 8, 63, 191],
    ("iso_y", 2): [1, 8, 95, 207],
    ("iso_y", 3): [1, 8, 127, 223],
    ("iso_y", 4): [1, 8, 159, 239],
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ChiyueValleyWallPackTest(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(ASSET_CATALOG.read_text(encoding="utf-8"))
        self.assets = self.catalog["assets"]

    def test_pack_has_exact_sixteen_slots_native_geometry_and_source_layout(self):
        self.assertEqual(len(self.assets), 16)
        self.assertEqual(self.catalog["wall_family_ids"], [FAMILY_ID])
        self.assertEqual(self.catalog["corner_join_mode"], "straight_overlap")
        ids = [asset["asset_id"] for asset in self.assets]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(asset_id.startswith(ASSET_PREFIX) for asset_id in ids))
        self.assertTrue(all("corner" not in asset_id and "pillar" not in asset_id for asset_id in ids))
        self.assertEqual(
            Counter((asset["axis"], asset["length_tiles"]) for asset in self.assets),
            Counter(
                {
                    ("iso_x", 1): 1,
                    ("iso_x", 2): 1,
                    ("iso_x", 3): 3,
                    ("iso_x", 4): 3,
                    ("iso_y", 1): 1,
                    ("iso_y", 2): 1,
                    ("iso_y", 3): 3,
                    ("iso_y", 4): 3,
                }
            ),
        )
        for asset in self.assets:
            length = int(asset["length_tiles"])
            width, height = asset["image_size"]
            self.assertEqual((width, height), (32 * length + 64, 208 + 16 * length))
            expected_bounds = EXPECTED_BOUNDS[(asset["axis"], length)]
            self.assertEqual(asset["visible_bounds_px"], expected_bounds)
            self.assertEqual(asset["selection_bounds_px"], expected_bounds)
            anchor = asset["placement_anchor_px"]
            self.assertEqual(anchor[1], 184)
            self.assertEqual(anchor[0], 64 if asset["axis"] == "iso_x" else width - 64)
            self.assertEqual(asset["wall_cap_projection_px"], [32, 16])
            self.assertEqual(asset["wall_cap_thickness_tiles"], 1)
            self.assertEqual(len(asset["render_parts"]), length)
            self.assertEqual(asset["collision_policy"], "none")
            self.assertEqual(asset["collision_cells"], [])
            self.assertEqual(asset["collision_footprint_tiles"], [0, 0])
            self.assertEqual(asset["collision_authority"], "manual_by_user")
            self.assertEqual(asset["navigation_policy"], "ignore")
            self.assertTrue(asset["manual_collision_expected"])
            self.assertFalse(asset["contains_corner_pillar"])
            self.assertIn("赤月洞穴岩壁", asset["display_name"])
            self.assertIn("赤月峡谷墙体", asset["palette_path"])

            layout = asset["source_variant_layout"]
            self.assertEqual(len(layout), length)
            self.assertEqual(
                len({(item["front_source_variant"], item["cap_source_variant"]) for item in layout}),
                length,
            )
            for previous, current in zip(layout, layout[1:]):
                self.assertNotEqual(
                    previous["front_source_variant"], current["front_source_variant"]
                )
                self.assertNotEqual(
                    previous["cap_source_variant"], current["cap_source_variant"]
                )
            for part, expected in zip(asset["render_parts"], layout):
                self.assertEqual(
                    (part["front_source_variant"], part["cap_source_variant"]),
                    (expected["front_source_variant"], expected["cap_source_variant"]),
                )
                self.assertRegex(part["front_source_path"], r"front_v0[1-4]\.png$")
                self.assertRegex(part["cap_source_path"], r"cap_v0[1-4]\.png$")

    def test_images_are_real_alpha_fixed_bounds_and_variants_differ(self):
        pngs = list(ART_ROOT.rglob("*.png"))
        self.assertEqual(len(pngs), 64)
        for asset in self.assets:
            image_path = ROOT / asset["image"]
            with Image.open(image_path) as opened:
                image = opened.convert("RGBA")
                self.assertEqual(image.size, tuple(asset["image_size"]))
                self.assertEqual(image.getchannel("A").getextrema(), (0, 255))
                used = image.getchannel("A").getbbox()
                self.assertIsNotNone(used)
                actual_bounds = [used[0], used[1], used[2] - used[0], used[3] - used[1]]
                self.assertEqual(actual_bounds, EXPECTED_BOUNDS[(asset["axis"], int(asset["length_tiles"]))])
            for part in asset["render_parts"]:
                part_path = ROOT / part["base_image"]
                self.assertTrue(part_path.is_file())
                with Image.open(part_path) as opened:
                    self.assertEqual(opened.convert("RGBA").getchannel("A").getextrema(), (0, 255))

        for axis in ("iso_x", "iso_y"):
            for length in (3, 4):
                selected = [
                    asset
                    for asset in self.assets
                    if asset["axis"] == axis and asset["length_tiles"] == length
                ]
                self.assertEqual(len(selected), 3)
                self.assertEqual(len({asset["output_sha256"] for asset in selected}), 3)

    def test_source_provenance_and_catalog_wiring(self):
        self.assertTrue(PROVENANCE.is_file())
        self.assertTrue(PREVIEW.is_file())
        provenance = json.loads(PROVENANCE.read_text(encoding="utf-8"))
        self.assertEqual(provenance["family_id"], FAMILY_ID)
        generation = provenance["generation"]
        self.assertEqual(generation["tool"], "image_gen.imagegen")
        self.assertEqual(set(generation["front_output_ids"]), FRONT_OUTPUT_IDS)
        self.assertEqual(
            {Path(path).name for path in generation["front_external_paths"]},
            FRONT_OUTPUT_IDS,
        )
        self.assertNotIn("48ad", json.dumps(generation))
        self.assertEqual(generation["cap_output_id"], CAP_OUTPUT_ID)
        self.assertEqual(Path(generation["cap_external_path"]).name, CAP_OUTPUT_ID)
        self.assertEqual(
            generation["clipboard_reference_sha256"],
            "382e3c0c87f44a0270e2bd9e399b88cebe75cf36d76fe65dd38359e112b23ffe",
        )
        self.assertEqual(
            generation["style_contract"]["variation"],
            "front_texture_window_and_cap_crop_only",
        )
        self.assertEqual(
            Path(generation["front_external_path"]).name,
            next(iter(FRONT_OUTPUT_IDS)),
        )
        self.assertEqual(len(generation["front_crop_boxes"]), 4)
        self.assertEqual(
            len({tuple(box) for box in generation["front_crop_boxes"]}),
            4,
        )

        source_files = provenance["source_files"]
        self.assertEqual(len(source_files), 8)
        source_by_key = {
            (entry["role"], int(entry["variant"])): entry for entry in source_files
        }
        self.assertEqual(
            {key for key in source_by_key if key[0] == "front"},
            {("front", 1), ("front", 2), ("front", 3), ("front", 4)},
        )
        self.assertEqual(
            {key for key in source_by_key if key[0] == "cap"},
            {("cap", 1), ("cap", 2), ("cap", 3), ("cap", 4)},
        )
        self.assertTrue(all(not path.exists() for path in LEGACY_SOURCES))
        for entry in source_files:
            source_path = ROOT / entry["tracked_path"]
            self.assertTrue(source_path.is_file())
            self.assertEqual(digest(source_path), entry["sha256"])
            with Image.open(source_path) as opened:
                expected_alpha = (255, 255) if entry["role"] == "front" else (0, 255)
                self.assertEqual(opened.convert("RGBA").getchannel("A").getextrema(), expected_alpha)
            self.assertEqual(entry["sha256"], entry["tracked_sha256"])
            self.assertEqual(len(entry["raw_sha256"]), 64)
            self.assertEqual(len(entry["tracked_sha256"]), 64)
            self.assertIn("hard_planar_wet_cave_rock", entry["style_contract"])

        front_entries = [entry for entry in source_files if entry["role"] == "front"]
        self.assertEqual({entry["raw_output_id"] for entry in front_entries}, FRONT_OUTPUT_IDS)
        self.assertEqual(
            {tuple(entry["crop_box_in_raw_source"]) for entry in front_entries},
            {tuple(box) for box in generation["front_crop_boxes"]},
        )
        self.assertTrue(
            all(
                entry["source_cleanup_policy"]
                == "internal_hard_planar_rock_crop_set_alpha_255"
                and entry["dimensions"] == [150, 750]
                and entry["alpha_extrema"] == [255, 255]
                for entry in front_entries
            )
        )

        cap_entries = [entry for entry in source_files if entry["role"] == "cap"]
        self.assertEqual({entry["raw_output_id"] for entry in cap_entries}, {CAP_OUTPUT_ID})
        self.assertEqual(
            {int(entry["variant"]): entry["tracked_sha256"] for entry in cap_entries},
            CAP_TRACKED_SHA256,
        )
        self.assertEqual(
            len({tuple(entry["crop_box_in_dominant_alpha"]) for entry in cap_entries}),
            4,
        )
        self.assertTrue(
            all(
                entry["source_cleanup_policy"]
                == "dominant_alpha_bbox_then_deterministic_quadrant_crop"
                for entry in cap_entries
            )
        )

        for asset in self.assets:
            self.assertEqual(
                asset["source_provenance_path"],
                "assets/art/maps/_shared/walls/chiyue_valley/source/chiyue_valley_wall_source_provenance.json",
            )
            self.assertEqual(len(asset["source_front_sha256"]), 64)
            self.assertEqual(len(asset["source_cap_sha256"]), 64)
        modules = json.loads(MODULE_CATALOG.read_text(encoding="utf-8"))["modules"]
        chiyue_modules = [module for module in modules if module.get("wall_family_id") == FAMILY_ID]
        self.assertEqual(len(chiyue_modules), 16)
        for module in chiyue_modules:
            self.assertEqual(module["collision_policy"], "none")
            self.assertEqual(module["collision_cells"], [])
            self.assertEqual(module["collision_footprint_tiles"], [0, 0])
            self.assertEqual(module["collision_authority"], "manual_by_user")
        families = json.loads(FAMILY_CATALOG.read_text(encoding="utf-8"))["wall_families"]
        family = next(item for item in families if item["wall_family_id"] == FAMILY_ID)
        self.assertEqual(family["wall_height_px"], 160)
        self.assertEqual(family["corner_join_mode"], "straight_overlap")
        self.assertEqual(family["collision_authority"], "manual_by_user")


if __name__ == "__main__":
    unittest.main()
