"""Ice Storm preview preserves the twenty original world-anchored frames."""

from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.half_moon_generator import hmg, ice_storm_editor


class IceStormEditorTest(unittest.TestCase):
    def test_primary_frames_and_local_preview(self):
        rows = ice_storm_editor.animation()["sequences"][0]["frames"]
        self.assertEqual([row["source_index"] for row in rows], list(range(3850, 3870)))
        before_hashes = []
        for frame, row in enumerate(rows):
            source = ice_storm_editor.source_frame(frame)
            self.assertEqual(list(source.size), row["pixel_size"])
            before_hashes.append(hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest())
            self.assertEqual(before_hashes[-1], row["png_sha256"])
            self.assertEqual(ice_storm_editor.approved_frame_png(frame),
                             (hmg.ROOT / row["path"]).read_bytes())
            with Image.open(io.BytesIO(ice_storm_editor.original_frame_png(frame))) as original:
                self.assertEqual(original.convert("RGBA").tobytes(), source.tobytes())
        with tempfile.TemporaryDirectory() as directory:
            workspace = ice_storm_editor.Workspace(Path(directory) / "ice_storm.json")
            self.assertEqual(workspace.state()["frame_time_ms"], 80)
            self.assertEqual(workspace.state()["center_rebase"], [0, 0])
            with Image.open(io.BytesIO(workspace.image(8))) as original:
                before_alpha = sum(original.getchannel("A").tobytes())
            workspace.action({"action": "tune", "haze_cleanup": 1.0})
            with Image.open(io.BytesIO(workspace.image(8))) as cleaned:
                self.assertLess(sum(cleaned.getchannel("A").tobytes()), before_alpha)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
        self.assertEqual(
            [hashlib.sha256((hmg.ROOT / row["path"]).read_bytes()).hexdigest() for row in rows],
            before_hashes)


if __name__ == "__main__":
    unittest.main()
