"""Hellfire preview follows primary frames and the formal six-segment trail."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import fireball_editor, hellfire_editor


class HellfireEditorTest(unittest.TestCase):
    def test_primary_frames_and_trail_geometry(self):
        profile = hellfire_editor.animation()
        rows = profile["animation"]["sequences"][0]["frames"]
        self.assertEqual(len(rows), 6)
        self.assertEqual(hellfire_editor.emission_count((160, 80)), 6)
        self.assertEqual(profile["render"]["trajectory_step_ms"], 50)
        self.assertEqual(hellfire_editor.sequence_center(), [
            (min(row["top_left_from_world_anchor"][0] for row in rows)
             + max(row["top_left_from_world_anchor"][0] + row["pixel_size"][0] for row in rows)) / 2,
            (min(row["top_left_from_world_anchor"][1] for row in rows)
             + max(row["top_left_from_world_anchor"][1] + row["pixel_size"][1] for row in rows)) / 2,
        ])
        for frame, row in enumerate(rows):
            source = hellfire_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            self.assertEqual(hashlib.sha256(
                (hellfire_editor.hmg.ROOT / row["path"]).read_bytes()
            ).hexdigest(), row["png_sha256"])
            with Image.open(hellfire_editor.hmg.ROOT / row["path"]) as formal:
                np.testing.assert_array_equal(
                    np.asarray(formal.convert("RGBA")),
                    np.asarray(fireball_editor.clean_frame(source, 1.5)))

    def test_cleanup_stays_local_and_preserves_rgb(self):
        source = hellfire_editor.source_frame(4)
        before = np.asarray(source)
        with tempfile.TemporaryDirectory() as directory:
            workspace = hellfire_editor.Workspace(Path(directory) / "hellfire.json")
            self.assertEqual(workspace.state()["haze_cleanup"], 1.0)
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            after = np.asarray(fireball_editor.clean_frame(source, 1.5))
            np.testing.assert_array_equal(after[:, :, :3], before[:, :, :3])
            self.assertLess(int(after[:, :, 3].sum()), int(before[:, :, 3].sum()))
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 1.0)


if __name__ == "__main__":
    unittest.main()
