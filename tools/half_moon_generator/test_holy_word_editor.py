"""Holy Word preview reads the target-attached original frames without publishing them."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hmg, holy_word_editor


class HolyWordEditorTest(unittest.TestCase):
    def test_original_frames_and_reversible_preview(self):
        rows = holy_word_editor.animation()["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(3930, 3946)))
        original_hashes = []
        for frame, row in enumerate(rows):
            self.assertEqual(list(holy_word_editor.source_frame(frame).size), row["pixel_size"])
            original_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(original_hashes[-1], row["png_sha256"])
        with tempfile.TemporaryDirectory() as directory:
            workspace = holy_word_editor.Workspace(Path(directory) / "holy_word.json")
            self.assertEqual(workspace.state()["frame_time_ms"], 80)
            with Image.open(io.BytesIO(workspace.image(3))) as original:
                before = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(3))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), before)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
        self.assertEqual(
            [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest() for row in rows],
            original_hashes)


if __name__ == "__main__":
    unittest.main()
