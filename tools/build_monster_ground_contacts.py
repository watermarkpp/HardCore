from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "assets" / "data"
ANIMATION_CATALOG = DATA_DIR / "runtime" / "monster_animation_catalog.json"
OUTPUT_PATH = DATA_DIR / "monster_ground_contacts.json"
MANIFEST_PATHS = (
    DATA_DIR / "complete_monster_client_art_sources.json",
    DATA_DIR / "classic_boss_client_art_sources.json",
    DATA_DIR / "bich_common_client_art_sources.json",
    DATA_DIR / "bich_undead_client_art_sources.json",
)
ACTION_NAMES = ("idle", "walk", "attack", "hit", "death")
ALPHA_THRESHOLD = 16


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_mapping(
    row: dict[str, Any], manifests: list[dict[str, Any]]
) -> tuple[dict[str, Any], str]:
    monster_key = str(int(row["monster_id"]))
    lookup_names: list[str] = []
    for field in ("resource_lookup", "name", "base_name"):
        value = str(row.get(field, ""))
        if value and value not in lookup_names:
            lookup_names.append(value)

    for manifest_path, manifest in zip(MANIFEST_PATHS, manifests):
        mapping: Any = manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key)
        if isinstance(mapping, str):
            mapping = manifest.get("runtimeMappings", {}).get(mapping)
        if isinstance(mapping, dict) and mapping:
            return mapping, manifest_path.name

        aliases = manifest.get("legacyAliases", {})
        for lookup_name in lookup_names:
            canonical_name = (
                str(aliases.get(lookup_name, lookup_name))
                if isinstance(aliases, dict)
                else lookup_name
            )
            mapping = manifest.get("runtimeMappings", {}).get(canonical_name)
            if isinstance(mapping, dict) and mapping:
                return mapping, manifest_path.name

    raise KeyError(
        f"monsterId={monster_key} has no formal client-art runtime mapping"
    )


def source_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"expected res:// path, got {resource_path!r}")
    return ROOT / resource_path.removeprefix("res://")


def rounded_median(values: list[float]) -> int:
    return int(round(statistics.median(values)))


def action_direction_contacts(
    mapping: dict[str, Any], action_name: str
) -> list[list[int]]:
    frame_width, frame_height = (int(value) for value in mapping["frameSize"])
    foot_x, foot_y = (int(value) for value in mapping["footAnchor"])
    action = mapping["actions"][action_name]
    frame_count = int(action["framesPerDirection"])
    atlas_path = source_path(str(action["path"]))
    atlas = Image.open(atlas_path).convert("RGBA")
    expected_size = (frame_width * frame_count, frame_height * 8)
    if atlas.size != expected_size:
        raise ValueError(
            f"{atlas_path.relative_to(ROOT)} size={atlas.size}, expected={expected_size}"
        )
    alpha = atlas.getchannel("A")
    result: list[list[int]] = []
    for direction in range(8):
        frame_x_offsets: list[float] = []
        frame_y_offsets: list[float] = []
        for frame in range(frame_count):
            left = frame * frame_width
            top = direction * frame_height
            frame_alpha = alpha.crop(
                (left, top, left + frame_width, top + frame_height)
            )
            bounds = frame_alpha.getbbox()
            if bounds is None:
                raise ValueError(
                    f"{atlas_path.relative_to(ROOT)} action={action_name} "
                    f"direction={direction} frame={frame} is transparent"
                )

            body_height = bounds[3] - bounds[1]
            band_height = max(3, min(10, body_height // 10))
            contact_band_top = max(bounds[1], bounds[3] - band_height)
            pixels = frame_alpha.load()
            contact_pixels_x: list[int] = []
            for y in range(contact_band_top, bounds[3]):
                for x in range(bounds[0], bounds[2]):
                    if pixels[x, y] > ALPHA_THRESHOLD:
                        contact_pixels_x.append(x)
            contact_x = (
                statistics.median(contact_pixels_x)
                if contact_pixels_x
                else (bounds[0] + bounds[2] - 1) * 0.5
            )
            contact_y = bounds[3] - 1
            frame_x_offsets.append(contact_x - foot_x)
            frame_y_offsets.append(contact_y - foot_y)
        result.append(
            [rounded_median(frame_x_offsets), rounded_median(frame_y_offsets)]
        )
    return result


def build_catalog() -> dict[str, Any]:
    animation_catalog = load_json(ANIMATION_CATALOG)
    manifests = [load_json(path) for path in MANIFEST_PATHS]
    profile_by_id: dict[str, str] = {}
    profiles: dict[str, Any] = {}
    legacy_name_to_id: dict[str, int] = {}
    profile_id_by_key: dict[str, str] = {}

    for row in animation_catalog.get("monsters", []):
        monster_id = int(row["monster_id"])
        monster_key = str(monster_id)
        mapping, manifest_name = resolve_mapping(row, manifests)
        profile_key = json.dumps(
            {
                "frameSize": mapping["frameSize"],
                "footAnchor": mapping["footAnchor"],
                "actions": {
                    action_name: {
                        "path": mapping["actions"][action_name]["path"],
                        "framesPerDirection": mapping["actions"][action_name][
                            "framesPerDirection"
                        ],
                    }
                    for action_name in ACTION_NAMES
                },
            },
            sort_keys=True,
            ensure_ascii=False,
        )
        if profile_key not in profile_id_by_key:
            profile_id = f"profile_{len(profile_id_by_key):03d}"
            profile_id_by_key[profile_key] = profile_id
            profiles[profile_id] = {
                "sourceManifest": manifest_name,
                "sourceLookup": str(
                    row.get("resource_lookup", row.get("name", ""))
                ),
                "offsetsByActionDirection": {
                    action_name: action_direction_contacts(mapping, action_name)
                    for action_name in ACTION_NAMES
                },
            }
        profile_by_id[monster_key] = profile_id_by_key[profile_key]
        for field in ("name", "base_name", "resource_lookup"):
            legacy_name = str(row.get(field, ""))
            if legacy_name and legacy_name not in legacy_name_to_id:
                legacy_name_to_id[legacy_name] = monster_id

    return {
        "schemaVersion": 1,
        "identityKey": "monsterId",
        "compatibilityKey": "legacyNameToMonsterId",
        "coordinateSpace": (
            "offset from the client WIL actor origin/footAnchor to the median "
            "visible ground-contact band for each action and direction"
        ),
        "policy": {
            "actions": list(ACTION_NAMES),
            "directions": 8,
            "alphaThreshold": ALPHA_THRESHOLD,
            "runtimeRule": (
                "monsterId first; legacy name only when stable identity is absent"
            ),
        },
        "summary": {
            "monsterCount": len(profile_by_id),
            "uniqueVisualProfileCount": len(profiles),
        },
        "groundContactProfileByMonsterId": profile_by_id,
        "groundContactProfiles": profiles,
        "legacyNameToMonsterId": legacy_name_to_id,
    }


def serialized(catalog: dict[str, Any]) -> str:
    return json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build stable monster ground-contact offsets from final atlases."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the committed catalog differs from freshly derived data.",
    )
    args = parser.parse_args()
    content = serialized(build_catalog())
    if args.check:
        if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != content:
            raise SystemExit(
                "monster_ground_contacts.json is stale; run this tool without --check"
            )
        print("MONSTER_GROUND_CONTACTS_CHECK_PASS")
        return
    OUTPUT_PATH.write_text(content, encoding="utf-8")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
