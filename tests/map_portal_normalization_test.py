from __future__ import annotations

import copy
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "map_editor" / "normalize_current_map_portals.py"
SPEC = importlib.util.spec_from_file_location("normalize_current_map_portals", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
NORMALIZER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = NORMALIZER
SPEC.loader.exec_module(NORMALIZER)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


class PortalFixture:
    """A small 67-document workspace assembled from the real network contract."""

    def __init__(self, root: Path, mode: str) -> None:
        self.root = root
        self.mode = mode
        source_registry = ROOT / "assets" / "data" / "map_design" / "map_identity_registry.json"
        source_network = ROOT / "assets" / "data" / "map_design" / "map_portal_network.json"
        self.workspace = root / "workspace"
        self.identity = root / "map_identity_registry.json"
        self.network = root / "map_portal_network.json"
        root.mkdir(parents=True, exist_ok=True)
        self.identity.write_bytes(source_registry.read_bytes())
        self.network.write_bytes(source_network.read_bytes())
        self.registry = read_json(self.identity)
        self.network_value = read_json(self.network)
        self._build()

    def _build(self) -> None:
        rows = self.registry["maps"]
        selected_by_formal = {
            row["map_id"]: (
                row["legacy_map_id"] if self.mode == "legacy" else row["map_id"],
                row["legacy_runtime_map_id"]
                if self.mode == "legacy"
                else row["runtime_map_id"],
            )
            for row in rows
        }
        formal_refs: list[tuple[str, str]] = []
        for connection in self.network_value["connections"]:
            if connection["mode"] == "bidirectional":
                formal_refs.extend(
                    [
                        (connection["a_map_id"], connection["a_portal_id"]),
                        (connection["b_map_id"], connection["b_portal_id"]),
                    ]
                )
            else:
                formal_refs.extend(
                    [
                        (connection["source_map_id"], connection["source_portal_id"]),
                        (connection["target_map_id"], connection["target_portal_id"]),
                    ]
                )
        tile_by_ref = {
            ref: [float(index + 1), float(index + 2)]
            for index, ref in enumerate(sorted(formal_refs))
        }
        bich_formal = "world_bich_province"
        bich_selected = selected_by_formal[bich_formal][0]
        for row in rows:
            formal_id = row["map_id"]
            selected_id, selected_runtime = selected_by_formal[formal_id]
            endpoint_ids = sorted(
                portal_id
                for map_id, portal_id in formal_refs
                if map_id == formal_id
            )
            endpoints: list[dict[str, Any]] = []
            for portal_id in endpoint_ids:
                endpoint = {
                    "content_layer": "personal_expansion",
                    "display_name": "前往" + portal_id,
                    "kind": "map_exit",
                    "semantic_id": portal_id,
                    "semantic_role": "map_portal_endpoint",
                    "tile": copy.deepcopy(tile_by_ref[(formal_id, portal_id)]),
                    "runtime_export": True,
                }
                if portal_id == "map_exit_000001" and formal_id in {
                    "bich_corpse_king_hall",
                    "mengzhong_zuma_leader_home",
                    "mengzhong_death_coffin",
                    "fengmo_final_hall",
                    "chiyue_demon_altar",
                    "chiyue_red_moon_lair",
                    "cangyue_bone_cave_f5",
                    "cangyue_bull_temple_hall",
                    "hidden_confusion_hall",
                    "hidden_hellfire",
                    "hidden_fallen_graveyard",
                    "hidden_death_temple",
                    "hidden_abyss_domain",
                    "hidden_pincer_nest",
                    "snake_unknown_dark_palace",
                }:
                    endpoint["display_name"] = "由祖玛阁进入，单向只可进入"
                    endpoint["semantic_role"] = "map_portal_arrival_anchor"
                if formal_id == bich_formal and portal_id == NORMALIZER.BICH_PORTAL_ID:
                    if self.mode == "legacy":
                        continue
                    endpoint.update(
                        {
                            "linked_visual_instance_id": "inst_bich_south",
                            "portal_anchor_contract_id": "linked_visual_footprint_center_v1",
                            "portal_visual_footprint_tiles": [6.0, 6.0],
                            "portal_visual_origin_tile": [73.0, 72.0],
                            "portal_trigger_policy_id": "bich_cave_mouth_explicit_v1",
                            "tile": [69.0, 72.0],
                        }
                    )
                endpoints.append(endpoint)
            door_points: list[dict[str, Any]] = []
            if formal_id == bich_formal and self.mode == "legacy":
                door_points.append(
                    {
                        "auto_created_from_asset": True,
                        "blocks_movement": False,
                        "content_layer": "personal_expansion",
                        "display_name": "由毒蛇山谷进入出口",
                        "door_id": "door.inst_bich_south",
                        "kind": "door",
                        "linked_visual_instance_id": "inst_bich_south",
                        "one_way": False,
                        "portal_anchor_contract_id": "linked_visual_footprint_center_v1",
                        "portal_trigger_policy_id": "bich_cave_mouth_explicit_v1",
                        "portal_visual_footprint_tiles": [6.0, 6.0],
                        "portal_visual_origin_tile": [73.0, 72.0],
                        "runtime_export": True,
                        "semantic_id": "door_bich_south",
                        "semantic_role": "map_portal",
                        "target_configured": False,
                        "tile": [69.0, 72.0],
                        "trigger_on_enter": True,
                    }
                )
            document = {
                "display_name": row["display_name"],
                "layers": {
                    "door_points": door_points,
                    "editor_guides": [{"freeze_marker": "untouched"}],
                    "map_exit_points": endpoints,
                    "monster_spawn": [{"monster_id": 17, "display_name": "冻结怪物"}],
                },
                "map_id": selected_id,
                "runtime_map_id": selected_runtime,
            }
            write_json(self.workspace / selected_id / f"{selected_id}.editor.json", document)

    def path(self, map_id: str) -> Path:
        return self.workspace / map_id / f"{map_id}.editor.json"

    def run(self, *, apply: bool = False) -> dict[str, Any]:
        return NORMALIZER.run(
            self.workspace,
            self.identity,
            self.network,
            self.mode,
            apply=apply,
        )


class MapPortalNormalizationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def fixture(self, mode: str) -> PortalFixture:
        return PortalFixture(Path(self.temp.name) / mode, mode)

    def test_legacy_promotion_and_legacy_target_identity(self) -> None:
        fixture = self.fixture("legacy")
        before = fixture.path("bich_province").read_bytes()
        dry = fixture.run()
        self.assertTrue(dry["dry_run"])
        self.assertIn("bich_province/bich_province.editor.json", dry["changed_files"])
        self.assertEqual(before, fixture.path("bich_province").read_bytes())

        result = fixture.run(apply=True)
        self.assertTrue(result["applied"])
        document = read_json(fixture.path("bich_province"))
        self.assertEqual([], document["layers"]["door_points"])
        south = next(
            endpoint
            for endpoint in document["layers"]["map_exit_points"]
            if endpoint["semantic_id"] == "map_exit_000005"
        )
        self.assertEqual("毒蛇山谷", south["display_name"])
        self.assertEqual([69.0, 72.0], south["tile"])
        self.assertEqual("snake_valley", south["target_map_key"])
        self.assertEqual(338, int(south["target_map_id"]))
        self.assertEqual("inst_bich_south", south["linked_visual_instance_id"])
        self.assertEqual("linked_visual_footprint_center_v1", south["portal_anchor_contract_id"])
        self.assertEqual(67, result["formal_docs"])
        self.assertEqual(132, result["portal_endpoints"])
        self.assertEqual(51, result["bidirectional_pairs"])
        self.assertEqual(15, result["one_way_sources"])
        self.assertEqual(15, result["arrival_anchors"])
        self.assertEqual(
            [{"freeze_marker": "untouched"}],
            document["layers"]["editor_guides"],
        )

    def test_formal_existing_endpoint_is_not_duplicated(self) -> None:
        fixture = self.fixture("formal")
        result = fixture.run(apply=True)
        document = read_json(fixture.path("world_bich_province"))
        south = [
            endpoint
            for endpoint in document["layers"]["map_exit_points"]
            if endpoint["semantic_id"] == "map_exit_000005"
        ]
        self.assertEqual(1, len(south))
        self.assertEqual("毒蛇山谷", south[0]["display_name"])
        self.assertEqual("world_snake_valley", south[0]["target_map_key"])
        self.assertEqual(910002, int(south[0]["target_map_id"]))
        self.assertEqual(132, result["portal_endpoints"])

    def test_delivery_backup_same_map_id_is_not_authority(self) -> None:
        fixture = self.fixture("legacy")
        backup = fixture.workspace / "_delivery_backups" / "bich_20260717_004728"
        backup.mkdir(parents=True)
        shutil.copy2(
            fixture.path("bich_province"),
            backup / "bich_province.editor.json",
        )
        result = fixture.run()
        self.assertTrue(result["ok"])
        self.assertEqual(67, result["formal_docs"])
        self.assertEqual(132, result["portal_endpoints"])

    def test_name_normalization_and_network_overrides(self) -> None:
        fixture = self.fixture("legacy")
        fixture.run(apply=True)
        bich = read_json(fixture.path("bich_province"))
        names = {
            endpoint["semantic_id"]: endpoint["display_name"]
            for endpoint in bich["layers"]["map_exit_points"]
        }
        self.assertEqual("兽人古墓", names["map_exit_000002"])
        self.assertEqual("比奇矿区", names["map_exit_000003"])
        self.assertEqual("毒蛇山谷", names["map_exit_000005"])
        self.assertNotIn("进入", names["map_exit_000001"])
        arrival = read_json(fixture.path("zmjzzj_2"))["layers"]["map_exit_points"][0]
        self.assertEqual("祖玛阁", arrival["display_name"])

    def test_apply_is_idempotent(self) -> None:
        fixture = self.fixture("legacy")
        fixture.run(apply=True)
        after_first = {
            path: path.read_bytes()
            for path in fixture.workspace.rglob("*.editor.json")
        }
        second = fixture.run(apply=True)
        self.assertEqual([], second["changed_files"])
        self.assertEqual(
            after_first,
            {path: path.read_bytes() for path in fixture.workspace.rglob("*.editor.json")},
        )

    def test_bad_endpoint_fails_closed_without_writes(self) -> None:
        fixture = self.fixture("formal")
        broken_path = fixture.path("bich_mine_f1")
        broken = read_json(broken_path)
        broken["layers"]["map_exit_points"] = [
            endpoint
            for endpoint in broken["layers"]["map_exit_points"]
            if endpoint["semantic_id"] != "map_exit_000001"
        ]
        write_json(broken_path, broken)
        before = {
            path: path.read_bytes()
            for path in fixture.workspace.rglob("*.editor.json")
        }
        with self.assertRaises(NORMALIZER.NormalizationError):
            fixture.run(apply=True)
        self.assertEqual(
            before,
            {path: path.read_bytes() for path in fixture.workspace.rglob("*.editor.json")},
        )


if __name__ == "__main__":
    unittest.main()
