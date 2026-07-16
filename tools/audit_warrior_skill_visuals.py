#!/usr/bin/env python3
"""Audit warrior attack body/weapon/effect atlases against declared source frames."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
WEAR = ROOT / "assets/data/warrior_wear_sources.json"
EFFECTS = ROOT / "assets/data/warrior_client_art_sources.json"
OUTPUT = ROOT / "outputs/validation/warrior_skill_visual_audit.json"
CAPTURE_DIR = ROOT / "outputs/visual_acceptance/warrior_skill_direction_audit"


def runtime_path(value: str) -> Path:
    return ROOT / value.removeprefix("res://")


def fits(frame: dict, cell: tuple[int, int], anchor: tuple[int, int], scale: float = 1.0) -> bool:
    x = anchor[0] + round(int(frame["drawOffset"][0]) * scale)
    y = anchor[1] + round(int(frame["drawOffset"][1]) * scale)
    width = max(1, round(int(frame["sourceSize"][0]) * scale))
    height = max(1, round(int(frame["sourceSize"][1]) * scale))
    return x >= 0 and y >= 0 and x + width <= cell[0] and y + height <= cell[1]


def audit_wear(manifest: dict) -> dict:
    seen: set[str] = set()
    checked_frames = 0
    weapon_attack_frames = 0
    weapon_tip_frames = 0
    overflows: list[dict] = []
    atlas_errors: list[str] = []
    judgement_old_overflows: list[dict] = []
    for item_name, mapping in manifest["runtimeMappings"].items():
        for appearance_type in ("weaponAppearance", "dressAppearance"):
            appearance = mapping.get(appearance_type)
            if not appearance:
                continue
            variants = appearance.get("genderVariants", {"legacy": appearance})
            for gender, variant in variants.items():
                if not variant.get("visible"):
                    continue
                for action_name, action in variant.get("actions", {}).items():
                    path = str(action["path"])
                    if path in seen:
                        continue
                    seen.add(path)
                    cell = tuple(map(int, action["cell"]))
                    anchor = tuple(map(int, action["footAnchor"]))
                    expected_size = (cell[0] * int(action["framesPerDirection"]), cell[1] * 8)
                    actual_size = Image.open(runtime_path(path)).size
                    if actual_size != expected_size:
                        atlas_errors.append(f"{path}: expected={expected_size} actual={actual_size}")
                    for frame in action["sourceFrames"]:
                        checked_frames += 1
                        if appearance_type == "weaponAppearance" and action_name == "attack":
                            weapon_attack_frames += 1
                            if len(frame.get("weaponTipOffset", [])) == 2:
                                weapon_tip_frames += 1
                        if not fits(frame, cell, anchor):
                            overflows.append({"path": path, "gender": gender, "action": action_name, **frame})
                        if appearance_type == "weaponAppearance" and int(variant["feature"]) == 48 and action_name == "attack":
                            if not fits(frame, (192, 160), (64, 80)):
                                judgement_old_overflows.append({
                                    "direction": frame["direction"], "frame": frame["frame"], "index": frame["index"]
                                })
    return {
        "uniqueAtlases": len(seen),
        "checkedFrames": checked_frames,
        "weaponAttackFrames": weapon_attack_frames,
        "weaponTipFrames": weapon_tip_frames,
        "overflowFrames": overflows,
        "atlasErrors": atlas_errors,
        "judgementOldLayoutOverflowFrames": judgement_old_overflows,
    }


def audit_effects(manifest: dict) -> dict:
    checked_frames = 0
    fire_ignition_frames = 0
    errors: list[dict | str] = []
    for skill_name, effect in manifest["effects"].items():
        cell = tuple(map(int, effect["cell"]))
        origin = tuple(map(int, effect["origin"]))
        scale = float(effect["sourceScaleBakedIntoAtlas"])
        frames = effect["sourceFrames"]
        for frame in frames:
            checked_frames += 1
            if skill_name == "烈火剑法" and len(frame.get("ignitionOffset", [])) == 2:
                fire_ignition_frames += 1
            expected_index = int(effect["hitEffectBase"]) + int(frame["direction"]) * 10 + int(frame["frame"])
            if int(frame["index"]) != expected_index or not fits(frame, cell, origin, scale):
                errors.append({"skill": skill_name, **frame})
        if "atlasShards" in effect:
            shard_info = effect["atlasShards"]
            expected_size = (cell[0] * int(shard_info["framesPerAtlas"]), cell[1] * int(shard_info["directionsPerAtlas"]))
            for row in shard_info["paths"]:
                for path in row:
                    actual_size = Image.open(runtime_path(str(path))).size
                    if actual_size != expected_size:
                        errors.append(f"{skill_name}/{path}: expected={expected_size} actual={actual_size}")
        else:
            expected_size = (cell[0] * 6, cell[1] * 8)
            actual_size = Image.open(runtime_path(str(effect["atlas"]))).size
            if actual_size != expected_size:
                errors.append(f"{skill_name}: expected={expected_size} actual={actual_size}")
    return {
        "skills": len(manifest["effects"]),
        "checkedFrames": checked_frames,
        "fireIgnitionFrames": fire_ignition_frames,
        "errors": errors,
    }


def main() -> int:
    wear = json.loads(WEAR.read_text(encoding="utf-8"))
    effects = json.loads(EFFECTS.read_text(encoding="utf-8"))
    wear_result = audit_wear(wear)
    effect_result = audit_effects(effects)
    capture_paths = [CAPTURE_DIR / name for name in (
        "basic_sword.png", "power_hit.png", "long_hit.png", "wide_hit.png", "wild_rush.png", "fire_hit.png",
        "fire_hit_weapon_head_isolated.png",
    )]
    captures_ok = all(path.exists() and path.stat().st_size > 0 for path in capture_paths)
    checks = {
        "primaryClientAssets": wear.get("sourcePolicy", {}).get("distributionId") == "client.classic_raw_complete"
            and effects.get("clientAssetDistribution") == "client.classic_raw_complete",
        "primaryClientRules": effects.get("clientRuleDistribution") == "source.original_gameofmir.mirclient",
        "wearNoClipping": not wear_result["overflowFrames"] and not wear_result["atlasErrors"],
        "effectsNoClippingAndFormulaCorrect": not effect_result["errors"],
        "oldJudgementDefectReproduced": len(wear_result["judgementOldLayoutOverflowFrames"]) == 9,
        "weaponHeadMetadataComplete": wear_result["weaponTipFrames"] == wear_result["weaponAttackFrames"],
        "fireIgnitionMetadataComplete": effect_result["fireIgnitionFrames"] == 48,
        "sixByEightRuntimeCapturesPresent": captures_ok,
    }
    payload = {
        "taskId": "WARRIOR-SKILL-VISUAL-AUDIT-2",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "checks": checks,
        "wear": wear_result,
        "effects": effect_result,
        "runtimeCaptures": [str(path.relative_to(ROOT)).replace("\\", "/") for path in capture_paths],
        "pass": all(checks.values()),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not payload["pass"]:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 1
    print(
        "WARRIOR_SKILL_VISUAL_AUDIT_PASS "
        f"wear_frames={wear_result['checkedFrames']} effect_frames={effect_result['checkedFrames']} "
        f"old_judgement_clipped={len(wear_result['judgementOldLayoutOverflowFrames'])} new_clipped=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
