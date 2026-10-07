"""Focused checks for the sharded fire-sword animation preview."""

import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.half_moon_generator import fire_editor


class FireEditorTests(unittest.TestCase):
    def test_archived_shards_keep_48_cells_and_approved_formal_identity(self):
        fire_editor.source_shards()
        for part, expected in fire_editor.SOURCE_HASHES.items():
            source = fire_editor.SOURCE_DIR / f"fire_hit_{part}_original.png"
            formal = fire_editor.FORMAL_DIR / f"fire_hit_{part}.png"
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), expected)
            self.assertEqual(hashlib.sha256(formal.read_bytes()).hexdigest(),
                             fire_editor.APPROVED_HASHES[part])
        for direction in range(8):
            for frame in range(6):
                self.assertEqual(fire_editor.source_cell(direction, frame).size, (640, 480))

    def test_trial_fades_dark_fire_without_changing_rgb_or_formal_shards(self):
        cell = fire_editor.source_cell(5, 3)
        self.assertEqual(fire_editor.clean_cell(cell, 0).tobytes(), cell.tobytes())
        trial = np.asarray(fire_editor.clean_cell(cell, 1.5))
        original = np.asarray(cell)
        self.assertTrue(np.array_equal(trial[:, :, :3], original[:, :, :3]))
        self.assertLess(float(trial[:, :, 3].mean()), float(original[:, :, 3].mean()))
        self.assertEqual(int(trial[:, :, 3].max()), 255)

    def test_editor_preview_and_saved_value_are_independent(self):
        with tempfile.TemporaryDirectory() as folder:
            workspace = fire_editor.Workspace(Path(folder) / "fire_project.json")
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
            for equipment in ("sword", "heavy"):
                with Image.open(io.BytesIO(workspace.image(1, equipment))) as strip:
                    self.assertEqual(strip.size, (4800, 624))
                    for frame in range(6):
                        cell = strip.crop((frame * 800, 0, (frame + 1) * 800, 624))
                        self.assertIsNotNone(cell.getchannel("A").getbbox())
            workspace.action({"action": "tune", "haze_cleanup": 1.5})
            self.assertEqual(fire_editor.Workspace(workspace.project_path).state()["haze_cleanup"], 1.5)
            workspace.action({"action": "undo"})
            self.assertEqual(workspace.state()["haze_cleanup"], 0.0)
            with self.assertRaises(ValueError):
                workspace.action({"action": "tune", "haze_cleanup": 3.1})

    def test_approved_30_percent_shards_are_reproducible(self):
        manifest = json.loads((fire_editor.hmg.ROOT /
                               "assets/data/warrior_client_art_sources.json")
                              .read_text(encoding="utf-8"))
        override = manifest["effects"]["烈火剑法"]["approvedShardsOverride"]
        self.assertEqual(override["darkFireCleanup"], fire_editor.APPROVED_STRENGTH)
        self.assertEqual(override["sourceSha256"], fire_editor.SOURCE_HASHES)
        self.assertEqual(override["shardSha256"], fire_editor.APPROVED_HASHES)
        for part in fire_editor.SOURCE_HASHES:
            atlas = fire_editor.clean_shard(part, fire_editor.APPROVED_STRENGTH)
            buffer = io.BytesIO()
            atlas.save(buffer, format="PNG", optimize=False)
            formal = fire_editor.FORMAL_DIR / f"fire_hit_{part}.png"
            self.assertEqual(hashlib.sha256(buffer.getvalue()).hexdigest(),
                             fire_editor.APPROVED_HASHES[part])
            self.assertEqual(buffer.getvalue(), formal.read_bytes())
