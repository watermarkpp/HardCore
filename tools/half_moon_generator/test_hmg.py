"""Contract tests for the local Half Moon art tool."""

import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
import numpy as np

from tools.half_moon_generator import hmg, server


ROOT = Path(__file__).resolve().parents[2]
FORMAL = ROOT / "assets/art/characters/warrior/effects/wide_hit.png"
ORIGINAL_SOURCE = hmg.ORIGINAL_SOURCE


class HalfMoonGeneratorTests(unittest.TestCase):
    def test_original_editor_keeps_one_work_animation_and_moves_all_six_frames(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.json"
            with patch.object(hmg, "PROJECT_PATH", path):
                workspace = server.Workspace()
                state = workspace.state()
                self.assertEqual(len(workspace.project["candidates"]), 1)
                self.assertEqual(state["candidate"]["render_version"], 4)
                self.assertEqual(state["selected_id"], hmg.ORIGINAL_WORK_ID)
                self.assertNotIn("generations", state)
                candidate = workspace.project["candidates"][state["selected_id"]]
                before = [hmg.render_cell(candidate, 0, frame).getchannel("A").getbbox()
                          for frame in range(6)]
                workspace.action({"action": "nudge", "direction": 0, "dx": 1, "dy": 0})
                after = [hmg.render_cell(candidate, 0, frame).getchannel("A").getbbox()
                         for frame in range(6)]
                self.assertEqual(after, [(left + 1, top, right + 1, bottom)
                                         for left, top, right, bottom in before])
                self.assertEqual(hmg.load_project(path)["candidates"][state["selected_id"]]
                                 ["direction_overrides"]["S"]["offset_x"], 1)
                with self.assertRaises(ValueError):
                    workspace.action({"action": "generate", "preset": "minimal_classic", "seed": 1})
                workspace.action({"action": "undo"})
                self.assertEqual(hmg.render_cell(candidate, 0, 4).getchannel("A").getbbox(),
                                 before[4])
                workspace.action({"action": "tune", "changes": {"core_gain": .3}})
                self.assertEqual(workspace.state()["candidate"]["parameters"]["core_gain"], .3)
                workspace.action({"action": "undo"})
                self.assertEqual(workspace.state()["candidate"]["parameters"]["core_gain"], .22)

    def test_original_editor_preserves_existing_candidate_archive(self):
        project = hmg.new_project(11)
        selected = hmg.add_sw_reference_batch(project)[10]["candidate_id"]
        project["selected_id"] = selected
        archived = json.loads(json.dumps(project["candidates"]))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.json"
            hmg.save_project(project, path)
            with patch.object(hmg, "PROJECT_PATH", path):
                workspace = server.Workspace()
                self.assertEqual(workspace.state()["selected_id"], hmg.ORIGINAL_WORK_ID)
                self.assertEqual(len(workspace.project["candidates"]), len(archived) + 1)
                self.assertEqual({key: workspace.project["candidates"][key]
                                  for key in archived}, archived)

    def test_original_cleanup_has_gradient_alpha_and_exact_reset(self):
        candidate = hmg.new_original_project()["candidates"][hmg.ORIGINAL_WORK_ID]
        before_hash = hashlib.sha256(ORIGINAL_SOURCE.read_bytes()).hexdigest()
        with Image.open(ORIGINAL_SOURCE) as source:
            original = source.convert("RGBA").crop((4 * 240, 4 * 224, 5 * 240, 5 * 224))
        cleaned = hmg.render_cell(candidate, 0, 4)
        original_alpha = np.asarray(original.getchannel("A"))
        cleaned_alpha = np.asarray(cleaned.getchannel("A"))
        self.assertTrue(np.any((cleaned_alpha > 0) & (cleaned_alpha < 255)))
        self.assertTrue(np.any((original_alpha == 255) & (cleaned_alpha < 128)))
        self.assertNotEqual(cleaned.tobytes(), original.tobytes())
        candidate["parameters"] = {"haze_cleanup": 0, "body_brightness": 1,
                                   "core_gain": 0, "edge_detail": 0}
        self.assertEqual(hmg.render_cell(candidate, 0, 4).tobytes(), original.tobytes())
        self.assertEqual(hashlib.sha256(ORIGINAL_SOURCE.read_bytes()).hexdigest(), before_hash)

    def test_haze_cleanup_above_100_fades_gray_without_changing_color(self):
        candidate = hmg.new_original_project()["candidates"][hmg.ORIGINAL_WORK_ID]
        samples = []
        for strength in (1.0, 1.5, 2.0):
            candidate["parameters"]["haze_cleanup"] = strength
            samples.append(np.asarray(hmg.render_cell(candidate, 0, 4)).copy())
        with Image.open(ORIGINAL_SOURCE) as source:
            original = np.asarray(source.crop((4 * 240, 4 * 224,
                                               5 * 240, 5 * 224)).convert("RGBA"))
        luma = original[:, :, :3].astype(np.float32) @ np.array((.24, .57, .19))
        gray_body = (original[:, :, 3] == 255) & (luma > 30) & (luma < 100)
        self.assertGreater(int(gray_body.sum()), 100)
        means = [float(sample[:, :, 3][gray_body].mean()) for sample in samples]
        self.assertGreater(means[0], means[1])
        self.assertGreater(means[1], means[2])
        self.assertTrue(np.any((samples[2][:, :, 3] > 0) &
                               (samples[2][:, :, 3] < 255)))
        self.assertEqual(int(samples[2][:, :, 3].max()), 255)
        self.assertTrue(all(np.array_equal(sample[:, :, :3], samples[0][:, :, :3])
                            for sample in samples[1:]))

    def test_approved_150_percent_atlas_is_the_formal_runtime_asset(self):
        self.assertEqual(hashlib.sha256(ORIGINAL_SOURCE.read_bytes()).hexdigest(),
                         hmg.ORIGINAL_BASE_SHA256)
        self.assertEqual(hmg.APPROVED_PARAMETERS,
                         {"haze_cleanup": 1.5, "body_brightness": 1.0,
                          "core_gain": 0.0, "edge_detail": 0.0})
        atlas = hmg.approved_atlas()
        buffer = io.BytesIO()
        atlas.save(buffer, format="PNG", optimize=False)
        self.assertEqual(hashlib.sha256(buffer.getvalue()).hexdigest(),
                         hmg.APPROVED_ATLAS_SHA256)
        self.assertEqual(hashlib.sha256(FORMAL.read_bytes()).hexdigest(),
                         hmg.APPROVED_ATLAS_SHA256)
        with Image.open(FORMAL) as formal:
            self.assertEqual(formal.tobytes(), atlas.tobytes())
        manifest = json.loads((ROOT / "assets/data/warrior_client_art_sources.json")
                              .read_text(encoding="utf-8"))
        override = manifest["effects"]["半月弯刀"]["approvedAtlasOverride"]
        self.assertEqual(override["atlasSha256"], hmg.APPROVED_ATLAS_SHA256)
        self.assertEqual(override["sourceSha256"], hmg.ORIGINAL_BASE_SHA256)

    def test_legacy_render_is_pixel_stable(self):
        candidate = {"candidate_id": "HM_TEST", "seed": 123,
                     "parameters": hmg.preset_parameters("classic_heavy"),
                     "direction_overrides": {}}
        digest = hashlib.sha256(hmg.render_cell(candidate, 0, 3).tobytes()).hexdigest()
        self.assertEqual(digest, "14b7539288d382a7366d3baa4d44f3a24ce187147be953403d6e98ca196c8762")

    def test_temporal_batch_is_120_degree_two_tile_and_preserves_history(self):
        project = hmg.new_project(1839421)
        original = json.loads(json.dumps(project["candidates"]))
        children = hmg.add_temporal_batch(project)
        self.assertEqual(len(children), 12)
        self.assertEqual(project["candidates"] | original, project["candidates"])
        self.assertEqual({k: project["candidates"][k] for k in original}, original)
        self.assertEqual(project["generations"][-1]["kind"], "temporal_120_v2")
        self.assertTrue(all(c["render_version"] == 2 and
                            c["parameters"]["arc_span_degrees"] == 120 and
                            c["parameters"]["outer_radius"] <= 64 and
                            c["parameters"]["rotation"] == 0 for c in children))
        self.assertEqual(len({json.dumps(c["parameters"], sort_keys=True) for c in children}), 12)
        with self.assertRaises(ValueError):
            hmg.add_temporal_batch(project)

    def test_temporal_south_swing_starts_above_and_sweeps_right_to_left(self):
        candidate = hmg.add_temporal_batch(hmg.new_project(9))[0]
        frames = [np.asarray(hmg.render_cell(candidate, 0, f).getchannel("A")) for f in range(6)]
        metrics = []
        for alpha in frames:
            yy, xx = np.nonzero(alpha > 24)
            self.assertGreater(len(xx), 0)
            metrics.append((len(xx), float(xx.mean()), float(yy.mean()), int(alpha.max())))
        self.assertLess(metrics[0][2], metrics[2][2])
        self.assertLess(metrics[1][2], metrics[3][2])
        self.assertGreater(metrics[2][1], metrics[3][1])
        self.assertGreater(metrics[3][1], metrics[4][1])
        self.assertEqual(max(range(6), key=lambda f: metrics[f][0]), 4)
        self.assertLess(metrics[5][0], metrics[4][0])
        self.assertLess(metrics[5][3], metrics[4][3])

    def test_sw_reference_batch_uses_six_exact_sources_and_preserves_history(self):
        project = hmg.new_project(11)
        old = json.loads(json.dumps(project["candidates"]))
        children = hmg.add_sw_reference_batch(project)
        self.assertEqual(len(children), 12)
        self.assertEqual({k: project["candidates"][k] for k in old}, old)
        self.assertEqual(project["generations"][-1]["kind"], "sw_reference_v3")
        self.assertTrue(all(c["render_version"] == 3 for c in children))
        with self.assertRaises(ValueError):
            hmg.add_sw_reference_batch(project)

    def test_sw_reference_shape_starts_small_peaks_mid_and_fades(self):
        candidate = hmg.add_sw_reference_batch(hmg.new_project(11))[4]
        frames = [np.asarray(hmg.render_cell(candidate, 1, f).getchannel("A")) for f in range(6)]
        boxes = [hmg.render_cell(candidate, 1, f).getchannel("A").getbbox()
                 for f in range(6)]
        self.assertGreaterEqual(boxes[4][2] - boxes[4][0], 155)
        area = [int(np.count_nonzero(alpha > 32)) for alpha in frames]
        self.assertLess(area[0], area[1])
        self.assertLess(area[1], area[2])
        self.assertGreater(area[3], area[0] * 3)
        self.assertGreater(area[4], area[0] * 3)
        self.assertGreater(area[3], area[5])
        self.assertLess(int(frames[5].max()), int(frames[3].max()))

    def test_sw_reference_bakes_all_eight_directions_without_clipping(self):
        for candidate in hmg.add_sw_reference_batch(hmg.new_project(11)):
            atlas = hmg.bake(candidate)
            cells = hmg.inspect_cells(atlas)
            self.assertEqual(len(cells), 48)
            self.assertTrue(all(cell["alpha_pixels"] > 0 for cell in cells))
            self.assertEqual(hmg.warnings_for(atlas, candidate), [], candidate["candidate_id"])

    def test_sw_reference_cardinal_arcs_keep_their_width_and_facing(self):
        candidate = hmg.add_sw_reference_batch(hmg.new_project(11))[4]
        bounds = {direction: hmg.render_cell(candidate, direction, 4).getchannel("A").getbbox()
                  for direction in (0, 1, 2, 4, 6)}
        for direction in (0, 4):
            left, top, right, bottom = bounds[direction]
            self.assertGreaterEqual(right - left, 155)
            self.assertGreater((right - left) / (bottom - top), 1.5)
        self.assertLess((bounds[1][2] - bounds[1][0]) /
                        (bounds[1][3] - bounds[1][1]), 1.5)
        self.assertLess(bounds[2][0], bounds[4][0])
        self.assertGreater(bounds[6][2], bounds[4][2])

    def test_direction_position_adjustment_moves_only_selected_direction(self):
        project = hmg.new_project(11)
        candidate = hmg.add_sw_reference_batch(project)[4]
        baseline_s = hmg.render_cell(candidate, 0, 4).getchannel("A").getbbox()
        baseline_sw = hmg.render_cell(candidate, 1, 4).tobytes()
        hmg.edit_candidate(project, candidate["candidate_id"],
                           {"offset_x": 3, "offset_y": -2}, direction="S")
        moved_s = hmg.render_cell(candidate, 0, 4).getchannel("A").getbbox()
        self.assertEqual(moved_s, (baseline_s[0] + 3, baseline_s[1] - 2,
                                    baseline_s[2] + 3, baseline_s[3] - 2))
        self.assertEqual(hmg.render_cell(candidate, 1, 4).tobytes(), baseline_sw)
        self.assertEqual(len(candidate["revisions"]), 1)

    def test_sw_reference_mutation_and_reload_keep_source_version(self):
        project = hmg.new_project(11)
        source = hmg.add_sw_reference_batch(project)[4]
        children = hmg.add_mutation(project, source["candidate_id"])
        self.assertTrue(all(c["render_version"] == 3 and
                            c["parent_id"] == source["candidate_id"] for c in children))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.json"
            hmg.save_project(project, path)
            loaded = hmg.load_project(path)
            self.assertEqual(loaded["candidates"][children[0]["candidate_id"]], children[0])

    def test_temporal_bake_is_repeatable_and_all_directions_occupied(self):
        candidate = hmg.add_temporal_batch(hmg.new_project(11))[0]
        first = hmg.bake(candidate)
        self.assertEqual(first.tobytes(), hmg.bake(candidate).tobytes())
        self.assertTrue(all(cell["alpha_pixels"] > 0 for cell in hmg.inspect_cells(first)))
        self.assertEqual(hmg.warnings_for(first), [])

    def test_half_moon_candidate_seed_deterministic(self):
        first = hmg.first_generation(1839421)
        self.assertEqual(first, hmg.first_generation(1839421))
        self.assertEqual(len(first), 12)
        self.assertEqual(len({json.dumps(c["parameters"], sort_keys=True) for c in first}), 12)

    def test_first_batch_has_visible_controlled_variation(self):
        first = hmg.first_generation(1839421)
        for group in (first[:4], first[4:8], first[8:12]):
            spans = [c["parameters"]["arc_span_degrees"] for c in group]
            thicknesses = [c["parameters"]["arc_thickness"] for c in group]
            self.assertGreaterEqual(max(spans) - min(spans), 30)
            self.assertGreaterEqual(max(thicknesses) - min(thicknesses), 5)

    def test_curated_batch_preserves_earlier_user_candidates(self):
        project = hmg.new_project(1839421)
        old = json.loads(json.dumps(project["candidates"]["HM_G01_A1"]))
        curated = hmg.add_curated_batch(project)
        self.assertEqual(len(curated), 12)
        self.assertEqual(project["candidates"]["HM_G01_A1"], old)
        self.assertEqual(curated[0]["candidate_id"], "HM_G02_A1")

    def test_half_moon_variant_parent(self):
        parent = hmg.first_generation(7)[6]
        children = hmg.mutate(parent, 8)
        self.assertEqual(len(children), 12)
        self.assertTrue(all(c["parent_id"] == parent["candidate_id"] for c in children))
        self.assertTrue(all(c["seed"] != parent["seed"] for c in children))
        self.assertEqual(children, hmg.mutate(parent, 8))

    def test_half_moon_direction_count(self):
        self.assertEqual(len(hmg.DIRECTIONS), 8)
        self.assertEqual(hmg.DIRECTION_ROWS, (4, 5, 6, 7, 0, 1, 2, 3))
        self.assertIn("return [4, 5, 6, 7, 0, 1, 2, 3][direction_index(direction)]",
                      (ROOT / "scripts/art_spec.gd").read_text(encoding="utf-8"))

    def test_half_moon_frame_count(self):
        self.assertEqual(hmg.FRAMES, 6)
        self.assertEqual(len(hmg.FRAME_ENVELOPE), hmg.FRAMES)
        self.assertGreater(hmg.FRAME_ENVELOPE[2], hmg.FRAME_ENVELOPE[0])
        self.assertGreater(hmg.FRAME_ENVELOPE[3], hmg.FRAME_ENVELOPE[5])

    def test_half_moon_bake_dimensions_and_alpha(self):
        atlas = hmg.bake(hmg.first_generation(19)[0])
        self.assertEqual(atlas.size, (1440, 1792))
        self.assertEqual(atlas.mode, "RGBA")
        self.assertEqual(atlas.getchannel("A").getextrema()[0], 0)
        self.assertGreater(atlas.getchannel("A").getextrema()[1], 0)
        self.assertEqual(len(hmg.inspect_cells(atlas)), 48)
        self.assertTrue(all(cell["alpha_pixels"] > 0 for cell in hmg.inspect_cells(atlas)))

    def test_half_moon_original_never_overwritten_by_preview(self):
        before = hashlib.sha256(FORMAL.read_bytes()).hexdigest()
        hmg.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=hmg.OUTPUT_DIR) as folder:
            target = Path(folder) / "preview.png"
            hmg.bake_preview(hmg.first_generation(31)[0], target)
            self.assertTrue(target.is_file())
        self.assertEqual(before, hashlib.sha256(FORMAL.read_bytes()).hexdigest())

    def test_half_moon_publish_requires_explicit_path(self):
        with self.assertRaises(ValueError):
            hmg.bake_preview(hmg.first_generation(31)[0], FORMAL)

    def test_half_moon_runtime_contract_unchanged(self):
        visual = (ROOT / "scripts/player_visual.gd").read_text(encoding="utf-8")
        combat = (ROOT / "scripts/warrior_combat_math.gd").read_text(encoding="utf-8")
        self.assertIn('"半月弯刀": {"asset": "wide_hit", "cell": Vector2i(240, 224), "origin": Vector2i(96, 143)}', visual)
        self.assertIn("const CLIENT_EFFECT_FRAME := 2", combat)
        with Image.open(FORMAL) as image:
            self.assertEqual(image.size, (1440, 1792))

    def test_project_history_favorites_and_fusion_survive_reload(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.json"
            project = hmg.new_project(54)
            parent = project["generations"][0]["candidate_ids"][0]
            hmg.add_mutation(project, parent)
            hmg.set_favorite(project, parent, True)
            hmg.add_fusion(project, parent, project["generations"][0]["candidate_ids"][5], parent, parent)
            hmg.save_project(project, path)
            loaded = hmg.load_project(path)
            self.assertEqual(len(loaded["generations"]), 2)
            self.assertTrue(loaded["candidates"][parent]["favorite"])
            self.assertEqual(len(loaded["candidates"]), 25)

    def test_generate_twelve_keeps_earlier_generation(self):
        project = hmg.new_project(54)
        original = tuple(project["generations"][0]["candidate_ids"])
        second = hmg.add_generation(project, "minimal_classic", 99)
        self.assertEqual(len(second), 12)
        self.assertEqual(tuple(project["generations"][0]["candidate_ids"]), original)
        self.assertTrue(all(c["preset"] == "minimal_classic" for c in second))
        self.assertTrue(all(c["parameters"]["arc_span_degrees"] == 120 for c in second))
        self.assertGreaterEqual(max(c["parameters"]["arc_radius"] for c in second) -
                                min(c["parameters"]["arc_radius"] for c in second), 8)

    def test_real_warrior_preview_has_six_nonempty_frames(self):
        strip = hmg.actor_strip(0, "base")
        self.assertEqual(strip.size, (1440, 224))
        self.assertTrue(all(strip.crop((f * 240, 0, (f + 1) * 240, 224)).getbbox()
                            for f in range(6)))
        self.assertEqual(hmg.weapon_anchor("weapon_004_attack.png"), (68, 112))

    def test_direction_override_changes_only_selected_direction(self):
        candidate = hmg.first_generation(64)[0]
        before_s = hmg.render_cell(candidate, 0, 3).tobytes()
        before_ne = hmg.render_cell(candidate, 5, 3).tobytes()
        candidate["direction_overrides"]["NE"] = {"offset_y": -20}
        self.assertEqual(before_s, hmg.render_cell(candidate, 0, 3).tobytes())
        self.assertNotEqual(before_ne, hmg.render_cell(candidate, 5, 3).tobytes())

    def test_technical_gradient_and_frame_curve_are_validated(self):
        project = hmg.new_project(22)
        candidate_id = project["selected_id"]
        hmg.edit_candidate(project, candidate_id, {
            "gradient": {"core": "#ffffff", "body": "#bb8844",
                         "outer": "#443322", "trail": "#775533"},
            "frame_envelope": [0.1, 0.4, 1.0, 1.1, 0.6, 0.2],
        })
        self.assertEqual(project["candidates"][candidate_id]["parameters"]["gradient"]["core"], "#ffffff")
        with self.assertRaises(ValueError):
            hmg.edit_candidate(project, candidate_id, {"gradient": {"core": "red"}})

    def test_technical_parameters_change_rendered_pixels(self):
        baseline = hmg.first_generation(171)[0]
        baseline["parameters"]["spark_count"] = 6
        source = hashlib.sha256(hmg.render_cell(baseline, 0, 3).tobytes()).hexdigest()
        for key, value in (("perspective_compression", .4), ("trail_falloff", .2),
                           ("breakup_scale", 6.0), ("spark_lifetime", .8),
                           ("spark_velocity", 15.0)):
            changed = json.loads(json.dumps(baseline))
            changed["parameters"][key] = value
            digest = hashlib.sha256(hmg.render_cell(changed, 0, 3).tobytes()).hexdigest()
            self.assertNotEqual(source, digest, key)

    def test_contact_sheet_export_is_development_output(self):
        candidate = hmg.first_generation(117)[0]
        path = hmg.export_contact_sheet(candidate)
        self.assertTrue(path.is_relative_to(hmg.OUTPUT_DIR.resolve()))
        with Image.open(path) as image:
            self.assertEqual(image.size, (1440, 1792))

    def test_edit_preserves_prior_parameters_for_recovery(self):
        project = hmg.new_project(12)
        candidate_id = project["selected_id"]
        old = project["candidates"][candidate_id]["parameters"]["arc_radius"]
        hmg.edit_candidate(project, candidate_id, {"arc_radius": old + 1})
        self.assertEqual(project["candidates"][candidate_id]["revisions"][0]["parameters"]["arc_radius"], old)

    def test_visual_checker_detects_empty_and_clipped_cells(self):
        atlas = hmg.bake(hmg.first_generation(42)[0])
        atlas.paste(Image.new("RGBA", (240, 224)), (0, 0))
        self.assertTrue(any(w.startswith("EMPTY_FRAME row=0 frame=0") for w in hmg.warnings_for(atlas)))
        atlas.paste(Image.new("RGBA", (240, 224), (255, 255, 255, 255)), (240, 0))
        warnings = hmg.warnings_for(atlas)
        self.assertTrue(any(w.startswith("CLIPPED_EDGE row=0 frame=1") for w in warnings))
        self.assertTrue(any(w.startswith("FULL_SCREEN_ALPHA row=0 frame=1") for w in warnings))


if __name__ == "__main__":
    unittest.main()
