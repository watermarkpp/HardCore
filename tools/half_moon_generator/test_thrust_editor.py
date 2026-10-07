"""Focused checks for the isolated long-hit animation preview."""

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import thrust_editor


class ThrustEditorTests(unittest.TestCase):
    def test_original_and_trial_keep_source_rgb_and_layout(self):
        source = thrust_editor.source_atlas()
        self.assertEqual(source.size, (1728, 1792))
        self.assertEqual(thrust_editor.clean_atlas(0).tobytes(), source.tobytes())
        trial = np.asarray(thrust_editor.clean_atlas(1.5))
        original = np.asarray(source)
        self.assertTrue(np.array_equal(trial[:, :, :3], original[:, :, :3]))
        self.assertLess(float(trial[:, :, 3].mean()), float(original[:, :, 3].mean()))
        self.assertEqual(int(trial[:, :, 3].max()), 255)
        self.assertTrue(np.any((trial[:, :, 3] > 0) & (trial[:, :, 3] < 255)))

    def test_preview_contains_six_frames_without_changing_formal_asset(self):
        formal_sha = hashlib.sha256(thrust_editor.FORMAL.read_bytes()).hexdigest()
        self.assertEqual(formal_sha, thrust_editor.APPROVED_SHA256)
        with tempfile.TemporaryDirectory() as folder:
            workspace = thrust_editor.Workspace(Path(folder) / "long_hit_project.json")
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
            for direction in range(8):
                with Image.open(io.BytesIO(workspace.image(direction, "heavy"))) as strip:
                    self.assertEqual(strip.size, (1920, 240))
                    for frame in range(6):
                        cell = strip.crop((frame * 320, 0, (frame + 1) * 320, 240))
                        self.assertIsNotNone(cell.getchannel("A").getbbox())
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            self.assertEqual(thrust_editor.Workspace(workspace.project_path).state()["haze_cleanup"], 1.5)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
            with self.assertRaises(ValueError):
                workspace.action({"action": "tune", "haze_cleanup": 3.1})
        self.assertEqual(hashlib.sha256(thrust_editor.FORMAL.read_bytes()).hexdigest(), formal_sha)

    def test_approved_150_percent_atlas_is_formal_runtime_asset(self):
        self.assertEqual(hashlib.sha256(thrust_editor.SOURCE.read_bytes()).hexdigest(),
                         thrust_editor.SOURCE_SHA256)
        atlas = thrust_editor.clean_atlas(thrust_editor.APPROVED_STRENGTH)
        buffer = io.BytesIO()
        atlas.save(buffer, format="PNG", optimize=False)
        self.assertEqual(hashlib.sha256(buffer.getvalue()).hexdigest(),
                         thrust_editor.APPROVED_SHA256)
        with Image.open(thrust_editor.FORMAL) as formal:
            self.assertEqual(formal.tobytes(), atlas.tobytes())
        import json
        manifest = json.loads((thrust_editor.hmg.ROOT /
                               "assets/data/warrior_client_art_sources.json")
                              .read_text(encoding="utf-8"))
        override = manifest["effects"]["刺杀剑术"]["approvedAtlasOverride"]
        self.assertEqual(override["atlasSha256"], thrust_editor.APPROVED_SHA256)
        self.assertEqual(override["sourceSha256"], thrust_editor.SOURCE_SHA256)
