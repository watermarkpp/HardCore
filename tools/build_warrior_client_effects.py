#!/usr/bin/env python3
"""Build classic warrior hit-effect atlases from the primary local client."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "dev_art_sources/reference/mir2_client_raw"
MIR_SOURCE = ROOT / "dev_art_sources/reference/original_gameofmir/MirClient"
OUTPUT = ROOT / "assets/art/characters/warrior/effects"
AUDIO_OUTPUT = ROOT / "assets/audio/warrior"
MANIFEST = ROOT / "assets/data/warrior_client_art_sources.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


SOURCE_FOOT_ANCHOR = (64, 80)
RUNTIME_FOOT_ANCHOR = (96, 108)
RUNTIME_ACTOR_OFFSET = tuple(source - runtime for source, runtime in zip(SOURCE_FOOT_ANCHOR, RUNTIME_FOOT_ANCHOR))
EFFECTS = {
    "攻杀剑术": {"effectNumber": 1, "baseIndex": 800, "file": "power_hit.png", "cell": (224, 224), "origin": (86, 130), "scale": 1.0},
    "刺杀剑术": {"effectNumber": 2, "baseIndex": 1410, "file": "long_hit.png", "cell": (288, 224), "origin": (119, 144), "scale": 1.0},
    "半月弯刀": {"effectNumber": 3, "baseIndex": 1700, "file": "wide_hit.png", "cell": (240, 224), "origin": (96, 143), "scale": 1.0},
    # Full-size fire spans 633x478 pixels. Split it into four 3x4 shards so
    # each texture remains 1920x1920 without shrinking the source effect.
    "烈火剑法": {
        "effectNumber": 4, "baseIndex": 3480, "file": "fire_hit.png",
        "cell": (640, 480), "origin": (296, 267), "scale": 1.0,
        "shards": True,
    },
}
SOUNDS = {
    "空手挥击": 57, "木制武器挥击": 51, "剑类武器挥击": 52,
    "攻杀男声": 130, "攻杀女声": 131, "刺杀技能声": 132, "半月技能声": 133,
    "野蛮左声道": 134, "野蛮右声道": 135, "烈火蓄力声": 136, "烈火命中声": 137,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(text: str, pattern: str, label: str) -> None:
    if re.search(pattern, text, re.MULTILINE) is None:
        raise RuntimeError(f"客户端主规则证据缺失：{label}")


def fire_ignition_offset(image: Image.Image, meta: dict) -> list[int]:
    """Find the proximal centroid of bright flame pixels in actor space."""
    rgba = image.convert("RGBA")
    points = []
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha > 80 and red > 160 and green > 35 and red > green * 1.4:
                points.append((x + int(meta["x"]), y + int(meta["y"])))
    if not points:
        points = [
            (x + int(meta["x"]), y + int(meta["y"]))
            for y in range(rgba.height)
            for x in range(rgba.width)
            if rgba.getpixel((x, y))[3] > 80
        ]
    points.sort(key=lambda point: point[0] * point[0] + point[1] * point[1])
    proximal = points[:max(1, len(points) // 20)]
    return [round(sum(x for x, _ in proximal) / len(proximal)), round(sum(y for _, y in proximal) / len(proximal))]


def build_effects() -> tuple[dict, dict]:
    magic_path = CLIENT / "Data/Magic.wil"
    data, palette, offsets, library_info = read_library(magic_path)
    result = {}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for skill_name, spec in EFFECTS.items():
        cell_w, cell_h = spec["cell"]
        scale = float(spec["scale"])
        sharded = bool(spec.get("shards", False))
        if sharded:
            atlases = [[Image.new("RGBA", (cell_w * 3, cell_h * 4), (0, 0, 0, 0)) for _ in range(2)] for _ in range(2)]
        else:
            atlas = Image.new("RGBA", (cell_w * 6, cell_h * 8), (0, 0, 0, 0))
        origin = tuple(spec["origin"])
        source_frames = []
        for direction in range(8):
            for frame in range(6):
                index = int(spec["baseIndex"]) + direction * 10 + frame
                image, meta = decode_sprite(data, offsets[index], palette)
                image = image.convert("RGBA")
                if scale != 1.0:
                    image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
                paste_x = origin[0] + round(int(meta["x"]) * scale)
                paste_y = origin[1] + round(int(meta["y"]) * scale)
                if paste_x < 0 or paste_y < 0 or paste_x + image.width > cell_w or paste_y + image.height > cell_h:
                    raise RuntimeError(
                        f"{skill_name} direction={direction} frame={frame} does not fit "
                        f"cell={(cell_w, cell_h)} origin={origin}: "
                        f"paste={(paste_x, paste_y)} size={image.size}"
                    )
                isolated = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
                isolated.alpha_composite(image, (paste_x, paste_y))
                if sharded:
                    direction_group = direction // 4
                    frame_group = frame // 3
                    atlases[direction_group][frame_group].alpha_composite(
                        isolated, ((frame % 3) * cell_w, (direction % 4) * cell_h)
                    )
                else:
                    atlas.alpha_composite(isolated, (frame * cell_w, direction * cell_h))
                frame_record = {
                    "index": index, "direction": direction, "frame": frame,
                    "drawOffset": [int(meta["x"]), int(meta["y"])],
                    "sourceSize": [int(meta["width"]), int(meta["height"])],
                }
                if skill_name == "烈火剑法":
                    frame_record["ignitionOffset"] = fire_ignition_offset(image, meta)
                source_frames.append(frame_record)
        if sharded:
            shard_paths = []
            stem = Path(str(spec["file"])).stem
            for direction_group in range(2):
                row = []
                for frame_group in range(2):
                    target = OUTPUT / f"{stem}_d{direction_group}_f{frame_group}.png"
                    atlases[direction_group][frame_group].save(target)
                    row.append(f"res://assets/art/characters/warrior/effects/{target.name}")
                shard_paths.append(row)
        else:
            target = OUTPUT / str(spec["file"])
            atlas.save(target)
        effect_record = {
            "effectNumber": spec["effectNumber"], "hitEffectBase": spec["baseIndex"],
            "distribution": "client.classic_raw_complete",
            "library": "dev_art_sources/reference/mir2_client_raw/Data/Magic.wil",
            "librarySha256": sha256(magic_path),
            "sourceFormula": "base + direction*10 + actionFrame", "sourceFrames": source_frames,
            "cell": [cell_w, cell_h], "origin": list(origin),
            "sourceScaleBakedIntoAtlas": scale, "runtimeActorOffset": list(RUNTIME_ACTOR_OFFSET),
            "directions": 8, "actionFrames": 6, "confidence": "A",
        }
        if sharded:
            effect_record["atlasShards"] = {
                "directionsPerAtlas": 4,
                "framesPerAtlas": 3,
                "paths": shard_paths,
            }
        else:
            effect_record["atlas"] = f"res://assets/art/characters/warrior/effects/{spec['file']}"
        result[skill_name] = effect_record
    return result, library_info


def copy_audio() -> dict:
    AUDIO_OUTPUT.mkdir(parents=True, exist_ok=True)
    result = {}
    for label, sound_id in SOUNDS.items():
        source = CLIENT / "Wav" / f"{sound_id}.wav"
        available = source.exists()
        runtime_path = ""
        if available and sound_id in (51, 52, 57):
            target = AUDIO_OUTPUT / f"{sound_id}.wav"
            shutil.copy2(source, target)
            runtime_path = f"res://assets/audio/warrior/{sound_id}.wav"
        result[label] = {
            "soundId": sound_id, "distribution": "client.classic_raw_complete",
            "source": f"dev_art_sources/reference/mir2_client_raw/Wav/{sound_id}.wav",
            "available": available, "runtimePath": runtime_path, "confidence": "A",
        }
    return result


def main() -> None:
    actor_path = MIR_SOURCE / "Actor.pas"
    magic_effect_path = MIR_SOURCE / "magiceff.pas"
    sound_path = MIR_SOURCE / "SoundUtil.pas"
    actor = actor_path.read_text(encoding="gbk", errors="replace")
    magic_effect = magic_effect_path.read_text(encoding="gbk", errors="replace")
    sound = sound_path.read_text(encoding="gbk", errors="replace")
    for number in range(1, 5):
        require(actor, rf"m_nHitEffectNumber\s*:=\s*{number}", f"HitEffectNumber {number}")
    for base in (800, 1410, 1700, 3480):
        require(magic_effect, rf"\b{base}\b", f"HitEffectBase {base}")
    for label, sound_id in SOUNDS.items():
        require(sound, rf"=\s*{sound_id};", label)
    effects, library_info = build_effects()
    sounds = copy_audio()
    payload = {
        "schemaVersion": 2, "taskId": "WARRIOR-SKILL-VISUAL-AUDIT-1",
        "sourcePolicy": "MIR-SOURCE-PRIORITY-1",
        "clientAssetDistribution": "client.classic_raw_complete",
        "clientRuleDistribution": "source.original_gameofmir.mirclient",
        "generatedFrom": [
            "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas",
            "dev_art_sources/reference/original_gameofmir/MirClient/magiceff.pas",
            "dev_art_sources/reference/original_gameofmir/MirClient/SoundUtil.pas",
            "dev_art_sources/reference/mir2_client_raw/Data/Magic.wil",
        ],
        "sourceHashes": {"Actor.pas": sha256(actor_path), "magiceff.pas": sha256(magic_effect_path),
            "SoundUtil.pas": sha256(sound_path), "Magic.wil": sha256(CLIENT / "Data/Magic.wil")},
        "clientAction": {"frames": 6, "frameMs": 85, "effectFrame": 2, "durationMs": 510},
        "alignment": {"bodyAtlasSourceFootAnchor": list(SOURCE_FOOT_ANCHOR),
            "bodyRuntimeFootAnchor": list(RUNTIME_FOOT_ANCHOR), "runtimeActorOffset": list(RUNTIME_ACTOR_OFFSET),
            "reason": "effect and body preserve one classic actor origin after runtime ground-anchor migration"},
        "libraryInfo": library_info, "effects": effects, "sounds": sounds,
        "missingSkillSounds": [label for label, row in sounds.items() if row["soundId"] >= 130 and not row["available"]],
        "policy": "主客户端缺少130—137号技能WAV时只记录缺失，不使用辅端或无来源音频冒充。",
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WARRIOR_CLIENT_EFFECTS_PASS effects={len(effects)} runtime_offset={RUNTIME_ACTOR_OFFSET}")


if __name__ == "__main__":
    main()
