"""The repulsion editor follows the production ten-frame source and anchor."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import fireball_editor, repulsion_editor


class RepulsionEditorTest(unittest.TestCase):
    def test_all_ten_original_frames_match_the_formal_manifest(self):
        rows = repulsion_editor.animation()["sequences"][0]["frames"]
        self.assertEqual(len(rows), 10)
        for index, row in enumerate(rows):
            source = repulsion_editor.source_frame(index)
            with Image.open(repulsion_editor.hmg.ROOT / row["path"]) as formal:
                np.testing.assert_array_equal(
                    np.asarray(formal),
                    np.asarray(fireball_editor.clean_frame(source, 1.0)))
            self.assertEqual(hashlib.sha256(
                (repulsion_editor.hmg.ROOT / row["path"]).read_bytes()
            ).hexdigest(), row["png_sha256"])
        self.assertEqual(rows[-1]["pixel_size"], [4, 1])

    def test_preview_tuning_changes_only_alpha_and_local_project(self):
        source = repulsion_editor.source_frame(5)
        before = np.asarray(source)
        with tempfile.TemporaryDirectory() as temp:
            workspace = repulsion_editor.Workspace(Path(temp) / "repulsion.json")
            self.assertEqual(workspace.state()["center_rebase"], [9.0, 42.0])
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            after = np.asarray(fireball_editor.clean_frame(source, 1.5))
            np.testing.assert_array_equal(after[:, :, :3], before[:, :, :3])
            self.assertLess(int(after[:, :, 3].sum()), int(before[:, :, 3].sum()))
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0)


if __name__ == "__main__":
    unittest.main()
