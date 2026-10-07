"""Temptation Light preview uses the actual target-attached primary frames."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import fireball_editor, power_editor, temptation_editor


class TemptationEditorTest(unittest.TestCase):
    def test_primary_and_formal_sources_match_all_sixteen_frames(self):
        rows = temptation_editor.animation()["sequences"][0]["frames"]
        self.assertEqual(len(rows), 16)
        for frame, row in enumerate(rows):
            source = temptation_editor.source_frame(frame)
            with Image.open(temptation_editor.hmg.ROOT / row["path"]) as formal:
                np.testing.assert_array_equal(np.asarray(formal),
                                              np.asarray(power_editor.clean_cell(source, 1.5)))
            self.assertEqual(hashlib.sha256(
                (temptation_editor.hmg.ROOT / row["path"]).read_bytes()
            ).hexdigest(), row["png_sha256"])

    def test_preview_change_is_local_and_preserves_blue_white_rgb(self):
        source = temptation_editor.source_frame(8)
        before = np.asarray(source)
        with tempfile.TemporaryDirectory() as temp:
            workspace = temptation_editor.Workspace(Path(temp) / "temptation.json")
            self.assertEqual(workspace.state()["center_rebase"], [0, 0])
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            after = np.asarray(power_editor.clean_cell(source, 1.5))
            np.testing.assert_array_equal(after[:, :, :3], before[:, :, :3])
            self.assertLess(int(after[:, :, 3].sum()), int(before[:, :, 3].sum()))
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0)


if __name__ == "__main__":
    unittest.main()
