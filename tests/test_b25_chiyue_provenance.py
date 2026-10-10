from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PRODUCER = ROOT / "tools" / "map_assets" / "build_chiyue_valley_wall_pack.py"


def _load_producer():
    spec = importlib.util.spec_from_file_location("chiyue_wall_producer", PRODUCER)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load producer: {PRODUCER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _dominant_front_red(part: Image.Image) -> int:
    counts: dict[int, int] = {}
    for red, green, blue, alpha in part.getdata():
        if alpha and red > green and red > blue:
            counts[red] = counts.get(red, 0) + 1
    if not counts:
        raise AssertionError("part has no opaque front pixels")
    return max(counts, key=counts.get)


def test_iso_y_source_coordinates_follow_rendered_parts() -> None:
    """Verify real producer output keeps source coordinates with parts."""
    producer = _load_producer()
    with TemporaryDirectory(prefix="b25_chiyue_provenance_") as scratch:
        scratch_path = Path(scratch)
        front_paths = []
        cap_paths = []
        for variant in range(1, 5):
            front_path = scratch_path / f"front_{variant}.png"
            cap_path = scratch_path / f"cap_{variant}.png"
            Image.new("RGBA", (32, 160), (variant * 50, 0, 0, 255)).save(front_path)
            Image.new("RGBA", (64, 64), (0, variant * 50, 0, 255)).save(cap_path)
            front_paths.append(front_path)
            cap_paths.append(cap_path)

        front = {
            variant: Image.open(front_paths[variant - 1]).convert("RGBA")
            for variant in range(1, 5)
        }
        cap = {
            variant: Image.open(cap_paths[variant - 1]).convert("RGBA")
            for variant in range(1, 5)
        }
        input_hashes = [
            hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (*front_paths, *cap_paths)
        ]
        assert all(len(value) == 64 for value in input_hashes)
        module = {"axis": "iso_y", "length_tiles": 2, "variant": 1, "canvas_size": [128, 240]}

        _artwork, parts, actual_layout = producer.straight_art(module, front, cap)

    assert actual_layout == ((1, 3), (4, 2))
    assert len(parts) == 2
    assert [_dominant_front_red(part) for part in parts] == [50, 200]


if __name__ == "__main__":
    test_iso_y_source_coordinates_follow_rendered_parts()
    print("B25 ART003 PASS")
