"""Exploding Flame preview follows twenty original world-anchored frames."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import exploding_flame_editor, fireball_editor, hmg


class ExplodingFlameEditorTest(unittest.TestCase):
    def test_primary_frames_and_local_cleanup(self):
        rows = exploding_flame_editor.animation()["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(1660, 1680)))
        before_hashes = []
        for frame, row in enumerate(rows):
            source = exploding_flame_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            before_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(before_hashes[-1], row["png_sha256"])
            with Image.open(hmg.ROOT / row["path"]) as formal:
                self.assertEqual(formal.convert("RGBA").tobytes(),
                                 fireball_editor.clean_frame(source, 1.0).tobytes())
        with tempfile.TemporaryDirectory() as directory:
            workspace = exploding_flame_editor.Workspace(Path(directory) / "explosion.json")
            self.assertEqual(workspace.state()["frame_time_ms"], 80)
            with Image.open(io.BytesIO(workspace.image(10))) as original:
                original_alpha = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(10))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), original_alpha)
        self.assertEqual(
            [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest() for row in rows],
            before_hashes)


if __name__ == "__main__":
    unittest.main()
