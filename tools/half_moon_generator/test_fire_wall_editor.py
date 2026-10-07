"""Fire Wall preview keeps the six source-pixel ground flame frames intact."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import fire_wall_editor, fireball_editor, hmg


class FireWallEditorTest(unittest.TestCase):
    def test_primary_frames_and_preview_cleanup(self):
        rows = fire_wall_editor.animation()["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(1630, 1636)))
        original_hashes = []
        for frame, row in enumerate(rows):
            source = fire_wall_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            original_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(original_hashes[-1], row["png_sha256"])
            with Image.open(hmg.ROOT / row["path"]) as formal:
                self.assertEqual(formal.convert("RGBA").tobytes(),
                                 fireball_editor.clean_frame(source, 1.0).tobytes())
        with tempfile.TemporaryDirectory() as directory:
            workspace = fire_wall_editor.Workspace(Path(directory) / "wall.json")
            self.assertEqual(workspace.state()["frame_time_ms"], 60)
            with Image.open(io.BytesIO(workspace.image(3))) as original:
                before = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(3))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), before)
        self.assertEqual(
            [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest() for row in rows],
            original_hashes)


if __name__ == "__main__":
    unittest.main()
