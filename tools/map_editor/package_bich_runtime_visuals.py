"""Copy baked editor chunks into exportable runtime assets and write a manifest."""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = ROOT / "map_editor_workspace/bich_province"
WORK = WORKSPACE / "ground"
DEST = ROOT / "assets/art/maps/bich/editor_runtime_chunks"
OUT = ROOT / "assets/data/runtime/map_editor/bich_province.visual.json"
GROUND_COORDINATE_CONTRACT_ID = "isometric_cell_center_64x32_v2"


def intersects_authored_diamond(rect, ground_size):
    """Return whether an axis-aligned chunk touches the authored isometric map."""
    x, y, width, height = (float(value) for value in rect)
    center_x = float(ground_size[0]) * 0.5
    center_y = float(ground_size[1]) * 0.5
    nearest_x = min(max(center_x, x), x + width)
    nearest_y = min(max(center_y, y), y + height)
    normalized_distance = (
        abs(nearest_x - center_x) / center_x
        + abs(nearest_y - center_y) / center_y
    )
    return normalized_distance <= 1.0


def _positive_integer(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and value > 0
        and float(value).is_integer()
    )


def validate_manifest_geometry(manifest):
    if manifest.get("coordinate_contract_id") != GROUND_COORDINATE_CONTRACT_ID:
        raise SystemExit(
            "BICH_RUNTIME_VISUAL_PACKAGE_FAILED ground coordinate contract invalid"
        )
    design_size = manifest.get("design_size")
    ground_size = manifest.get("ground_pixel_size")
    if (
        not isinstance(design_size, list)
        or len(design_size) != 2
        or not all(_positive_integer(value) for value in design_size)
    ):
        raise SystemExit("BICH_RUNTIME_VISUAL_PACKAGE_FAILED design_size invalid")
    if (
        not isinstance(ground_size, list)
        or len(ground_size) != 2
        or not all(_positive_integer(value) for value in ground_size)
    ):
        raise SystemExit("BICH_RUNTIME_VISUAL_PACKAGE_FAILED ground_pixel_size invalid")
    width, height = (int(value) for value in design_size)
    expected_size = [(width + height) * 32, (width + height) * 16]
    if [int(value) for value in ground_size] != expected_size:
        raise SystemExit(
            "BICH_RUNTIME_VISUAL_PACKAGE_FAILED ground_pixel_size contract mismatch"
        )
    return [width, height], expected_size


def ground_pixel_center_v2(design_size, ground_size):
    width, height = design_size
    return [float(ground_size[0]) / 2.0, float(width + height - 2) * 8.0]


def main():
    manifest = json.loads(
        (WORK / "ground_manifest.json").read_text(encoding="utf-8")
    )
    design_size, ground_size = validate_manifest_geometry(manifest)
    required_chunks = [
        chunk
        for chunk in manifest["chunks"]
        if intersects_authored_diamond(chunk["rect_px"], ground_size)
    ]
    missing = []
    for chunk in required_chunks:
        preview = chunk.get("preview_png")
        source = WORKSPACE / preview if preview else None
        if not preview or source is None or not source.is_file():
            missing.append(chunk["chunk_id"])
    if missing:
        raise SystemExit(
            "BICH_RUNTIME_VISUAL_PACKAGE_FAILED missing authored chunks: "
            + ", ".join(missing)
        )

    DEST.mkdir(parents=True, exist_ok=True)
    expected_names = {Path(chunk["preview_png"]).name for chunk in required_chunks}
    for stale in DEST.glob("*.png"):
        if stale.name not in expected_names:
            stale.unlink()
            stale_import = stale.with_name(stale.name + ".import")
            if stale_import.exists():
                stale_import.unlink()

    chunks = []
    for chunk in required_chunks:
        source = WORKSPACE / chunk["preview_png"]
        destination = DEST / source.name
        shutil.copy2(source, destination)
        chunks.append(
            {
                "chunk_id": chunk["chunk_id"],
                "rect_px": chunk["rect_px"],
                "image": destination.relative_to(ROOT).as_posix(),
            }
        )

    payload = {
        "schema_version": 1,
        "map_id": "bich_province",
        "runtime_map_id": 4,
        "design_size": design_size,
        "ground_pixel_size": ground_size,
        "ground_coordinate_contract_id": GROUND_COORDINATE_CONTRACT_ID,
        "ground_pixel_center": ground_pixel_center_v2(design_size, ground_size),
        "base_color": "#465827",
        "guard_band_px": 1536,
        "render_mode": "batched_canvas_draw",
        "coverage": {
            "required_chunk_count": len(required_chunks),
            "packaged_chunk_count": len(chunks),
            "complete": len(required_chunks) == len(chunks),
        },
        "chunks": chunks,
    }
    OUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "BICH_RUNTIME_VISUAL_PACKAGE_PASS "
        f"chunks={len(chunks)} coverage_complete=true "
        "render_mode=batched_canvas_draw"
    )


if __name__ == "__main__":
    main()
