from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets" / "data"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ACTIONS = {
    "idle": 4,
    "walk": 6,
    "attack": 6,
    "cast": 6,
    "hit": 3,
    "death": 4,
}
HELMET_ACTIONS = ACTIONS
SOURCE_MANIFEST = DATA / "equipment_male_world_helmet.json"
OVERRIDE_NAME = "equipment_helmet_visual_v2_overrides.json"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, payload: dict) -> None:
    (DATA / name).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def rounded_point(values: list[float]) -> list[int]:
    # Match Godot roundi for these positive cell coordinates (half away from 0).
    return [
        int(math.floor(float(values[0]) + 0.5)),
        int(math.floor(float(values[1]) + 0.5)),
    ]


def identity_frames(
    manifest: dict, identity_id: str
) -> dict[str, dict[str, list[dict]]]:
    identity = manifest["visualIdentities"][identity_id]
    result: dict[str, dict[str, list[dict]]] = {}
    for action, frame_count in HELMET_ACTIONS.items():
        by_direction = {direction: [] for direction in DIRECTIONS}
        for frame in identity["actions"][action]["frames"]:
            direction = frame["direction"]
            if direction not in by_direction:
                continue
            by_direction[direction].append(frame)
        for direction in DIRECTIONS:
            by_direction[direction].sort(key=lambda frame: int(frame["frame"]))
            assert len(by_direction[direction]) == frame_count
        result[action] = by_direction
    return result


def source_frames() -> dict[str, dict[str, list[dict]]]:
    return identity_frames(read_json(SOURCE_MANIFEST), "elf")


def build_head_sockets(frames: dict[str, dict[str, list[dict]]]) -> dict:
    manifest = read_json(SOURCE_MANIFEST)
    manifest_sha = sha256(SOURCE_MANIFEST)
    hair_library = manifest["sourceEvidence"]["hairLibrary"]
    hair_library_sha = manifest["sourceEvidence"]["hairLibraryFileSha256"]
    actions: dict[str, dict] = {}
    max_jump_by_action: dict[str, int] = {}
    for action, frame_count in ACTIONS.items():
        by_direction: dict[str, list[dict]] = {}
        maximum_jump = 0
        for direction in DIRECTIONS:
            records: list[dict] = []
            previous: list[int] | None = None
            for frame in frames[action][direction]:
                centroid = frame["hairAnchorCentroid"]
                socket = rounded_point(centroid)
                if previous is not None:
                    maximum_jump = max(
                        maximum_jump,
                        abs(socket[0] - previous[0]) + abs(socket[1] - previous[1]),
                    )
                previous = socket
                hair_frame = frame["hairFrame"]
                records.append(
                    {
                        "frame_index": int(frame["frame"]),
                        "head_socket": socket,
                        "coordinateSpace": "body_cell_integer_pixels",
                        "status": "calibrated_primary_hair_same_frame",
                        "evidence": {
                            "derivation": "round_same_frame_hair_alpha_centroid",
                            "sourceManifest": "res://assets/data/equipment_male_world_helmet.json",
                            "sourceManifestSha256": manifest_sha,
                            "hairLibrary": hair_library,
                            "hairLibrarySha256": hair_library_sha,
                            "hairSourceIndex": int(hair_frame["sourceIndex"]),
                            "hairHot": hair_frame["hot"],
                            "hairSourceSize": hair_frame["sourceSize"],
                            "hairSourceRgbaSha256": hair_frame["sourceRgbaSha256"],
                            "hairAnchorCentroid": centroid,
                        },
                    }
                )
            by_direction[direction] = records
        max_jump_by_action[action] = maximum_jump
        actions[action] = {
            "frameCount": frame_count,
            "directions": by_direction,
        }
    return {
        "schemaVersion": 2,
        "contractId": "player.visual.head_socket.v1",
        "canonicalDirections": DIRECTIONS,
        "coordinatePolicy": {
            "integerOnly": True,
            "perActionDirectionFrame": True,
            "globalHelmetOffsetForbidden": True,
            "bodyFootPointChanged": False,
            "bodyDirectionRowsChanged": False,
            "bodyShadowChanged": False,
            "maxAdjacentJumpByAction": max_jump_by_action,
        },
        "source": {
            "lane": "player_world_visuals",
            "tier": "primary",
            "distribution": "research.mir2_client_raw",
            "path": hair_library,
            "fileSha256": hair_library_sha,
            "derivationTool": "res://tools/analyze_client_helmet_parameters.py",
            "parameterBaseline": (
                "res://outputs/resource_catalog/black_iron_helmet/"
                "client_helmet_parameter_baseline.json"
            ),
            "formalEvidenceManifest": (
                "res://assets/data/equipment_male_world_helmet.json"
            ),
            "formalEvidenceManifestSha256": manifest_sha,
            "evidence": (
                "Every socket is the rounded alpha centroid of the same Hair.wil "
                "male appearance/action/direction/frame recorded by the primary "
                "client parameter analysis."
            ),
        },
        "playerVisuals": {
            "player.male.cloth_002": {
                "player_visual_id": "player.male.cloth_002",
                "gender": "male",
                "dressItemId": 116,
                "dressName": "布衣(男)",
                "dressFeature": 2,
                "actions": actions,
            }
        },
    }


def pivots_for_source_direction(
    frames: dict[str, dict[str, list[dict]]], source_direction: str
) -> dict[str, list[list[int]]]:
    return {
        action: [
            rounded_point(frame["hairAnchorCentroid"])
            for frame in frames[action][source_direction]
        ]
        for action in HELMET_ACTIONS
    }


def calibration_overlays(direction: str) -> dict:
    # Rectangles are integer offsets from the current body head socket. They are
    # calibration evidence overlays, not player pixels and never ship as art.
    rear = direction in ["N", "NE", "NW"]
    return {
        "face_mask": {
            "shape": "rect",
            "offset": [-4, -1],
            "size": [8, 10],
            "rearDirection": rear,
        },
        "hair_mask": {
            "shape": "rect",
            "offset": [-8, -9],
            "size": [16, 10],
        },
    }


def direction_record(
    direction: str,
    source_row: int,
    action_paths: dict[str, str],
    pivot_by_action_frame: dict[str, list[list[int]]],
    face_policy: str,
    hair_policy: str,
    opening_visibility: str,
    locked: bool,
) -> dict:
    return {
        "texture": action_paths["idle"],
        "texturesByAction": action_paths,
        "source_direction": direction,
        "source_row": source_row,
        "source_slot_id": f"slot_{source_row}",
        "pivot": pivot_by_action_frame["idle"][0],
        "pivotByActionFrame": pivot_by_action_frame,
        "nudge": [0, 0],
        "face_policy": face_policy,
        "hair_policy": hair_policy,
        "openingVisibility": opening_visibility,
        "status": "valid",
        "locked": locked,
        "flip_h": False,
        "runtime_scale": [1, 1],
        "calibrationOverlays": calibration_overlays(direction),
        "layers": {
            "helmet_back": None,
            "helmet_front": action_paths,
            "head_occlusion_mask": None,
        },
    }


def build_visual_contract(frames: dict[str, dict[str, list[dict]]]) -> dict:
    manifest = read_json(SOURCE_MANIFEST)
    elf_paths = {
        action: f"res://assets/art/items/client/world_wear/helmet/male/elf_helmet_{action}.png"
        for action in HELMET_ACTIONS
    }
    # User-calibrated source semantics. Row 3 is the only unused duplicate
    # slot and is replaced at bake time by the explicitly authorized,
    # pivot-aligned horizontal mirror of the accepted NE source in row 5.
    elf_source_map = {
        "N": 4, "NE": 5, "E": 6, "SE": 1,
        "S": 0, "SW": 7, "W": 2, "NW": 3,
    }
    # Preserve the existing local-pivot records while the item 146 pilot is
    # being calibrated. Runtime direction selection is supplied by overrides.
    elf_pivot_compat_map = {
        "N": 4, "NE": 3, "E": 2, "SE": 1,
        "S": 0, "SW": 7, "W": 6, "NW": 5,
    }
    opening = {
        "N": "none",
        "NE": "partial",
        "E": "partial",
        "SE": "partial",
        "S": "full",
        "SW": "partial",
        "W": "partial",
        "NW": "partial",
    }
    elf_directions: dict[str, dict] = {}
    for direction in DIRECTIONS:
        source_direction = DIRECTIONS[elf_pivot_compat_map[direction]]
        elf_directions[direction] = direction_record(
            direction,
            elf_pivot_compat_map[direction],
            elf_paths,
            pivots_for_source_direction(frames, source_direction),
            "open_crown",
            "keep",
            opening[direction],
            True,
        )

    item_specs = {
        int(item_id): item
        for item_id, item in manifest["itemsById"].items()
    }
    asset_id_by_identity = {
        "elf": "elf_146",
        "black_iron": "black_iron_golden_151",
    }
    item_visual_asset_refs: dict[str, str] = {}
    grouped_item_ids: dict[str, list[int]] = {}
    for item_id, item in sorted(item_specs.items()):
        identity_id = item["identityId"]
        asset_id = asset_id_by_identity.get(identity_id, identity_id)
        item_visual_asset_refs[str(item_id)] = asset_id
        grouped_item_ids.setdefault(asset_id, []).append(item_id)

    visual_assets: dict[str, dict] = {
        "elf_146": {
            "visual_asset_id": "elf_146",
            "pilotItemId": 146,
            "calibrationItemId": 146,
            "calibrationScope": "all_helmet_editor",
            "player_visual_id": "player.male.cloth_002",
            "source": {
                "lane": "helmet_world_visuals",
                "tier": "primary",
                "distribution": "research.mir2_client_raw",
                "path": (
                    "res://assets/art/items/client/world_wear/helmet/male/"
                    "source/elf_helmet_8dir.png"
                ),
                "acceptanceEvidence": (
                    "res://assets/art/items/client/world_wear/helmet/male/"
                    "acceptance/elf_direction_mapping.png"
                ),
                "poseEvidence": "res://assets/data/equipment_male_world_helmet.json",
            },
            "source_direction_map": elf_source_map,
            "bakedSourceOverrides": {
                "recipeId": "elf_146.user_authorized_nw_mirror.v1",
                "runtimeFlip": False,
                "rows": {
                    "3": {
                        "direction": "NW",
                        "sourceRow": 5,
                        "sourceDirection": "NE",
                        "operation": "horizontal_mirror",
                        "alignment": "source_pivot_to_target_pivot",
                        "authorization": "user_explicit_2026-07-26",
                    }
                },
            },
            "directions": elf_directions,
        },
    }

    for asset_id, item_ids in grouped_item_ids.items():
        if asset_id == "elf_146":
            continue
        identity_id = item_specs[item_ids[0]]["identityId"]
        identity = manifest["visualIdentities"][identity_id]
        identity_action_paths = {
            action: identity["actions"][action]["path"]
            for action in HELMET_ACTIONS
        }
        source_order = identity["sourceSlotDirectionOrder"]
        assert sorted(source_order) == sorted(DIRECTIONS)
        source_map = {
            direction: source_order.index(direction)
            for direction in DIRECTIONS
        }
        identity_frame_map = identity_frames(manifest, identity_id)
        directions: dict[str, dict] = {}
        for direction in DIRECTIONS:
            record = direction_record(
                direction,
                source_map[direction],
                identity_action_paths,
                pivots_for_source_direction(identity_frame_map, direction),
                "half_open" if identity_id == "black_iron" else "open_crown",
                "hide" if identity_id == "black_iron" else "keep",
                opening[direction],
                False,
            )
            record["status"] = "unassigned"
            if identity_id == "black_iron":
                # The user assigns opaque source slots by sight.
                record.pop("source_direction")
            directions[direction] = record
        asset = {
            "visual_asset_id": asset_id,
            "itemIds": item_ids,
            "calibrationItemId": item_ids[0],
            "player_visual_id": "player.male.cloth_002",
            "editableSourceSlots": True,
            "sourceSlotSemantics": (
                "unknown_user_assigned"
                if identity_id == "black_iron"
                else "formal_manifest_direction_order"
            ),
            "sourceSlots": {f"slot_{row}": row for row in range(8)},
            "source": {
                "lane": "helmet_world_visuals",
                "tier": "primary",
                "distribution": "research.mir2_client_raw",
                "identityId": identity_id,
                "stateItemIndex": int(identity["sourceIndex"]),
                "manifest": "res://assets/data/equipment_male_world_helmet.json",
                "sourceSlotDirectionOrder": source_order,
                "actions": {
                    action: {
                        "path": path,
                        "sha256": sha256(ROOT / path.removeprefix("res://")),
                    }
                    for action, path in identity_action_paths.items()
                },
                "pixelPolicy": "immutable_primary_source_runtime_atlas",
            },
            "directions": directions,
        }
        if identity_id == "bronze_magic":
            asset["source"].update({
                "calibrationSourceSheet": identity["concept"],
                "calibrationSourceSheetSha256": identity["conceptFileSha256"],
                "calibrationSourceGrid": identity["sourceGrid"],
                "calibrationSourceSlotDirectionOrder": source_order,
                "calibrationPreparedSourceRows": identity.get(
                    "calibrationPreparedSourceRows", []
                ),
                "calibrationSourceMatte": "green_chroma_key_despill_v2",
                "calibrationPreviewPolicy": (
                    "single_authored_source_for_buttons_previews_and_bakes"
                ),
            })
        if identity_id != "black_iron":
            asset["source_direction_map"] = source_map
        else:
            asset.update({
                "itemId": 151,
                "readOnlyGoldenReference": False,
                "historicalGoldenReferenceSuperseded": (
                    "res://assets/data/equipment_helmet_151_golden_reference.json"
                ),
                "bakedSourceOverrides": {
                    "recipeId": (
                        "black_iron_151.user_authorized_nw_from_ne_mirror.v2"
                    ),
                    "runtimeFlip": False,
                    "rows": {
                        "5": {
                            "direction": "NW",
                            "sourceRow": 1,
                            "sourceDirection": "NE",
                            "operation": "horizontal_mirror",
                            "alignment": "source_pivot_to_target_pivot",
                            "authorization": "user_explicit_2026-07-26",
                        },
                    },
                },
            })
        visual_assets[asset_id] = asset

    calibration_items = []
    for asset_id, item_ids in grouped_item_ids.items():
        names = [item_specs[item_id]["itemName"] for item_id in item_ids]
        calibration_items.append({
            "calibrationItemId": item_ids[0],
            "itemIds": item_ids,
            "displayName": " / ".join(names),
            "visualAssetId": asset_id,
        })
    calibration_items.sort(key=lambda item: int(item["calibrationItemId"]))

    return {
        "schemaVersion": 3,
        "contractId": "equipment.world_helmet.player_visual_v2",
        "canonicalDirections": DIRECTIONS,
        "runtimeFormula": (
            "final_position = body_head_socket - "
            "source_helmet_local_pivot(action,source_row,frame) + integer_nudge"
        ),
        "renderPipeline": [
            "helmet_back",
            "body_and_original_face",
            "helmet_front",
            "head_occlusion_mask",
        ],
        "maskComposition": {
            "semantic": "destination_alpha *= (1.0 - mask_alpha)",
            "execution": "CPU current-cell composition before helmet_front",
            "ordinarySpriteOverlayForbidden": True,
        },
        "policies": {
            "facePolicyValues": ["open_crown", "half_open", "closed"],
            "hairPolicyValues": ["keep", "clip", "hide"],
            "statusValues": [
                "unassigned",
                "valid",
                "mapping_error",
                "art_error",
                "anchor_error",
                "mask_error",
                "locked",
            ],
            "integerCoordinatesOnly": True,
            "textureFilter": "nearest",
            "runtimeScalingForbidden": True,
            "rotationForbidden": True,
            "horizontalFlipForbidden": True,
            "bakedPlayerFaceForbidden": True,
        },
        "headSocketDatabase": "res://assets/data/player_head_socket_db.json",
        "calibrationOverride": f"res://assets/data/{OVERRIDE_NAME}",
        "calibrationItems": calibration_items,
        "itemVisualAssetRefs": item_visual_asset_refs,
        "visualAssets": visual_assets,
        "sharedVisualAssets": {
            "bronze_magic": {
                "visual_asset_id": "bronze_magic",
                "itemIds": [147, 148],
                "calibrationItemId": 147,
                "singleCalibrationRecordRequired": True,
                "status": "loaded_in_calibration_tool",
            },
        },
    }


def build_overrides() -> dict:
    return {
        "schemaVersion": 1,
        "contractId": "equipment.world_helmet.player_visual_v2.overrides.v1",
        "runtimeReadable": True,
        "itemOverrides": {},
        "visualAssetOverrides": {},
    }


def build_golden() -> dict:
    actions = {
        "idle": {
            "frames": 32,
            "compositeRgbaSequenceSha256": "02a245cce66274fa34946ae403b8b3eb838f2aaece1dc13d8a3e1000a2291953",
            "bodyAtlasSha256": "bbb1a24ff2cabfec586721221e5fae8ad298816b3ffdc329ff0effbc5692a84",
            "helmetAtlasSha256": "8a78c841d88b47946ef6f559f731cbbe9c08313e11c7ef48e5457d12d839e052",
        },
        "walk": {
            "frames": 48,
            "compositeRgbaSequenceSha256": "39d32f754125ca6f534476de2145062a322ddf21a93facb0b61d6d6b5e5087d5",
            "bodyAtlasSha256": "e2f12338fe19987c476de8601663ce89d6f99805dd5c1310e3a75c3aca800bbd",
            "helmetAtlasSha256": "8b32472b1dd8ebe2723b34cb1fd2d5d73d151891c7372dfc4f93a4f5d3ceb4a6",
        },
        "attack": {
            "frames": 48,
            "compositeRgbaSequenceSha256": "5635f59deb313bffcf6e6aac389dd6d48a7916778dec95c78a2ef7692c01989e",
            "bodyAtlasSha256": "e990f918d200e446c0b690d354bc233e84b5a8e15b3b5d630b9c5fa64035ebf4",
            "helmetAtlasSha256": "427855f0a799fd8cc442071255861e6a22456532facb3801e9774c4236f069ca",
        },
        "hit": {
            "frames": 24,
            "compositeRgbaSequenceSha256": "c6688d0e7be4f803f815447f79a9ecec8794e082b40852b9c1b4dd193dccbd1c",
            "bodyAtlasSha256": "ecfda8e1fd6fa2764baa0382ed925105b16a5ceb1c787e1cc36d002bef7695f3",
            "helmetAtlasSha256": "605d12ebd303bbc9be5ee3da645145ad53f9077d28e0fff83ac5d95970575cf7",
        },
        "death": {
            "frames": 32,
            "compositeRgbaSequenceSha256": "07abb524f79d8757309bf22ec8a4bb9f9c95ef3cbe6fa312942561d258d39c54",
            "bodyAtlasSha256": "b101305b65c447e871c6f9b0f06e48df095ac0a251f8a5566908a93a098a6206",
            "helmetAtlasSha256": "f99492398eadb01b1b7e50f1f7c5bb347b42994054a165e3318922fd5599beec",
        },
    }
    return {
        "schemaVersion": 3,
        "contractId": "equipment.world_helmet.historical_baseline.151.v1",
        "itemId": 151,
        "itemName": "黑铁头盔",
        "visualAssetId": "black_iron_golden_151",
        "readOnly": False,
        "superseded": True,
        "runtimeValidationGate": False,
        "supersededReason": (
            "User rejected the historical direction mapping and placement; "
            "only original source atlas hashes remain immutable evidence."
        ),
        "capturedBeforePlayerVisualHelmetV2": True,
        "baselineCommit": "49fa8d38a0f4d3848e16a73533d4f257f37ffca8",
        "stateItemSource": {
            "library": "StateItem.wil",
            "index": 344,
            "originalSize": [28, 32],
        },
        "fixture": {
            "playerVisualId": "player.male.cloth_002",
            "gender": "male",
            "dress": "布衣(男)",
            "actions": list(ACTIONS),
            "canonicalDirections": DIRECTIONS,
        },
        "historicalPixelDiffTolerance": 0,
        "compatibilityPivotPolicy": (
            "Per-frame pivot equals the primary same-frame head socket, preserving "
            "the immutable full-cell atlas at zero final delta."
        ),
        "directionRemapChanged": "user_editable_override",
        "assetPixelsChanged": False,
        "actions": actions,
    }


def build_audit() -> dict:
    return {
        "schemaVersion": 2,
        "contractId": "equipment.world_helmet.player_visual_v2.audit.v1",
        "baselineCommit": "49fa8d38a0f4d3848e16a73533d4f257f37ffca8",
        "findings": [
            {"id": 1, "topic": "player_direction_order", "result": DIRECTIONS, "status": "explicit"},
            {
                "id": 2,
                "topic": "helmet_source_direction_order",
                "result": (
                    "Elf concept slot 0 is visibly front and slot 4 back; explicit "
                    "user-calibrated remap is N..NW = 4,5,6,1,0,7,2,3; "
                    "row 3 NW is a user-authorized baked mirror of row 5 NE."
                ),
                "status": "user_corrected_and_baked",
            },
            {
                "id": 3,
                "topic": "head_socket_granularity",
                "result": (
                    "232 sockets derived independently from primary same-frame "
                    "Hair.wil centroids, including cast/attack/hit/death movement."
                ),
                "status": "implemented_from_primary_evidence",
            },
            {
                "id": 4,
                "topic": "mask_semantics",
                "result": (
                    "Optional masks execute destination alpha subtraction on the "
                    "current body cell before helmet-front composition."
                ),
                "status": "cpu_composition_contract",
            },
            {
                "id": 5,
                "topic": "historical_golden_151",
                "result": (
                    "The user rejected the historical mapping/placement baseline. "
                    "StateItem 344 and all six original atlases remain pixel-frozen, "
                    "while target-to-source-slot mapping is user editable."
                ),
                "status": "superseded_not_a_runtime_gate",
            },
        ],
    }


def main() -> None:
    frames = source_frames()
    write_json("player_head_socket_db.json", build_head_sockets(frames))
    write_json("equipment_helmet_visual_v2.json", build_visual_contract(frames))
    override_path = DATA / OVERRIDE_NAME
    if not override_path.exists():
        write_json(OVERRIDE_NAME, build_overrides())
    write_json("equipment_helmet_151_golden_reference.json", build_golden())
    write_json("equipment_helmet_v2_audit.json", build_audit())
    print(
        "BUILD_PLAYER_HELMET_V2_CONTRACTS_PASS "
        "sockets=232 calibration_assets=11 item_ids=12 "
        "directions=8 primary_hair=true cast=true"
    )


if __name__ == "__main__":
    main()
