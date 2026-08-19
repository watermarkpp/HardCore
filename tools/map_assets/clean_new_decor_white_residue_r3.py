from __future__ import annotations

import argparse
from collections import Counter, deque
from pathlib import Path

from PIL import Image, ImageDraw

from new_decor_r3_common import (
    CATALOG_PATH,
    REPO_ROOT,
    WHITE_CATEGORIES,
    WHITE_PREVIEW_DIR,
    WHITE_REPORT_PATH,
    asset_map,
    category_cn,
    is_target_asset,
    load_json,
    original_new_batch_ids,
    save_json,
    sha256_bytes,
)


ALPHA_TRANSPARENT = 8

WHITE_MIN = 235
WHITE_SPREAD_MAX = 24

# 自动删除只允许处理半透明白边。
# 绝对禁止自动删除完全不透明的白色物体细节。
AUTO_ALPHA_MAX = 245


def is_near_white(
    rgba: tuple[int, int, int, int],
) -> bool:
    r, g, b, a = rgba

    if a <= 0:
        return False

    low = min(r, g, b)
    high = max(r, g, b)

    return (
        low >= WHITE_MIN
        and high - low
        <= WHITE_SPREAD_MAX
    )


def neighbor_coords(
    x: int,
    y: int,
    w: int,
    h: int,
):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue

            nx = x + dx
            ny = y + dy

            if (
                0 <= nx < w
                and 0 <= ny < h
            ):
                yield nx, ny


def safe_white_residue_pixels(
    image: Image.Image,
) -> set[tuple[int, int]]:
    rgba = image.convert("RGBA")

    w, h = rgba.size
    px = rgba.load()

    candidate = set()
    transparent = set()

    for y in range(h):
        for x in range(w):
            value = px[x, y]
            a = value[3]

            if a <= ALPHA_TRANSPARENT:
                transparent.add((x, y))
                continue

            if (
                a <= AUTO_ALPHA_MAX
                and is_near_white(value)
            ):
                candidate.add((x, y))

    seeds = deque()
    reached = set()

    for x, y in candidate:
        adjacent_outside = (
            x == 0
            or y == 0
            or x == w - 1
            or y == h - 1
        )

        adjacent_transparent = any(
            (nx, ny) in transparent
            for nx, ny
            in neighbor_coords(
                x,
                y,
                w,
                h,
            )
        )

        if (
            adjacent_outside
            or adjacent_transparent
        ):
            seeds.append((x, y))
            reached.add((x, y))

    while seeds:
        x, y = seeds.popleft()

        for nx, ny in neighbor_coords(
            x,
            y,
            w,
            h,
        ):
            point = (nx, ny)

            if (
                point in candidate
                and point not in reached
            ):
                reached.add(point)
                seeds.append(point)

    # 最多额外清 2 层低 alpha 白 halo。
    frontier = set(reached)

    for _ in range(2):
        next_frontier = set()

        for x, y in frontier:
            for nx, ny in neighbor_coords(
                x,
                y,
                w,
                h,
            ):
                point = (nx, ny)

                if point in reached:
                    continue

                value = px[nx, ny]

                if (
                    value[3] <= 180
                    and is_near_white(value)
                ):
                    reached.add(point)
                    next_frontier.add(
                        point
                    )

        frontier = next_frontier

        if not frontier:
            break

    return reached


def opaque_white_review_pixels(
    image: Image.Image,
) -> set[tuple[int, int]]:
    rgba = image.convert("RGBA")

    w, h = rgba.size
    px = rgba.load()

    transparent = set()

    for y in range(h):
        for x in range(w):
            if (
                px[x, y][3]
                <= ALPHA_TRANSPARENT
            ):
                transparent.add((x, y))

    review = set()

    for y in range(h):
        for x in range(w):
            value = px[x, y]

            if value[3] <= AUTO_ALPHA_MAX:
                continue

            if not is_near_white(value):
                continue

            if any(
                (nx, ny) in transparent
                for nx, ny
                in neighbor_coords(
                    x,
                    y,
                    w,
                    h,
                )
            ):
                review.add((x, y))

    return review


def cleaned_image(
    image: Image.Image,
) -> tuple[Image.Image, int, int]:
    rgba = image.convert("RGBA")

    removable = (
        safe_white_residue_pixels(
            rgba
        )
    )

    review = (
        opaque_white_review_pixels(
            rgba
        )
    )

    px = rgba.load()

    for x, y in removable:
        px[x, y] = (
            0,
            0,
            0,
            0,
        )

    return (
        rgba,
        len(removable),
        len(review),
    )


def checkerboard(
    size: tuple[int, int],
) -> Image.Image:
    w, h = size

    result = Image.new(
        "RGB",
        size,
        (205, 205, 205),
    )

    draw = ImageDraw.Draw(result)

    cell = 16

    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if (
                (x // cell + y // cell)
                % 2
            ):
                draw.rectangle(
                    (
                        x,
                        y,
                        min(w, x + cell),
                        min(h, y + cell),
                    ),
                    fill=(235, 235, 235),
                )

    return result


def composite_preview(
    before: Image.Image,
    after: Image.Image,
    target: Path,
) -> None:
    before = before.convert("RGBA")
    after = after.convert("RGBA")

    max_w = 420
    max_h = 420

    before_thumb = before.copy()
    after_thumb = after.copy()

    before_thumb.thumbnail(
        (max_w, max_h),
        Image.Resampling.LANCZOS,
    )

    after_thumb.thumbnail(
        (max_w, max_h),
        Image.Resampling.LANCZOS,
    )

    panel_w = max(
        before_thumb.width,
        after_thumb.width,
    )

    panel_h = max(
        before_thumb.height,
        after_thumb.height,
    )

    canvas = Image.new(
        "RGB",
        (
            panel_w * 2 + 24,
            panel_h + 40,
        ),
        (40, 40, 40),
    )

    for index, thumb in enumerate(
        (before_thumb, after_thumb)
    ):
        bg = checkerboard(
            (
                panel_w,
                panel_h,
            )
        )

        x = (
            panel_w - thumb.width
        ) // 2

        y = (
            panel_h - thumb.height
        ) // 2

        bg.paste(
            thumb,
            (x, y),
            thumb,
        )

        canvas.paste(
            bg,
            (
                index
                * (panel_w + 24),
                40,
            ),
        )

    draw = ImageDraw.Draw(canvas)

    draw.text(
        (10, 10),
        "BEFORE",
        fill=(255, 255, 255),
    )

    draw.text(
        (panel_w + 34, 10),
        "AFTER",
        fill=(255, 255, 255),
    )

    target.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    canvas.save(target)


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--apply",
        action="store_true",
    )

    args = parser.parse_args()

    catalog = load_json(
        CATALOG_PATH
    )

    assets = asset_map(
        catalog
    )

    batch_ids = original_new_batch_ids()

    target_ids = sorted(
        asset_id
        for asset_id, asset
        in assets.items()
        if (
            is_target_asset(
                asset,
                batch_ids,
            )
            and category_cn(asset)
            in WHITE_CATEGORIES
            and bool(
                asset.get(
                    "placeable",
                    True,
                )
            )
        )
    )

    stats = Counter()
    report_rows = []

    pending_writes = []

    for asset_id in target_ids:
        asset = assets[asset_id]

        category = category_cn(asset)

        image_rel = str(
            asset.get(
                "image",
                "",
            )
        )

        image_path = (
            REPO_ROOT / image_rel
        )

        if not image_path.is_file():
            report_rows.append({
                "asset_id": asset_id,
                "category": category,
                "image": image_rel,
                "removed": 0,
                "opaque_review": 0,
                "result": "MISSING_IMAGE",
            })

            stats["missing"] += 1
            continue

        before = Image.open(
            image_path
        ).convert("RGBA")

        after, removed, opaque_review = (
            cleaned_image(before)
        )

        result = "NO_CHANGE"

        if removed > 0:
            result = "CLEANED"

            preview_path = (
                WHITE_PREVIEW_DIR
                / (
                    asset_id
                    .replace(".", "_")
                    + ".png"
                )
            )

            composite_preview(
                before,
                after,
                preview_path,
            )

            pending_writes.append(
                (
                    asset_id,
                    image_path,
                    after,
                )
            )

            stats[
                f"cleaned_{category}"
            ] += 1

        if opaque_review > 0:
            stats[
                "opaque_review_assets"
            ] += 1

        stats[
            "removed_pixels"
        ] += removed

        stats[
            "opaque_review_pixels"
        ] += opaque_review

        report_rows.append({
            "asset_id": asset_id,
            "category": category,
            "image": image_rel,
            "removed": removed,
            "opaque_review":
                opaque_review,
            "result": result,
        })

    if args.apply:
        for (
            asset_id,
            image_path,
            after,
        ) in pending_writes:
            after.save(
                image_path,
                "PNG",
            )

            payload = image_path.read_bytes()

            digest = sha256_bytes(
                payload
            )

            asset = assets[
                asset_id
            ]

            # source_sha256 保留原始来源。
            # 输出文件 hash 更新。
            asset[
                "output_sha256"
            ] = digest

            asset[
                "thumbnail_source_sha256"
            ] = digest

            asset[
                "white_cleanup_policy_id"
            ] = (
                "edge_connected_"
                "semiwhite_v1"
            )

        save_json(
            CATALOG_PATH,
            catalog,
        )

    lines = [
        "# New Decor White Residue R3",
        "",
        (
            "TARGET_ASSETS = "
            f"{len(target_ids)}"
        ),
        (
            "REMOVED_PIXELS = "
            f"{stats['removed_pixels']}"
        ),
        (
            "OPAQUE_WHITE_REVIEW_ASSETS = "
            f"{stats['opaque_review_assets']}"
        ),
        (
            "OPAQUE_WHITE_REVIEW_PIXELS = "
            f"{stats['opaque_review_pixels']}"
        ),
        "",
        (
            "| category | asset_id | image | "
            "removed | opaque_review | result |"
        ),
        (
            "|---|---|---|---:|---:|---|"
        ),
    ]

    for row in report_rows:
        lines.append(
            "| "
            f"{row['category']} | "
            f"{row['asset_id']} | "
            f"{row['image']} | "
            f"{row['removed']} | "
            f"{row['opaque_review']} | "
            f"{row['result']} |"
        )

    WHITE_REPORT_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    WHITE_REPORT_PATH.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print(
        f"TARGET_ASSETS={len(target_ids)}"
    )
    print(
        "REMOVED_PIXELS="
        f"{stats['removed_pixels']}"
    )
    print(
        "OPAQUE_WHITE_REVIEW_ASSETS="
        f"{stats['opaque_review_assets']}"
    )
    print(
        "OPAQUE_WHITE_REVIEW_PIXELS="
        f"{stats['opaque_review_pixels']}"
    )

    if args.apply:
        print(
            "WHITE_RESIDUE_APPLY=OK"
        )
    else:
        print(
            "WHITE_RESIDUE_DRY_RUN=OK"
        )


if __name__ == "__main__":
    main()
