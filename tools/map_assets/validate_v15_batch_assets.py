"""Validate locally processed V1.5 staging batches without promoting them."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2] / "assets" / "art" / "maps" / "_staging" / "v1_5"


def main() -> int:
    errors: list[str] = []
    batches = sorted(ROOT.rglob("batch_metadata.json"))
    total = 0
    for metadata_path in batches:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        output_dir = metadata_path.parent / "editor_canvas"
        files = sorted(output_dir.glob("*.png"))
        expected = int(metadata["expected_count"])
        if len(files) != expected:
            errors.append(f"{metadata['batch_id']}: expected={expected} actual={len(files)}")
        for output in files:
            with Image.open(output) as image:
                if image.mode != "RGBA":
                    errors.append(f"{output}: expected_rgba got={image.mode}")
                if list(image.size) != metadata["target_canvas_size"]:
                    errors.append(f"{output}: unexpected_canvas={list(image.size)}")
                if image.getchannel("A").getextrema()[0] != 0:
                    errors.append(f"{output}: no_transparent_background")
        total += len(files)
    print(f"v1_5_batches={len(batches)} assets={total} errors={len(errors)}")
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
