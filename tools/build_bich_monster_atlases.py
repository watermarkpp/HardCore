from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
FRAME = (64, 64)
FOOT = (32, 52)
GRID = (4, 2)

MONSTERS = {
    "strawman": (
        ROOT / "dev_art_sources/monsters/bich/strawman/strawman_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bich/strawman",
    ),
    "rake_cat": (
        ROOT / "dev_art_sources/monsters/bich/rake_cat/rake_cat_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bich/rake_cat",
    ),
    "half_orc": (
        ROOT / "dev_art_sources/monsters/bich/half_orc/half_orc_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bich/half_orc",
    ),
    "forest_yeti": (
        ROOT / "dev_art_sources/monsters/bich/forest_yeti/forest_yeti_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bich/forest_yeti",
    ),
    "cannibal_flower": (
        ROOT / "dev_art_sources/monsters/bich/cannibal_flower/cannibal_flower_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bich/cannibal_flower",
    ),
}

BOSSES = {
    "skeleton_spirit": (
        ROOT / "dev_art_sources/monsters/bosses/skeleton_spirit/skeleton_spirit_turnaround_alpha.png",
        ROOT / "assets/art/monsters/bosses/skeleton_spirit",
    ),
}

STATE_PLANS = {
    "idle": [
        {"bob": 0}, {"bob": -1}, {"bob": 0}, {"bob": 1},
    ],
    "walk": [
		{"bob": 1}, {"bob": 0}, {"bob": -1}, {"bob": 0},
		{"bob": 1}, {"bob": 0}, {"bob": -1}, {"bob": 0},
    ],
    "attack": [
		{"scale_x": 1.0, "scale_y": 1.0, "shift": 0},
		{"scale_x": 0.96, "scale_y": 1.04, "shift": -2},
		{"scale_x": 1.08, "scale_y": 0.96, "shift": 5, "bob": -1},
		{"scale_x": 1.15, "scale_y": 0.90, "shift": 10, "bob": 1},
		{"scale_x": 1.06, "scale_y": 0.96, "shift": 5},
		{"scale_x": 1.0, "scale_y": 1.0, "shift": 0},
    ],
    "hit": [
        {"shift": 0}, {"shift": -3, "tint": 0.34, "bob": 1}, {"shift": 0},
    ],
    "death": [
        {"angle": 0, "scale_y": 1.0}, {"angle": 5, "scale_y": 0.98, "bob": 1},
        {"angle": 15, "scale_y": 0.92, "bob": 3}, {"angle": 30, "scale_y": 0.80, "bob": 5},
        {"angle": 55, "scale_y": 0.62, "bob": 7}, {"angle": 78, "scale_y": 0.45, "bob": 8},
    ],
}


def _cells(source: Image.Image) -> list[Image.Image]:
    width = source.width // GRID[0]
    height = source.height // GRID[1]
    result: list[Image.Image] = []
    for direction in range(8):
        column = direction % GRID[0]
        row = direction // GRID[0]
        cell = source.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
        box = cell.getchannel("A").getbbox()
        if box is None:
            raise ValueError(f"empty cell at direction {direction}")
        result.append(cell.crop(box))
    return result


def _base_scale(cells: list[Image.Image], maximum_width: int, maximum_height: int) -> float:
    widest = max(cell.width for cell in cells)
    tallest = max(cell.height for cell in cells)
    return min(float(maximum_width) / widest, float(maximum_height) / tallest)


def _render(cell: Image.Image, base_scale: float, direction: int, params: dict, frame_size: tuple[int, int], foot: tuple[int, int]) -> Image.Image:
    direction_sign = -1 if direction in [1, 2, 3] else 1 if direction in [5, 6, 7] else 1
    scale_x = float(params.get("scale_x", 1.0))
    scale_y = float(params.get("scale_y", 1.0))
    size = (
        max(1, round(cell.width * base_scale * scale_x)),
        max(1, round(cell.height * base_scale * scale_y)),
    )
    image = cell.resize(size, Image.Resampling.LANCZOS)
    tint = float(params.get("tint", 0.0))
    if tint > 0.0:
        alpha = image.getchannel("A")
        overlay = Image.new("RGBA", image.size, (255, 62, 38, 255))
        image = Image.blend(image, overlay, tint)
        image.putalpha(alpha)
    angle = float(params.get("angle", 0.0)) * direction_sign
    if angle != 0.0:
        image = image.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    opacity = float(params.get("opacity", 1.0))
    if opacity < 1.0:
        image.putalpha(image.getchannel("A").point(lambda value: round(value * opacity)))
    shift = round(float(params.get("shift", 0.0)) * direction_sign)
    bob = round(float(params.get("bob", 0.0)))
    frame = Image.new("RGBA", frame_size, (0, 0, 0, 0))
    x = foot[0] - image.width // 2 + shift
    y = foot[1] - image.height + bob
    frame.alpha_composite(image, (x, y))
    return frame


def build_monster(
    slug: str,
    source_path: Path,
    output_dir: Path,
    frame_size: tuple[int, int] = FRAME,
    foot: tuple[int, int] = FOOT,
    maximum_width: int = 54,
    maximum_height: int = 56,
) -> None:
    source = Image.open(source_path).convert("RGBA")
    cells = _cells(source)
    scale = _base_scale(cells, maximum_width, maximum_height)
    output_dir.mkdir(parents=True, exist_ok=True)
    for state, plan in STATE_PLANS.items():
        atlas = Image.new("RGBA", (frame_size[0] * len(plan), frame_size[1] * 8), (0, 0, 0, 0))
        for direction, cell in enumerate(cells):
            for frame_index, params in enumerate(plan):
                frame = _render(cell, scale, direction, params, frame_size, foot)
                atlas.alpha_composite(frame, (frame_index * frame_size[0], direction * frame_size[1]))
        output = output_dir / f"{slug}_{state}.png"
        atlas.save(output)
        print(f"MONSTER_ATLAS={output} SIZE={atlas.size}")


def build() -> None:
    for slug, (source, output_dir) in MONSTERS.items():
        build_monster(slug, source, output_dir)
    for slug, (source, output_dir) in BOSSES.items():
        build_monster(slug, source, output_dir, (128, 128), (64, 108), 116, 114)


if __name__ == "__main__":
    build()
