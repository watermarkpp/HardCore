"""Focused checks for the isolated power-hit animation editor."""

import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.half_moon_generator import power_editor


class PowerEditorTests(unittest.TestCase):
    def test_cleanup_preserves_source_rgb_and_gently_fades_dark_body(self):
        source = power_editor.source_atlas()
        self.assertEqual(power_editor.clean_atlas(0).tobytes(), source.tobytes())
        one = np.asarray(power_editor.clean_atlas(1.0))
        two = np.asarray(power_editor.clean_atlas(2.0))
        three = np.asarray(power_editor.clean_atlas(3.0))
        self.assertTrue(np.array_equal(one[:, :, :3], two[:, :, :3]))
        self.assertTrue(np.array_equal(two[:, :, :3], three[:, :, :3]))
        self.assertTrue(np.array_equal(one[:, :, :3], np.asarray(source)[:, :, :3]))
        self.assertLess(float(two[:, :, 3].mean()), float(one[:, :, 3].mean()))
        self.assertLess(float(three[:, :, 3].mean()), float(two[:, :, 3].mean()))
        self.assertEqual(int(two[:, :, 3].max()), 255)
        self.assertTrue(np.any((two[:, :, 3] > 0) & (two[:, :, 3] < 255)))

    def test_editor_is_independent_and_does_not_replace_formal_asset(self):
        original_sha = hashlib.sha256(power_editor.FORMAL.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "power_project.json"
            workspace = power_editor.Workspace(path)
            self.assertEqual(workspace.state()["haze_cleanup"], 2.0)
            self.assertEqual(workspace.state()["formal_sha256"], original_sha)
            self.assertGreater(len(workspace.image(1, "heavy")), 1000)
            workspace.action({"action": "tune", "haze_cleanup": 2.75})
            self.assertEqual(power_editor.Workspace(path).state()["haze_cleanup"], 2.75)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 2.0)
            with self.assertRaises(ValueError):
                workspace.action({"action": "tune", "haze_cleanup": 3.1})
        self.assertEqual(hashlib.sha256(power_editor.FORMAL.read_bytes()).hexdigest(),
                         original_sha)

    def test_approved_200_percent_atlas_is_formal_runtime_asset(self):
        self.assertEqual(hashlib.sha256(power_editor.SOURCE.read_bytes()).hexdigest(),
                         power_editor.SOURCE_SHA256)
        atlas = power_editor.clean_atlas(power_editor.APPROVED_STRENGTH)
        buffer = io.BytesIO()
        atlas.save(buffer, format="PNG", optimize=False)
        self.assertEqual(hashlib.sha256(buffer.getvalue()).hexdigest(),
                         power_editor.APPROVED_SHA256)
        self.assertEqual(hashlib.sha256(power_editor.FORMAL.read_bytes()).hexdigest(),
                         power_editor.APPROVED_SHA256)
        from PIL import Image
        with Image.open(power_editor.FORMAL) as formal:
            self.assertEqual(formal.tobytes(), atlas.tobytes())
        manifest = json.loads((power_editor.hmg.ROOT /
                               "assets/data/warrior_client_art_sources.json")
                              .read_text(encoding="utf-8"))
        override = manifest["effects"]["攻杀剑术"]["approvedAtlasOverride"]
        self.assertEqual(override["atlasSha256"], power_editor.APPROVED_SHA256)
        self.assertEqual(override["sourceSha256"], power_editor.SOURCE_SHA256)
