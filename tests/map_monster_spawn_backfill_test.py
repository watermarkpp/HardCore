from __future__ import annotations

import copy
import importlib.util
import json
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "tools"
    / "map_editor"
    / "backfill_approved_runtime_monster_spawns.py"
)
SPEC = importlib.util.spec_from_file_location("monster_spawn_backfill", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
BACKFILL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BACKFILL
SPEC.loader.exec_module(BACKFILL)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(BACKFILL.canonical_bytes(value))


class Fixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.source_root = root / "map_editor_workspace"
        self.runtime_root = root / "runtime"
        self.release_registry = root / "map_runtime_release_registry.json"
        self.identity_registry = root / "map_identity_registry.json"
        self.portal_overlay = root / "map_portal_network.json"
        self.candidate_output = root / "candidates"
        self.inventory_output = root / "inventory.json"
        self._build()

    def paths(self):
        return BACKFILL.AuditPaths(
            self.source_root,
            self.release_registry,
            self.runtime_root,
            self.identity_registry,
            self.portal_overlay,
            self.candidate_output,
            self.inventory_output,
        )

    def _build(self) -> None:
        (self.root / ".git").mkdir()
        release_rows = []
        identity_rows = []
        for index, map_id in enumerate(BACKFILL.TARGET_MAPS, start=1):
            runtime_id = 100 + index
            map_root = self.source_root / map_id
            manifest = map_root / "ground" / "ground_manifest.json"
            state = map_root / "ground" / "ground_state.json"
            write_json(manifest, {"map": map_id, "kind": "manifest"})
            write_json(state, {"map": map_id, "kind": "state", "blocked": []})
            source = {
                "schema_version": Decimal("4.0"),
                "map_id": map_id,
                "runtime_map_id": Decimal(runtime_id),
                "display_name": map_id,
                "content_layer": "personal_expansion",
                "editor_meta": {"revision": Decimal("1.0")},
                "design": {"design_size": [Decimal("8.0"), Decimal("8.0")]},
                "ground": {
                    "workspace_manifest": f"res://map_editor_workspace/{map_id}/ground/ground_manifest.json",
                    "workspace_state": f"res://map_editor_workspace/{map_id}/ground/ground_state.json",
                },
                "layers": {
                    "boss_spawn": [],
                    "editor_guides": [{"note": "frozen"}],
                    "monster_spawn": [],
                },
            }
            source_path = map_root / f"{map_id}.editor.json"
            write_json(source_path, source)
            (map_root / f"{map_id}.editor.json.bak").write_bytes(b"backup-frozen\n")

            monster = {
                "content_layer": "personal_expansion",
                "count": Decimal("1.0"),
                "kind": "monster_spawn",
                "max_alive": Decimal("1.0"),
                "monster_id": Decimal(20 + index),
                "radius_gu": Decimal("3.0"),
                "respawn_policy_id": "normal_cave",
                "runtime_export": True,
                "semantic_id": "monster_spawn_000001",
                "spawn_rule": "ambient",
                "tile": [Decimal("2.0"), Decimal("3.0")],
            }
            bosses = []
            if map_id == "wooma_temple_3":
                bosses = [{
                    "content_layer": "personal_expansion",
                    "count": Decimal("1.0"),
                    "kind": "boss_spawn",
                    "max_alive": Decimal("1.0"),
                    "monster_id": Decimal("76.0"),
                    "radius_gu": Decimal("0.0"),
                    "runtime_export": True,
                    "semantic_id": "boss_spawn_000001",
                    "spawn_group_id": "editor:105:boss:leader",
                    "spawn_rule": "boss",
                    "tile": [Decimal("4.0"), Decimal("4.0")],
                }]
            candidate = copy.deepcopy(source)
            candidate["layers"]["monster_spawn"] = [monster]
            candidate["layers"]["boss_spawn"] = bosses
            document_hash = BACKFILL.sha256_bytes(BACKFILL.canonical_bytes(candidate))
            fingerprint = {
                "document_sha256": document_hash,
                "ground_manifest_sha256": BACKFILL.sha256_file(manifest),
                "ground_state_sha256": BACKFILL.sha256_file(state),
            }
            binding = {
                "contract_id": BACKFILL.CANDIDATE_BINDING_CONTRACT,
                "map_key": map_id,
                "runtime_map_id": Decimal(runtime_id),
                "document_revision": Decimal("1.0"),
                **fingerprint,
                "authoring_sha256": BACKFILL.sha256_bytes(
                    BACKFILL.canonical_bytes(fingerprint)
                ),
            }
            runtime = {
                "build_sha256": "",
                "runtime_schema_version": Decimal("2.0"),
                "source": {
                    "map_id": map_id,
                    "runtime_map_id": Decimal(runtime_id),
                    "candidate_binding": binding,
                },
                "design": copy.deepcopy(source["design"]),
                "semantics": {
                    "monster_spawn": [monster],
                    "boss_spawn": bosses,
                },
            }
            runtime["build_sha256"] = BACKFILL.sha256_bytes(
                BACKFILL.canonical_bytes(runtime)
            )
            write_json(self.runtime_root / f"{map_id}.runtime.json", runtime)
            release_rows.append({
                "map_key": map_id,
                "runtime_map_id": Decimal(runtime_id),
                "runtime_path": f"res://assets/data/runtime/map_editor/{map_id}.runtime.json",
                "release_state": "implemented_playable",
                "approved_build_sha256": runtime["build_sha256"],
            })
            identity_rows.append({
                "legacy_map_id": map_id,
                "legacy_runtime_map_id": Decimal(runtime_id),
                "map_id": f"formal_{map_id}",
                "runtime_map_id": Decimal(900000 + index),
            })
        write_json(self.release_registry, {
            "schema_version": Decimal("1.0"),
            "registry_contract_id": BACKFILL.RELEASE_CONTRACT,
            "maps": release_rows,
        })
        write_json(self.identity_registry, {
            "schema_version": Decimal("1.0"),
            "contract_id": BACKFILL.IDENTITY_CONTRACT,
            "maps": identity_rows,
        })
        write_json(self.portal_overlay, {
            "schema_version": Decimal("1.0"),
            "contract_id": BACKFILL.PORTAL_CONTRACT,
            "identity_contract_id": BACKFILL.IDENTITY_CONTRACT,
            "connections": [],
        })


class MonsterSpawnBackfillTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.fixture = Fixture(Path(self.temp.name))

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_dry_run_is_ready_and_writes_nothing(self) -> None:
        inventory = BACKFILL.run(
            self.fixture.paths(), write_candidates=False, write_inventory=False
        )
        self.assertEqual("READY", inventory["overall_status"])
        self.assertEqual(5, inventory["summary"]["ready_map_count"])
        self.assertFalse(self.fixture.candidate_output.exists())
        self.assertFalse(self.fixture.inventory_output.exists())
        self.assertTrue(inventory["protected_input_proof"]["all_unchanged"])
        encoded = json.dumps(inventory, ensure_ascii=False)
        self.assertNotIn(str(self.fixture.root), encoded)
        self.assertNotIn(r"C:\Users\Administrator", encoded)
        self.assertNotIn("HardCore-worktrees", encoded)
        self.assertTrue(
            inventory["maps"][0]["source_editor"]["path"].startswith(
                "source_editor_root:bich_province/"
            )
        )

    def test_write_is_atomic_and_changes_only_two_layers(self) -> None:
        source_hashes = {
            map_id: BACKFILL.sha256_file(
                self.fixture.source_root / map_id / f"{map_id}.editor.json"
            )
            for map_id in BACKFILL.TARGET_MAPS
        }
        inventory = BACKFILL.run(
            self.fixture.paths(), write_candidates=True, write_inventory=True
        )
        self.assertEqual("candidate_write", inventory["mode"])
        self.assertTrue(self.fixture.inventory_output.is_file())
        for map_id in BACKFILL.TARGET_MAPS:
            source_path = self.fixture.source_root / map_id / f"{map_id}.editor.json"
            candidate_path = self.fixture.candidate_output / map_id / f"{map_id}.editor.json"
            runtime_path = self.fixture.runtime_root / f"{map_id}.runtime.json"
            self.assertEqual(source_hashes[map_id], BACKFILL.sha256_file(source_path))
            source = BACKFILL._load_json(source_path)
            candidate = BACKFILL._load_json(candidate_path)
            runtime = BACKFILL._load_json(runtime_path)
            self.assertEqual(
                BACKFILL._project_without_spawn_layers(source),
                BACKFILL._project_without_spawn_layers(candidate),
            )
            for layer in BACKFILL.SPAWN_LAYERS:
                self.assertEqual(runtime["semantics"][layer], candidate["layers"][layer])

    def test_registry_hash_mismatch_blocks_all_candidate_writes(self) -> None:
        registry = BACKFILL._load_json(self.fixture.release_registry)
        registry["maps"][0]["approved_build_sha256"] = "0" * 64
        write_json(self.fixture.release_registry, registry)
        inventory = BACKFILL.run(
            self.fixture.paths(), write_candidates=False, write_inventory=False
        )
        self.assertEqual("BLOCKED", inventory["overall_status"])
        self.assertIn(
            "approved_registry_hash_mismatch",
            {row["code"] for row in inventory["maps"][0]["blockers"]},
        )
        with self.assertRaisesRegex(BACKFILL.AuditError, "candidate_write_blocked"):
            BACKFILL.run(
                self.fixture.paths(), write_candidates=True, write_inventory=False
            )
        self.assertFalse(self.fixture.candidate_output.exists())

    def test_ground_or_non_spawn_drift_blocks_instead_of_guessing(self) -> None:
        target = BACKFILL.TARGET_MAPS[0]
        state = self.fixture.source_root / target / "ground" / "ground_state.json"
        state.write_bytes(state.read_bytes() + b" ")
        source_path = self.fixture.source_root / target / f"{target}.editor.json"
        source = BACKFILL._load_json(source_path)
        source["layers"]["editor_guides"][0]["note"] = "new-human-geometry"
        write_json(source_path, source)
        inventory = BACKFILL.run(
            self.fixture.paths(), write_candidates=False, write_inventory=False
        )
        codes = {row["code"] for row in inventory["maps"][0]["blockers"]}
        self.assertIn("ground_state_sha256_mismatch", codes)
        self.assertIn("candidate_binding_document_sha256_mismatch", codes)

    def test_explicit_authoring_evolution_mode_preserves_non_spawn_and_copies_exact_spawns(self) -> None:
        target = BACKFILL.TARGET_MAPS[0]
        state = self.fixture.source_root / target / "ground" / "ground_state.json"
        state.write_bytes(state.read_bytes() + b" ")
        source_path = self.fixture.source_root / target / f"{target}.editor.json"
        source = BACKFILL._load_json(source_path)
        source["layers"]["editor_guides"][0]["note"] = "new-human-geometry"
        write_json(source_path, source)
        inventory = BACKFILL.run(
            self.fixture.paths(),
            write_candidates=True,
            write_inventory=False,
            allow_authoring_evolution=True,
        )
        self.assertEqual("READY", inventory["overall_status"])
        row = inventory["maps"][0]
        self.assertFalse(row["proof"]["candidate_binding_matches"])
        self.assertTrue(row["proof"]["current_authoring_evolution_preserved"])
        candidate = BACKFILL._load_json(
            self.fixture.candidate_output / target / f"{target}.editor.json"
        )
        runtime = BACKFILL._load_json(
            self.fixture.runtime_root / f"{target}.runtime.json"
        )
        self.assertEqual(
            BACKFILL._project_without_spawn_layers(source),
            BACKFILL._project_without_spawn_layers(candidate),
        )
        for layer in BACKFILL.SPAWN_LAYERS:
            self.assertEqual(runtime["semantics"][layer], candidate["layers"][layer])

    def test_missing_runtime_spawn_field_is_a_blocker(self) -> None:
        target = BACKFILL.TARGET_MAPS[0]
        runtime_path = self.fixture.runtime_root / f"{target}.runtime.json"
        runtime = BACKFILL._load_json(runtime_path)
        runtime["semantics"]["monster_spawn"][0].pop("respawn_policy_id")
        runtime["build_sha256"] = ""
        runtime["build_sha256"] = BACKFILL.sha256_bytes(
            BACKFILL.canonical_bytes(runtime)
        )
        write_json(runtime_path, runtime)
        registry = BACKFILL._load_json(self.fixture.release_registry)
        registry["maps"][0]["approved_build_sha256"] = runtime["build_sha256"]
        write_json(self.fixture.release_registry, registry)
        inventory = BACKFILL.run(
            self.fixture.paths(), write_candidates=False, write_inventory=False
        )
        codes = {row["code"] for row in inventory["maps"][0]["blockers"]}
        self.assertIn("spawn_required_fields_missing", codes)

    def test_candidate_output_cannot_overlap_source(self) -> None:
        paths = self.fixture.paths()
        overlapping = BACKFILL.AuditPaths(
            paths.source_editor_root,
            paths.release_registry,
            paths.runtime_root,
            paths.identity_registry,
            paths.portal_overlay,
            paths.source_editor_root / "candidate",
            paths.inventory_output,
        )
        with self.assertRaisesRegex(BACKFILL.AuditError, "overlaps_protected_root"):
            BACKFILL.run(overlapping, write_candidates=False, write_inventory=False)


if __name__ == "__main__":
    unittest.main()
