#!/usr/bin/env python3
"""Build verified five-action atlases for every still-unbound monsterId.

The binding chain is deliberately local and reproducible:

1. project monsterId/name identity;
2. the selected 1.76 Paradox Monster.DB RaceImg/Appr fields;
3. the original client Actor.pas action and WIL-offset tables;
4. drawable pixels in the bundled Mon*.wil libraries.

An action is emitted only when all eight directions and every declared frame
decode to non-empty pixels. Monsters whose original client table intentionally
defines no walk/hit/death action receive an explicit same-profile action alias;
they are never substituted with another monster's artwork.
"""

from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
MONSTERS_PATH = ROOT / "assets/data/legend176_data.json"
COMMON_PATH = ROOT / "assets/data/bich_common_client_art_sources.json"
UNDEAD_PATH = ROOT / "assets/data/bich_undead_client_art_sources.json"
BOSSES_PATH = ROOT / "assets/data/classic_boss_client_art_sources.json"
MONSTER_DB_PATH = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "mylgd_mir2server_176/Mud2/DB/Monster.DB"
)
ACTOR_PATH = ROOT / "dev_art_sources/reference/original_gameofmir/Client/Actor.pas"
PRIMARY_CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
COMPLETE_CLIENT_DATA = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT_DIR = ROOT / "assets/art/monsters/client_complete"
MANIFEST_PATH = ROOT / "assets/data/complete_monster_client_art_sources.json"

PADDING = 8
REQUIRED_ACTIONS = {
    "idle": "ActStand",
    "walk": "ActWalk",
    "attack": "ActAttack",
    "hit": "ActStruck",
    "death": "ActDie",
}

# Active GetRaceByPM cases in the version-bound original client. RaceImg 13 is
# intentionally absent here because its already-bound 食人花 profile has a
# pixel-verified MA13 override in build_bich_client_common_monsters.py.
RACE_IMAGE_TO_ACTION_TABLE = {
    9: "MA9",
    10: "MA10",
    11: "MA11",
    12: "MA12",
    13: "MA14",
    14: "MA14",
    15: "MA15",
    16: "MA16",
    17: "MA14",
    18: "MA14",
    19: "MA19",
    20: "MA19",
    21: "MA19",
    22: "MA15",
    23: "MA14",
    24: "MA12",
    30: "MA17",
    31: "MA17",
    32: "MA24",
    33: "MA25",
    34: "MA30",
    35: "MA31",
    36: "MA32",
    37: "MA19",
    40: "MA19",
    41: "MA20",
    42: "MA20",
    43: "MA21",
    45: "MA19",
    47: "MA22",
    48: "MA23",
    49: "MA23",
    52: "MA19",
    53: "MA19",
    54: "MA28",
    55: "MA29",
    60: "MA33",
    61: "MA33",
    62: "MA33",
    63: "MA34",
    64: "MA19",
    65: "MA19",
    66: "MA19",
    67: "MA19",
    68: "MA19",
    69: "MA19",
    70: "MA33",
    71: "MA33",
    72: "MA33",
    73: "MA19",
    74: "MA19",
    75: "MA39",
    76: "MA38",
    77: "MA39",
    78: "MA40",
    79: "MA19",
    80: "MA42",
    81: "MA43",
    83: "MA44",
    84: "MA45",
    85: "MA45",
    86: "MA45",
    87: "MA45",
    88: "MA45",
    89: "MA45",
    90: "MA30",
    98: "MA27",
    99: "MA26",
}

# 21CQ appearance 171 and the local Monster.DB both show that the project's
# 神兽0 row is the animated second form, while the database's unsuffixed 神兽
# row is appearance 170. This is a name-version compatibility alias, not an
# inferred visual substitution.
DB_NAME_OVERRIDES = {146: "神兽1"}

# These original tables describe a single fixed-body sequence. The client
# renders that sequence regardless of facing, so the atlas repeats the same
# verified pixels across eight logical direction rows.
NON_DIRECTIONAL_ACTION_TABLES = {"MA21", "MA30", "MA31"}

# 宝箱 uses ordinary directional idle/walk/attack/hit rows, but its WIL block
# stores only one terminal death/open sequence at offsets 260..269.
NON_DIRECTIONAL_ACTION_OVERRIDES = {(166, "death")}

# MA30/MA31 declare a ten-slot fixed-body walk range, but their bundled WIL
# blocks contain only the four standing frames at that location. The original
# actors do not translate across the map, so walk intentionally projects the
# verified stand sequence instead of accepting six transparent slots.
ACTION_SOURCE_OVERRIDES = {
    ("MA30", "walk"): "ActStand",
    ("MA31", "walk"): "ActStand",
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _decode_paradox_int(raw: bytes) -> int | None:
    value = struct.unpack(">i", raw)[0]
    if value == 0:
        return None
    complement = 1 << 31
    return value + complement if value < 0 else value - complement


def read_monster_db() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Read the fixed-width fields used by the selected Paradox Monster.DB."""
    payload = MONSTER_DB_PATH.read_bytes()
    if len(payload) < 2048:
        raise ValueError("Monster.DB is truncated")
    header_units = struct.unpack(">H", payload[2:4])[0]
    header_size = header_units * 1024 // 4
    block_size = int(payload[5]) * 1024
    field_count = int(payload[33])
    header = payload[:header_size]
    filename = MONSTER_DB_PATH.name.encode("ascii")
    filename_offset = header.find(filename)
    if filename_offset < 0:
        raise ValueError("Monster.DB header does not contain its table name")

    definitions = header[120:]
    names = (
        header[filename_offset + len(filename) :]
        .strip(b"\x00")
        .split(b"\x00")[:field_count]
    )
    fields = [
        {
            "name": names[index].decode("ascii"),
            "type": int(definitions[index * 2]),
            "size": int(definitions[index * 2 + 1]),
        }
        for index in range(field_count)
    ]
    expected_prefix = ["Name", "Race", "RaceImg", "Appr"]
    if [field["name"] for field in fields[:4]] != expected_prefix:
        raise ValueError("Monster.DB field layout does not match the 1.76 schema")
    if any(field["type"] not in {1, 4} for field in fields):
        raise ValueError("Monster.DB contains an unsupported Paradox field type")

    record_size = sum(int(field["size"]) for field in fields)
    rows: list[dict[str, Any]] = []
    previous_record: bytes | None = None
    block_count = (len(payload) - header_size) // block_size
    for block_index in range(block_count):
        block_start = header_size + block_index * block_size
        block_header = payload[block_start : block_start + 6]
        offset = block_start + 6
        block_end = min(len(payload), block_start + block_size)
        while offset + record_size <= block_end:
            record = payload[offset : offset + record_size]
            offset += record_size
            if not record.strip(b"\x00"):
                break
            if record == previous_record:
                continue
            previous_record = record
            row: dict[str, Any] = {}
            cursor = 0
            for field in fields:
                size = int(field["size"])
                raw = record[cursor : cursor + size]
                cursor += size
                if int(field["type"]) == 1:
                    row[str(field["name"])] = raw.rstrip(b"\x00").decode(
                        "gbk", errors="strict"
                    )
                else:
                    row[str(field["name"])] = _decode_paradox_int(raw)
            rows.append(row)
        if len(block_header) == 6 and struct.unpack(">H", block_header[:2])[0] == 0:
            break

    if len(rows) < 380:
        raise ValueError(f"Monster.DB scan returned only {len(rows)} rows")
    return rows, {
        "path": (
            "dev_art_sources/reference/mir2_database_candidates/"
            "mylgd_mir2server_176/Mud2/DB/Monster.DB"
        ),
        "sha256": sha256(MONSTER_DB_PATH),
        "fieldCount": field_count,
        "recordSize": record_size,
        "decodedRowCount": len(rows),
    }


def parse_action_tables() -> dict[str, dict[str, dict[str, int]]]:
    text = ACTOR_PATH.read_bytes().decode("cp936", errors="replace")
    text = re.sub(r"\{.*?\}", "", text, flags=re.DOTALL)
    text = re.sub(r"//[^\r\n]*", "", text)
    tables: dict[str, dict[str, dict[str, int]]] = {}
    table_pattern = re.compile(
        r"\b(MA\d+)\s*:\s*TMonsterAction\s*=\s*\((.*?)\n\s*\);",
        flags=re.DOTALL | re.IGNORECASE,
    )
    action_pattern = re.compile(
        r"\b(Act\w+)\s*:\s*\(\s*start\s*:\s*(\d+)\s*;"
        r"\s*frame\s*:\s*(\d+)\s*;\s*skip\s*:\s*(\d+)\s*;"
        r"\s*ftime\s*:\s*(\d+)",
        flags=re.IGNORECASE,
    )
    for table_match in table_pattern.finditer(text):
        actions: dict[str, dict[str, int]] = {}
        for action_match in action_pattern.finditer(table_match.group(2)):
            start, frames, skip, frame_ms = map(int, action_match.groups()[1:])
            actions[action_match.group(1).casefold()] = {
                "start": start,
                "frames": frames,
                "skip": skip,
                "frameMs": frame_ms,
            }
        if len(actions) == 7:
            tables[table_match.group(1).upper()] = actions
    required_tables = set(RACE_IMAGE_TO_ACTION_TABLE.values())
    missing_tables = sorted(required_tables - set(tables))
    if missing_tables:
        raise ValueError(f"Actor.pas action tables missing: {missing_tables}")
    return tables


def existing_bound_ids(project_monsters: list[dict[str, Any]]) -> set[int]:
    explicit_ids: set[int] = set()
    mapped_names: set[str] = set()
    for path in (COMMON_PATH, UNDEAD_PATH, BOSSES_PATH):
        payload = json.loads(path.read_text(encoding="utf-8"))
        explicit_ids.update(
            int(key) for key in payload.get("runtimeMappingsByMonsterId", {})
        )
        mapped_names.update(str(key) for key in payload.get("runtimeMappings", {}))
        mapped_names.update(str(key) for key in payload.get("legacyAliases", {}))
    result: set[int] = set()
    for monster in project_monsters:
        monster_id = int(monster["monsterId"])
        candidates: list[str] = []
        for candidate in (
            str(monster.get("name", "")),
            str(monster.get("baseName", "")),
            str(monster.get("name", "")).rstrip("0"),
            str(monster.get("baseName", "")).rstrip("0"),
        ):
            if candidate and candidate not in candidates:
                candidates.append(candidate)
        if monster_id in explicit_ids or any(
            candidate in mapped_names for candidate in candidates
        ):
            result.add(monster_id)
    return result


def source_location(appearance: int) -> tuple[Path, int, str]:
    group, position = divmod(appearance, 10)
    library_name = f"Mon{group + 1}.wil"
    primary = PRIMARY_CLIENT_DATA / library_name
    library = primary if primary.exists() else COMPLETE_CLIENT_DATA / library_name
    if not library.exists():
        raise FileNotFoundError(library)

    if group == 0:
        base = position * 280
    elif group == 1:
        base = position * 230
    elif group in {2, 3, 7, 8, 9, 10, 11, 12, 14, 15, 16}:
        base = position * 360
    elif group == 4:
        base = 600 if position == 1 else position * 360
    elif group == 5:
        base = position * 430
    elif group == 6:
        base = position * 440
    elif group == 13:
        base = {0: 0, 1: 360, 2: 440, 3: 550}.get(position, position * 360)
    elif group == 17:
        base = 920 if position == 2 else position * 350
    elif group == 18:
        base = {0: 0, 1: 520, 2: 950}[position]
    elif group == 19:
        base = {0: 0, 1: 370, 2: 810, 3: 1250, 4: 1630, 5: 2010, 6: 2390}[
            position
        ]
    elif group == 20:
        base = {
            0: 0,
            1: 360,
            2: 720,
            3: 1080,
            4: 1440,
            5: 1800,
            6: 2350,
            7: 3060,
        }[position]
    else:
        raise ValueError(f"unregistered Actor.pas GetOffset group: {group}")
    return library, base, library_name


def resolved_action(
    action_name: str,
    table: dict[str, dict[str, int]],
) -> tuple[str, dict[str, int], str]:
    source_name = REQUIRED_ACTIONS[action_name]
    source = table[source_name.casefold()]
    if int(source["frames"]) > 0:
        return source_name, source, ""
    alias_candidates = {
        "walk": ["ActStand"],
        "attack": ["ActCritical", "ActStand"],
        "hit": ["ActStand"],
        "death": ["ActDeath", "ActStand"],
    }.get(action_name, ["ActStand"])
    for candidate in alias_candidates:
        candidate_spec = table[candidate.casefold()]
        if int(candidate_spec["frames"]) > 0:
            return (
                candidate,
                candidate_spec,
                f"{source_name} has zero frames in the original action table",
            )
    raise ValueError(f"no drawable same-profile alias exists for {action_name}")


def build_profile(
    appearance: int,
    race_img: int,
    action_table: str,
    tables: dict[str, dict[str, dict[str, int]]],
) -> dict[str, Any]:
    library, base, library_name = source_location(appearance)
    data, palette, offsets, info = read_library(library)
    table = tables[action_table]
    decoded: dict[str, dict[str, Any]] = {}
    bounds: list[tuple[int, int, int, int]] = []

    for action_name in REQUIRED_ACTIONS:
        source_override = ACTION_SOURCE_OVERRIDES.get((action_table, action_name), "")
        if source_override:
            source_action = source_override
            spec = table[source_override.casefold()]
            alias_reason = (
                f"{action_table} fixed body has no drawable native "
                f"{REQUIRED_ACTIONS[action_name]} sequence"
            )
        else:
            source_action, spec, alias_reason = resolved_action(action_name, table)
        frame_count = int(spec["frames"])
        direction_stride = frame_count + int(spec["skip"])
        repeat_fixed_body = (
            action_table in NON_DIRECTIONAL_ACTION_TABLES
            or (appearance, action_name) in NON_DIRECTIONAL_ACTION_OVERRIDES
        )
        action_frames: dict[tuple[int, int], tuple[Image.Image, dict[str, int], int]] = {}
        missing: list[int] = []
        for direction in range(8):
            for frame in range(frame_count):
                source_direction = 0 if repeat_fixed_body else direction
                index = (
                    base
                    + int(spec["start"])
                    + source_direction * direction_stride
                    + frame
                )
                if index >= len(offsets):
                    missing.append(index)
                    continue
                try:
                    image, meta = decode_sprite(data, offsets[index], palette)
                except (IndexError, ValueError):
                    missing.append(index)
                    continue
                image = image.convert("RGBA")
                alpha_bounds = image.getchannel("A").getbbox()
                if alpha_bounds is None:
                    missing.append(index)
                    continue
                typed_meta = {"x": int(meta["x"]), "y": int(meta["y"])}
                action_frames[(direction, frame)] = (image, typed_meta, index)
                bounds.append(
                    (
                        typed_meta["x"] + alpha_bounds[0],
                        typed_meta["y"] + alpha_bounds[1],
                        typed_meta["x"] + alpha_bounds[2],
                        typed_meta["y"] + alpha_bounds[3],
                    )
                )
        if missing:
            raise ValueError(
                f"appearance={appearance} raceImg={race_img} {action_name} "
                f"has {len(missing)} missing/non-drawable frames: {missing[:8]}"
            )
        decoded[action_name] = {
            "sourceAction": source_action,
            "aliasReason": alias_reason,
            "spec": spec,
            "directionStride": 0 if repeat_fixed_body else direction_stride,
            "directionProjectionReason": (
                "original fixed-body sequence repeated across logical directions"
                if repeat_fixed_body
                else ""
            ),
            "frames": action_frames,
        }

    if not bounds:
        raise ValueError(f"appearance={appearance} contains no drawable action frames")
    # The actor origin/foot point must remain inside every atlas cell even
    # when every decoded sprite happens to have a positive draw offset.
    min_x = min(0, min(row[0] for row in bounds))
    min_y = min(0, min(row[1] for row in bounds))
    max_x = max(0, max(row[2] for row in bounds))
    max_y = max(0, max(row[3] for row in bounds))
    cell_width = ((max_x - min_x + PADDING * 2 + 15) // 16) * 16
    cell_height = ((max_y - min_y + PADDING * 2 + 15) // 16) * 16
    foot_anchor = (-min_x + PADDING, -min_y + PADDING)

    slug = f"appearance_{appearance:03d}_race_{race_img:02d}"
    output_dir = OUTPUT_DIR / slug
    output_dir.mkdir(parents=True, exist_ok=True)
    actions: dict[str, dict[str, Any]] = {}
    for action_name, action in decoded.items():
        spec = action["spec"]
        frame_count = int(spec["frames"])
        atlas = Image.new(
            "RGBA",
            (cell_width * frame_count, cell_height * 8),
            (0, 0, 0, 0),
        )
        for (direction, frame), (image, meta, index) in action["frames"].items():
            isolated = Image.new(
                "RGBA", (cell_width, cell_height), (0, 0, 0, 0)
            )
            isolated.alpha_composite(
                image,
                (foot_anchor[0] + meta["x"], foot_anchor[1] + meta["y"]),
            )
            atlas.alpha_composite(
                isolated, (frame * cell_width, direction * cell_height)
            )
        target = output_dir / f"{slug}_{action_name}.png"
        # WIL libraries are palette based.  Keeping the generated atlas
        # palette based preserves the decoded pixels exactly while avoiding
        # hundreds of unnecessarily large RGBA PNGs.
        palette_atlas = atlas.quantize(
            colors=256,
            method=Image.Quantize.FASTOCTREE,
            dither=Image.Dither.NONE,
        )
        palette_changed_pixels = (
            palette_atlas.getpixel((0, 0)) != 0
            or ImageChops.difference(atlas, palette_atlas.convert("RGBA")).getbbox()
            is not None
        )
        if palette_changed_pixels:
            atlas.save(target, optimize=True, compress_level=9)
            png_mode = "RGBA"
        else:
            palette_atlas.save(target, optimize=True, transparency=0)
            png_mode = "indexed_lossless"
        action_record: dict[str, Any] = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": frame_count,
            "frameMs": int(spec["frameMs"]),
            "sourceAction": action["sourceAction"],
            "sourceStart": base + int(spec["start"]),
            "sourceDirectionStride": int(action["directionStride"]),
            "validatedSourceFrameCount": frame_count * 8,
            "missingFrames": [],
            "confidence": "A",
            "pngStorageMode": png_mode,
        }
        if action["aliasReason"]:
            action_record["actionAliasReason"] = action["aliasReason"]
        if action["directionProjectionReason"]:
            action_record["directionProjectionReason"] = action[
                "directionProjectionReason"
            ]
        actions[action_name] = action_record

    client_library = (
        f"dev_art_sources/{library.relative_to(ROOT / 'dev_art_sources').as_posix()}"
    )
    return {
        "appearance": appearance,
        "raceImg": race_img,
        "actionTable": action_table,
        "mappingConfidence": "B",
        "pixelConfidence": "A",
        "mappingSource": (
            "local 1.76 Monster.DB RaceImg/Appr + original Client/Actor.pas "
            "GetRaceByPM/GetOffset + bundled Mon*.wil pixels"
        ),
        "clientLibrary": client_library,
        "clientLibrarySha256": sha256(library),
        "clientLibraryImageCount": int(info["image_count"]),
        "blockBase": base,
        "frameSize": [cell_width, cell_height],
        "footAnchor": [foot_anchor[0], foot_anchor[1]],
        "directions": 8,
        "actions": actions,
    }


def main() -> None:
    project_monsters = json.loads(MONSTERS_PATH.read_text(encoding="utf-8"))[
        "monsters"
    ]
    already_bound = existing_bound_ids(project_monsters)
    targets = [
        monster
        for monster in project_monsters
        if int(monster["monsterId"]) not in already_bound
    ]
    if len(project_monsters) != 214 or len(targets) != 143:
        raise ValueError(
            f"unexpected binding baseline total={len(project_monsters)} "
            f"alreadyBound={len(already_bound)} targets={len(targets)}"
        )

    database_rows, database_metadata = read_monster_db()
    database_by_name: dict[str, list[dict[str, Any]]] = {}
    for row in database_rows:
        database_by_name.setdefault(str(row["Name"]), []).append(row)
    action_tables = parse_action_tables()

    resolutions: dict[int, dict[str, Any]] = {}
    rejected: list[dict[str, Any]] = []
    for monster in targets:
        monster_id = int(monster["monsterId"])
        requested_names = []
        override = DB_NAME_OVERRIDES.get(monster_id, "")
        for name in (override, str(monster["name"]), str(monster["baseName"])):
            if name and name not in requested_names:
                requested_names.append(name)
        selected_name = next(
            (name for name in requested_names if name in database_by_name), ""
        )
        if not selected_name:
            rejected.append(
                {
                    "monsterId": monster_id,
                    "name": monster["name"],
                    "reason": "Monster.DB name/baseName unresolved",
                }
            )
            continue
        candidates = database_by_name[selected_name]
        bindings = {
            (int(row["Race"]), int(row["RaceImg"]), int(row["Appr"]))
            for row in candidates
            if row.get("Race") is not None
            and row.get("RaceImg") is not None
            and row.get("Appr") is not None
        }
        if len(bindings) != 1:
            rejected.append(
                {
                    "monsterId": monster_id,
                    "name": monster["name"],
                    "reason": f"Monster.DB binding ambiguity: {sorted(bindings)}",
                }
            )
            continue
        service_race, race_img, appearance = next(iter(bindings))
        action_table = RACE_IMAGE_TO_ACTION_TABLE.get(race_img, "")
        if not action_table:
            rejected.append(
                {
                    "monsterId": monster_id,
                    "name": monster["name"],
                    "reason": f"Actor.pas has no RaceImg={race_img} action table",
                }
            )
            continue
        resolutions[monster_id] = {
            "monster": monster,
            "databaseName": selected_name,
            "resolutionStatus": (
                "exact_monster_db_name"
                if selected_name == str(monster["name"])
                else "controlled_name_compatibility"
            ),
            "serviceRace": service_race,
            "raceImg": race_img,
            "appearance": appearance,
            "actionTable": action_table,
        }

    profiles: dict[tuple[int, int, str], dict[str, Any]] = {}
    failed_profiles: set[tuple[int, int, str]] = set()
    for resolution in resolutions.values():
        key = (
            int(resolution["appearance"]),
            int(resolution["raceImg"]),
            str(resolution["actionTable"]),
        )
        if key in profiles or key in failed_profiles:
            continue
        try:
            profiles[key] = build_profile(*key, action_tables)
        except (FileNotFoundError, KeyError, ValueError, IndexError) as error:
            failed_profiles.add(key)
            rejected.append(
                {
                    "appearance": key[0],
                    "raceImg": key[1],
                    "actionTable": key[2],
                    "reason": str(error),
                }
            )

    runtime_by_id: dict[str, dict[str, Any]] = {}
    runtime_by_name: dict[str, dict[str, Any]] = {}
    resolution_counts: dict[str, int] = {}
    for monster_id, resolution in sorted(resolutions.items()):
        key = (
            int(resolution["appearance"]),
            int(resolution["raceImg"]),
            str(resolution["actionTable"]),
        )
        if key not in profiles:
            continue
        record = deepcopy(profiles[key])
        monster = resolution["monster"]
        record.update(
            {
                "monsterId": monster_id,
                "name": str(monster["name"]),
                "baseName": str(monster["baseName"]),
                "monsterIds": [monster_id],
                "databaseName": resolution["databaseName"],
                "resolutionStatus": resolution["resolutionStatus"],
                "serviceRace": int(resolution["serviceRace"]),
            }
        )
        runtime_by_id[str(monster_id)] = record
        runtime_by_name[str(monster["name"])] = record
        status = str(resolution["resolutionStatus"])
        resolution_counts[status] = resolution_counts.get(status, 0) + 1

    if rejected or len(runtime_by_id) != len(targets):
        details = json.dumps(rejected, ensure_ascii=False, indent=2)
        raise ValueError(
            f"complete monster build rejected entries; built={len(runtime_by_id)} "
            f"target={len(targets)}\n{details}"
        )

    payload = {
        "schemaVersion": 1,
        "baseline": "2003 official 1.76 identity set with local 1.76 server/client evidence",
        "identityKey": "monsterId",
        "compatibilityKey": "runtimeMappings/name/baseName",
        "requiredActions": list(REQUIRED_ACTIONS),
        "requiredDirections": 8,
        "mappingPolicy": (
            "Every formal binding requires a local Monster.DB RaceImg/Appr row, "
            "an original Actor.pas action table and offset, and complete drawable "
            "WIL pixels for all emitted frames. Zero-frame native actions use an "
            "explicit same-profile alias and never another monster's artwork."
        ),
        "sources": {
            "projectIdentity": "assets/data/legend176_data.json",
            "monsterDatabase": database_metadata,
            "clientActionRules": {
                "path": (
                    "dev_art_sources/reference/original_gameofmir/Client/Actor.pas"
                ),
                "sha256": sha256(ACTOR_PATH),
            },
            "primaryClientData": (
                "dev_art_sources/reference/mir2_client_raw/Data/Mon*.wil"
            ),
            "completeClientFallback": (
                "dev_art_sources/external/mir2opensource_full/Data/Mon*.wil"
            ),
        },
        "summary": {
            "projectMonsterCount": len(project_monsters),
            "previouslyFormalMonsterCount": len(already_bound),
            "newFormalMonsterCount": len(runtime_by_id),
            "uniqueVisualProfileCount": len(profiles),
            "generatedAtlasCount": len(profiles) * len(REQUIRED_ACTIONS),
            "resolutionStatusCounts": resolution_counts,
            "rejectedCount": len(rejected),
        },
        "runtimeMappingsByMonsterId": runtime_by_id,
        "runtimeMappings": runtime_by_name,
        "rejectedMappings": rejected,
    }
    MANIFEST_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "COMPLETE_MONSTER_CLIENT_ART "
        f"ids={len(runtime_by_id)} profiles={len(profiles)} "
        f"atlases={payload['summary']['generatedAtlasCount']} rejected=0"
    )


if __name__ == "__main__":
    main()
