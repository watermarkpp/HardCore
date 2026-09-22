#!/usr/bin/env python3
"""Audited audio source inventory and binding validation for HardCore.

The tool never guesses semantic ownership from a filename.  It records bytes,
WAV container metadata, sound.lst rows, and source-to-source comparison facts;
runtime binding ownership remains in audio_bindings.source.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import wave
from pathlib import Path
from typing import Any


BASE_SHA_DEFAULT = "7c3019da4d3732766bdea2655abfedbea84e5b7b"
INDEX_ENCODING = "cp949"

# Exact identity bridge from MirClient/Grobal2.pas SKILL_* constants.  The
# Chinese comments in that primary source were decoded with CP936 and checked
# against the canonical display names/aliases; these are distinct namespaces,
# so the bridge is explicit rather than inferred from list order or filenames.
CLASSIC_SKILL_IDS: dict[str, int] = {
    "wizard.fireball": 1,
    "taoist.healing": 2,
    "taoist.spiritual_warfare": 3,
    "warrior.basic_swordsmanship": 4,
    "wizard.great_fireball": 5,
    "taoist.poison": 6,
    "warrior.slaying_swordsmanship": 7,
    "wizard.repulsion_ring": 8,
    "wizard.hellfire": 9,
    "wizard.laser": 10,
    "wizard.lightning": 11,
    "warrior.thrusting": 12,
    "taoist.soul_fire_talisman": 13,
    "taoist.magic_defense": 14,
    "taoist.defense": 15,
    "taoist.entrapment": 16,
    "taoist.summon_skeleton": 17,
    "taoist.invisibility": 18,
    "taoist.mass_invisibility": 19,
    "wizard.temptation_light": 20,
    "wizard.teleport": 21,
    "wizard.fire_wall": 22,
    "wizard.exploding_flame": 23,
    "wizard.hell_lightning": 24,
    "warrior.half_moon": 25,
    "warrior.fire_sword": 26,
    "warrior.wild_rush": 27,
    "taoist.revelation": 28,
    "taoist.mass_healing": 29,
    "taoist.summon_divine_beast": 30,
    "wizard.magic_shield": 31,
    "wizard.holy_word": 32,
    "wizard.ice_storm": 33,
}

PROJECTILE_SKILLS = {
    "wizard.fireball",
    "wizard.great_fireball",
    "taoist.soul_fire_talisman",
}

BODY_SKILL_SOUNDS: dict[str, list[tuple[int, str]]] = {
    "warrior.slaying_swordsmanship": [(130, "male"), (131, "female")],
    "warrior.thrusting": [(132, "default")],
    "warrior.half_moon": [(133, "default")],
    "warrior.fire_sword": [(137, "default")],
}

MONSTER_PHASES: dict[int, tuple[str, str]] = {
    0: ("appear", "action_start"),
    1: ("ambient", "walk_or_turn_frame_1_random_1_in_8"),
    2: ("attack_start", "action_start"),
    3: ("attack_frame", "client_attack_frame_3"),
    4: ("hurt", "struck_action_start"),
    5: ("death", "death_action_start"),
    6: ("death_secondary", "client_death_frame_2_appearance_80"),
}

EQUIPMENT_CLICK_SOUND_BY_CATEGORY: dict[str, int] = {
    "武器": 111,
    "盔甲": 112,
    "戒指": 113,
    "项链": 115,
    "头盔": 116,
}

PLAYER_WEAPON_SOUNDS: tuple[tuple[str, int, tuple[int, ...]], ...] = (
    ("short", 50, (6, 20)),
    ("wood", 51, (1,)),
    ("sword", 52, (2, 5, 9, 13, 14, 22)),
    ("blade", 53, (4, 10, 15, 16, 17, 23)),
    ("axe", 54, (3, 7, 11)),
    ("club", 55, (24,)),
    ("long", 56, (8, 12, 18, 21)),
    ("fist", 57, ()),
)

# TActor.RunSound/SetSound exact player struck/death layers. Contact sound IDs
# 66..69 are deliberately absent: SoundUtil declares only 60..65 and 70..73.
PLAYER_REACTION_SOUNDS: tuple[tuple[str, tuple[int, ...], str], ...] = (
    ("player.hurt.pve.body", (72,), "pve_struck_action_start"),
    ("player.hurt.voice", (138, 139), "struck_action_start"),
    ("player.death.voice", (144, 145), "death_action_start"),
)

PLAYER_CONTACT_SOUNDS: tuple[tuple[str, int], ...] = (
    ("player.contact.weapon.short", 60),
    ("player.contact.weapon.wood", 61),
    ("player.contact.weapon.sword", 62),
    ("player.contact.weapon.blade", 63),
    ("player.contact.weapon.axe", 64),
    ("player.contact.weapon.club", 65),
    ("player.contact.body.sword", 70),
    ("player.contact.body.axe", 71),
    ("player.contact.body.long", 72),
    ("player.contact.body.fist", 73),
)

GENERIC_ITEM_EVENTS: dict[str, tuple[int, str]] = {
    "currency.gold.changed": (106, "committed_gold_balance_change"),
    "item.use.food_or_drug.success": (107, "committed_consumable_use"),
    "item.use.drug.success": (108, "committed_consumable_use"),
    "item.inventory.select.weapon": (111, "committed_equipment_interaction"),
    "item.inventory.select.armor": (112, "committed_equipment_interaction"),
    "item.inventory.select.ring": (113, "committed_equipment_interaction"),
    "item.inventory.select.belt": (114, "committed_equipment_interaction"),
    "item.inventory.select.necklace": (115, "committed_equipment_interaction"),
    "item.inventory.select.helmet": (116, "committed_equipment_interaction"),
    "item.inventory.select.bracelet_or_glove": (117, "committed_equipment_interaction"),
    "item.inventory.select.generic": (118, "committed_equipment_interaction"),
    "ui.button.normal.click": (103, "accepted_ui_click"),
    "ui.button.rock.click": (104, "accepted_ui_click"),
    "ui.button.glass.click": (105, "accepted_ui_click"),
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_path(value: str) -> str:
    path = value.replace("\\", "/").strip().lstrip("./")
    if path.casefold().startswith("wav/"):
        path = path[4:]
    return path.casefold()


def whitespace_normalized_path(value: str) -> str:
    return re.sub(r"\s+", "", normalized_path(value))


def snapshot_hash(root: Path, files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256_file(path).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def parse_sound_index(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    try:
        text = raw.decode(INDEX_ENCODING)
        encoding_status = "cp949"
    except UnicodeDecodeError:
        text = raw.decode("replace")
        encoding_status = "cp949_decode_error"

    entries: list[dict[str, Any]] = []
    id_pattern = re.compile(r"^(\d+)\s*:\s*(.*?)\s*$")
    for line_number, raw_line in enumerate(raw.splitlines(), start=1):
        decoded_line = raw_line.decode(INDEX_ENCODING, errors="replace")
        stripped = decoded_line.strip()
        is_comment = not stripped or stripped.startswith(";")
        match = id_pattern.match(stripped) if not is_comment else None
        sound_id: int | None = int(match.group(1)) if match else None
        raw_path = match.group(2).strip() if match else ""
        entries.append(
            {
                "line_number": line_number,
                "sound_id": sound_id,
                "raw_line_utf8": decoded_line,
                "raw_line_sha256": hashlib.sha256(raw_line).hexdigest(),
                "is_comment_or_blank": is_comment,
                "raw_path": raw_path,
                "normalized_path": normalized_path(raw_path) if raw_path else "",
                "has_path": bool(raw_path),
            }
        )
    return {
        "path": path.as_posix(),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "encoding": encoding_status,
        "byte_length": len(raw),
        "entries": entries,
    }


def wav_metadata(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "relative_path": path.name,
        "file_sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
    }
    try:
        with wave.open(str(path), "rb") as reader:
            channels = reader.getnchannels()
            sample_rate = reader.getframerate()
            sample_width = reader.getsampwidth()
            frame_count = reader.getnframes()
            result.update(
                {
                    "container_format": "RIFF/WAVE",
                    "codec": "pcm",
                    "sample_rate_hz": sample_rate,
                    "channels": channels,
                    "sample_width_bytes": sample_width,
                    "sample_count": frame_count,
                    "duration_seconds": frame_count / sample_rate if sample_rate else 0.0,
                    "read_or_decode_status": "PASS",
                }
            )
    except (EOFError, OSError, wave.Error) as error:
        result.update(
            {
                "container_format": "unknown",
                "codec": "unknown",
                "read_or_decode_status": "FAIL",
                "decode_error": str(error),
            }
        )
    return result


def wav_files(root: Path) -> list[Path]:
    return sorted(
        [path for path in root.rglob("*") if path.is_file() and path.suffix.casefold() == ".wav"],
        key=lambda item: item.relative_to(root).as_posix().casefold(),
    )


def source_inventory(root: Path, distribution: str, index_path: Path | None) -> dict[str, Any]:
    files = wav_files(root)
    index = parse_sound_index(index_path) if index_path and index_path.is_file() else None
    by_normalized = {path.relative_to(root).as_posix().casefold(): path for path in files}
    records: list[dict[str, Any]] = []
    refs_by_path: dict[str, list[dict[str, Any]]] = {}
    if index:
        for entry in index["entries"]:
            if entry["has_path"] and not entry["is_comment_or_blank"]:
                refs_by_path.setdefault(entry["normalized_path"], []).append(entry)
    for path in files:
        relative = path.relative_to(root).as_posix()
        key = normalized_path(relative)
        record = wav_metadata(path)
        record["relative_path"] = relative
        record["source_distribution"] = distribution
        record["index_references"] = [
            {
                "line_number": item["line_number"],
                "sound_id": item["sound_id"],
                "raw_path": item["raw_path"],
            }
            for item in refs_by_path.get(key, [])
        ]
        records.append(record)
    collisions: dict[str, list[str]] = {}
    whitespace_collisions: dict[str, list[str]] = {}
    for path in files:
        relative = path.relative_to(root).as_posix()
        collisions.setdefault(normalized_path(relative), []).append(relative)
        whitespace_collisions.setdefault(whitespace_normalized_path(relative), []).append(relative)
    return {
        "source_distribution": distribution,
        "root_locator": root.as_posix(),
        "file_count": len(files),
        "snapshot_sha256": snapshot_hash(root, files),
        "casefold_path_collisions": [
            {"normalized_path": key, "paths": value}
            for key, value in sorted(collisions.items())
            if len(value) > 1
        ],
        "whitespace_normalized_path_collisions": [
            {"normalized_path": key, "paths": value}
            for key, value in sorted(whitespace_collisions.items())
            if len(value) > 1
        ],
        "sound_index": index,
        "files": records,
        "_by_normalized": by_normalized,
    }


def public_inventory(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result.pop("_by_normalized", None)
    return result


def source_comparison(primary: dict[str, Any], user: dict[str, Any]) -> dict[str, Any]:
    primary_files = {item["relative_path"].casefold(): item for item in primary["files"]}
    user_files = {item["relative_path"].casefold(): item for item in user["files"]}
    records: list[dict[str, Any]] = []
    for key in sorted(set(primary_files) | set(user_files)):
        left = primary_files.get(key)
        right = user_files.get(key)
        if left and right:
            status = "BYTE_IDENTICAL" if left["file_sha256"] == right["file_sha256"] else "CONTENT_DIFFERENCE"
        elif left:
            status = "PRIMARY_ONLY"
        else:
            status = "USER_ONLY"
        records.append(
            {
                "normalized_relative_path": key,
                "status": status,
                "primary_sha256": left["file_sha256"] if left else None,
                "user_sha256": right["file_sha256"] if right else None,
                "primary_size_bytes": left["size_bytes"] if left else None,
                "user_size_bytes": right["size_bytes"] if right else None,
            }
        )
    return {
        "schema_version": 1,
        "primary_distribution": primary["source_distribution"],
        "user_distribution": user["source_distribution"],
        "primary_snapshot_sha256": primary["snapshot_sha256"],
        "user_snapshot_sha256": user["snapshot_sha256"],
        "primary_file_count": primary["file_count"],
        "user_file_count": user["file_count"],
        "status_counts": {
            status: sum(1 for item in records if item["status"] == status)
            for status in ["BYTE_IDENTICAL", "CONTENT_DIFFERENCE", "PRIMARY_ONLY", "USER_ONLY"]
        },
        "files": records,
        "sound_index_sha_equal": bool(
            primary.get("sound_index")
            and user.get("sound_index")
            and primary["sound_index"]["sha256"] == user["sound_index"]["sha256"]
        ),
    }


def anomalies(inventory: dict[str, Any]) -> dict[str, Any]:
    index = inventory.get("sound_index") or {}
    entries = [entry for entry in index.get("entries", []) if entry.get("sound_id") is not None]
    path_keys = {normalized_path(item["relative_path"]): item for item in inventory["files"]}
    by_id: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        by_id.setdefault(str(entry["sound_id"]), []).append(entry)
    missing = [
        {"line_number": entry["line_number"], "sound_id": entry["sound_id"], "raw_path": entry["raw_path"]}
        for entry in entries
        if entry["has_path"] and entry["normalized_path"] not in path_keys
    ]
    referenced = {entry["normalized_path"] for entry in entries if entry["has_path"]}
    unreferenced = [item["relative_path"] for item in inventory["files"] if normalized_path(item["relative_path"]) not in referenced]
    cross_number = []
    for entry in entries:
        if not entry["has_path"]:
            continue
        basename = Path(entry["raw_path"].replace("\\", "/")).name
        match = re.match(r"(\d+)(?:[-.].*)?\.wav$", basename, re.IGNORECASE)
        if match and int(match.group(1)) != int(entry["sound_id"]):
            cross_number.append(
                {"line_number": entry["line_number"], "sound_id": entry["sound_id"], "raw_path": entry["raw_path"]}
            )
    return {
        "schema_version": 1,
        "source_distribution": inventory["source_distribution"],
        "sound_index_sha256": index.get("sha256"),
        "non_comment_record_count": len(entries),
        "distinct_sound_id_count": len(by_id),
        "empty_path_count": sum(1 for entry in entries if not entry["has_path"]),
        "duplicate_sound_ids": {
            key: value for key, value in by_id.items() if len(value) > 1
        },
        "missing_referenced_files": missing,
        "unreferenced_wav_files": sorted(unreferenced),
        "cross_number_references": cross_number,
        "casefold_path_collisions": inventory.get("casefold_path_collisions", []),
        "whitespace_normalized_path_collisions": inventory.get("whitespace_normalized_path_collisions", []),
        "encoding_status": index.get("encoding"),
        "policy_note": "Anomaly records are preserved evidence; they do not authorize filename repair or semantic guessing.",
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def effective_sound_slots(index: dict[str, Any]) -> dict[int, dict[str, Any]]:
    """Reproduce MirClient SoundUtil.LoadSoundList's strict-increasing loader.

    The original loader only accepts a row when `n > idx`.  Consequently the
    second 1680/1943 rows are ignored; preserving all raw rows and separately
    deriving effective slots prevents a silent last-write-wins guess.
    """
    slots: dict[int, dict[str, Any]] = {}
    current_index = 0
    for entry in index.get("entries", []):
        sound_id = entry.get("sound_id")
        if sound_id is None:
            continue
        sound_id = int(sound_id)
        if sound_id <= current_index:
            continue
        current_index = sound_id
        slots[sound_id] = entry
    return slots


def source_file_lookup(source_root: Path) -> dict[str, Path]:
    return {
        normalized_path(path.relative_to(source_root).as_posix()): path
        for path in wav_files(source_root)
    }


def sound_resolution(
    sound_id: int,
    slots: dict[int, dict[str, Any]],
    files: dict[str, Path],
) -> dict[str, Any]:
    entry = slots.get(sound_id)
    if entry is None or not entry.get("has_path", False):
        return {
            "sound_id": sound_id,
            "mapping_status": "SILENCE_VERIFIED",
            "reason": "MirClient effective sound slot is absent or empty; PlaySound therefore emits no sample",
            "source_index_line": entry.get("line_number") if entry else None,
        }
    key = str(entry.get("normalized_path", ""))
    source_file = files.get(key)
    result: dict[str, Any] = {
        "sound_id": sound_id,
        "source_index_line": entry.get("line_number"),
        "source_raw_path": entry.get("raw_path", ""),
        "source_relative_path": key,
    }
    if source_file is None:
        result.update(
            {
                "mapping_status": "MISSING_SOURCE",
                "reason": "MirClient effective slot names a sample absent from the primary client_assets snapshot",
            }
        )
        return result
    result.update(
        {
            "mapping_status": "EXACT",
            "source_sha256": sha256_file(source_file),
            "source_size_bytes": source_file.stat().st_size,
            "_source_file": source_file,
        }
    )
    return result


def managed_runtime_path(sound_id: int, source_file: Path) -> str:
    safe_stem = re.sub(r"[^A-Za-z0-9._-]+", "_", source_file.stem).strip("._") or "sample"
    return f"res://assets/audio/sfx/client/{sound_id}__{safe_stem}.wav"


def public_resolution(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result.pop("_source_file", None)
    return result


def monster_appearance(record: dict[str, Any], catalog: dict[str, Any]) -> int | None:
    source_evidence = record.get("source_evidence") or {}
    status = source_evidence.get("status") or {}
    appearance_translation = status.get("appearance_translation") or {}
    translated = appearance_translation.get("client_appearance")
    if translated is not None:
        return int(translated)
    profile_id = str(record.get("appearance_profile_id", ""))
    profile = catalog.get("appearance_profiles", {}).get(profile_id, {})
    atlas_appearance = profile.get("atlas", {}).get("appearance")
    return int(atlas_appearance) if atlas_appearance is not None else None


def source_rule_evidence(project_root: Path) -> dict[str, Any]:
    paths = {
        "sound_loader_and_constants": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/SoundUtil.pas", "source.original_gameofmir.mirclient"),
        "actor_formula_and_calls": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas", "source.original_gameofmir.mirclient"),
        "skill_identity_constants": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/Grobal2.pas", "source.original_gameofmir.mirclient"),
        "magic_phase_classification": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/PlayScn.pas", "source.original_gameofmir.mirclient"),
        "magic_effect_impact_call": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/magiceff.pas", "source.original_gameofmir.mirclient"),
        "item_operation_calls": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/ClMain.pas", "source.original_gameofmir.mirclient"),
        "item_inventory_calls": (project_root / "dev_art_sources/reference/original_gameofmir/MirClient/FState.pas", "source.original_gameofmir.mirclient"),
        "current_projectile_authority": (project_root / "scripts/combat_resolution_rules.gd", "project.current_runtime_authority"),
        "current_weapon_shape_authority": (project_root / "assets/data/equipment_visual_catalog.json", "project.current_equipment_visual_authority"),
    }
    return {
        key: {
            "distribution": distribution,
            "path": path.relative_to(project_root).as_posix(),
            "sha256": sha256_file(path),
        }
        for key, (path, distribution) in paths.items()
    }


def command_build_exact(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).resolve()
    source_root = Path(args.primary_root).resolve()
    index = parse_sound_index(Path(args.primary_index).resolve())
    slots = effective_sound_slots(index)
    files = source_file_lookup(source_root)
    skills_doc = json.loads(Path(args.skills).read_text(encoding="utf-8"))
    monsters_doc = json.loads(Path(args.monsters).read_text(encoding="utf-8"))
    equipment_items_path = Path(args.equipment_items)
    service_items_path = Path(args.service_items)
    item_runtime_authority_path = Path(args.item_runtime_authority)
    equipment_items_doc = json.loads(equipment_items_path.read_text(encoding="utf-8"))
    service_items_doc = json.loads(service_items_path.read_text(encoding="utf-8"))
    item_runtime_authority_doc = json.loads(item_runtime_authority_path.read_text(encoding="utf-8"))
    source_path = Path(args.source_authoring)
    runtime_path = Path(args.runtime)
    requirements_path = Path(args.requirements)
    authoring = json.loads(source_path.read_text(encoding="utf-8"))
    previous_runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    requirements = json.loads(requirements_path.read_text(encoding="utf-8"))
    evidence = source_rule_evidence(project_root)
    item_identity_sources = [
        {
            "scope": "equipment_item_id_and_category",
            "path": equipment_items_path.as_posix(),
            "sha256": sha256_file(equipment_items_path),
            "distribution": "project.current_equipment_runtime_authority",
        },
        {
            "scope": "service_index_non_equipment_identity_and_type",
            "path": service_items_path.as_posix(),
            "sha256": sha256_file(service_items_path),
            "distribution": "project.current_service_item_catalog",
        },
        {
            "scope": "new_canonical_item_id_and_type",
            "path": item_runtime_authority_path.as_posix(),
            "sha256": sha256_file(item_runtime_authority_path),
            "distribution": "project.hardcore.item_runtime_authority.v1",
        },
    ]

    generated_events: list[dict[str, Any]] = []
    runtime_events: dict[str, Any] = {}
    item_event_routes: dict[str, Any] = {}
    needed_files: dict[str, tuple[Path, str]] = {}

    def add_runtime_event(
        event_id: str,
        owner_kind: str,
        owner_id: str,
        display_name: str,
        semantic_event: str,
        phase: str,
        resolutions: list[dict[str, Any]],
        source_rule: dict[str, Any],
        variant_policy: str = "single",
        priority: int = 50,
    ) -> None:
        statuses = {str(item.get("mapping_status", "")) for item in resolutions}
        public_items = [public_resolution(item) for item in resolutions]
        exact = [item for item in resolutions if item.get("mapping_status") == "EXACT"]
        mapping_status = "EXACT" if exact and statuses <= {"EXACT"} else (
            "MISSING_SOURCE" if "MISSING_SOURCE" in statuses else "SILENCE_VERIFIED"
        )
        event = {
            "event_id": event_id,
            "owner_kind": owner_kind,
            "canonical_owner_id": owner_id,
            "display_name": display_name,
            "semantic_event": semantic_event,
            "phase": phase,
            "mapping_status": mapping_status,
            "integration_status": "BOUND" if event_id.startswith("player.") else "NOT_STARTED",
            "source_rule": source_rule,
            "samples": public_items,
        }
        generated_events.append(event)
        if mapping_status != "EXACT":
            return
        runtime_paths: list[str] = []
        sound_ids: list[int] = []
        for item in exact:
            source_file = item["_source_file"]
            target = managed_runtime_path(int(item["sound_id"]), source_file)
            item["runtime_path"] = target
            public_items[resolutions.index(item)]["runtime_path"] = target
            needed_files[target] = (source_file, str(item["source_sha256"]))
            runtime_paths.append(target)
            sound_ids.append(int(item["sound_id"]))
        runtime_events[event_id] = {
            "owner_kind": owner_kind,
            "canonical_owner_id": owner_id,
            "semantic_event": semantic_event,
            "phase": phase,
            "mapping_status": "EXACT",
            "sound_ids": sound_ids,
            "runtime_paths": runtime_paths,
            "variant_policy": variant_policy,
            "priority": priority,
            "playback_policy": {"bus": "SFX", "loop": False, "spatial": False},
        }

    skill_records = {str(item.get("skill_id", "")): item for item in skills_doc.get("skills", [])}
    skill_audit: dict[str, list[dict[str, Any]]] = {skill_id: [] for skill_id in skill_records}
    for skill_id, record in skill_records.items():
        classic_id = CLASSIC_SKILL_IDS.get(skill_id)
        display_name = str(record.get("display_name", skill_id))
        if classic_id is None:
            skill_audit[skill_id].append({"mapping_status": "UNRESOLVED", "reason": "No exact primary client identity bridge"})
            continue
        if skill_id in BODY_SKILL_SOUNDS:
            resolutions = [sound_resolution(sound_id, slots, files) for sound_id, _ in BODY_SKILL_SOUNDS[skill_id]]
            event_suffix = {
                "warrior.slaying_swordsmanship": "slaying",
                "warrior.thrusting": "thrusting",
                "warrior.half_moon": "half_moon",
                "warrior.fire_sword": "fire_sword",
            }[skill_id]
            add_runtime_event(
                f"player.skill.{event_suffix}", "skill", skill_id, display_name,
                "skill_attack_cue", "client_effect_frame", resolutions,
                {
                    **evidence["actor_formula_and_calls"],
                    "identity": {**evidence["skill_identity_constants"], "classic_magic_id": classic_id},
                    "call": "TActor.RunActSound exact SM_* body action at frame=2",
                },
                "context.gender_male_female" if len(resolutions) == 2 else "single",
                90,
            )
            skill_audit[skill_id].extend(public_resolution(item) for item in resolutions)
            continue
        if str(record.get("activation", "")) in {"passive", "toggle_attack_mode"} or skill_id in {
            "warrior.wild_rush", "warrior.basic_swordsmanship", "taoist.spiritual_warfare"
        }:
            skill_audit[skill_id].append({
                "mapping_status": "SILENCE_VERIFIED",
                "classic_magic_id": classic_id,
                "reason": "Primary MirClient has no dedicated PlaySound call for this current passive/toggle/rush semantic; shared movement/weapon sounds remain separate events",
            })
            continue

        base = 10000 + classic_id * 10
        cast = sound_resolution(base, slots, files)
        add_runtime_event(
            f"skill.{skill_id}.cast", "skill", skill_id, display_name, "cast", "accepted_cast_action_start",
            [cast], {
                **evidence["actor_formula_and_calls"],
                "identity": {**evidence["skill_identity_constants"], "classic_magic_id": classic_id},
                "formula": "10000 + MagicSerial * 10; TActor.RunSound(SM_SPELL)",
            }, priority=85,
        )
        skill_audit[skill_id].append(public_resolution(cast))
        if skill_id in PROJECTILE_SKILLS:
            launch = sound_resolution(base + 1, slots, files)
            impact = sound_resolution(base + 2, slots, files)
            add_runtime_event(
                f"skill.{skill_id}.launch", "skill", skill_id, display_name, "projectile_launch", "canonical_projectile_spawn_success",
                [launch], {
                    **evidence["magic_phase_classification"],
                    "runtime_authority": evidence["current_projectile_authority"],
                    "formula": "MagicSerial offset +1 when NewMagic returns bofly=true",
                }, priority=80,
            )
            add_runtime_event(
                f"skill.{skill_id}.impact", "skill", skill_id, display_name, "projectile_impact", "canonical_projectile_impact",
                [impact], {**evidence["magic_effect_impact_call"], "formula": "MagicSerial offset +2 when flying effect reaches target"}, priority=75,
            )
            skill_audit[skill_id].extend([public_resolution(launch), public_resolution(impact)])
        else:
            effect = sound_resolution(base + 2, slots, files)
            add_runtime_event(
                f"skill.{skill_id}.effect", "skill", skill_id, display_name, "effect_success", "canonical_effect_commit",
                [effect], {
                    **evidence["magic_phase_classification"],
                    "runtime_authority": evidence["current_projectile_authority"],
                    "formula": "MagicSerial offset +2 when NewMagic returns bofly=false",
                }, priority=80,
            )
            skill_audit[skill_id].append(public_resolution(effect))

    # Player weapon calls are exact primary Actor.pas frame-2 cues and are
    # independent layers from body-skill cues.
    for weapon_id, sound_id, classic_shapes in PLAYER_WEAPON_SOUNDS:
        resolution = sound_resolution(sound_id, slots, files)
        add_runtime_event(
            f"player.weapon.{weapon_id}.swing", "player", f"player.weapon.{weapon_id}", weapon_id,
            "weapon_swing", "client_effect_frame", [resolution],
            {
                **evidence["actor_formula_and_calls"],
                "runtime_shape_authority": evidence["current_weapon_shape_authority"],
                "call": "TActor.RunActSound human attack frame=2 via m_nWeaponSound",
                "classic_weapon_shapes": list(classic_shapes),
                "fallback": "fist only when no weapon is equipped; unknown equipped shape fails closed",
            },
            priority=100,
        )

    for event_id, sound_ids, phase in PLAYER_REACTION_SOUNDS:
        resolutions = [sound_resolution(sound_id, slots, files) for sound_id in sound_ids]
        add_runtime_event(
            event_id,
            "player",
            event_id.rsplit(".", 1)[0],
            event_id,
            "player_reaction_voice" if event_id.endswith("voice") else "player_struck_body_contact",
            phase,
            resolutions,
            {
                **evidence["actor_formula_and_calls"],
                "constants": evidence["sound_loader_and_constants"],
                "call": (
                    "TActor.RunSound SM_NOWDEATH action start via m_nDieSound"
                    if event_id.startswith("player.death")
                    else "TActor.RunSound SM_STRUCK action start; current PvE non-human attacker keeps initialized body-longstick 72 and selects scream by sex"
                ),
                "current_scope": "PvE player actor; PvP dress/attacker material branches are not implemented",
            },
            "context.gender_male_female" if len(sound_ids) == 2 else "single",
            98,
        )

    for event_id, sound_id in PLAYER_CONTACT_SOUNDS:
        resolution = sound_resolution(sound_id, slots, files)
        add_runtime_event(
            event_id,
            "player_physical_contact",
            event_id.rsplit(".", 1)[0],
            event_id,
            "confirmed_player_physical_contact",
            "target_struck_action_start",
            [resolution],
            {
                **evidence["actor_formula_and_calls"],
                "constants": evidence["sound_loader_and_constants"],
                "runtime_shape_authority": evidence["current_weapon_shape_authority"],
                "call": "TActor.SetSound/RunSound SM_STRUCK weapon-contact then body-contact layers",
                "resolver": "AudioRuntimeService.play_player_physical_contact reproduces the primary source's classic-shape cases, including its second integer division for m_nStruckWeaponSound",
            },
            priority=96,
        )

    monster_audit: dict[str, Any] = {}
    runtime_monsters = [item for item in monsters_doc.get("entries", []) if bool(item.get("runtime_allowed", False))]
    for record in runtime_monsters:
        monster_id = int(record.get("monster_id"))
        display_name = str(record.get("canonical_name", monster_id))
        appearance = monster_appearance(record, monsters_doc)
        phase_records: list[dict[str, Any]] = []
        if appearance is None:
            monster_audit[str(monster_id)] = {
                "mapping_status": "UNRESOLVED",
                "reason": "Canonical runtime record has no exact client appearance",
                "phases": [],
            }
            continue
        for offset, (semantic, phase) in MONSTER_PHASES.items():
            if offset == 6 and appearance != 80:
                not_applicable = {
                    "semantic_event": semantic,
                    "phase": phase,
                    "mapping_status": "NOT_APPLICABLE_SOURCE_GUARD",
                    "reason": "Primary MirClient calls the secondary death cue only for client appearance 80",
                }
                phase_records.append(not_applicable)
                generated_events.append({
                    "event_id": f"monster.{monster_id}.{semantic}",
                    "owner_kind": "monster",
                    "canonical_owner_id": f"monster.{monster_id}",
                    "display_name": display_name,
                    "semantic_event": semantic,
                    "phase": phase,
                    "mapping_status": "NOT_APPLICABLE_SOURCE_GUARD",
                    "integration_status": "NOT_APPLICABLE",
                    "source_rule": {
                        **evidence["actor_formula_and_calls"],
                        "call_guard": "client appearance == 80",
                    },
                    "samples": [],
                })
                continue
            resolution = sound_resolution(200 + appearance * 10 + offset, slots, files)
            phase_records.append({"semantic_event": semantic, "phase": phase, **public_resolution(resolution)})
            add_runtime_event(
                f"monster.{monster_id}.{semantic}", "monster", f"monster.{monster_id}", display_name,
                semantic, phase, [resolution],
                {
                    **evidence["actor_formula_and_calls"],
                    "formula": f"200 + m_wAppearance({appearance}) * 10 + {offset}",
                    "canonical_appearance_source": "assets/data/runtime/canonical_monster_catalog.json exact monster_id record",
                },
                priority=70 if semantic in {"death", "appear"} else 45,
            )
        exact_count = sum(1 for item in phase_records if item.get("mapping_status") == "EXACT")
        phase_statuses = {str(item.get("mapping_status", "")) for item in phase_records}
        monster_audit[str(monster_id)] = {
            "client_appearance": appearance,
            "mapping_status": (
                "PARTIAL_MISSING_SOURCE" if "MISSING_SOURCE" in phase_statuses else
                "EXACT" if phase_statuses <= {"EXACT", "NOT_APPLICABLE_SOURCE_GUARD"} else
                "EXACT_WITH_VERIFIED_SILENT_PHASES" if exact_count else
                "SILENCE_VERIFIED"
            ),
            "exact_phase_count": exact_count,
            "phases": phase_records,
        }

    # Item sounds in the primary client are shared by semantic type.  Build
    # each shared sample once, then route exact current stable identities to
    # it.  This avoids both display-name runtime lookup and 727 duplicate WAVs.
    for event_id, (sound_id, phase) in GENERIC_ITEM_EVENTS.items():
        resolution = sound_resolution(sound_id, slots, files)
        add_runtime_event(
            event_id,
            "ui" if event_id.startswith("ui.") else "item_type",
            event_id.rsplit(".", 1)[0],
            event_id,
            event_id.rsplit(".", 1)[-1],
            phase,
            [resolution],
            {
                **evidence["sound_loader_and_constants"],
                "item_calls": evidence["item_operation_calls"],
                "inventory_calls": evidence["item_inventory_calls"],
                "sound_id": sound_id,
                "phase_adaptation": (
                    "HardCore emits the material cue only after the operation commits; "
                    "the source client invoked ItemClickSound before the server response"
                    if event_id.startswith("item.inventory.select.") else
                    "none"
                ),
            },
            priority=65 if event_id.startswith("currency.") else 55,
        )

    equipment_event_by_category = {
        "武器": "item.inventory.select.weapon",
        "盔甲": "item.inventory.select.armor",
        "戒指": "item.inventory.select.ring",
        "项链": "item.inventory.select.necklace",
        "头盔": "item.inventory.select.helmet",
    }
    item_audit: list[dict[str, Any]] = []

    def add_item_audit(
        stable_key: str,
        record: dict[str, Any],
        identity_kind: str,
        identity_value: int | str,
    ) -> None:
        kind = str(record.get("kind", "equipment" if identity_kind == "item_id" else "unknown"))
        category = str(record.get("category", ""))
        display_name = str(record.get("name", record.get("serviceName", stable_key)))
        usable = bool(record.get("usable", kind == "consumable"))
        routes: dict[str, str] = {}
        phase_evidence: list[dict[str, Any]] = []

        if kind == "equipment":
            event_id = equipment_event_by_category.get(category, "")
            if category == "手镯":
                # SoundUtil's exact name predicate is applied only at build
                # time; runtime still resolves solely by stable item ID.
                event_id = (
                    "item.inventory.select.bracelet_or_glove"
                    if "手镯" in display_name or "手套" in display_name
                    else "item.inventory.select.belt"
                )
            if not event_id:
                event_id = "item.inventory.select.generic"
            if event_id in runtime_events:
                routes["equip_success"] = event_id
                routes["unequip_success"] = event_id
            phase_evidence.append({
                "semantic_events": ["equip_success", "unequip_success"],
                "mapping_status": "EXACT_SHARED_TYPE",
                "runtime_event_id": event_id,
                "source": evidence["sound_loader_and_constants"],
                "source_rule": "ItemClickSound exact StdMode/category family; 手镯/手套 predicate compiled by stable item_id",
                "phase_adaptation": "current commit success only; failed equip/unequip stays silent",
            })
        elif kind == "consumable" and usable and ("药" in category or identity_kind == "authority_item_id"):
            event_id = "item.use.drug.success"
            if event_id in runtime_events:
                routes["use_success"] = event_id
            phase_evidence.append({
                "semantic_events": ["use_success"],
                "mapping_status": "EXACT_SHARED_TYPE",
                "runtime_event_id": event_id,
                "source": evidence["sound_loader_and_constants"],
                "source_rule": "current canonical kind=consumable/category=药品 bridges to MirClient ItemUseSound drug semantic",
                "phase_adaptation": "current inventory consumption/save commit success only",
            })
        else:
            phase_evidence.append({
                "semantic_events": ["use_success"],
                "mapping_status": "SILENCE_VERIFIED" if not usable or kind in {"scroll", "skill_book"} else "UNRESOLVED",
                "source": evidence["sound_loader_and_constants"],
                "reason": (
                    "MirClient ItemUseSound plays only drug/food StdMode 0..2; current unsupported or non-drug type has no exact success cue"
                    if not usable or kind in {"scroll", "skill_book"} else
                    "Current canonical type has no exact bridge to a MirClient ItemUseSound branch"
                ),
            })
        phase_evidence.extend([
            {
                "semantic_events": ["pickup_success"],
                "mapping_status": "SILENCE_VERIFIED",
                "source": evidence["item_operation_calls"],
                "reason": "SM_ADDITEM/ClientGetAddItem commits the item without PlaySound",
            },
            {
                "semantic_events": ["drop_success"],
                "mapping_status": "SILENCE_VERIFIED",
                "source": evidence["item_operation_calls"],
                "reason": "drop request/ack path has no item-drop success PlaySound; s_drop_stonepiece belongs to mining",
            },
        ])
        item_event_routes[stable_key] = {
            "identity_kind": identity_kind,
            "identity_value": identity_value,
            "kind": kind,
            "category": category,
            "events": routes,
        }
        item_audit.append({
            "stable_item_key": stable_key,
            "identity_kind": identity_kind,
            "identity_value": identity_value,
            "display_name": display_name,
            "kind": kind,
            "category": category,
            "use_effect": str(record.get("useEffect", "")),
            "usable": usable,
            "audio_mapping_status": "EXACT_SHARED_TYPE" if routes else "SILENCE_VERIFIED_OR_UNRESOLVED",
            "runtime_routes": routes,
            "phase_evidence": phase_evidence,
        })

    for record in equipment_items_doc.get("records", []):
        if isinstance(record, dict):
            item_id = int(record.get("itemId", -1))
            if item_id >= 0:
                add_item_audit(f"item:{item_id}", record, "item_id", item_id)
    for record in service_items_doc.get("runtimeItems", []):
        if isinstance(record, dict):
            service_index = int(record.get("serviceIndex", -1))
            if service_index >= 0:
                add_item_audit(f"service:{service_index}", record, "service_index", service_index)
    for record in item_runtime_authority_doc.get("newItems", []):
        if isinstance(record, dict):
            item_id = int(record.get("itemId", -1))
            if item_id >= 0:
                add_item_audit(f"item:{item_id}", record, "authority_item_id", item_id)
    gold_event_id = "currency.gold.changed"
    item_event_routes["currency:gold"] = {
        "identity_kind": "currency",
        "identity_value": "gold",
        "kind": "currency",
        "category": "货币",
        "events": {
            "loot_success": gold_event_id,
            "balance_change_success": gold_event_id,
        } if gold_event_id in runtime_events else {},
    }
    item_audit.append({
        "stable_item_key": "currency:gold",
        "identity_kind": "currency",
        "identity_value": "gold",
        "display_name": "金币",
        "kind": "currency",
        "category": "货币",
        "usable": False,
        "audio_mapping_status": "EXACT_SHARED_TYPE",
        "runtime_routes": item_event_routes["currency:gold"]["events"],
        "phase_evidence": [{
            "semantic_events": ["loot_success", "balance_change_success"],
            "mapping_status": "EXACT",
            "runtime_event_id": gold_event_id,
            "source": evidence["item_operation_calls"],
            "source_rule": "SM_GOLDCHANGED calls s_money after the server balance message",
        }],
    })

    managed_root = project_root / "assets/audio/sfx/client"
    managed_root.mkdir(parents=True, exist_ok=True)
    expected_local: set[Path] = set()
    for res_path, (source_file, expected_sha) in needed_files.items():
        target = project_root / res_path.removeprefix("res://")
        expected_local.add(target.resolve())
        if not target.is_file() or sha256_file(target) != expected_sha:
            shutil.copyfile(source_file, target)
        if sha256_file(target) != expected_sha:
            raise OSError(f"generated asset hash mismatch: {target}")
    for old_file in managed_root.glob("*.wav"):
        if old_file.resolve() not in expected_local:
            old_file.unlink()

    # Preserve the user-authorized NPC bindings while making the already-wired
    # integration state truthful.  Events are deterministic generated output.
    for binding in authoring.get("bindings", []):
        if binding.get("owner_kind") == "npc":
            binding["integration_status"] = "BOUND"
    authoring["client_rules_primary"] = evidence
    authoring["item_identity_sources"] = item_identity_sources
    authoring["events"] = generated_events
    authoring["event_generation"] = {
        "command": "audio_pipeline.py build-exact",
        "effective_loader_semantics": "SoundUtil.LoadSoundList accepts only strictly increasing sound IDs",
        "generated_event_count": len(generated_events),
        "runtime_event_count": len(runtime_events),
        "managed_asset_count": len(needed_files),
        "current_item_identity_count": len(item_audit),
        "item_route_count": sum(len(item.get("runtime_routes", {})) for item in item_audit),
        "player_core_event_count": len(PLAYER_REACTION_SOUNDS) + len(PLAYER_CONTACT_SOUNDS),
    }
    authoring["unresolved_scope"] = [
        {
            "owner_kind": "item_non_drug_use_or_untyped_ui",
            "reason": "Exact shared drug/equipment/gold routes are generated. Unsupported/non-drug use and UI widgets without an explicit normal/rock/glass class remain silent or unresolved rather than borrowing a click.",
        },
        {
            "owner_kind": "skill_or_monster_missing_sample",
            "reason": "Entries marked MISSING_SOURCE retain the exact sound ID and primary index path; no adjacent file substitution is permitted.",
        },
        {
            "owner_kind": "player_footstep_surface",
            "reason": "Primary IDs/cadence are known, but current maps do not expose an audited legacy tile-to-footstep-surface identity. Leave runtime unbound rather than treating every map as ground.",
        },
        {
            "owner_kind": "ui_material",
            "reason": "Primary normal/rock/glass IDs are known, but current widgets have no explicit material identity contract. Runtime callpoints remain NOT_STARTED.",
        },
    ]
    write_json(source_path, authoring)

    runtime_bindings = previous_runtime.get("bindings", {})
    for binding in runtime_bindings.values():
        if isinstance(binding, dict) and binding.get("owner_kind") == "npc":
            binding["integration_status"] = "BOUND"
    runtime_doc = {
        "schema_version": 1,
        "contract_id": "audio.bindings.runtime.v1",
        "base_sha": args.base_sha,
        "source_authoring": "res://assets/data/audio/audio_bindings.source.json",
        "runtime_initialization_policy": previous_runtime.get("runtime_initialization_policy", {}),
        "bindings": runtime_bindings,
        "events": runtime_events,
        "item_event_routes": item_event_routes,
    }
    write_json(runtime_path, runtime_doc)

    skill_req = {str(item.get("canonical_skill_id", "")): item for item in requirements.get("skills", [])}
    for skill_id, audit in skill_audit.items():
        if skill_id not in skill_req:
            continue
        statuses = {str(item.get("mapping_status", "")) for item in audit}
        skill_req[skill_id]["classic_magic_id"] = CLASSIC_SKILL_IDS.get(skill_id)
        skill_req[skill_id]["audio_mapping_status"] = (
            "PARTIAL_MISSING_SOURCE" if "MISSING_SOURCE" in statuses else
            "EXACT_WITH_VERIFIED_SILENT_PHASES" if "EXACT" in statuses and "SILENCE_VERIFIED" in statuses else
            "EXACT" if "EXACT" in statuses else
            "SILENCE_VERIFIED" if statuses == {"SILENCE_VERIFIED"} else
            "UNRESOLVED"
        )
        skill_req[skill_id]["phase_evidence"] = audit
        skill_req[skill_id].pop("missing_evidence", None)
    monster_req = {str(item.get("monster_id")): item for item in requirements.get("monsters", [])}
    for monster_id, audit in monster_audit.items():
        if monster_id not in monster_req:
            continue
        monster_req[monster_id]["client_appearance"] = audit.get("client_appearance")
        monster_req[monster_id]["audio_mapping_status"] = audit.get("mapping_status", "UNRESOLVED")
        monster_req[monster_id]["phase_evidence"] = audit.get("phases", [])
        monster_req[monster_id].pop("missing_evidence", None)
    requirements["summary"].update(
        {
            "runtime_event_count": len(runtime_events),
            "managed_asset_count": len(needed_files),
            "skill_exact_or_silence_count": sum(
                1 for item in requirements.get("skills", [])
                if item.get("audio_mapping_status") in {"EXACT", "EXACT_WITH_VERIFIED_SILENT_PHASES", "SILENCE_VERIFIED"}
            ),
            "monster_exact_count": sum(
                1 for item in requirements.get("monsters", [])
                if item.get("audio_mapping_status") in {"EXACT", "EXACT_WITH_VERIFIED_SILENT_PHASES"}
            ),
            "all_non_npc_mappings_unresolved": False,
            "current_item_identity_count": len(item_audit),
            "item_exact_route_identity_count": sum(1 for item in item_audit if item.get("runtime_routes")),
            "item_runtime_route_count": sum(len(item.get("runtime_routes", {})) for item in item_audit),
            "player_core_event_count": len(PLAYER_REACTION_SOUNDS) + len(PLAYER_CONTACT_SOUNDS),
        }
    )
    requirements["player_core"] = {
        "mapping_status": "EXACT",
        "runtime_status": "BOUND",
        "events": [
            {
                "event_id": event["event_id"],
                "semantic_event": event["semantic_event"],
                "phase": event["phase"],
                "mapping_status": event["mapping_status"],
                "samples": event["samples"],
            }
            for event in generated_events
            if str(event.get("event_id", "")).startswith((
                "player.hurt.",
                "player.death.",
                "player.contact.",
            ))
        ],
        "verified_silent_or_unbound": [
            {
                "semantic": "ordinary_attack_miss",
                "status": "SILENCE_VERIFIED",
                "reason": "Primary client plays the frame-2 weapon swing for the attack action but has no miss-specific PlaySound call.",
            },
            {
                "semantic": "footstep_surface",
                "status": "CURRENT_RUNTIME_IDENTITY_MISSING",
                "reason": "Primary sound IDs 1..32 are not bound without an audited current map surface identity.",
            },
            {
                "semantic": "ui_material",
                "status": "NOT_STARTED",
                "reason": "Current widgets do not declare normal/rock/glass material identity.",
            },
        ],
    }
    requirements["items"] = item_audit
    requirements["summary"]["item_count"] = len(item_audit)
    requirements["item_identity_contract"] = {
        "equipment": "item:<canonical item_id>",
        "service_non_equipment": "service:<stable serviceIndex>",
        "authority_new_item": "item:<canonical itemId>",
        "currency": "currency:gold",
        "runtime_names_forbidden": True,
        "sources": item_identity_sources,
    }
    write_json(requirements_path, requirements)

    report = {
        "schema_version": 1,
        "contract_id": "audio.exact_mapping.report.v1",
        "base_sha": args.base_sha,
        "source_rules": evidence,
        "item_identity_sources": item_identity_sources,
        "sound_index_sha256": index["sha256"],
        "effective_loader": {
            "raw_duplicate_ids": [1680, 1943],
            "accepted_rows": {str(sound_id): slots[sound_id].get("line_number") for sound_id in [1680, 1943] if sound_id in slots},
            "rule": "strictly increasing ID; later duplicate rows ignored",
        },
        "counts": {
            "canonical_skills": len(skill_records),
            "runtime_monsters": len(runtime_monsters),
            "authoring_events": len(generated_events),
            "runtime_events": len(runtime_events),
            "managed_unique_assets": len(needed_files),
            "current_item_identities": len(item_audit),
            "item_route_identities": sum(1 for item in item_audit if item.get("runtime_routes")),
            "item_runtime_routes": sum(len(item.get("runtime_routes", {})) for item in item_audit),
        },
        "missing_sources": [
            {"event_id": item["event_id"], "samples": item["samples"]}
            for item in generated_events if item.get("mapping_status") == "MISSING_SOURCE"
        ],
        "verified_silent_events": [
            {"event_id": item["event_id"], "samples": item["samples"]}
            for item in generated_events if item.get("mapping_status") == "SILENCE_VERIFIED"
        ],
        "source_guarded_not_applicable_events": [
            item["event_id"] for item in generated_events
            if item.get("mapping_status") == "NOT_APPLICABLE_SOURCE_GUARD"
        ],
        "integration_api": {
            "method": "AudioRuntimeService.play_event(event_id, context)",
            "monster_helper": "AudioRuntimeService.play_monster_event(monster_id, semantic_event, context)",
            "success_only": True,
        },
    }
    write_json(Path(args.report), report)
    print(json.dumps({"status": "PASS", **report["counts"], "report": Path(args.report).as_posix()}, ensure_ascii=False))
    return 0


def command_inventory(args: argparse.Namespace) -> int:
    primary_root = Path(args.primary_root).resolve()
    user_root = Path(args.user_root).resolve()
    primary_index = Path(args.primary_index).resolve() if args.primary_index else primary_root / "sound.lst"
    user_index = Path(args.user_index).resolve() if args.user_index else user_root / "sound.lst"
    primary = source_inventory(primary_root, args.primary_distribution, primary_index)
    user = source_inventory(user_root, args.user_distribution, user_index)
    out_dir = Path(args.out_dir)
    write_json(out_dir / "source_inventory.json", {"schema_version": 1, "base_sha": args.base_sha, "sources": [public_inventory(primary), public_inventory(user)]})
    write_json(out_dir / "source_comparison.json", source_comparison(primary, user))
    write_json(
        out_dir / "sound_index_entries.json",
        {
            "schema_version": 1,
            "authoritative_source": primary["source_distribution"],
            "primary": primary.get("sound_index"),
            "user_extract": user.get("sound_index"),
            "same_index_sha256": primary["sound_index"]["sha256"] == user["sound_index"]["sha256"],
        },
    )
    write_json(out_dir / "source_anomalies.json", anomalies(primary))
    comparison = source_comparison(primary, user)
    print(json.dumps({"status": "PASS", "out_dir": out_dir.as_posix(), "comparison": comparison["status_counts"]}, ensure_ascii=False))
    return 0


def command_validate(args: argparse.Namespace) -> int:
    source_path = Path(args.source)
    runtime_path = Path(args.runtime)
    source = json.loads(source_path.read_text(encoding="utf-8"))
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    errors: list[str] = []
    project_root = Path(args.project_root).resolve()
    runtime_ids = set(runtime.get("bindings", {}))
    for binding in source.get("bindings", []):
        owner_id = binding.get("canonical_owner_id", "")
        if binding.get("mapping_status") in {"EXACT", "SHARED_VERIFIED"} and binding.get("owner_kind") == "npc":
            if owner_id not in runtime_ids:
                errors.append(f"missing runtime binding: {owner_id}")
            runtime_binding = runtime.get("bindings", {}).get(owner_id, {})
            runtime_paths = {
                Path(str(path).replace("res://", "", 1)).name.casefold(): str(path)
                for path in runtime_binding.get("runtime_paths", [])
            }
            for variant in binding.get("source_variants", []):
                filename = str(variant.get("filename", ""))
                expected_sha = str(
                    variant.get("source_sha256", variant.get("sha256", ""))
                ).lower()
                runtime_rel = runtime_paths.get(Path(filename).name.casefold())
                if not runtime_rel:
                    errors.append(f"missing runtime variant: {owner_id}:{filename}")
                    continue
                local = project_root / runtime_rel.removeprefix("res://").replace("/", "\\")
                if not local.is_file():
                    errors.append(f"missing runtime file: {owner_id}:{runtime_rel}")
                    continue
                actual_sha = sha256_file(local).lower()
                if expected_sha and actual_sha != expected_sha:
                    errors.append(f"runtime hash mismatch: {owner_id}:{filename}:{actual_sha}!={expected_sha}")
    for owner_id, binding in runtime.get("bindings", {}).items():
        if binding.get("mapping_status") not in {"EXACT", "SHARED_VERIFIED"}:
            errors.append(f"unresolved runtime binding: {owner_id}")
        for path in binding.get("runtime_paths", []):
            if not path.startswith("res://"):
                errors.append(f"non-res path: {owner_id}:{path}")
                continue
            local = project_root / path.removeprefix("res://").replace("/", "\\")
            if not local.is_file():
                errors.append(f"missing runtime file: {owner_id}:{path}")
    runtime_events = runtime.get("events", {})
    if not isinstance(runtime_events, dict):
        errors.append("runtime events must be an event_id dictionary")
        runtime_events = {}
    source_events = {
        str(event.get("event_id", "")): event
        for event in source.get("events", [])
        if isinstance(event, dict) and event.get("event_id")
    }
    for event_id, event in runtime_events.items():
        if event_id not in source_events:
            errors.append(f"runtime event has no authoring record: {event_id}")
        if event.get("mapping_status") != "EXACT":
            errors.append(f"non-exact runtime event: {event_id}")
        runtime_paths = event.get("runtime_paths", [])
        if not isinstance(runtime_paths, list) or not runtime_paths:
            errors.append(f"runtime event has no sample: {event_id}")
            continue
        for path in runtime_paths:
            if not isinstance(path, str) or not path.startswith("res://assets/audio/"):
                errors.append(f"invalid runtime event path: {event_id}:{path}")
                continue
            local = project_root / path.removeprefix("res://").replace("/", "\\")
            if not local.is_file():
                errors.append(f"missing runtime event file: {event_id}:{path}")
    for event_id, event in source_events.items():
        if event.get("mapping_status") != "EXACT":
            continue
        if event_id not in runtime_events:
            errors.append(f"exact authoring event missing at runtime: {event_id}")
            continue
        runtime_event_paths = set(runtime_events[event_id].get("runtime_paths", []))
        authoring_event_paths: set[str] = set()
        for sample in event.get("samples", []):
            if not isinstance(sample, dict) or sample.get("mapping_status") != "EXACT":
                continue
            path = str(sample.get("runtime_path", ""))
            authoring_event_paths.add(path)
            if path not in runtime_event_paths:
                errors.append(f"authoring/runtime event path mismatch: {event_id}:{path}")
                continue
            local = project_root / path.removeprefix("res://").replace("/", "\\")
            if not local.is_file():
                continue
            expected_sha = str(sample.get("source_sha256", "")).lower()
            if expected_sha and sha256_file(local).lower() != expected_sha:
                errors.append(f"runtime event hash mismatch: {event_id}:{path}")
        if authoring_event_paths != runtime_event_paths:
            errors.append(f"runtime event path set differs from authoring: {event_id}")
    item_event_routes = runtime.get("item_event_routes", {})
    if not isinstance(item_event_routes, dict):
        errors.append("item_event_routes must be a stable-key dictionary")
        item_event_routes = {}
    stable_item_key_pattern = re.compile(r"^(?:item:\d+|service:\d+|currency:gold)$")
    for stable_item_key, route in item_event_routes.items():
        if not stable_item_key_pattern.match(str(stable_item_key)):
            errors.append(f"invalid or name-based item route key: {stable_item_key}")
        if not isinstance(route, dict):
            errors.append(f"item route must be dictionary: {stable_item_key}")
            continue
        events = route.get("events", {})
        if not isinstance(events, dict):
            errors.append(f"item route events must be dictionary: {stable_item_key}")
            continue
        for semantic_event, event_id in events.items():
            if str(event_id) not in runtime_events:
                errors.append(f"item route event missing at runtime: {stable_item_key}:{semantic_event}:{event_id}")
    result = {
        "status": "PASS" if not errors else "FAIL",
        "errors": errors,
        "runtime_binding_count": len(runtime_ids),
        "runtime_event_count": len(runtime_events),
        "item_route_identity_count": len(item_event_routes),
    }
    print(json.dumps(result, ensure_ascii=False))
    return 0 if not errors else 1


def command_rules(args: argparse.Namespace) -> int:
    source_path = Path(args.sound_util)
    source_sha256 = sha256_file(source_path)
    lines = source_path.read_text(encoding=args.encoding, errors="replace").splitlines()
    pattern = re.compile(r"^\s*(s_[A-Za-z0-9_]+)\s*=\s*([0-9]+)\s*;")
    rules: list[dict[str, Any]] = []
    for line_number, line in enumerate(lines, start=1):
        match = pattern.match(line)
        if not match:
            continue
        rules.append(
            {
                "symbol": match.group(1),
                "sound_id": int(match.group(2)),
                "source_line": line_number,
                "source_text": line.strip(),
            }
        )
    result = {
        "schema_version": 1,
        "contract_id": "audio.client_sound_constants.v1",
        "source_distribution": "source.original_gameofmir.mirclient",
        "source_path": source_path.as_posix(),
        "source_sha256": source_sha256,
        "encoding": args.encoding,
        "rules": rules,
        "semantic_mapping_note": "Constants are preserved as source evidence. A constant does not become a runtime binding without an object, phase, and current-project callsite.",
        "current_project_exact_bindings": [
            {
                "owner_id": f"player.weapon.{weapon_id}",
                "sound_id": sound_id,
                "classic_weapon_shapes": list(classic_shapes),
                "callsite": "scripts/player_visual.gd:_weapon_audio_event_id",
                "binding_source": "assets/data/audio/audio_bindings.source.json",
            }
            for weapon_id, sound_id, classic_shapes in PLAYER_WEAPON_SOUNDS
        ],
        "unbound_constants_require_callsite_evidence": True,
    }
    write_json(Path(args.out), result)
    print(json.dumps({"status": "PASS", "rule_count": len(rules), "out": Path(args.out).as_posix()}, ensure_ascii=False))
    return 0


def command_requirements(args: argparse.Namespace) -> int:
    """Enumerate current canonical objects without inventing sound mappings."""
    skills_path = Path(args.skills)
    monsters_path = Path(args.monsters)
    items_path = Path(args.items)
    skills_doc = json.loads(skills_path.read_text(encoding="utf-8"))
    monsters_doc = json.loads(monsters_path.read_text(encoding="utf-8"))
    items_doc = json.loads(items_path.read_text(encoding="utf-8"))
    skills = list(skills_doc.get("skills", []))
    monsters = list(monsters_doc.get("records", []))
    items = list(items_doc.get("records", []))
    unresolved_skill_reason = [
        "exact SoundUtil symbol or sound.lst ID to canonical skill ID is not proven",
        "current runtime accepted audio phase callsite is not owned by this audio-only package",
    ]
    unresolved_monster_reason = [
        "exact monster_id-to-sound.lst/SoundUtil mapping is not proven",
        "current runtime attack/hurt/death audio callsite is not owned by this audio-only package",
    ]
    unresolved_item_reason = [
        "item operation success branch to exact source sound is not proven per item_id",
        "current runtime item/equipment audio callsite is not owned by this audio-only package",
    ]
    result = {
        "schema_version": 1,
        "contract_id": "audio.requirements_inventory.v1",
        "base_sha": args.base_sha,
        "source_files": [
            {
                "kind": "skills",
                "path": skills_path.as_posix(),
                "sha256": sha256_file(skills_path),
                "record_count": len(skills),
                "authority": "project_canonical_skill_source_of_truth",
            },
            {
                "kind": "monsters",
                "path": monsters_path.as_posix(),
                "sha256": sha256_file(monsters_path),
                "record_count": len(monsters),
                "authority": "current_monster_runtime_authority_records",
            },
            {
                "kind": "items",
                "path": items_path.as_posix(),
                "sha256": sha256_file(items_path),
                "record_count": len(items),
                "authority": "vanilla_core_item_records",
            },
        ],
        "event_audit_scope": [
            "skill cast/release/projectile/hit/effect-end where the current runtime proves the phase",
            "monster spawn/attack/hurt/death/special lifecycle by exact monster_id",
            "item use/equip/unequip/pickup/drop success by exact item_id",
            "interaction/UI only where a current success callsite exists",
        ],
        "skills": [
            {
                "canonical_skill_id": str(record.get("skill_id", "")),
                "display_name": str(record.get("display_name", "")),
                "profession": str(record.get("class", "")),
                "activation": str(record.get("activation", "")),
                "membership_status": str(record.get("membership_status", "")),
                "content_layer": str(record.get("content_layer", "")),
                "audio_mapping_status": "UNRESOLVED_NO_EXACT_SOURCE_AND_CALLSITE",
                "missing_evidence": unresolved_skill_reason,
            }
            for record in skills
            if isinstance(record, dict)
        ],
        "monsters": [
            {
                "monster_id": record.get("monster_id"),
                "canonical_name": str(record.get("canonical_name", "")),
                "classification": str(record.get("classification", "")),
                "runtime_allowed": bool(record.get("runtime_allowed", False)),
                "boss": bool((record.get("special") or {}).get("boss", False)),
                "ranged": bool((record.get("special") or {}).get("ranged", False)),
                "special_attack": bool((record.get("special") or {}).get("special_attack", False)),
                "audio_mapping_status": "UNRESOLVED_NO_EXACT_SOURCE_AND_CALLSITE",
                "missing_evidence": unresolved_monster_reason,
            }
            for record in monsters
            if isinstance(record, dict)
        ],
        "items": [
            {
                "item_id": record.get("itemId"),
                "display_name": str(record.get("name", "")),
                "category": str(record.get("category", "")),
                "availability_default": bool(record.get("availabilityDefault", False)),
                "audio_mapping_status": "UNRESOLVED_NO_EXACT_SOURCE_AND_CALLSITE",
                "missing_evidence": unresolved_item_reason,
            }
            for record in items
            if isinstance(record, dict)
        ],
        "summary": {
            "skill_count": len(skills),
            "monster_count": len(monsters),
            "runtime_allowed_monster_count": sum(
                1 for record in monsters if isinstance(record, dict) and bool(record.get("runtime_allowed", False))
            ),
            "item_count": len(items),
            "all_non_npc_mappings_unresolved": True,
        },
        "policy_note": "This is a complete identity/requirement inventory, not permission to guess audio. An object remains unresolved until exact source evidence and an accepted current-project success phase are both recorded.",
    }
    write_json(Path(args.out), result)
    print(
        json.dumps(
            {
                "status": "PASS",
                "skill_count": len(skills),
                "monster_count": len(monsters),
                "item_count": len(items),
                "out": Path(args.out).as_posix(),
            },
            ensure_ascii=False,
        )
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    inventory = subparsers.add_parser("inventory")
    inventory.add_argument("--primary-root", required=True)
    inventory.add_argument("--user-root", required=True)
    inventory.add_argument("--primary-index")
    inventory.add_argument("--user-index")
    inventory.add_argument("--primary-distribution", default="client.classic_raw_complete")
    inventory.add_argument("--user-distribution", default="client.user_supplied_extract")
    inventory.add_argument("--base-sha", default=BASE_SHA_DEFAULT)
    inventory.add_argument("--out-dir", required=True)
    inventory.set_defaults(handler=command_inventory)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--source", required=True)
    validate.add_argument("--runtime", required=True)
    validate.add_argument("--project-root", default=".")
    validate.set_defaults(handler=command_validate)
    rules = subparsers.add_parser("rules")
    rules.add_argument("--sound-util", required=True)
    rules.add_argument("--encoding", default="cp949")
    rules.add_argument("--out", required=True)
    rules.set_defaults(handler=command_rules)
    requirements = subparsers.add_parser("requirements")
    requirements.add_argument("--skills", required=True)
    requirements.add_argument("--monsters", required=True)
    requirements.add_argument("--items", required=True)
    requirements.add_argument("--base-sha", default=BASE_SHA_DEFAULT)
    requirements.add_argument("--out", required=True)
    requirements.set_defaults(handler=command_requirements)
    exact = subparsers.add_parser("build-exact")
    exact.add_argument("--primary-root", required=True)
    exact.add_argument("--primary-index", required=True)
    exact.add_argument("--skills", required=True)
    exact.add_argument("--monsters", required=True)
    exact.add_argument("--equipment-items", default="assets/data/vanilla_176/items.json")
    exact.add_argument("--service-items", default="assets/data/service_item_catalog.json")
    exact.add_argument("--item-runtime-authority", default="assets/data/item_runtime_authority_v1.json")
    exact.add_argument("--source-authoring", required=True)
    exact.add_argument("--runtime", required=True)
    exact.add_argument("--requirements", required=True)
    exact.add_argument("--report", required=True)
    exact.add_argument("--project-root", default=".")
    exact.add_argument("--base-sha", default=BASE_SHA_DEFAULT)
    exact.set_defaults(handler=command_build_exact)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.handler(args))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
