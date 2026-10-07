"""Magic Shield preview keeps ten primary frames and the actor-footpoint origin."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import magic_shield_editor, hmg


class MagicShieldEditorTest(unittest.TestCase):
    def test_primary_frames_and_local_preview(self):
        animation = magic_shield_editor.animation()
        rows = animation["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(3880, 3890)))
        original_hashes = []
        for frame, row in enumerate(rows):
            source = magic_shield_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            original_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(original_hashes[-1], row["png_sha256"])
        with tempfile.TemporaryDirectory() as directory:
            workspace = magic_shield_editor.Workspace(Path(directory) / "magic_shield.json")
            self.assertEqual(workspace.state()["center_rebase"], [7.5, 0.0])
            actor_png, actor_offset = magic_shield_editor.actor_idle_frame()
            with Image.open(io.BytesIO(actor_png)) as actor:
                self.assertEqual(actor.size, (192, 160))
                self.assertIsNotNone(actor.getchannel("A").getbbox())
            self.assertEqual(workspace.state()["actor_offset"], actor_offset)
            self.assertEqual(actor_offset, [-88.5, -95.5])
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
