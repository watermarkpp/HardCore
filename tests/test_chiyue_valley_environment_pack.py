from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GROUND_CATALOG = ROOT / "assets/data/assets/map_chiyue_valley_ground_asset_catalog.json"
FLOOR_CATALOG = ROOT / "assets/data/assets/map_chiyue_valley_floor_asset_catalog.json"
SERVICE = ROOT / "scripts/map_assets/map_asset_catalog_service.gd"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def asset_path(value: str) -> Path:
    return ROOT / value


class ChiyueValleyEnvironmentPackTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ground = json.loads(GROUND_CATALOG.read_text(encoding="utf-8"))
        cls.floor = json.loads(FLOOR_CATALOG.read_text(encoding="utf-8"))
        cls.rocks = cls.ground["assets"]
        cls.floors = cls.floor["assets"]

    def test_counts_ids_and_service_registration(self) -> None:
        self.assertEqual(12, len(self.rocks))
        self.assertEqual(6, len(self.floors))
        ids = [asset["asset_id"] for asset in self.rocks + self.floors]
        self.assertEqual(18, len(set(ids)))
        self.assertEqual(
            [f"chiyue_valley_ground_rock_block_{i:02d}" for i in range(1, 7)],
            ids[:6],
        )
        self.assertEqual(
            [f"chiyue_valley_ground_rock_pile_{i:02d}" for i in range(1, 7)],
            ids[6:12],
        )
        self.assertEqual(
            [f"mse.ground.chiyue_valley_floor.{i:02d}" for i in range(1, 7)],
            ids[12:],
        )
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("map_chiyue_valley_ground_asset_catalog.json", service)
        self.assertIn("map_chiyue_valley_floor_asset_catalog.json", service)

    def test_rocks_are_true_alpha_tight_and_background_clean(self) -> None:
        output_hashes: set[str] = set()
        for asset in self.rocks:
            with self.subTest(asset=asset["asset_id"]):
                image_path = asset_path(asset["image"])
                source_path = asset_path(asset["source_path"])
                self.assertTrue(image_path.is_file())
                self.assertTrue(source_path.is_file())
                self.assertEqual(sha256(image_path), asset["output_sha256"])
                self.assertEqual(sha256(source_path), asset["source_sha256"])
                output_hashes.add(asset["output_sha256"])

                image = Image.open(image_path).convert("RGBA")
                self.assertEqual(list(image.size), asset["canvas_size"])
                rgba = np.asarray(image, dtype=np.uint8)
                alpha = rgba[:, :, 3]
                self.assertEqual(0, int(alpha[0, 0]))
                self.assertEqual(0, int(alpha[0, -1]))
                self.assertEqual(0, int(alpha[-1, 0]))
                self.assertEqual(0, int(alpha[-1, -1]))
                bbox = image.getchannel("A").getbbox()
                self.assertIsNotNone(bbox)
                x0, y0, x1, y1 = bbox
                expected = [x0, y0, x1 - x0, y1 - y0]
                self.assertEqual(expected, asset["visible_bounds_px"])
                self.assertEqual(expected, asset["selection_bounds_px"])
                self.assertEqual([x0 + (x1 - x0) // 2, y1], asset["anchor_px"])

                chroma = rgba[:, :, :3].max(2).astype(np.int16) - rgba[:, :, :3].min(2).astype(np.int16)
                bright_translucent = (
                    (rgba[:, :, :3].min(2) > 200)
                    & (chroma < 40)
                    & (alpha > 0)
                    & (alpha < 255)
                )
                self.assertEqual(0, int(bright_translucent.sum()), "white/checker alpha halo remains")
                self.assertEqual([1, 1], asset["footprint_tiles"])
                self.assertTrue(asset["allow_overlap"])
                self.assertEqual("always_allow", asset["overlap_policy"])
                self.assertEqual("none", asset["collision_policy"])
                self.assertEqual([0, 0], asset["collision_footprint_tiles"])
                self.assertEqual([], asset["collision_cells"])
                self.assertEqual("ignore", asset["navigation_policy"])
                self.assertTrue(asset["manual_collision_expected"])
                self.assertEqual("manual_by_user", asset["collision_authority"])
        self.assertEqual(12, len(output_hashes))

    def test_floors_match_current_64x32_isometric_ground_contract(self) -> None:
        output_hashes: set[str] = set()
        for asset in self.floors:
            with self.subTest(asset=asset["asset_id"]):
                image_path = asset_path(asset["image"])
                source_path = asset_path(asset["source_path"])
                self.assertTrue(image_path.is_file())
                self.assertTrue(source_path.is_file())
                self.assertEqual(sha256(image_path), asset["output_sha256"])
                self.assertEqual(sha256(source_path), asset["source_sha256"])
                output_hashes.add(asset["output_sha256"])
                image = Image.open(image_path).convert("RGBA")
                self.assertEqual((64, 32), image.size)
                alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
                self.assertEqual(0, int(alpha[0, 0]))
                self.assertEqual(0, int(alpha[0, 63]))
                self.assertEqual(0, int(alpha[31, 0]))
                self.assertEqual(0, int(alpha[31, 63]))
                self.assertGreater(int(alpha[16, 32]), 0)
                self.assertEqual([32, 16], asset["anchor_px"])
                self.assertEqual([32, 16], asset["placement_anchor_px"])
                self.assertEqual([1, 1], asset["footprint_tiles"])
                self.assertEqual("ground_brush", asset["asset_type"])
                self.assertEqual("ground_base", asset["default_layer"])
                self.assertEqual("base_tile", asset["ground_brush_role"])
                self.assertEqual("chiyue_valley_wet_karst_rock", asset["terrain_type"])
                self.assertEqual("mse.ground.chiyue_valley_floor.v1", asset["variation_group_id"])
                self.assertEqual("none", asset["collision_policy"])
                self.assertEqual([0, 0], asset["collision_footprint_tiles"])
                self.assertEqual([], asset["collision_cells"])
                self.assertTrue(asset["allow_overlap"])
        self.assertEqual(6, len(output_hashes))

    def test_pack_is_linked_to_approved_wall_system(self) -> None:
        for catalog in (self.ground, self.floor):
            self.assertEqual("chiyue_valley_rock_environment_u0", catalog["style_family_id"])
            self.assertEqual("chiyue_valley_rock_wall_u0", catalog["wall_family_reference"])
        provenance_path = (
            ROOT
            / "assets/art/maps/_shared/terrain/chiyue_valley/source/chiyue_valley_environment_source_provenance.json"
        )
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        self.assertEqual("hard_planar_wet_cave_rock", provenance["material_contract"])
        self.assertIn("user-rejected diamond-shaped rock", provenance["rejected_source"])
        self.assertEqual(12, len(provenance["rock_assets"]))
        self.assertEqual(6, len(provenance["floor_assets"]))


if __name__ == "__main__":
    unittest.main()
