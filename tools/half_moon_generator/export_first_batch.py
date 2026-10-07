"""Export the saved first 12 candidates as a labeled animated comparison."""

from pathlib import Path

from PIL import Image, ImageDraw

from tools.half_moon_generator import hmg


def export(project_path: Path = hmg.PROJECT_PATH) -> tuple[Path, Path]:
    project = hmg.load_project(project_path)
    curated = next((g for g in project["generations"] if g.get("kind") == "sw_reference_v3" and
                    g.get("curated")), None)
    if curated is None:
        curated = next((g for g in project["generations"] if g.get("kind") == "temporal_120_v2" and
                        g.get("curated")), None)
    if curated is None:
        curated = next((g for g in project["generations"] if g.get("kind") == "curated_a_b_c"),
                       project["generations"][0])
    ids = curated["candidate_ids"]
    if len(ids) != 12:
        raise ValueError("First generation must contain twelve candidates")
    with Image.open(hmg.ROOT / "assets/art/maps/bich/editor_runtime_chunks/c_2_1.png") as source:
        ground = source.convert("RGBA").crop((392, 400, 632, 624))
    direction = 1 if curated.get("kind") == "sw_reference_v3" else 0
    strips = [hmg.composite_strip(project["candidates"][candidate_id], direction, "sword")
              for candidate_id in ids]
    frames = []
    for frame in range(hmg.FRAMES):
        board = Image.new("RGBA", (960, 3 * 250), (20, 24, 23, 255))
        draw = ImageDraw.Draw(board)
        for index, candidate_id in enumerate(ids):
            x = index % 4 * 240
            y = index // 4 * 250
            cell = ground.copy()
            cell.alpha_composite(strips[index].crop((frame * 240, 0, (frame + 1) * 240, 224)))
            board.paste(cell, (x, y + 26))
            label = candidate_id.split("_")[-1]
            draw.text((x + 10, y + 6), f"{label}  {project['candidates'][candidate_id]['preset']}",
                      fill=(231, 195, 137, 255))
        frames.append(board)
    hmg.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = ("sw_reference_12" if curated.get("kind") == "sw_reference_v3" else
            "temporal_120_12" if curated.get("kind") == "temporal_120_v2" else
            "first_batch_12")
    still_frame = 3 if curated.get("kind") == "sw_reference_v3" else 4
    still = (hmg.OUTPUT_DIR / f"{stem}_f{still_frame}.png").resolve()
    animation = (hmg.OUTPUT_DIR / f"{stem}.gif").resolve()
    frames[still_frame].save(still)
    frames[0].save(animation, save_all=True, append_images=frames[1:],
                   duration=130, loop=0, disposal=2, optimize=False)
    return still, animation


if __name__ == "__main__":
    print(*export(), sep="\n")
