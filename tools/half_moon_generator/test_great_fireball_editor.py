"""Great Fireball preview reads the formal primary projectile frames."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import fireball_editor, great_fireball_editor, hmg


class GreatFireballEditorTest(unittest.TestCase):
    def test_original_directions_and_local_preview(self):
        animation = great_fireball_editor.animation()
        rows = [row for sequence in animation["sequences"] for row in sequence["frames"]]
        self.assertEqual(len(rows), 96)
        for direction in range(16):
            for frame in range(6):
                row = animation["sequences"][direction]["frames"][frame]
                self.assertEqual(row["source_index"], 410 + direction * 10 + frame)
                self.assertEqual(great_fireball_editor.source_frame(direction, frame).size,
                                 tuple(row["pixel_size"]))
                with Image.open(hmg.ROOT / row["path"]) as formal:
                    self.assertEqual(formal.convert("RGBA").tobytes(),
                                     fireball_editor.clean_frame(
                                         great_fireball_editor.source_frame(direction, frame), 1.5).tobytes())
        formal_path = hmg.ROOT / rows[50]["path"]
        formal_hash = hashlib.sha256(formal_path.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            workspace = great_fireball_editor.Workspace(Path(directory) / "great_fireball.json")
            self.assertEqual(workspace.state()["frame_time_ms"], 50)
            with Image.open(io.BytesIO(workspace.image(8, 2))) as original:
                before = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(8, 2))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), before)
            self.assertEqual(hashlib.sha256(formal_path.read_bytes()).hexdigest(), formal_hash)


if __name__ == "__main__":
    unittest.main()
