"""Lightning preview reads primary Magic2.wil without editing formal frames."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.half_moon_generator import lightning_editor, power_editor


class LightningEditorTest(unittest.TestCase):
    def test_reads_all_six_primary_frames(self):
        rows = lightning_editor.animation()["sequences"][0]["frames"]
        self.assertEqual(len(rows), 6)
        self.assertEqual(hashlib.sha256(lightning_editor.PRIMARY_WIL.read_bytes()).hexdigest(),
                         lightning_editor.PRIMARY_WIL_SHA256)
        for frame, row in enumerate(rows):
            image = lightning_editor.source_frame(frame)
            self.assertEqual(list(image.size), row["pixel_size"])
            self.assertEqual(row["source_index"], 10 + frame)

    def test_preview_cleanup_preserves_color_and_source(self):
        image = lightning_editor.source_frame(1)
        source = np.asarray(image).copy()
        with tempfile.TemporaryDirectory() as temporary:
            workspace = lightning_editor.Workspace(Path(temporary) / "lightning.json")
            self.assertEqual(workspace.state()["haze_cleanup"], 1.5)
            workspace.action({"action": "tune", "haze_cleanup": 2.0})
            result = np.asarray(power_editor.clean_cell(image, 2.0))
            np.testing.assert_array_equal(result[:, :, :3], source[:, :, :3])
            self.assertLess(int(result[:, :, 3].sum()), int(source[:, :, 3].sum()))
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 1.5)


if __name__ == "__main__":
    unittest.main()
