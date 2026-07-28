from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "vendor"))

from PIL import Image, ImageChops  # noqa: E402


CELL = (192, 160)
DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
ACTIONS = {
    "idle": 4,
    "walk": 6,
    "attack": 6,
    "cast": 6,
    "hit": 3,
    "death": 4,
}
SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "bronze_magic_helmet_8dir_transparent.png"
)
SOURCE_SHA256 = (
    "8d5b9b4af6e28947cb4437d5f09ea8f26fd8822b4d589d619a8153eda37504ee"
)
OUTPUT_ROOT = (
    ROOT / "assets/generated/helmet_v2/bronze_magic/scale_100"
)
FROZEN_SHA256 = {
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00147_head.png": (
        "640d25cc53cb81d632ff962ad52c56024935197aaf741c52119982252595be7b"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00147_erase_mask.png": (
        "51458660b7065576d26ea09d74230f399fb4b98180eebff38cd57c3fb8fbcb9d"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00148_head.png": (
        "640d25cc53cb81d632ff962ad52c56024935197aaf741c52119982252595be7b"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00148_erase_mask.png": (
        "51458660b7065576d26ea09d74230f399fb4b98180eebff38cd57c3fb8fbcb9d"
    ),
    "assets/art/items/client/inventory/100.png": (
        "1f592a0abcf0ae714ab84f386313dc8155d08248151f93d0f1cdbdffe87a7569"
    ),
    "assets/art/items/client/ground/100.png": (
        "99b6e7e551402cf7f4d280678411f17eda1ad734bb292b1f624335508afc4eef"
    ),
}
PIPELINE_ID = (
    "bronze_magic.transparent_source."
    "premultiplied_alpha_lanczos_high_res_single_pass_nearest_runtime_v2"
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def significant_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    visible = alpha.point(lambda value: 255 if value > 7 else 0)
    return visible.getbbox()


def crop_source_direction(
    source_sheet: Image.Image,
    source_slot: int,
) -> Image.Image:
    tile_width = source_sheet.width // 4
    tile_height = source_sheet.height // 2
    tile = source_sheet.crop(
        (
            (source_slot % 4) * tile_width,
            (source_slot // 4) * tile_height,
            ((source_slot % 4) + 1) * tile_width,
            ((source_slot // 4) + 1) * tile_height,
        )
    )
    bbox = tile.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"empty source direction slot {source_slot}")
    return tile.crop(bbox)


def premultiplied_lanczos_resize(
    image: Image.Image,
    size: tuple[int, int],
) -> Image.Image:
    """Downsample once from the authored cutout without dark edge bleeding."""
    source = image.convert("RGBA")
    alpha = source.getchannel("A")
    red, green, blue, _ = source.split()
    premultiplied = Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    ).resize(size, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    source_pixels = premultiplied.load()
    output_pixels = output.load()
    for y in range(size[1]):
        for x in range(size[0]):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha <= 1:
                continue
            red = min(255, round(red * 255 / alpha))
            green = min(255, round(green * 255 / alpha))
            blue = min(255, round(blue * 255 / alpha))
            green = min(green, max(red, blue) + 6)
            output_pixels[x, y] = (
                red,
                green,
                blue,
                alpha,
            )
    return output


def assert_frozen_assets() -> dict[str, str]:
    actual: dict[str, str] = {}
    for relative, expected in FROZEN_SHA256.items():
        path = ROOT / relative
        digest = file_sha256(path)
        if digest != expected:
            raise AssertionError(
                f"frozen asset changed: {relative}: {digest} != {expected}"
            )
        actual[relative] = digest
    return actual


def build_action(
    action: str,
    frame_count: int,
    source_directions: tuple[Image.Image, ...],
) -> Image.Image:
    output_path = (
        OUTPUT_ROOT / f"bronze_magic_{action}_scale_100.png"
    )
    layout = Image.open(output_path).convert("RGBA")
    expected_size = (CELL[0] * frame_count, CELL[1] * len(DIRECTIONS))
    if layout.size != expected_size:
        raise AssertionError(
            f"{action} atlas size changed: {layout.size} != {expected_size}"
        )
    rebuilt = Image.new("RGBA", layout.size, (0, 0, 0, 0))
    for source_row, direction in enumerate(DIRECTIONS):
        authored = source_directions[source_row]
        for frame_index in range(frame_count):
            cell_box = (
                frame_index * CELL[0],
                source_row * CELL[1],
                (frame_index + 1) * CELL[0],
                (source_row + 1) * CELL[1],
            )
            layout_cell = layout.crop(cell_box)
            placement = significant_bbox(layout_cell)
            if placement is None:
                raise AssertionError(
                    f"missing layout: {action}/{direction}/frame_{frame_index}"
                )
            target_size = (
                placement[2] - placement[0],
                placement[3] - placement[1],
            )
            fitted = premultiplied_lanczos_resize(authored, target_size)
            rebuilt.alpha_composite(
                fitted,
                (
                    cell_box[0] + placement[0],
                    cell_box[1] + placement[1],
                ),
            )
    return rebuilt


def rebuild(check: bool) -> dict[str, object]:
    if file_sha256(SOURCE) != SOURCE_SHA256:
        raise AssertionError("bronze/magic transparent source hash changed")
    frozen_before = assert_frozen_assets()
    source_sheet = Image.open(SOURCE).convert("RGBA")
    if source_sheet.size != (1774, 887):
        raise AssertionError(
            f"bronze/magic source size changed: {source_sheet.size}"
        )
    source_directions = tuple(
        crop_source_direction(source_sheet, slot)
        for slot in range(len(DIRECTIONS))
    )
    results: dict[str, str] = {}
    changed: list[str] = []
    for action, frame_count in ACTIONS.items():
        output_path = (
            OUTPUT_ROOT / f"bronze_magic_{action}_scale_100.png"
        )
        rebuilt = build_action(action, frame_count, source_directions)
        current_bytes = output_path.read_bytes()
        if check:
            from io import BytesIO

            buffer = BytesIO()
            rebuilt.save(buffer, format="PNG", optimize=False)
            if buffer.getvalue() != current_bytes:
                raise AssertionError(
                    f"{output_path.relative_to(ROOT)} needs resolution rebuild"
                )
        else:
            rebuilt.save(output_path, format="PNG", optimize=False)
            if output_path.read_bytes() != current_bytes:
                changed.append(action)
        results[action] = file_sha256(output_path)
    frozen_after = assert_frozen_assets()
    if frozen_after != frozen_before:
        raise AssertionError("a frozen paper-doll/inventory/ground asset changed")
    return {
        "identityId": "bronze_magic",
        "itemIds": [147, 148],
        "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "sourceSha256": SOURCE_SHA256,
        "pipelineId": PIPELINE_ID,
        "actions": results,
        "changedActions": changed,
        "frozenAssets": frozen_after,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify committed outputs without writing",
    )
    args = parser.parse_args()
    print(json.dumps(rebuild(args.check), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
