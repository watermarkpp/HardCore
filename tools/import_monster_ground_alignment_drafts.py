#!/usr/bin/env python3
"""Promote the user's per-monster visual-lab drafts into the formal contract.

The local draft files are immutable evidence.  This importer validates every
saved value, records each source hash, and writes one consolidated auditable
manual contract plus the v5 runtime calibration input.  It never edits the
source drafts and it preserves the two airborne falcon profiles that do not
use a body-to-ground foot alignment.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from copy import deepcopy
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/monster_animation_catalog.json"
CALIBRATION_PATH = (
    ROOT / "assets/data/runtime/monster_ground_contact_calibrations.json"
)
MANUAL_CONTRACT_PATH = (
    ROOT / "assets/data/runtime/monster_ground_alignment_manual_v1.json"
)

DRAFT_CONTRACT = "local.visual_acceptance_lab.monster_ground_alignment_draft.v1"
MANUAL_CONTRACT = "monster.ground_alignment.manual.v1"
CALIBRATION_CONTRACT = "monster.ground_contact.calibration.v5"
USER_SOURCE = "user_visual_acceptance_lab_v1"
PRESERVED_SOURCE = "manual_runtime_composite_review_v4"
EXPECTED_PRESERVED_AIRBORNE_IDS = {97, 98}
EPSILON = 0.0001


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def vector(value: Any, field: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{field} must contain exactly two numbers")
    result = [float(value[0]), float(value[1])]
    if not all(math.isfinite(component) for component in result):
        raise ValueError(f"{field} contains a non-finite value")
    return result


def close(left: list[float], right: list[float]) -> bool:
    return all(
        math.isclose(a, b, rel_tol=0.0, abs_tol=EPSILON)
        for a, b in zip(left, right, strict=True)
    )


def aggregate_hash(rows: list[tuple[str, str]]) -> str:
    payload = "\n".join(
        f"{name}:{digest}" for name, digest in sorted(rows)
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_draft(
    path: Path,
    expected_id: int,
    expected_name: str,
) -> dict[str, Any]:
    draft = load_json(path)
    if draft.get("contractId") != DRAFT_CONTRACT:
        raise ValueError(f"{path.name} draft contract mismatch")
    if int(draft.get("monsterId", -1)) != expected_id:
        raise ValueError(f"{path.name} monsterId mismatch")
    if str(draft.get("monsterName", "")) != expected_name:
        raise ValueError(f"{path.name} monster name mismatch")
    if bool(draft.get("formalRuntimeWritten", True)):
        raise ValueError(f"{path.name} was already marked as formally written")

    runtime_origin = vector(
        draft.get("runtimeVisualOrigin"), f"{path.name}.runtimeVisualOrigin"
    )
    visual_offset = vector(
        draft.get("visualOffset"), f"{path.name}.visualOffset"
    )
    picked_foot = vector(
        draft.get("pickedVisualFootOffset"),
        f"{path.name}.pickedVisualFootOffset",
    )
    final_point = vector(
        draft.get("finalVisualFootPoint"), f"{path.name}.finalVisualFootPoint"
    )
    calculated_final = [
        runtime_origin[index] + visual_offset[index] + picked_foot[index]
        for index in range(2)
    ]
    if not close(calculated_final, final_point) or not close(final_point, [0.0, 0.0]):
        raise ValueError(
            f"{path.name} does not place the final visual foot at the canonical origin"
        )

    recommended = draft.get("recommendedRuntime")
    if not isinstance(recommended, dict):
        raise ValueError(f"{path.name}.recommendedRuntime missing")
    visual_root = vector(
        recommended.get("visualRootOffset"),
        f"{path.name}.recommendedRuntime.visualRootOffset",
    )
    visual_foot = vector(
        recommended.get("visualFootOffset"),
        f"{path.name}.recommendedRuntime.visualFootOffset",
    )
    ring_center = vector(
        recommended.get("ringCenterOffset"),
        f"{path.name}.recommendedRuntime.ringCenterOffset",
    )
    if not close(visual_root, visual_offset):
        raise ValueError(f"{path.name} changed the saved visual root offset")
    if not close(visual_foot, picked_foot):
        raise ValueError(f"{path.name} changed the saved visual foot offset")
    expected_ring = [
        -(runtime_origin[index] + visual_offset[index])
        for index in range(2)
    ]
    if not close(ring_center, expected_ring):
        raise ValueError(f"{path.name} ring center does not resolve to actor origin")

    selection = draft.get("selection")
    if not isinstance(selection, dict):
        raise ValueError(f"{path.name}.selection missing")
    action = str(selection.get("action", ""))
    direction = int(selection.get("direction", -1))
    frame = int(selection.get("frame", -1))
    if action not in {"idle", "walk", "attack", "hit", "death"}:
        raise ValueError(f"{path.name} action is invalid")
    if direction not in range(8) or frame < 0:
        raise ValueError(f"{path.name} direction/frame is invalid")

    return draft


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--draft-root",
        type=Path,
        required=True,
        help="directory containing the user's frozen monster_<id>.json drafts",
    )
    parser.add_argument(
        "--monster-id",
        action="append",
        type=int,
        default=[],
        help=(
            "promote only this monsterId; repeat for multiple explicitly "
            "authorized drafts. Unselected formal entries must remain unchanged"
        ),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    draft_root = args.draft_root.resolve()
    if not draft_root.is_dir():
        raise FileNotFoundError(draft_root)

    catalog = load_json(CATALOG_PATH)
    catalog_rows = {
        int(row["monster_id"]): row for row in catalog.get("monsters", [])
    }
    if len(catalog_rows) != 214:
        raise ValueError("formal animation catalog must contain 214 monsterIds")

    old_calibrations = load_json(CALIBRATION_PATH)
    old_entries = old_calibrations.get("entriesByMonsterId", {})
    if not isinstance(old_entries, dict) or set(old_entries) != {
        str(monster_id) for monster_id in catalog_rows
    }:
        raise ValueError("existing calibration coverage is not exactly 214 IDs")

    source_files = sorted(draft_root.glob("monster_*.json"), key=lambda path: path.name)
    source_by_id: dict[int, Path] = {}
    for path in source_files:
        try:
            monster_id = int(path.stem.removeprefix("monster_"))
        except ValueError as error:
            raise ValueError(f"unexpected draft filename: {path.name}") from error
        if monster_id in source_by_id:
            raise ValueError(f"duplicate draft for monsterId={monster_id}")
        source_by_id[monster_id] = path

    unknown_ids = set(source_by_id) - set(catalog_rows)
    if unknown_ids:
        raise ValueError(f"drafts contain unknown monsterIds: {sorted(unknown_ids)}")
    preserved_ids = set(catalog_rows) - set(source_by_id)
    if preserved_ids != EXPECTED_PRESERVED_AIRBORNE_IDS:
        raise ValueError(
            "manual draft coverage changed; expected only airborne falcons "
            f"{sorted(EXPECTED_PRESERVED_AIRBORNE_IDS)} to be preserved, got "
            f"{sorted(preserved_ids)}"
        )

    requested_ids = set(args.monster_id)
    if not requested_ids:
        requested_ids = set(source_by_id)
    invalid_requested_ids = requested_ids - set(source_by_id)
    if invalid_requested_ids:
        raise ValueError(
            "requested monsterIds do not have grounded/hover drafts: "
            f"{sorted(invalid_requested_ids)}"
        )

    existing_manual = (
        load_json(MANUAL_CONTRACT_PATH)
        if MANUAL_CONTRACT_PATH.exists()
        else {}
    )
    existing_manual_entries = existing_manual.get("entriesByMonsterId", {})
    targeted_update = bool(args.monster_id)
    if targeted_update and (
        not isinstance(existing_manual_entries, dict)
        or set(existing_manual_entries) != {
            str(monster_id) for monster_id in source_by_id
        }
    ):
        raise ValueError(
            "targeted update requires a complete existing manual contract"
        )

    manual_entries: dict[str, Any] = (
        deepcopy(existing_manual_entries) if targeted_update else {}
    )
    calibration_entries: dict[str, Any] = (
        deepcopy(old_entries) if targeted_update else {}
    )
    source_hash_rows = [
        (path.name, sha256(path)) for path in source_files
    ]
    source_hashes = {
        monster_id: sha256(path) for monster_id, path in source_by_id.items()
    }
    if targeted_update:
        for monster_id in sorted(set(source_by_id) - requested_ids):
            expected_hash = str(
                existing_manual_entries[str(monster_id)].get(
                    "sourceDraftSha256", ""
                )
            )
            if source_hashes[monster_id] != expected_hash:
                raise ValueError(
                    f"unselected monsterId={monster_id} draft changed; "
                    "refusing to touch it during a targeted update"
                )

    for monster_id in sorted(requested_ids):
        key = str(monster_id)
        row = catalog_rows[monster_id]
        previous = deepcopy(old_entries[key])
        path = source_by_id[monster_id]
        draft = validate_draft(path, monster_id, str(row["name"]))
        digest = source_hashes[monster_id]
        recommended = draft["recommendedRuntime"]
        selection = draft["selection"]
        evidence = {
            "contractId": DRAFT_CONTRACT,
            "sourceDraftFile": path.name,
            "sourceDraftSha256": digest,
            "savedAt": str(draft["savedAt"]),
            "selection": deepcopy(selection),
        }
        manual_entries[key] = {
            "monsterId": monster_id,
            "monsterName": str(row["name"]),
            **evidence,
            "runtimeVisualOrigin": deepcopy(draft["runtimeVisualOrigin"]),
            "visualRootOffset": deepcopy(recommended["visualRootOffset"]),
            "visualFootOffset": deepcopy(recommended["visualFootOffset"]),
            "ringCenterOffset": deepcopy(recommended["ringCenterOffset"]),
            "finalVisualFootPoint": deepcopy(draft["finalVisualFootPoint"]),
            "physicsFootprintRadii": deepcopy(draft["physicsFootprintRadii"]),
            "formalSnapshot": deepcopy(draft["formalSnapshot"]),
            "sourceEvidence": deepcopy(draft["sourceEvidence"]),
        }

        previous["visualRootOffset"] = deepcopy(recommended["visualRootOffset"])
        previous["visualFootOffset"] = deepcopy(recommended["visualFootOffset"])
        previous["ringCenterOffset"] = deepcopy(recommended["ringCenterOffset"])
        previous["calibrationSource"] = USER_SOURCE
        previous["manualAlignmentEvidence"] = evidence
        previous_review = previous.get("review", {})
        previous["review"] = {
            "status": "approved",
            "archetype": str(previous_review.get("archetype", "user_aligned")),
            "poses": [
                "%s:direction%d:frame%d"
                % (
                    str(selection["action"]),
                    int(selection["direction"]),
                    int(selection["frame"]),
                )
            ],
            "decision": (
                f"monsterId={monster_id} user-aligned in the visual acceptance "
                "lab; the saved body foot and visual root resolve exactly to the "
                "canonical actor/map/physics origin."
            ),
        }
        calibration_entries[key] = previous

    if not targeted_update:
        for monster_id in sorted(preserved_ids):
            key = str(monster_id)
            previous = deepcopy(old_entries[key])
            if previous.get("projectionStrategy") != "flying":
                raise ValueError(
                    f"preserved monsterId={monster_id} is not an airborne projection"
                )
            previous["visualRootOffset"] = [0.0, 0.0]
            previous["manualAlignmentEvidence"] = {
                "status": "preserved_airborne_projection",
                "reason": (
                    "The flying body is intentionally separated from the ground "
                    "ring and does not use a grounded body-foot alignment draft."
                ),
            }
            calibration_entries[key] = previous

    aggregate = aggregate_hash(source_hash_rows)
    manual_contract = {
        "schemaVersion": 1,
        "contract": MANUAL_CONTRACT,
        "sourceContract": DRAFT_CONTRACT,
        "identityKey": "monsterId",
        "sourceDraftRootRole": (
            "User-owned local calibration output; imported as immutable evidence."
        ),
        "sourceAggregateSha256": aggregate,
        "summary": {
            "catalogMonsterCount": len(catalog_rows),
            "userDraftCount": len(manual_entries),
            "preservedAirborneCount": len(preserved_ids),
            "preservedAirborneMonsterIds": sorted(preserved_ids),
            "canonicalFinalFootPoint": [0.0, 0.0],
        },
        "entriesByMonsterId": manual_entries,
    }
    calibration_contract = {
        "schemaVersion": 5,
        "contract": CALIBRATION_CONTRACT,
        "identityKey": "monsterId",
        "manualAlignmentContract": MANUAL_CONTRACT,
        "manualAlignmentAggregateSha256": aggregate,
        "policy": (
            "Each grounded/hover monster uses the exact user-saved visual root "
            "and body-foot offsets. The two airborne falcons retain the prior "
            "reviewed separation between flying body and ground projection."
        ),
        "entriesByMonsterId": calibration_entries,
    }
    manual_serialized = (
        json.dumps(manual_contract, ensure_ascii=False, indent=2) + "\n"
    )
    calibration_serialized = (
        json.dumps(calibration_contract, ensure_ascii=False, indent=2) + "\n"
    )
    if args.check:
        if (
            not MANUAL_CONTRACT_PATH.exists()
            or MANUAL_CONTRACT_PATH.read_text(encoding="utf-8")
            != manual_serialized
            or CALIBRATION_PATH.read_text(encoding="utf-8")
            != calibration_serialized
        ):
            raise SystemExit(
                "formal monster alignment data is stale; rerun this importer"
            )
    else:
        MANUAL_CONTRACT_PATH.write_text(
            manual_serialized,
            encoding="utf-8",
        )
        CALIBRATION_PATH.write_text(
            calibration_serialized,
            encoding="utf-8",
        )
    print(
        "MONSTER_GROUND_ALIGNMENT_IMPORT_PASS "
        f"drafts={len(manual_entries)} preserved_airborne={len(preserved_ids)} "
        f"updated={','.join(str(value) for value in sorted(requested_ids))} "
        f"aggregate_sha256={aggregate}"
    )


if __name__ == "__main__":
    main()
