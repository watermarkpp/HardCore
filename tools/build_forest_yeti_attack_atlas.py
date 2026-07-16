from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\Administrator\.codex\generated_images\019f0edc-1065-7ac2-a95d-1d3fba22251f")
SOURCES = {
    "south": GENERATED / "exec-443ad366-eb29-422d-8f37-8700e9e4203a.png",
    "southwest": GENERATED / "exec-8db67658-04b7-48be-9bd4-fb31011d1222.png",
    "west": GENERATED / "exec-49cb8822-c794-44e4-a24b-d5ac7e680695.png",
    "northwest": GENERATED / "exec-cc4aca85-4f5c-4441-bd98-b90875bea3fd.png",
    "north": GENERATED / "exec-3a43ace5-28fb-49c7-8a8f-7f9f23fca228.png",
}
OUT = PROJECT / "assets/art/monsters/bich/forest_yeti/forest_yeti_attack.png"
SOURCE_ARCHIVE = PROJECT / "dev_art_sources/monsters/bich/forest_yeti/generated_attack_v1"

CELL = 64
FRAMES = 6
DIRECTIONS = ("south", "southwest", "west", "northwest", "north", "northeast", "east", "southeast")
MIRRORS = {"northeast": "northwest", "east": "west", "southeast": "southwest"}


def chroma_key(source: Image.Image) -> Image.Image:
    image = source.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            # Generated backgrounds vary around (245, 4, 247), so RGB distance
            # from literal #ff00ff leaves a large opaque rectangle.  Photoshop's
            # Color Range behavior is better represented by magenta dominance.
            magenta_score = min(r, b) - g
            alpha = max(0, min(255, round((145.0 - magenta_score) * 255.0 / 95.0)))
            if alpha == 0:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            # Remove magenta spill from antialiased edge pixels.
            a = alpha / 255.0
            background_r = 248.0
            background_b = 248.0
            clean_r = max(0, min(255, round((r - (1.0 - a) * background_r) / a)))
            clean_g = max(0, min(255, round(g / a)))
            clean_b = max(0, min(255, round((b - (1.0 - a) * background_b) / a)))
            pixels[x, y] = (clean_r, clean_g, clean_b, alpha)
    return image


def keep_largest_component(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    width, height = image.size
    mask = alpha.point(lambda value: 255 if value >= 24 else 0)
    data = mask.load()
    seen: set[tuple[int, int]] = set()
    largest: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            if not data[x, y] or (x, y) in seen:
                continue
            queue = deque([(x, y)])
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while queue:
                px, py = queue.popleft()
                component.append((px, py))
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < width and 0 <= ny < height and data[nx, ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        queue.append((nx, ny))
            if len(component) > len(largest):
                largest = component
    if not largest:
        return image
    component_mask = Image.new("L", image.size, 0)
    component_pixels = component_mask.load()
    for x, y in largest:
        component_pixels[x, y] = 255
    # Slight dilation preserves the original soft outline around the connected body.
    from PIL import ImageFilter
    component_mask = component_mask.filter(ImageFilter.MaxFilter(5))
    original_alpha = image.getchannel("A")
    image.putalpha(Image.composite(original_alpha, Image.new("L", image.size, 0), component_mask))
    return image


def split_strip(path: Path) -> list[Image.Image]:
    source = Image.open(path).convert("RGBA")
    width, height = source.size
    frames: list[Image.Image] = []
    for index in range(FRAMES):
        left = round(index * width / FRAMES)
        right = round((index + 1) * width / FRAMES)
        frame = source.crop((left, 0, right, height))
        frame = keep_largest_component(chroma_key(frame))
        bbox = frame.getbbox()
        if bbox is None:
            raise RuntimeError(f"empty frame {path.name}:{index}")
        frames.append(frame.crop(bbox))
    return frames


def main() -> None:
    SOURCE_ARCHIVE.mkdir(parents=True, exist_ok=True)
    for direction, source in SOURCES.items():
        if not source.exists():
            raise FileNotFoundError(source)
        archived = SOURCE_ARCHIVE / f"forest_yeti_attack_{direction}_source.png"
        if not archived.exists():
            archived.write_bytes(source.read_bytes())

    base_frames = {direction: split_strip(source) for direction, source in SOURCES.items()}
    max_width = max(frame.width for frames in base_frames.values() for frame in frames)
    max_height = max(frame.height for frames in base_frames.values() for frame in frames)
    scale = min(60.0 / max_width, 59.0 / max_height)

    atlas = Image.new("RGBA", (CELL * FRAMES, CELL * len(DIRECTIONS)), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        source_direction = MIRRORS.get(direction, direction)
        mirror = direction in MIRRORS
        for column, raw in enumerate(base_frames[source_direction]):
            frame = raw.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirror else raw
            size = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
            frame = frame.resize(size, Image.Resampling.LANCZOS)
            # All feet end at y=60, and every pose is centered on x=32.
            x = column * CELL + (CELL - frame.width) // 2
            y = row * CELL + 60 - frame.height
            atlas.alpha_composite(frame, (x, y))

    # Final chroma-spill pass: generated antialiasing can leave isolated purple
    # pixels after keying.  The yeti palette contains no magenta, so removing
    # only pixels where both red and blue strongly dominate green is safe.
    atlas_pixels = atlas.load()
    for y in range(atlas.height):
        for x in range(atlas.width):
            r, g, b, a = atlas_pixels[x, y]
            if a and r - g > 34 and b - g > 34:
                strength = min(r - g, b - g)
                new_alpha = max(0, round(a * max(0.0, (78.0 - strength) / 44.0)))
                atlas_pixels[x, y] = (r, g, b, new_alpha)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT, optimize=True)
    print(f"WROTE {OUT}")
    print(f"SIZE {atlas.size} SCALE {scale:.6f} SOURCE_MAX {max_width}x{max_height}")


if __name__ == "__main__":
    main()
