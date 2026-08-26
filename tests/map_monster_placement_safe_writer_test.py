"""Self-contained tests for the map authoring snapshot and safe writer."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WRITER_PATH = ROOT / "tools" / "map_editor" / "map_monster_placement_safe_writer.py"
TRACKED_SNAPSHOT_PATH = ROOT / "assets" / "data" / "map_design" / "map_authoring_snapshot_20260826.json"
SPEC = importlib.util.spec_from_file_location("map_monster_placement_safe_writer", WRITER_PATH)
assert SPEC is not None and SPEC.loader is not None
WRITER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WRITER)


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _synthetic_registry() -> dict[str, object]:
    return {
        "contract_id": "hardcore.formal_map_identity.v1",
        "formal_map_count": 2,
        "maps": [
            {
                "legacy_map_id": "map_a",
                "map_id": "world_map_a",
                "runtime_map_id": 910001,
                "legacy_runtime_map_id": 1001,
                "display_name": "Synthetic A",
            },
            {
                "legacy_map_id": "map_b",
                "map_id": "world_map_b",
                "runtime_map_id": 910002,
                "legacy_runtime_map_id": 1002,
                "display_name": "Synthetic B",
            },
        ],
    }


def _authority_token(
    map_id: str,
    legacy_map_id: str,
    *,
    source_line: int,
    source_category_role: str,
    source_token_index: int,
    placement_kind: str,
    monster_ids: list[int],
    auto_allowed: bool,
    auto_status: str,
    status: str = "resolved",
    resolution_status: str = "resolved",
    placement_allowed: bool = True,
) -> dict[str, object]:
    return {
        "raw_token": f"token-{source_line}-{source_token_index}",
        "normalized_token": f"token-{source_line}-{source_token_index}",
        "source_line": source_line,
        "source_category": source_category_role,
        "source_category_role": source_category_role,
        "source_token_index": source_token_index,
        "resolution_kind": "unique_exact_monster_id" if len(monster_ids) == 1 else "canonical_variant_group",
        "classification": source_category_role,
        "placement_kind": placement_kind,
        "placement_allowed": placement_allowed,
        "auto_placement_status": auto_status,
        "auto_placement_allowed": auto_allowed,
        "status": status,
        "resolution_status": resolution_status,
        "resolved_monster_ids": monster_ids,
        "resolved_variant_codes": [""] * len(monster_ids),
        "resolved_canonical_names": [f"Monster {monster_id}" for monster_id in monster_ids],
        "resolved_monster_id": monster_ids[0] if len(monster_ids) == 1 else None,
        "map_id": map_id,
        "runtime_id": 910001 if legacy_map_id == "map_a" else 910002,
        "runtime_map_id": 910001 if legacy_map_id == "map_a" else 910002,
        "legacy_map_id": legacy_map_id,
        "legacy_runtime_id": 1001 if legacy_map_id == "map_a" else 1002,
    }


def _synthetic_authority() -> dict[str, object]:
    map_a = "world_map_a"
    map_b = "world_map_b"
    return {
        "schema_version": 2,
        "manifest_id": "hardcore.map_monster_placement_authority.v2",
        "contract_id": "hardcore.map_monster_placement_authority.v2",
        "summary": {"formal_map_count": 2},
        "maps": [
            {
                "map_id": map_a,
                "legacy_map_id": "map_a",
                "tokens": [
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=10,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[21],
                        auto_allowed=True,
                        auto_status="AUTO_PLACEMENT_ALLOWED",
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=11,
                        source_category_role="special",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[23],
                        auto_allowed=False,
                        auto_status="SPECIAL_SYSTEM_REQUIRED",
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=12,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[22],
                        auto_allowed=False,
                        auto_status="EXPLICIT_PLACEMENT_REQUIRED",
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=13,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[24, 25],
                        auto_allowed=True,
                        auto_status="AUTO_PLACEMENT_ALLOWED",
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=14,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[],
                        auto_allowed=False,
                        auto_status="EXPLICIT_PLACEMENT_REQUIRED",
                        status="blocked",
                        resolution_status="blocked",
                        placement_allowed=False,
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=15,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[],
                        auto_allowed=False,
                        auto_status="INTENTIONALLY_EXCLUDED",
                        status="excluded",
                        resolution_status="intentionally_excluded",
                        placement_allowed=False,
                    ),
                    _authority_token(
                        map_a,
                        "map_a",
                        source_line=20,
                        source_category_role="elite",
                        source_token_index=1,
                        placement_kind="boss_spawn",
                        monster_ids=[50],
                        auto_allowed=True,
                        auto_status="AUTO_PLACEMENT_ALLOWED",
                    ),
                ],
            },
            {
                "map_id": map_b,
                "legacy_map_id": "map_b",
                "tokens": [
                    _authority_token(
                        map_b,
                        "map_b",
                        source_line=10,
                        source_category_role="ordinary",
                        source_token_index=1,
                        placement_kind="monster_spawn",
                        monster_ids=[31],
                        auto_allowed=True,
                        auto_status="AUTO_PLACEMENT_ALLOWED",
                    )
                ],
            },
        ],
    }


def _synthetic_layers() -> dict[str, list[object]]:
    return {name: [] for name in WRITER.KNOWN_LAYER_NAMES}


def _synthetic_document(legacy_map_id: str, runtime_map_id: int, *, blocked: bool) -> dict[str, object]:
    layers = _synthetic_layers()
    if blocked:
        layers["collision"] = [
            {
                "blocks_monster": True,
                "shape": "rect",
                "data": {"rect": [2.0, 2.0, 1.0, 1.0]},
            }
        ]
        # This erase cell proves the writer follows the editor collision
        # order without making the fixture depend on a production map.
        layers["collision_erase"] = [{"tile": [3.0, 3.0]}]
        layers["object_base"] = [
            {
                "tile": [1.0, 4.0],
                "collision_policy": "solid_footprint",
                "collision_footprint_tiles": [2.0, 2.0],
                "footprint_tiles": [2.0, 2.0],
            }
        ]
        layers["door_points"] = [{"tile": [4.0, 4.0]}]
        layers["map_exit_points"] = [{"tile": [5.0, 5.0]}]
        layers["map_entrance_points"] = [{"tile": [7.0, 7.0]}]
        layers["npc_points"] = [
            {"tile": [6.0, 6.0], "occupancy_footprint_tiles": [1.0, 1.0]}
        ]
        layers["safe_area"] = [
            {"tile": [0.0, 7.0], "shape": "circle", "radius_tiles": 0.0}
        ]
        layers["respawn_points"] = [{"tile": [0.0, 1.0]}]
    return {
        "map_id": legacy_map_id,
        "runtime_map_id": runtime_map_id,
        "display_name": f"Synthetic {legacy_map_id}",
        "design": {"design_size": [8.0, 8.0]},
        "layers": layers,
    }


class MapMonsterPlacementSafeWriterTest(unittest.TestCase):
    """Exercise source immutability, snapshot drift, and placement guards."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="map_monster_safe_writer_")
        self.temp_root = Path(self.temp_dir.name)
        self.source_root = self.temp_root / "source"
        self.registry_path = self.temp_root / "map_identity_registry.json"
        self.portal_path = self.temp_root / "portal_overlay.json"
        self.authority_path = self.temp_root / "map_monster_placement_authority_v2.json"
        self.snapshot_path = self.temp_root / "snapshot.json"
        _write_json(self.registry_path, _synthetic_registry())
        _write_json(self.authority_path, _synthetic_authority())
        _write_json(
            self.portal_path,
            {
                "bidirectional_pair_count": 1,
                "connections": [
                    {
                        "mode": "bidirectional",
                        "a_map_id": "map_a",
                        "a_portal_id": "exit_a",
                        "b_map_id": "map_b",
                        "b_portal_id": "entrance_b",
                    }
                ],
            },
        )
        _write_json(
            self.source_root / "map_a" / "map_a.editor.json",
            _synthetic_document("map_a", 1001, blocked=True),
        )
        _write_json(
            self.source_root / "map_b" / "map_b.editor.json",
            _synthetic_document("map_b", 1002, blocked=False),
        )
        self.snapshot_kwargs = {
            "registry_path": self.registry_path,
            "portal_overlay_path": self.portal_path,
            "require_formal_count": False,
        }
        self.writer_kwargs = {
            **self.snapshot_kwargs,
            "authority_path": self.authority_path,
        }
        WRITER.build_snapshot(self.source_root, self.snapshot_path, **self.snapshot_kwargs)
        self.map_id = "map_a"
        self.source_file = self.source_root / self.map_id / f"{self.map_id}.editor.json"
        self.source_document = json.loads(self.source_file.read_text(encoding="utf-8"))
        self.output_path = self.temp_root / "candidate-output" / "map_a.candidate.json"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _legal_tile(self) -> list[int]:
        size = WRITER._document_size(self.source_document, legacy_map_id=self.map_id)
        blocked = WRITER._collect_static_blocked(self.source_document, size)
        for y in range(size[1]):
            for x in range(size[0]):
                if (x, y) not in blocked:
                    return [x, y]
        self.fail("fixture has no walkable tile")

    def _placement(self, *, tile: list[int] | None = None) -> dict[str, object]:
        return {
            "layers": {
                "monster_spawn": [
                    {
                        "kind": "monster_spawn",
                        "monster_id": 21,
                        "spawn_group_id": "synthetic.phase0.field.a",
                        "respawn_policy_id": "beginner_outdoor",
                        "semantic_id": "monster_spawn.phase0.000001",
                        "authority_ref": {
                            "map_id": "world_map_a",
                            "source_line": 10,
                            "source_category_role": "ordinary",
                            "source_token_index": 1,
                        },
                        "tile": tile or self._legal_tile(),
                        "count": 1,
                        "max_alive": 1,
                        "radius_gu": 2.0,
                    }
                ],
                "boss_spawn": [],
            }
        }

    def _placement_file(self, value: dict[str, object], name: str = "placement.json") -> Path:
        path = self.temp_root / name
        _write_json(path, value)
        return path

    def _write(self, placement: dict[str, object], *, output: Path | None = None, dry_run: bool = True) -> dict[str, object]:
        return WRITER.write_candidate(
            self.source_root,
            self.snapshot_path,
            self.map_id,
            self._placement_file(placement),
            output or self.output_path,
            dry_run=dry_run,
            **self.writer_kwargs,
        )

    def test_tracked_snapshot_structure_is_67_maps_and_has_no_host_absolute_paths(self) -> None:
        raw = TRACKED_SNAPSHOT_PATH.read_text(encoding="utf-8")
        self.assertNotRegex(raw, r"[A-Za-z]:[\\/]")
        snapshot = json.loads(raw)
        self.assertEqual(snapshot["formal_map_count"], 67)
        self.assertEqual(len(snapshot["maps"]), 67)
        self.assertEqual(snapshot["portal_overlay"]["statistics"]["connection_count"], 66)
        self.assertEqual(
            snapshot["portal_overlay"]["statistics"]["mode_counts"],
            {"bidirectional": 51, "one_way": 15},
        )
        self.assertEqual(snapshot["portal_overlay"]["statistics"]["map_count"], 67)
        required = {
            "ground",
            "collision",
            "collision_erase",
            "instances",
            "map_exits",
            "door",
            "safe",
            "respawn",
            "npc",
            "monster_spawn",
            "boss_spawn",
        }
        for record in snapshot["maps"]:
            self.assertTrue(required.issubset(record["layers"]))
            self.assertFalse(Path(record["source_relative_path"]).is_absolute())
            self.assertEqual(record["source_sha256"], record["sha256"])
            self.assertEqual(record["source_mtime_ns"], record["mtime_ns"])
            self.assertEqual(record["layer_counts"]["collision"], record["layers"]["collision"]["count"])
            self.assertEqual(record["layer_hashes"]["collision"], record["layers"]["collision"]["sha256"])

    def test_synthetic_snapshot_and_verify_cover_all_fixture_maps_and_portals(self) -> None:
        snapshot = json.loads(self.snapshot_path.read_text(encoding="utf-8"))
        self.assertEqual(snapshot["formal_map_count"], 2)
        self.assertEqual(len(snapshot["maps"]), 2)
        self.assertEqual(snapshot["portal_overlay"]["statistics"]["connection_count"], 1)
        self.assertEqual(snapshot["portal_overlay"]["statistics"]["endpoint_count"], 2)
        for record in snapshot["maps"]:
            self.assertEqual(
                record["source_relative_path"],
                f"{record['legacy_map_id']}/{record['legacy_map_id']}.editor.json",
            )
            self.assertFalse(Path(record["source_relative_path"]).is_absolute())
        result = WRITER.verify_snapshot(self.source_root, self.snapshot_path, **self.snapshot_kwargs)
        self.assertEqual(result["source_map_sha256_verified"], 2)

    def test_production_registry_count_remains_locked_without_fixture_opt_out(self) -> None:
        with self.assertRaisesRegex(WRITER.SafeWriterError, "expected=67"):
            WRITER.build_snapshot(
                self.source_root,
                self.temp_root / "strict.json",
                registry_path=self.registry_path,
                portal_overlay_path=self.portal_path,
            )

    def test_valid_candidate_changes_only_two_spawn_layers_and_does_not_touch_source(self) -> None:
        before_bytes = {
            path: path.read_bytes()
            for path in self.source_root.glob("*/*.editor.json")
        }
        before_bak = list(self.source_root.rglob("*.bak"))
        report = self._write(self._placement(), dry_run=False)
        self.assertTrue(report["written"])
        self.assertTrue(report["non_target_fields_unchanged"])
        self.assertEqual(report["authority_sha256"], _sha256(self.authority_path))
        self.assertEqual(
            before_bytes,
            {path: path.read_bytes() for path in self.source_root.glob("*/*.editor.json")},
        )
        self.assertEqual(before_bak, list(self.source_root.rglob("*.bak")))

        candidate = json.loads(self.output_path.read_text(encoding="utf-8"))
        source = json.loads(before_bytes[self.source_file].decode("utf-8"))
        self.assertEqual(WRITER._non_target_document(source), WRITER._non_target_document(candidate))
        self.assertEqual(len(candidate["layers"]["monster_spawn"]), 1)
        self.assertEqual(candidate["layers"]["boss_spawn"], [])

    def test_default_dry_run_writes_no_candidate(self) -> None:
        report = self._write(self._placement())
        self.assertEqual(report["mode"], "dry-run")
        self.assertFalse(self.output_path.exists())

    def test_invalid_map_id_and_snapshot_drift_fail_closed(self) -> None:
        placement_file = self._placement_file(self._placement(), "invalid_map.json")
        with self.assertRaisesRegex(WRITER.SafeWriterError, "map-id-must-match-one"):
            WRITER.write_candidate(
                self.source_root,
                self.snapshot_path,
                "not_a_registry_map",
                placement_file,
                self.output_path,
                **self.writer_kwargs,
            )

        original = self.source_file.read_bytes()
        self.source_file.write_bytes(original + b"\n")
        with self.assertRaisesRegex(WRITER.SafeWriterError, "snapshot-drift-fail-closed"):
            WRITER.verify_snapshot(self.source_root, self.snapshot_path, **self.snapshot_kwargs)

    def test_collision_safe_door_exit_entrance_npc_and_solid_object_are_rejected(self) -> None:
        blocked_tiles = {
            "collision": [2, 2],
            "safe": [0, 7],
            "solid object": [1, 4],
            "door": [4, 4],
            "map exit": [5, 5],
            "map entrance": [7, 7],
            "npc": [6, 6],
        }
        for label, tile in blocked_tiles.items():
            with self.subTest(label=label):
                with self.assertRaisesRegex(WRITER.SafeWriterError, "landing-blocked"):
                    self._write(self._placement(tile=tile))

    def test_missing_stable_id_or_policy_and_non_target_input_are_rejected(self) -> None:
        placement = self._placement()
        del placement["layers"]["monster_spawn"][0]["authority_ref"]
        with self.assertRaisesRegex(WRITER.SafeWriterError, "authority_ref-required"):
            self._write(placement)

        placement = self._placement()
        del placement["layers"]["monster_spawn"][0]["spawn_group_id"]
        with self.assertRaisesRegex(WRITER.SafeWriterError, "spawn_group_id-required"):
            self._write(placement)

        placement = self._placement()
        del placement["layers"]["monster_spawn"][0]["respawn_policy_id"]
        with self.assertRaisesRegex(WRITER.SafeWriterError, "respawn_policy_id-required"):
            self._write(placement)

        placement = self._placement()
        placement["layers"]["monster_spawn"][0]["semantic_id"] = "random-uuid-0001"
        with self.assertRaisesRegex(WRITER.SafeWriterError, "random-or-uuid-forbidden"):
            self._write(placement)

        non_target = {"layers": {"monster_spawn": [], "collision": []}}
        with self.assertRaisesRegex(WRITER.SafeWriterError, "non-target-layer-forbidden"):
            self._write(non_target)

    def test_authority_reference_must_be_current_auto_allowed_unique_token(self) -> None:
        cases = {
            "wrong map": {
                "map_id": "world_map_b",
                "source_line": 10,
                "source_category_role": "ordinary",
                "source_token_index": 1,
            },
            "special system": {
                "map_id": "world_map_a",
                "source_line": 11,
                "source_category_role": "special",
                "source_token_index": 1,
            },
            "explicit required": {
                "map_id": "world_map_a",
                "source_line": 12,
                "source_category_role": "ordinary",
                "source_token_index": 1,
            },
            "unresolved blocked": {
                "map_id": "world_map_a",
                "source_line": 14,
                "source_category_role": "ordinary",
                "source_token_index": 1,
            },
            "excluded": {
                "map_id": "world_map_a",
                "source_line": 15,
                "source_category_role": "ordinary",
                "source_token_index": 1,
            },
        }
        for label, reference in cases.items():
            with self.subTest(label=label):
                placement = self._placement()
                placement["layers"]["monster_spawn"][0]["authority_ref"] = reference
                with self.assertRaises(WRITER.SafeWriterError):
                    self._write(placement)

        placement = self._placement()
        placement["layers"]["monster_spawn"][0]["monster_id"] = 34
        with self.assertRaisesRegex(WRITER.SafeWriterError, "authority_ref-monster-id-mismatch"):
            self._write(placement)

        placement = self._placement()
        placement["layers"]["monster_spawn"][0]["authority_ref"] = {
            "map_id": "world_map_a",
            "source_line": 13,
            "source_category_role": "ordinary",
            "source_token_index": 1,
        }
        placement["layers"]["monster_spawn"][0]["monster_id"] = 24
        with self.assertRaisesRegex(WRITER.SafeWriterError, "authority_ref-monster-id-not-unique"):
            self._write(placement)

    def test_invalid_geometry_and_candidate_overlap_are_rejected(self) -> None:
        placement = self._placement(tile=[8, 0])
        with self.assertRaisesRegex(WRITER.SafeWriterError, "tile-out-of-bounds"):
            self._write(placement)

        placement = self._placement()
        placement["layers"]["monster_spawn"].append(
            {
                "monster_id": 21,
                "spawn_group_id": "synthetic.phase0.field.b",
                "respawn_policy_id": "normal_cave",
                "semantic_id": "monster_spawn.phase0.000002",
                "authority_ref": {
                    "map_id": "world_map_a",
                    "source_line": 10,
                    "source_category_role": "ordinary",
                    "source_token_index": 1,
                },
                "tile": placement["layers"]["monster_spawn"][0]["tile"],
            }
        )
        with self.assertRaisesRegex(WRITER.SafeWriterError, "overlaps-candidate"):
            self._write(placement)

    def test_output_inside_source_root_or_runtime_path_is_rejected(self) -> None:
        with self.assertRaisesRegex(WRITER.SafeWriterError, "outside-source-root"):
            self._write(self._placement(), output=self.source_root / "candidate.json")
        with self.assertRaisesRegex(WRITER.SafeWriterError, "path-forbidden"):
            self._write(self._placement(), output=self.temp_root / "runtime" / "candidate.json")


if __name__ == "__main__":
    unittest.main()
