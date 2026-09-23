"""Read-only source pixel audit for the actual resources exported by the CPU probe.

Does not edit images/import settings or infer GPU cost from alpha coverage.
Run tests/monster_animation_cpu_profile_test.tscn first.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, default=Path("outputs/repair_v93/monster_animation_cpu.json"))
    parser.add_argument("--output", type=Path, default=Path("outputs/repair_v93/monster_atlas_audit.json"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    profile = json.loads(args.profile.read_text(encoding="utf-8"))
    rows = []
    for mid, record in profile["profiles"].items():
        width, height = record["frame_size"]
        row = {"monster_id": int(mid), "name": record["name"], "frame_size": [width, height], "actions": {}}
        union_box = [width, height, 0, 0]
        for action, texture in record["actions"].items():
            path = root / texture["path"].removeprefix("res://")
            with Image.open(path) as image:
                assert image.size == (texture["width"], texture["height"])
                assert image.width % width == 0 and image.height == height * 8
                alpha = image.convert("RGBA").getchannel("A")
                histogram = alpha.histogram()
                for y in range(0, image.height, height):
                    for x in range(0, image.width, width):
                        bounds = alpha.crop((x, y, x + width, y + height)).getbbox()
                        if bounds:
                            union_box = [min(union_box[0], bounds[0]), min(union_box[1], bounds[1]),
                                         max(union_box[2], bounds[2]), max(union_box[3], bounds[3])]
                row["actions"][action] = {
                    "path": texture["path"], "size": list(image.size),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "nontransparent_pixels": sum(histogram[1:]),
                    "transparent_fraction": histogram[0] / (image.width * image.height),
                    "decoded_rgba8_bytes": image.width * image.height * 4,
                }
        row["all_actions_directions_alpha_union_in_frame"] = union_box
        row["transparent_border_area_fraction"] = 1 - ((union_box[2] - union_box[0]) * (union_box[3] - union_box[1])) / (width * height)
        rows.append(row)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "status": "PASS", "scope": "18 representative species; source pixels, not GPU cost or residency",
        "input_profile_sha256": hashlib.sha256(args.profile.read_bytes()).hexdigest(),
        "monsters": rows,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MONSTER_ATLAS_AUDIT_PASS species={len(rows)}")


if __name__ == "__main__":
    main()
