"""Hell Lightning preview keeps original frames and sequence-centred origin."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hell_lightning_editor, hmg


class HellLightningEditorTest(unittest.TestCase):
    def test_primary_frames_and_local_preview(self):
        animation = hell_lightning_editor.animation()
        rows = animation["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(1680, 1690)))
        original_hashes = []
        for frame, row in enumerate(rows):
            source = hell_lightning_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            original_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(original_hashes[-1], row["png_sha256"])
        with tempfile.TemporaryDirectory() as directory:
            workspace = hell_lightning_editor.Workspace(Path(directory) / "hell_lightning.json")
            self.assertEqual(workspace.state()["center_rebase"], [8.5, 26.0])
            with Image.open(io.BytesIO(workspace.image(4))) as original:
                before = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(4))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), before)
        self.assertEqual(
            [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest() for row in rows],
            original_hashes)


if __name__ == "__main__":
    unittest.main()
