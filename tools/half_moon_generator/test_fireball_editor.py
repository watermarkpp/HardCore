"""Production fireball preview stays tied to the active 16x6 frame manifest."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import fireball_editor


class FireballEditorTest(unittest.TestCase):
    def test_zero_strength_preserves_every_production_frame(self):
        sequences = fireball_editor.animation()["sequences"]
        self.assertEqual((len(sequences), len(sequences[0]["frames"])), (16, 6))
        for direction, sequence in enumerate(sequences):
            for frame, row in enumerate(sequence["frames"]):
                source = fireball_editor.source_frame(direction, frame)
                self.assertEqual(hashlib.sha256(
                    (fireball_editor.hmg.ROOT / row["path"]).read_bytes()
                ).hexdigest(), row["png_sha256"])
                with Image.open(fireball_editor.hmg.ROOT / row["path"]) as formal:
                    np.testing.assert_array_equal(
                        np.asarray(formal),
                        np.asarray(fireball_editor.clean_frame(source, 1.5)))
                np.testing.assert_array_equal(
                    np.asarray(fireball_editor.clean_frame(source, 0)), np.asarray(source))

    def test_preview_tune_only_changes_project_and_dark_alpha(self):
        formal = fireball_editor.source_frame(8, 3)
        before = np.asarray(formal)
        with tempfile.TemporaryDirectory() as temp:
            workspace = fireball_editor.Workspace(Path(temp) / "fireball.json")
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            after = np.asarray(fireball_editor.clean_frame(formal, 1.5))
            np.testing.assert_array_equal(after[:, :, :3], before[:, :, :3])
            self.assertLess(int(after[:, :, 3].sum()), int(before[:, :, 3].sum()))
            self.assertEqual(workspace.state()["haze_cleanup"], 1.5)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0)
            np.testing.assert_array_equal(np.asarray(fireball_editor.source_frame(8, 3)), before)


if __name__ == "__main__":
    unittest.main()
