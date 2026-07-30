#!/usr/bin/env python3
"""Extract the first map-enabled classic bosses from the bundled Mir2 client."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
CLIENT_ACTOR = (
    ROOT
    / "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas"
)
OUTPUT = ROOT / "assets/art/monsters/client_classic_bosses"
MANIFEST = ROOT / "assets/data/classic_boss_client_art_sources.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


PADDING = 10

# The ranges are the original TMonsterAction tables.  A repeated action is
# intentional for stationary monsters: runtime still requires five states.
TABLES = {
    "MA19": {
        "idle": (0, 4, 200, 10),
        "walk": (80, 6, 160, 10),
        "attack": (160, 6, 100, 10),
        "hit": (240, 2, 100, 2),
        "death": (260, 10, 140, 10),
    },
    "ZUMA_TAURUS": {
        # The appearance-63 block starts with a 20-frame materialization
        # sequence.  Its five ordinary actor states begin at block offset 20;
        # using MA34's unshifted starts reads materialization/effect frames as
        # directions and creates the previously visible body fragments.
        "idle": (20, 4, 200, 10),
        "walk": (100, 6, 200, 10),
        "attack": (180, 6, 120, 10),
        "hit": (260, 2, 100, 2),
        "death": (280, 10, 200, 10),
    },
    # TCentipedeKing is immobile. This block is directionless in the bundled
    # WIL: its visible ranges are 0..3, 10..15, 50..51 and 60..89.
    "CENTIPEDE_FIXED": {
		"idle": (0, 4, 300, 0),
		"walk": (0, 4, 300, 0),
		"attack": (10, 6, 150, 0),
		"hit": (50, 2, 150, 0),
		"death": (60, 8, 80, 0),
    },
}

BOSSES = {
    "沃玛教主": {
        "monsterId": 76,
        "slug": "wooma_taurus",
        "appearance": 34,
        "actionTable": "MA19",
        "mappingConfidence": "B",
        "mappingNote": "外观块和动作范围由WIL像素确认；缺失1.76 Monster.DB，RaceImg仅按块结构采用MA19。",
    },
    "触龙神": {
        "monsterId": 124,
        "slug": "evil_centipede",
        "appearance": 140,
        "actionTable": "CENTIPEDE_FIXED",
        "mappingConfidence": "B",
        "mappingNote": "Mon15固定体可见像素范围已确认；缺失1.76 Monster.DB动作绑定，固定体动作复制到八个逻辑朝向。",
		"renderScale": 0.5,
    },
    "祖玛教主": {
        "monsterId": 160,
        "slug": "zuma_taurus",
        "appearance": 63,
        "actionTable": "ZUMA_TAURUS",
        "mappingConfidence": "B",
        "mappingNote": (
            "Mon7 appearance-63 contains a 20-frame materialization prefix. "
            "Primary MirClient Actor.pas establishes MA34 timing/direction "
            "semantics; drawable primary WIL evidence fixes the five body "
            "sequences at offsets 20/100/180/260/280."
        ),
        # Keep the exact visual coordinate system used by the user's approved
        # monster-foot draft while replacing only the wrongly selected frames.
        "lockedFrameSize": [384, 336],
        "lockedFootAnchor": [114, 237],
    },
}


def source_location(appearance: int) -> tuple[Path, int, str]:
    """Apply the exact Actor.pas GetOffset grouping used by this client."""
    group, position = divmod(appearance, 10)
    library_name = f"Mon{group + 1}.wil"
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
    else:
        raise ValueError(f"unregistered classic GetOffset group: {group}")
    return CLIENT_DATA / library_name, base, library_name


def build_boss(name: str, spec: dict) -> dict:
    library, base, library_name = source_location(int(spec["appearance"]))
    data, palette, offsets, info = read_library(library)
    output_dir = OUTPUT / str(spec["slug"])
    output_dir.mkdir(parents=True, exist_ok=True)
    decoded: dict = {}
    bounds: list[tuple[int, int, int, int]] = []

    for action_name, (start, count, frame_ms, stride) in TABLES[str(spec["actionTable"])].items():
        action = {"frames": {}, "count": count, "frame_ms": frame_ms, "start": start, "stride": stride}
        decoded[action_name] = action
        for direction in range(8):
            for frame in range(count):
                index = base + start + direction * stride + frame
                image, meta = decode_sprite(data, offsets[index], palette)
                image = image.convert("RGBA")
                render_scale = float(spec.get("renderScale", 1.0))
                if render_scale != 1.0:
                    image = image.resize(
                        (max(1, round(image.width * render_scale)), max(1, round(image.height * render_scale))),
                        Image.Resampling.NEAREST,
                    )
                    meta = {**meta, "x": round(meta["x"] * render_scale), "y": round(meta["y"] * render_scale)}
                alpha_bounds = image.getchannel("A").getbbox()
                if alpha_bounds is None:
                    raise ValueError(f"empty source frame {index} for {name}/{action_name}")
                action["frames"][(direction, frame)] = (image, meta, index)
                bounds.append((
                    meta["x"] + alpha_bounds[0], meta["y"] + alpha_bounds[1],
                    meta["x"] + alpha_bounds[2], meta["y"] + alpha_bounds[3],
                ))

    min_x = min(row[0] for row in bounds)
    min_y = min(row[1] for row in bounds)
    max_x = max(row[2] for row in bounds)
    max_y = max(row[3] for row in bounds)
    if "lockedFrameSize" in spec:
        cell_w, cell_h = map(int, spec["lockedFrameSize"])
        foot = tuple(map(int, spec["lockedFootAnchor"]))
        if (
            min_x + foot[0] < 0
            or min_y + foot[1] < 0
            or max_x + foot[0] > cell_w
            or max_y + foot[1] > cell_h
        ):
            raise ValueError(
                f"{name} corrected frames do not fit the locked user canvas"
            )
    else:
        cell_w = ((max_x - min_x + PADDING * 2 + 15) // 16) * 16
        cell_h = ((max_y - min_y + PADDING * 2 + 15) // 16) * 16
        foot = (-min_x + PADDING, -min_y + PADDING)
    actions = {}

    for action_name, action in decoded.items():
        count = int(action["count"])
        atlas = Image.new("RGBA", (cell_w * count, cell_h * 8), (0, 0, 0, 0))
        source_frames = []
        for (direction, frame), (image, meta, index) in action["frames"].items():
            isolated = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
            isolated.alpha_composite(image, (foot[0] + meta["x"], foot[1] + meta["y"]))
            atlas.alpha_composite(isolated, (frame * cell_w, direction * cell_h))
            source_frames.append({"index": index, "direction": direction, "frame": frame})
        target = output_dir / f"{spec['slug']}_{action_name}.png"
        atlas.save(target)
        actions[action_name] = {
            "path": f"res://{target.relative_to(ROOT).as_posix()}",
            "framesPerDirection": count,
            "frameMs": int(action["frame_ms"]),
            "sourceStart": base + int(action["start"]),
            "sourceDirectionStride": int(action["stride"]),
            "sourceFrames": source_frames,
            "confidence": spec["mappingConfidence"],
        }

    return {
        "monsterId": int(spec["monsterId"]),
        "name": name,
        "appearance": int(spec["appearance"]),
        "actionTable": spec["actionTable"],
        "mappingConfidence": spec["mappingConfidence"],
		"mappingNote": spec["mappingNote"],
		"renderScale": float(spec.get("renderScale", 1.0)),
        "mappingSource": (
            "primary classic client WIL pixels + primary "
            "MirClient/Actor.pas GetOffset/TMonsterAction"
        ),
        "clientRuleDistribution": "source.original_gameofmir.mirclient",
        "clientRulePath": (
            "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas"
        ),
        "clientLibrary": f"dev_art_sources/reference/mir2_client_raw/Data/{library_name}",
        "clientLibraryImageCount": info["image_count"],
        "blockBase": base,
        "frameSize": [cell_w, cell_h],
        "footAnchor": [foot[0], foot[1]],
        "directions": 8,
        "atlasCellIsolation": "per_frame",
        "actions": actions,
    }


def main() -> None:
    if not CLIENT_ACTOR.exists():
        raise FileNotFoundError(CLIENT_ACTOR)
    mappings = {name: build_boss(name, spec) for name, spec in BOSSES.items()}
    payload = {
        "schemaVersion": 1,
        "identityKey": "monsterId",
        "compatibilityKey": "runtimeMappings by legacy name",
        "baseline": "bundled 2003 classic client",
        "mapActivationOrder": [76, 124, 160],
        "runtimeMappingsByMonsterId": {str(row["monsterId"]): row for row in mappings.values()},
        "runtimeMappings": mappings,
        "generatedAtlases": len(mappings) * 5,
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CLASSIC_BOSS_MAPPINGS={len(mappings)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    main()
