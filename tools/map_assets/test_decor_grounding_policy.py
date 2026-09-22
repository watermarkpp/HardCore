#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import unittest

from PIL import (
    Image,
    ImageDraw,
)

from decor_grounding_policy import (
    GROUNDING_POLICY_ID,
    calibrate_asset_geometry,
    category_occlusion,
    placement_anchor_px,
)


class DecorGroundingPolicyTests(
    unittest.TestCase
):

    def test_tall_pole_does_not_become_10_tiles_deep(
        self,
    ):
        image = Image.new(
            "RGBA",
            (64, 320),
            (0, 0, 0, 0),
        )

        draw = ImageDraw.Draw(
            image
        )

        # 高 300px，但是脚只有约 20px 宽。
        draw.rectangle(
            (22, 10, 42, 319),
            fill=(255, 255, 255, 255),
        )

        result = calibrate_asset_geometry(
            image,
            "旗帜",
            1.0,
        )

        self.assertEqual(
            result[
                "footprint_tiles"
            ],
            [1, 1],
        )

        self.assertEqual(
            result[
                "grounding_policy_id"
            ],
            GROUNDING_POLICY_ID,
        )

    def test_statue_base_controls_footprint(
        self,
    ):
        image = Image.new(
            "RGBA",
            (256, 320),
            (0, 0, 0, 0),
        )

        draw = ImageDraw.Draw(
            image
        )

        # 身体很高。
        draw.rectangle(
            (112, 20, 144, 270),
            fill=(255, 255, 255, 255),
        )

        # 底座约 128px 宽。
        draw.rectangle(
            (64, 270, 191, 319),
            fill=(255, 255, 255, 255),
        )

        result = calibrate_asset_geometry(
            image,
            "雕塑",
            1.0,
        )

        fp = result[
            "footprint_tiles"
        ]

        self.assertLessEqual(
            fp[0],
            3,
        )

        self.assertEqual(
            fp[0],
            fp[1],
        )

    def test_carpet_uses_flat_ground_geometry(
        self,
    ):
        image = Image.new(
            "RGBA",
            (192, 96),
            (255, 255, 255, 255),
        )

        result = calibrate_asset_geometry(
            image,
            "地毯",
            1.0,
        )

        self.assertEqual(
            result[
                "footprint_tiles"
            ],
            [3, 3],
        )

        self.assertFalse(
            category_occlusion(
                "地毯"
            )
        )

    def test_tree_is_occluder(
        self,
    ):
        self.assertTrue(
            category_occlusion(
                "树木"
            )
        )

    def test_placement_anchor_matches_project_policy(
        self,
    ):
        result = placement_anchor_px(
            [100, 300],
            [4, 4],
            [1.0, 1.0],
        )

        self.assertAlmostEqual(
            result[0],
            100.0,
        )

        self.assertAlmostEqual(
            result[1],
            236.0,
        )


if __name__ == "__main__":
    unittest.main()
