from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets/art/characters/warrior/male"
SOURCE_DIR = ROOT / "dev_art_sources/characters/warrior/male"
IDLE_SOURCE = SOURCE_DIR / "warrior_turnaround_alpha.png"
IDLE_OUTPUT = ASSET_DIR / "warrior_idle.png"
WALK_SOURCE = SOURCE_DIR / "warrior_walk_key_alpha.png"
WALK_OUTPUT = ASSET_DIR / "warrior_walk.png"
ATTACK_SOURCE = SOURCE_DIR / "warrior_attack_key_alpha.png"
ATTACK_OUTPUT = ASSET_DIR / "warrior_attack.png"
HIT_SOURCE = SOURCE_DIR / "warrior_hit_key_alpha.png"
HIT_OUTPUT = ASSET_DIR / "warrior_hit.png"
DEATH_SOURCE = SOURCE_DIR / "warrior_death_key_alpha.png"
DEATH_OUTPUT = ASSET_DIR / "warrior_death.png"

FRAME = (64, 96)
FOOT_TARGET = (32, 80)
GRID = (4, 2)
SCALE = 0.17

# Source order: s, sw, w, nw, n, ne, e, se. Values are local cell foot anchors.
IDLE_FOOT_POINTS = [
    (215, 450), (205, 462), (146, 465), (160, 464),
    (215, 415), (171, 422), (141, 429), (120, 433),
]
WALK_FOOT_POINTS = [
    (200, 453), (218, 461), (223, 465), (224, 463),
    (196, 457), (196, 462), (160, 462), (151, 455),
]


def _open_source(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def _cell(source: Image.Image, direction: int) -> Image.Image:
    cell_width = source.width // GRID[0]
    cell_height = source.height // GRID[1]
    column = direction % GRID[0]
    row = direction // GRID[0]
    return source.crop((column * cell_width, row * cell_height, (column + 1) * cell_width, (row + 1) * cell_height))


def _composite_frame(atlas: Image.Image, frame_index: int, direction: int, source: Image.Image, foot_points: list[tuple[int, int]], bob: int = 0, shift_x: int = 0) -> None:
    cell = _cell(source, direction)
    cell_width = source.width // GRID[0]
    cell_height = source.height // GRID[1]
    scaled = cell.resize((round(cell_width * SCALE), round(cell_height * SCALE)), Image.Resampling.LANCZOS)
    foot_x, foot_y = foot_points[direction]
    paste_x = round(FOOT_TARGET[0] - foot_x * SCALE + shift_x)
    paste_y = round(FOOT_TARGET[1] - foot_y * SCALE + bob)
    atlas.alpha_composite(scaled, (frame_index * FRAME[0] + paste_x, direction * FRAME[1] + paste_y))


def _auto_foot_points(source: Image.Image) -> list[tuple[int, int]]:
    points: list[tuple[int, int]] = []
    for direction in range(8):
        cell = _cell(source, direction)
        alpha = cell.getchannel("A")
        box = alpha.getbbox()
        if box is None:
            raise ValueError(f"empty directional source cell: {direction}")
        bottom = box[3] - 1
        xs: list[int] = []
        for y in range(max(box[1], bottom - 12), bottom + 1):
            for x in range(box[0], box[2]):
                if alpha.getpixel((x, y)) >= 96:
                    xs.append(x)
        foot_x = round(sum(xs) / len(xs)) if xs else round((box[0] + box[2]) / 2)
        points.append((foot_x, bottom))
    return points


def _bbox_bottom_points(source: Image.Image) -> list[tuple[int, int]]:
    points: list[tuple[int, int]] = []
    for direction in range(8):
        box = _cell(source, direction).getchannel("A").getbbox()
        if box is None:
            raise ValueError(f"empty directional source cell: {direction}")
        points.append((round((box[0] + box[2]) / 2), box[3] - 1))
    return points


def build_idle() -> None:
    source = _open_source(IDLE_SOURCE)
    atlas = Image.new("RGBA", (FRAME[0] * 4, FRAME[1] * 8), (0, 0, 0, 0))
    idle_offsets = [0, -1, 0, 1]
    for direction in range(8):
        for frame, bob in enumerate(idle_offsets):
            _composite_frame(atlas, frame, direction, source, IDLE_FOOT_POINTS, bob)
    IDLE_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(IDLE_OUTPUT)
    print(f"WARRIOR_IDLE_ATLAS={IDLE_OUTPUT} SIZE={atlas.size}")


def build_walk() -> None:
    idle_source = _open_source(IDLE_SOURCE)
    walk_source = _open_source(WALK_SOURCE)
    atlas = Image.new("RGBA", (FRAME[0] * 8, FRAME[1] * 8), (0, 0, 0, 0))
    # Eight runtime frames are required by ArtSpec. The two approved key poses are
    # alternated with small anchor shifts to form a stable, symmetrical gait loop.
    frame_plan = [
        (idle_source, IDLE_FOOT_POINTS, 1, 0),
        (walk_source, WALK_FOOT_POINTS, 0, -1),
        (walk_source, WALK_FOOT_POINTS, -1, 0),
        (idle_source, IDLE_FOOT_POINTS, 0, 1),
        (idle_source, IDLE_FOOT_POINTS, 1, 0),
        (walk_source, WALK_FOOT_POINTS, 0, 1),
        (walk_source, WALK_FOOT_POINTS, -1, 0),
        (idle_source, IDLE_FOOT_POINTS, 0, -1),
    ]
    for direction in range(8):
        direction_sign = -1 if direction in [1, 2, 3] else 1 if direction in [5, 6, 7] else 0
        for frame, (source, anchors, bob, stride) in enumerate(frame_plan):
            _composite_frame(atlas, frame, direction, source, anchors, bob, stride * direction_sign)
    WALK_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(WALK_OUTPUT)
    print(f"WARRIOR_WALK_ATLAS={WALK_OUTPUT} SIZE={atlas.size}")


def build_attack() -> None:
    idle_source = _open_source(IDLE_SOURCE)
    attack_source = _open_source(ATTACK_SOURCE)
    attack_feet = _auto_foot_points(attack_source)
    atlas = Image.new("RGBA", (FRAME[0] * 6, FRAME[1] * 8), (0, 0, 0, 0))
    # Six-frame one-shot: ready, wind-up, contact, follow-through, recover, ready.
    frame_plan = [
        (idle_source, IDLE_FOOT_POINTS, 0, 0),
        (attack_source, attack_feet, 0, -1),
        (attack_source, attack_feet, -1, 0),
        (attack_source, attack_feet, 0, 1),
        (idle_source, IDLE_FOOT_POINTS, 0, 1),
        (idle_source, IDLE_FOOT_POINTS, 0, 0),
    ]
    for direction in range(8):
        direction_sign = -1 if direction in [1, 2, 3] else 1 if direction in [5, 6, 7] else 0
        for frame, (source, anchors, bob, lunge) in enumerate(frame_plan):
            _composite_frame(atlas, frame, direction, source, anchors, bob, lunge * direction_sign)
    ATTACK_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(ATTACK_OUTPUT)
    print(f"WARRIOR_ATTACK_ATLAS={ATTACK_OUTPUT} SIZE={atlas.size}")


def build_hit() -> None:
    idle_source = _open_source(IDLE_SOURCE)
    hit_source = _open_source(HIT_SOURCE)
    hit_feet = _auto_foot_points(hit_source)
    atlas = Image.new("RGBA", (FRAME[0] * 3, FRAME[1] * 8), (0, 0, 0, 0))
    for direction in range(8):
        _composite_frame(atlas, 0, direction, idle_source, IDLE_FOOT_POINTS)
        _composite_frame(atlas, 1, direction, hit_source, hit_feet, 1)
        _composite_frame(atlas, 2, direction, idle_source, IDLE_FOOT_POINTS)
    HIT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(HIT_OUTPUT)
    print(f"WARRIOR_HIT_ATLAS={HIT_OUTPUT} SIZE={atlas.size}")


def build_death() -> None:
    idle_source = _open_source(IDLE_SOURCE)
    hit_source = _open_source(HIT_SOURCE)
    death_source = _open_source(DEATH_SOURCE)
    hit_feet = _auto_foot_points(hit_source)
    death_ground = _bbox_bottom_points(death_source)
    atlas = Image.new("RGBA", (FRAME[0] * 6, FRAME[1] * 8), (0, 0, 0, 0))
    for direction in range(8):
        _composite_frame(atlas, 0, direction, idle_source, IDLE_FOOT_POINTS)
        _composite_frame(atlas, 1, direction, hit_source, hit_feet, 1)
        _composite_frame(atlas, 2, direction, hit_source, hit_feet, 5)
        _composite_frame(atlas, 3, direction, death_source, death_ground)
        _composite_frame(atlas, 4, direction, death_source, death_ground, 1)
        _composite_frame(atlas, 5, direction, death_source, death_ground, 1)
    DEATH_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(DEATH_OUTPUT)
    print(f"WARRIOR_DEATH_ATLAS={DEATH_OUTPUT} SIZE={atlas.size}")


def build() -> None:
    build_idle()
    build_walk()
    build_attack()
    build_hit()
    build_death()


if __name__ == "__main__":
    build()
