#!/usr/bin/env python3
"""Migrate the accepted formal map workspaces to canonical identities and portals.

The dirty maps worktree is read-only authority.  This tool mirrors only its 67
formal workspaces into a separate task worktree, leaves sandbox_64 untouched,
then performs a deterministic identity/portal metadata migration.  It never
decodes or rewrites PNG files and never rebuilds authored map content.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SANDBOX_ID = "sandbox_64"
IDENTITY_CONTRACT = "hardcore.formal_map_identity.v1"
NETWORK_CONTRACT = "hardcore.formal_map_portal_network.v1"
CONNECTION_POLICY = "map_connection_unified_bidirectional_v2"
PORTAL_CONTRACT = "unified_map_portal_endpoint_v1"
ARRIVAL_POLICY = "portal_arrival_guard_v2"


@dataclass(frozen=True)
class Identity:
    old: str
    new: str
    runtime: int
    series: str


def identities() -> list[Identity]:
    rows: list[Identity] = [
        Identity("bich_province", "world_bich_province", 910001, "world"),
        Identity("snake_valley", "world_snake_valley", 910002, "world"),
        Identity("mengzhong_province", "world_mengzhong_province", 910003, "world"),
        Identity("wooma_forest", "world_wooma_forest", 910004, "world"),
        Identity("fmg_1", "world_fengmo_valley", 910005, "world"),
        Identity("brm_2", "world_white_day_gate", 910006, "world"),
        Identity("cyd_1", "world_cangyue_island", 910007, "world"),
    ]
    rows += [Identity(f"orc_tomb_{n}", f"bich_orc_tomb_f{n}", 911000 + n, "bich_orc_tomb") for n in range(1, 4)]
    rows += [
        Identity("bich_mine_1", "bich_mine_f1", 911101, "bich_mine"),
        Identity("bich_mine_2", "bich_mine_f2", 911102, "bich_mine"),
        Identity("corpse_king_hall", "bich_corpse_king_hall", 911103, "bich_mine"),
        Identity("connection_passage_1", "snake_mine_passage_1", 912001, "snake_mine"),
        Identity("connection_passage_2", "snake_mine_passage_2", 912002, "snake_mine"),
        Identity("quest_1", "snake_unknown_dark_palace", 912003, "snake_mine"),
    ]
    rows += [Identity(f"stone_tomb_{n}", f"mengzhong_stone_tomb_f{n}", 913000 + n, "mengzhong_stone_tomb") for n in range(1, 5)]
    rows += [Identity(f"zuma_temple_{n}", f"mengzhong_zuma_temple_f{n}", 913100 + n, "mengzhong_zuma") for n in range(1, 5)]
    rows += [
        Identity("zumage_1", "mengzhong_zuma_pavilion", 913105, "mengzhong_zuma"),
        Identity("zmjzzj_2", "mengzhong_zuma_leader_home", 913106, "mengzhong_zuma"),
        Identity("swsg_2", "mengzhong_death_valley_dungeon", 913201, "mengzhong_death_valley"),
        Identity("sgcw_2", "mengzhong_stone_coffin_room", 913202, "mengzhong_death_valley"),
        Identity("hadd_2", "mengzhong_dark_area", 913203, "mengzhong_death_valley"),
        Identity("between_life_and_death", "mengzhong_between_life_and_death", 913204, "mengzhong_death_valley"),
        Identity("terror_space", "mengzhong_terror_space", 913205, "mengzhong_death_valley"),
        Identity("thin_sky_passage", "mengzhong_thin_sky_passage", 913206, "mengzhong_death_valley"),
        Identity("death_coffin", "mengzhong_death_coffin", 913207, "mengzhong_death_valley"),
        Identity("ql_1", "fengmo_forked_path", 914001, "fengmo_route"),
        Identity("gmhl_1", "fengmo_light_corridor", 914002, "fengmo_route"),
        Identity("gmhl_thunder_road", "fengmo_thunder_road", 914003, "fengmo_route"),
        Identity("gmhl_bazhe_hall", "fengmo_bazhe_hall", 914004, "fengmo_route"),
        Identity("gmhl_zonghengdao", "fengmo_zonghengdao", 914005, "fengmo_route"),
        Identity("gmhl_mohun_dian", "fengmo_mohun_hall", 914006, "fengmo_route"),
        Identity("gmhl_purgatory_corridor", "fengmo_purgatory_corridor", 914007, "fengmo_route"),
        Identity("gmhl_fengmo_dian", "fengmo_final_hall", 914008, "fengmo_route"),
        Identity("wooma_temple_1", "wooma_temple_f1", 915001, "wooma_temple"),
        Identity("wooma_temple_2", "wooma_temple_f2", 915002, "wooma_temple"),
        Identity("wooma_temple_3", "wooma_temple_boss_hall", 915003, "wooma_temple"),
        Identity("cyxg_2", "chiyue_valley", 916001, "chiyue"),
        Identity("cyxggc_2", "chiyue_valley_square", 916002, "chiyue"),
        Identity("chiyue_choice_land", "chiyue_choice_land", 916003, "chiyue"),
        Identity("chiyue_valley_secret_passage_a", "chiyue_valley_secret_passage_a", 916004, "chiyue"),
        Identity("chiyue_valley_secret_passage_b", "chiyue_valley_secret_passage_b", 916005, "chiyue"),
        Identity("emjt_2", "chiyue_demon_altar", 916006, "chiyue"),
        Identity("cymx_2", "chiyue_red_moon_lair", 916007, "chiyue"),
    ]
    rows += [Identity(f"gmd_{n}", f"cangyue_bone_cave_f{n}", 917000 + n, "cangyue_bone_cave") for n in range(1, 6)]
    rows += [Identity(f"nmsm_{n}", f"cangyue_bull_temple_f{n}", 917100 + n, "cangyue_bull_temple") for n in range(1, 5)]
    rows += [
        Identity("nmsm_hall", "cangyue_bull_temple_hall", 917105, "cangyue_bull_temple"),
        Identity("boss_2", "hidden_confusion_hall", 918001, "hidden_boss"),
        Identity("dyly_2", "hidden_hellfire", 918002, "hidden_boss"),
        Identity("dlfc_2", "hidden_fallen_graveyard", 918003, "hidden_boss"),
        Identity("swsd_2", "hidden_death_temple", 918004, "hidden_boss"),
        Identity("symy_2", "hidden_abyss_domain", 918005, "hidden_boss"),
        Identity("qccx_2", "hidden_pincer_nest", 918006, "hidden_boss"),
    ]
    assert len(rows) == 67
    return rows


ONE_WAY = [
    ("bich_mine_2", "map_exit_000002", "corpse_king_hall", "map_exit_000001"),
    ("bich_province", "map_exit_000004", "dyly_2", "map_exit_000001"),
    ("wooma_forest", "map_exit_000005", "dlfc_2", "map_exit_000001"),
    ("wooma_forest", "map_exit_000006", "symy_2", "map_exit_000001"),
    ("brm_2", "map_exit_000003", "qccx_2", "map_exit_000001"),
    ("fmg_1", "map_exit_000003", "swsd_2", "map_exit_000001"),
    ("stone_tomb_4", "map_exit_000002", "boss_2", "map_exit_000001"),
    ("connection_passage_2", "map_exit_000001", "quest_1", "map_exit_000001"),
    ("gmhl_purgatory_corridor", "map_exit_000002", "gmhl_fengmo_dian", "map_exit_000001"),
    ("gmd_4", "map_exit_000002", "gmd_5", "map_exit_000001"),
    ("nmsm_4", "map_exit_000002", "nmsm_hall", "map_exit_000001"),
    ("thin_sky_passage", "map_exit_000002", "death_coffin", "map_exit_000001"),
    ("zumage_1", "map_exit_000002", "zmjzzj_2", "map_exit_000001"),
    ("chiyue_valley_secret_passage_a", "map_exit_000002", "emjt_2", "map_exit_000001"),
    ("chiyue_valley_secret_passage_b", "map_exit_000002", "cymx_2", "map_exit_000001"),
]


LABEL_ALIASES = {
    "比奇": "bich_province",
    "比奇省": "bich_province",
    "毒蛇山谷": "snake_valley",
    "盟重": "mengzhong_province",
    "盟重省": "mengzhong_province",
    "石墓": "stone_tomb_1",
    "祖玛寺庙": "zuma_temple_1",
    "牛魔寺庙": "nmsm_1",
    "骨魔洞": "gmd_1",
    "连接通道1层": "connection_passage_1",
    "连接通道2层": "connection_passage_2",
    "山谷矿区": "connection_passage_1",
}


# A world-map entrance is named after the dungeon system that players are
# entering, even when the physical destination is a currently available first
# floor or intermediate map.  The label is UX metadata only; target_map_key
# remains the exact canonical destination.
WORLD_DUNGEON_PORTAL_LABELS = {
    ("bich_province", "map_exit_000002"): "兽人古墓",
    ("bich_province", "map_exit_000003"): "比奇矿区",
    ("snake_valley", "map_exit_000003"): "山谷矿区",
    ("mengzhong_province", "map_exit_000002"): "石墓",
    ("mengzhong_province", "map_exit_000003"): "祖玛寺庙",
    ("mengzhong_province", "map_exit_000005"): "死亡山谷",
    ("wooma_forest", "map_exit_000001"): "沃玛寺庙",
    ("fmg_1", "map_exit_000002"): "封魔矿区",
    ("brm_2", "map_exit_000002"): "赤月峡谷",
    ("cyd_1", "map_exit_000001"): "牛魔寺庙",
    ("cyd_1", "map_exit_000002"): "骨魔洞",
}
for _n in range(1, 6):
    LABEL_ALIASES[f"骨魔洞{_n}层"] = f"gmd_{_n}"
for _n in range(1, 5):
    LABEL_ALIASES[f"牛魔寺庙{_n}层"] = f"nmsm_{_n}"
    LABEL_ALIASES[f"祖玛{_n}层"] = f"zuma_temple_{_n}"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def document_path(workspace: Path, map_id: str) -> Path:
    return workspace / map_id / f"{map_id}.editor.json"


def normalize_label(label: str) -> str:
    value = label.strip()
    for prefix in ("前往", "进入", "返回"):
        if value.startswith(prefix):
            value = value[len(prefix):]
            break
    return value.strip()


def build_label_index(docs: dict[str, dict[str, Any]]) -> dict[str, str]:
    index = dict(LABEL_ALIASES)
    for map_id, doc in docs.items():
        name = str(doc.get("display_name", "")).strip()
        index[name] = map_id
        index[name.replace("（单机重制）", "")] = map_id
    return index


def endpoint_id(endpoint: dict[str, Any]) -> str:
    return str(endpoint.get("semantic_id") or endpoint.get("exit_id") or endpoint.get("door_id") or "")


def endpoints(doc: dict[str, Any]) -> list[dict[str, Any]]:
    return list(doc.get("layers", {}).get("map_exit_points", []))


def find_endpoint(doc: dict[str, Any], semantic_id: str) -> dict[str, Any]:
    matches = [entry for entry in endpoints(doc) if endpoint_id(entry) == semantic_id]
    if len(matches) != 1:
        raise ValueError(f"endpoint lookup {doc.get('map_id')}:{semantic_id} count={len(matches)}")
    return matches[0]


def promote_bich_door(docs: dict[str, dict[str, Any]]) -> None:
    doc = docs["bich_province"]
    layers = doc["layers"]
    doors = list(layers.get("door_points", []))
    candidates = [entry for entry in doors if str(entry.get("semantic_role", "")) == "map_portal"]
    if len(candidates) != 1:
        raise ValueError(f"bich formal door count={len(candidates)}")
    door = candidates[0]
    old_semantic = endpoint_id(door)
    used = {endpoint_id(entry) for entry in endpoints(doc)}
    ordinal = 1
    while f"map_exit_{ordinal:06d}" in used:
        ordinal += 1
    new_id = f"map_exit_{ordinal:06d}"
    promoted = copy.deepcopy(door)
    promoted["legacy_door_id"] = str(door.get("door_id", old_semantic))
    promoted["legacy_semantic_id"] = old_semantic
    promoted.pop("door_id", None)
    promoted["semantic_id"] = new_id
    promoted["exit_id"] = new_id
    promoted["kind"] = "map_exit"
    promoted["semantic_role"] = "map_portal_endpoint"
    promoted["runtime_export"] = bool(promoted.get("runtime_export", True))
    promoted["trigger_on_enter"] = True
    promoted["blocks_movement"] = False
    layers["door_points"] = [entry for entry in doors if entry is not door]
    layers.setdefault("map_exit_points", []).append(promoted)


def defaults() -> dict[str, Any]:
    return {
        "connection_policy_id": CONNECTION_POLICY,
        "portal_contract_id": PORTAL_CONTRACT,
        "portal_role": "bidirectional_endpoint",
        "semantic_role": "map_portal_endpoint",
        "connection_mode": "bidirectional",
        "one_way": False,
        "arrival_reentry_policy_id": ARRIVAL_POLICY,
        "arrival_locks_current_portal": True,
        "requires_leave_before_retrigger": True,
        "return_minimum_seconds": 3.0,
        "return_unlock_distance_tiles": 1.5,
        "return_requires_fresh_activation": True,
        "travel_request_single_flight": True,
        "trigger_on_enter": True,
        "blocks_movement": False,
        "runtime_export": True,
    }


def set_bidirectional(
    source_map: str,
    source: dict[str, Any],
    target_map: str,
    target: dict[str, Any],
    pair_id: str,
    direction: str,
    old_to_identity: dict[str, Identity],
) -> None:
    source.update(defaults())
    source.pop("arrival_only", None)
    source.pop("explicit_one_way_reason", None)
    source["kind"] = "map_exit"
    source["exit_id"] = endpoint_id(source)
    source["target_configured"] = True
    source["target_map_id"] = old_to_identity[target_map].runtime
    source["target_map_key"] = old_to_identity[target_map].new
    source["target_portal_id"] = endpoint_id(target)
    source["target_entrance_id"] = endpoint_id(target)
    source["target_tile"] = copy.deepcopy(target.get("tile", []))
    source["official_connection_id"] = f"portal.{old_to_identity[source_map].new}.{endpoint_id(source)}"
    source["connection_pair_id"] = pair_id
    source["connection_direction"] = direction
    source["source_map_key"] = old_to_identity[source_map].new
    source["reciprocal_exit_id"] = endpoint_id(target)
    source["reciprocal_map_key"] = old_to_identity[target_map].new


def set_one_way_source(
    source_map: str,
    source: dict[str, Any],
    target_map: str,
    target: dict[str, Any],
    old_to_identity: dict[str, Identity],
) -> None:
    source.update(defaults())
    source["kind"] = "map_exit"
    source["exit_id"] = endpoint_id(source)
    source["portal_role"] = "one_way_endpoint"
    source["connection_mode"] = "one_way"
    source["one_way"] = True
    source["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
    source["target_configured"] = True
    source["target_map_id"] = old_to_identity[target_map].runtime
    source["target_map_key"] = old_to_identity[target_map].new
    source["target_portal_id"] = endpoint_id(target)
    source["target_entrance_id"] = endpoint_id(target)
    source["target_tile"] = copy.deepcopy(target.get("tile", []))
    source["official_connection_id"] = f"portal.{old_to_identity[source_map].new}.{endpoint_id(source)}"
    source["source_map_key"] = old_to_identity[source_map].new
    for field in ("connection_pair_id", "connection_direction", "reciprocal_exit_id", "reciprocal_map_key", "arrival_only", "exit_policy"):
        source.pop(field, None)


def set_arrival(target: dict[str, Any]) -> None:
    target.update(defaults())
    target["kind"] = "map_exit"
    target["exit_id"] = endpoint_id(target)
    target["portal_role"] = "arrival_only_endpoint"
    target["semantic_role"] = "map_portal_arrival_anchor"
    target["connection_mode"] = "arrival_only"
    target["one_way"] = False
    target["arrival_only"] = True
    target["trigger_on_enter"] = False
    target["target_configured"] = False
    target["target_map_id"] = -1
    target["explicit_one_way_reason"] = "terminal_dungeon_has_no_return_portal"
    target["exit_policy"] = "town_scroll_or_death_only"
    for field in (
        "connection_pair_id", "connection_direction", "reciprocal_exit_id", "reciprocal_map_key",
        "target_map_key", "target_portal_id", "target_entrance_id", "target_tile",
        "official_connection_id", "source_map_key",
    ):
        target.pop(field, None)


def configure_portals(docs: dict[str, dict[str, Any]], old_to_identity: dict[str, Identity]) -> list[dict[str, Any]]:
    promote_bich_door(docs)
    if len(ONE_WAY) != 15:
        raise ValueError("one-way plan must contain 15 links")
    consumed: set[tuple[str, str]] = set()
    records: list[dict[str, Any]] = []
    for source_map, source_id, target_map, target_id in ONE_WAY:
        source = find_endpoint(docs[source_map], source_id)
        target = find_endpoint(docs[target_map], target_id)
        set_one_way_source(source_map, source, target_map, target, old_to_identity)
        set_arrival(target)
        consumed.update(((source_map, source_id), (target_map, target_id)))
        records.append({
            "mode": "one_way",
            "source_map_id": old_to_identity[source_map].new,
            "source_portal_id": source_id,
            "target_map_id": old_to_identity[target_map].new,
            "target_portal_id": target_id,
        })

    label_index = build_label_index(docs)
    candidates: dict[tuple[str, str], str] = {}
    for source_map, doc in docs.items():
        for entry in endpoints(doc):
            key = (source_map, endpoint_id(entry))
            if key in consumed:
                continue
            label = normalize_label(str(entry.get("display_name", "")))
            target_map = label_index.get(label)
            if not target_map:
                raise ValueError(f"unresolved portal label {source_map}:{key[1]}:{label}")
            candidates[key] = target_map

    visited: set[tuple[str, str]] = set()
    for source_key in sorted(candidates):
        if source_key in visited:
            continue
        source_map, source_id = source_key
        target_map = candidates[source_key]
        reciprocal = [key for key, destination in candidates.items() if key[0] == target_map and destination == source_map and key not in visited]
        if len(reciprocal) != 1:
            raise ValueError(f"reciprocal count {source_map}:{source_id}->{target_map} = {reciprocal}")
        target_key = reciprocal[0]
        source = find_endpoint(docs[source_map], source_id)
        target = find_endpoint(docs[target_map], target_key[1])
        ordered = sorted((source_key, target_key))
        pair_id = f"portal_pair.{old_to_identity[ordered[0][0]].new}.{ordered[0][1]}.{old_to_identity[ordered[1][0]].new}.{ordered[1][1]}"
        set_bidirectional(source_map, source, target_map, target, pair_id, "forward", old_to_identity)
        set_bidirectional(target_map, target, source_map, source, pair_id, "reverse", old_to_identity)
        visited.update((source_key, target_key))
        records.append({
            "mode": "bidirectional",
            "pair_id": pair_id,
            "a_map_id": old_to_identity[source_map].new,
            "a_portal_id": source_id,
            "b_map_id": old_to_identity[target_map].new,
            "b_portal_id": target_key[1],
        })

    if len(visited) != 102 or len(records) != 66:
        raise ValueError(f"network counts bidirectional_endpoints={len(visited)} records={len(records)}")
    for (map_id, portal_id), display_name in WORLD_DUNGEON_PORTAL_LABELS.items():
        find_endpoint(docs[map_id], portal_id)["display_name"] = display_name
    return sorted(records, key=lambda row: (row["mode"], json.dumps(row, ensure_ascii=False, sort_keys=True)))


def deep_replace(value: Any, old: str, new: str) -> Any:
    if isinstance(value, dict):
        return {deep_replace(key, old, new): deep_replace(item, old, new) for key, item in value.items()}
    if isinstance(value, list):
        return [deep_replace(item, old, new) for item in value]
    if isinstance(value, str):
        if old == new or new in value:
            return value
        return value.replace(old, new)
    return value


def authored_freeze_projection(document: dict[str, Any], current_id: str, legacy_id: str) -> dict[str, Any]:
    """Return the human-authored payload with allowed migration fields removed."""
    projected = copy.deepcopy(document)
    for field in (
        "map_id", "runtime_map_id", "legacy_map_id", "legacy_runtime_map_id",
        "identity_contract_id",
    ):
        projected.pop(field, None)
    meta = projected.get("editor_meta", {})
    if isinstance(meta, dict):
        for field in (
            "workspace", "revision", "connection_policy_id", "portal_contract_id",
            "default_connection_mode", "identity_contract_id", "blank_template_id",
            "official_version_id", "template_version_id", "one_way_exception_id",
        ):
            meta.pop(field, None)
    ground = projected.get("ground", {})
    if isinstance(ground, dict):
        for field in (
            "chunk_manifest", "source_manifest", "paint_manifest", "paint_state",
            "workspace_manifest", "workspace_state",
        ):
            ground.pop(field, None)
    layers = projected.get("layers", {})
    if isinstance(layers, dict):
        layers.pop("map_exit_points", None)
        layers["door_points"] = [
            entry for entry in layers.get("door_points", [])
            if not isinstance(entry, dict) or str(entry.get("semantic_role", "")) != "map_portal"
        ]

    def remove_identity_keys(value: Any) -> None:
        if isinstance(value, dict):
            for key in list(value):
                if str(key) in ("structure_id", "clone_source_map_id", "generated_by"):
                    value.pop(key, None)
                else:
                    remove_identity_keys(value[key])
        elif isinstance(value, list):
            for item in value:
                remove_identity_keys(item)

    remove_identity_keys(projected)
    return projected


def mirror_authority(authority: Path, repo: Path, rows: list[Identity]) -> None:
    source_workspace = authority / "map_editor_workspace"
    target_workspace = repo / "map_editor_workspace"
    expected = {row.old for row in rows}
    if any(not document_path(source_workspace, old).is_file() for old in expected):
        missing = sorted(old for old in expected if not document_path(source_workspace, old).is_file())
        raise ValueError(f"authority formal documents missing: {missing}")
    target_workspace.mkdir(parents=True, exist_ok=True)
    authority_dirs = expected | {SANDBOX_ID}
    for child in target_workspace.iterdir():
        if not child.is_dir():
            continue
        candidate = child / f"{child.name}.editor.json"
        if candidate.is_file() and child.name not in authority_dirs:
            resolved = child.resolve()
            if resolved.parent != target_workspace.resolve():
                raise ValueError(f"unsafe stale workspace target: {resolved}")
            shutil.rmtree(resolved)
    for row in rows:
        shutil.copytree(source_workspace / row.old, target_workspace / row.old, dirs_exist_ok=True)
    shutil.copy2(
        authority / "assets/data/map_design/map_blank_templates.json",
        repo / "assets/data/map_design/map_blank_templates.json",
    )


def snapshot_pngs(repo: Path, rows: list[Identity], use_old: bool) -> dict[str, str]:
    result: dict[str, str] = {}
    for row in rows:
        map_id = row.old if use_old else row.new
        root = repo / "map_editor_workspace" / map_id
        for path in sorted(root.rglob("*.png")):
            result[f"{row.old}/{path.relative_to(root).as_posix()}"] = sha256(path)
    return result


def migrate(repo: Path, authority: Path) -> dict[str, Any]:
    rows = identities()
    old_to_identity = {row.old: row for row in rows}
    if len(old_to_identity) != 67 or len({row.new for row in rows}) != 67 or len({row.runtime for row in rows}) != 67:
        raise ValueError("identity plan is not unique")
    mirror_authority(authority, repo, rows)
    workspace = repo / "map_editor_workspace"
    png_before = snapshot_pngs(repo, rows, True)
    docs = {row.old: read_json(document_path(workspace, row.old)) for row in rows}
    for row in rows:
        if str(docs[row.old].get("map_id", "")) != row.old:
            raise ValueError(f"document identity mismatch: {row.old}")
    authored_before = {
        row.old: authored_freeze_projection(docs[row.old], row.old, row.old)
        for row in rows
    }
    records = configure_portals(docs, old_to_identity)

    for row in rows:
        old_root = workspace / row.old
        new_root = workspace / row.new
        legacy_runtime = int(docs[row.old].get("runtime_map_id", -1))
        # Rewrite auxiliary authoring JSON metadata before the directory moves.
        for path in sorted(old_root.rglob("*.json")) + sorted(old_root.rglob("*.json.bak")):
            if path == document_path(workspace, row.old):
                continue
            # Preserve unrelated/misnamed historical backup files byte-for-byte.
            if path.name.endswith(".editor.json.bak") and not path.name.startswith(row.old):
                continue
            parsed = read_json(path)
            write_json(path, deep_replace(parsed, row.old, row.new))

        document = deep_replace(docs[row.old], row.old, row.new)
        document["map_id"] = row.new
        document["runtime_map_id"] = row.runtime
        document["legacy_map_id"] = row.old
        document["legacy_runtime_map_id"] = legacy_runtime
        document["identity_contract_id"] = IDENTITY_CONTRACT
        meta = document.setdefault("editor_meta", {})
        meta["workspace"] = f"res://map_editor_workspace/{row.new}"
        meta["connection_policy_id"] = CONNECTION_POLICY
        meta["portal_contract_id"] = PORTAL_CONTRACT
        meta["default_connection_mode"] = "bidirectional"
        meta["identity_contract_id"] = IDENTITY_CONTRACT
        meta["revision"] = int(meta.get("revision", 1)) + 1
        old_main = document_path(workspace, row.old)
        write_json(old_main, document)
        if row.old != row.new:
            if new_root.exists():
                raise ValueError(f"canonical workspace already exists: {new_root}")
            old_root.rename(new_root)
            old_main = new_root / f"{row.old}.editor.json"
            old_main.rename(new_root / f"{row.new}.editor.json")
            old_backup = new_root / f"{row.old}.editor.json.bak"
            if old_backup.exists():
                old_backup.rename(new_root / f"{row.new}.editor.json.bak")

    # Update the accepted template catalog and any map-design file that directly
    # references a migrated authoring identity.  Source-data maps.json is not in
    # this ownership lane and is deliberately untouched.
    design_root = repo / "assets/data/map_design"
    for path in sorted(design_root.glob("*.json")):
        if path.name in ("map_identity_registry.json", "map_portal_network.json"):
            continue
        value: Any = read_json(path)
        changed = False
        for row in rows:
            encoded = json.dumps(value, ensure_ascii=False, sort_keys=True)
            if row.old in encoded:
                value = deep_replace(value, row.old, row.new)
                changed = True
        if path.name == "map_blank_templates.json":
            for entry in value.get("templates", []):
                matching = next((row for row in rows if str(entry.get("map_id", "")) == row.new), None)
                if matching:
                    entry["runtime_map_id"] = matching.runtime
                    changed = True
        if changed:
            write_json(path, value)

    identity_manifest = {
        "schema_version": 1,
        "contract_id": IDENTITY_CONTRACT,
        "canonical_runtime_range": [910001, 918006],
        "formal_map_count": 67,
        "sandbox_excluded": SANDBOX_ID,
        "maps": [
            {
                "map_id": row.new,
                "runtime_map_id": row.runtime,
                "legacy_map_id": row.old,
                "legacy_runtime_map_id": int(docs[row.old].get("runtime_map_id", -1)),
                "display_name": str(docs[row.old].get("display_name", "")),
                "series": row.series,
            }
            for row in rows
        ],
    }
    network_manifest = {
        "schema_version": 1,
        "contract_id": NETWORK_CONTRACT,
        "identity_contract_id": IDENTITY_CONTRACT,
        "formal_map_count": 67,
        "logical_connection_count": 66,
        "bidirectional_pair_count": 51,
        "one_way_connection_count": 15,
        "formal_portal_endpoint_count": 132,
        "display_label_overrides": [
            {
                "map_id": old_to_identity[map_id].new,
                "portal_id": portal_id,
                "display_name": display_name,
                "target_map_id": str(find_endpoint(docs[map_id], portal_id).get("target_map_key", "")),
            }
            for (map_id, portal_id), display_name in sorted(WORLD_DUNGEON_PORTAL_LABELS.items())
        ],
        "connections": records,
    }
    write_json(design_root / "map_identity_registry.json", identity_manifest)
    write_json(design_root / "map_portal_network.json", network_manifest)
    png_after = snapshot_pngs(repo, rows, False)
    if png_before != png_after:
        raise ValueError("PNG hash freeze violated")
    authored_after = {
        row.old: authored_freeze_projection(
            read_json(document_path(workspace, row.new)), row.new, row.old
        )
        for row in rows
    }
    if authored_before != authored_after:
        changed = sorted(key for key in authored_before if authored_before[key] != authored_after[key])
        raise ValueError(f"human-authored payload freeze violated: {changed}")
    return verify(repo, png_before)


def verify(repo: Path, expected_pngs: dict[str, str] | None = None) -> dict[str, Any]:
    identity = read_json(repo / "assets/data/map_design/map_identity_registry.json")
    network = read_json(repo / "assets/data/map_design/map_portal_network.json")
    rows = identities()
    by_new = {row.new: row for row in rows}
    workspace = repo / "map_editor_workspace"
    docs = {row.new: read_json(document_path(workspace, row.new)) for row in rows}
    errors: list[str] = []
    if len(docs) != 67:
        errors.append("formal_map_count")
    if len({str(doc.get("map_id", "")) for doc in docs.values()}) != 67:
        errors.append("duplicate_map_id")
    if len({int(doc.get("runtime_map_id", -1)) for doc in docs.values()}) != 67:
        errors.append("duplicate_runtime_map_id")
    if any(str(docs[row.new].get("legacy_map_id", "")) != row.old for row in rows):
        errors.append("legacy_identity_missing")
    if len(identity.get("maps", [])) != 67 or len(network.get("connections", [])) != 66:
        errors.append("manifest_count")

    all_endpoints: dict[tuple[str, str], dict[str, Any]] = {}
    for map_id, doc in docs.items():
        formal_doors = [entry for entry in doc.get("layers", {}).get("door_points", []) if str(entry.get("semantic_role", "")) == "map_portal"]
        if formal_doors:
            errors.append(f"formal_door_not_promoted:{map_id}")
        for entry in endpoints(doc):
            all_endpoints[(map_id, endpoint_id(entry))] = entry
    bidirectional = [entry for entry in all_endpoints.values() if str(entry.get("connection_mode", "")) == "bidirectional"]
    one_way = [entry for entry in all_endpoints.values() if str(entry.get("connection_mode", "")) == "one_way"]
    arrivals = [entry for entry in all_endpoints.values() if str(entry.get("connection_mode", "")) == "arrival_only"]
    if (len(all_endpoints), len(bidirectional), len(one_way), len(arrivals)) != (132, 102, 15, 15):
        errors.append(f"portal_counts:{len(all_endpoints)}:{len(bidirectional)}:{len(one_way)}:{len(arrivals)}")
    runtime_by_map = {row.new: row.runtime for row in rows}
    for (map_id, portal_id), entry in all_endpoints.items():
        mode = str(entry.get("connection_mode", ""))
        if mode == "arrival_only":
            if bool(entry.get("target_configured", True)) or bool(entry.get("trigger_on_enter", True)) or int(entry.get("target_map_id", 0)) != -1:
                errors.append(f"arrival_contract:{map_id}:{portal_id}")
            continue
        target_map = str(entry.get("target_map_key", ""))
        target_portal = str(entry.get("target_portal_id", ""))
        target = all_endpoints.get((target_map, target_portal))
        if target is None:
            errors.append(f"missing_target:{map_id}:{portal_id}")
            continue
        if int(entry.get("target_map_id", -1)) != runtime_by_map.get(target_map, -2):
            errors.append(f"target_runtime:{map_id}:{portal_id}")
        if list(entry.get("target_tile", [])) != list(target.get("tile", [])):
            errors.append(f"target_tile:{map_id}:{portal_id}")
        if mode == "bidirectional":
            if str(target.get("target_map_key", "")) != map_id or str(target.get("target_portal_id", "")) != portal_id:
                errors.append(f"reciprocal:{map_id}:{portal_id}")
            if str(target.get("connection_pair_id", "")) != str(entry.get("connection_pair_id", "")):
                errors.append(f"pair:{map_id}:{portal_id}")
        elif mode == "one_way" and str(target.get("connection_mode", "")) != "arrival_only":
            errors.append(f"one_way_target:{map_id}:{portal_id}")
    for (legacy_map_id, portal_id), display_name in WORLD_DUNGEON_PORTAL_LABELS.items():
        map_id = next(row.new for row in rows if row.old == legacy_map_id)
        endpoint = find_endpoint(docs[map_id], portal_id)
        if str(endpoint.get("display_name", "")) != display_name:
            errors.append(f"dungeon_portal_label:{map_id}:{portal_id}")
    ql_targets = {str(entry.get("target_map_key", "")) for entry in endpoints(docs["fengmo_forked_path"])}
    if ql_targets != {"world_fengmo_valley", "fengmo_light_corridor"}:
        errors.append(f"fengmo_forked_path_targets:{sorted(ql_targets)}")
    if not document_path(workspace, SANDBOX_ID).is_file():
        errors.append("sandbox_missing")
    current_dirs = [path for path in workspace.iterdir() if path.is_dir() and (path / f"{path.name}.editor.json").is_file()]
    if len(current_dirs) != 68:
        errors.append(f"workspace_count:{len(current_dirs)}")
    if expected_pngs is not None:
        current_pngs = snapshot_pngs(repo, rows, False)
        if current_pngs != expected_pngs:
            errors.append("png_hash")
    if errors:
        raise ValueError("verification failed: " + ";".join(errors))
    return {
        "ok": True,
        "formal_maps": 67,
        "workspace_maps": 68,
        "runtime_ids": len({row.runtime for row in rows}),
        "portal_endpoints": len(all_endpoints),
        "bidirectional_pairs": len(bidirectional) // 2,
        "one_way_sources": len(one_way),
        "arrival_anchors": len(arrivals),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--authority-root", type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    if not (repo / ".git").exists():
        # Linked worktrees use a .git file rather than a directory.
        if not (repo / ".git").is_file():
            raise ValueError(f"not a git worktree: {repo}")
    if args.apply:
        if args.authority_root is None:
            raise ValueError("--authority-root is required with --apply")
        authority = args.authority_root.resolve()
        if authority == repo:
            raise ValueError("authority must remain read-only and separate")
        result = migrate(repo, authority)
    elif args.verify:
        result = verify(repo)
    else:
        rows = identities()
        result = {
            "ok": True,
            "dry_run": True,
            "formal_maps": len(rows),
            "canonical_ids": len({row.new for row in rows}),
            "runtime_ids": len({row.runtime for row in rows}),
            "one_way_plan": len(ONE_WAY),
        }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # deterministic CLI failure for CI/PowerShell
        print(f"MAP_IDENTITY_PORTAL_MIGRATION_FAILED: {exc}", file=sys.stderr)
        raise
