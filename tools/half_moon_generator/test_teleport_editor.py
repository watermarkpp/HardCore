"""Teleport preview stays tied to both original Magic.wil phases."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hmg, power_editor, teleport_editor


class TeleportEditorTest(unittest.TestCase):
    def test_both_phases_are_original_and_only_preview_is_edited(self):
        rows = teleport_editor.frames()
        self.assertEqual([row["source_index"] for row in rows], list(range(1590, 1610)))
        formal_hashes = []
        for index, row in enumerate(rows):
            source = teleport_editor.source_frame(index)
            formal_path = hmg.ROOT / row["path"]
            formal_hashes.append(hashlib.sha256(formal_path.read_bytes()).hexdigest())
            self.assertEqual(formal_hashes[-1], row["png_sha256"])
            self.assertEqual(list(source.size), row["pixel_size"])
            with Image.open(formal_path) as formal:
                self.assertEqual(formal.convert("RGBA").tobytes(),
                                 power_editor.clean_cell(source, 1.0).tobytes())
        with tempfile.TemporaryDirectory() as directory:
            workspace = teleport_editor.Workspace(Path(directory) / "teleport.json")
            self.assertEqual(workspace.state()["frame_count"], 20)
            self.assertEqual(workspace.state()["frame_time_ms"], 30)
            with Image.open(io.BytesIO(workspace.image(5))) as original:
                original_alpha = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            with Image.open(io.BytesIO(workspace.image(5))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), original_alpha)
            self.assertEqual(
                [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest()
                 for row in rows], formal_hashes)


if __name__ == "__main__":
    unittest.main()
