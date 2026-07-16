from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "dev_art_sources" / "ui" / "gothic_hud_v1" / "alpha_sources"
OUTPUT_ROOT = ROOT / "assets" / "ui" / "gothic_preview" / "frames"


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError("generated frame has no visible pixels")
    return bbox


def build_slot_frame() -> None:
    source_path = SOURCE_ROOT / "gothic_slot_frame_v1.png"
    output_path = OUTPUT_ROOT / "gothic_slot_frame_runtime_v1.png"
    image = Image.open(source_path).convert("RGBA")
    image = image.crop(alpha_bbox(image))
    width, height = image.size

    # The generated source contains a black preview window. Runtime icons need a
    # genuinely independent layer, so clear that window while preserving the
    # carved inset lip and the outer ornament.
    alpha = image.getchannel("A")
    hole = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(hole)
    draw.rounded_rectangle(
        (int(width * 0.205), int(height * 0.205), int(width * 0.795), int(height * 0.795)),
        radius=int(min(width, height) * 0.055),
        fill=255,
    )
    alpha.paste(0, mask=hole)
    image.putalpha(alpha)
    image = image.resize((96, 96), Image.Resampling.LANCZOS)
    image.save(output_path, optimize=True)
    print(f"GOTHIC_SLOT_FRAME={output_path}")


def build_chassis() -> None:
    source_path = SOURCE_ROOT / "bottom_hud_chassis_v1.png"
    output_path = OUTPUT_ROOT / "bottom_hud_chassis_runtime_v1.png"
    image = Image.open(source_path).convert("RGBA")
    image = image.crop(alpha_bbox(image))
    width, height = image.size
    canvas = Image.new("RGBA", (840, 180), (0, 0, 0, 0))

    # Preserve the circular bezel proportions and stretch only the thin bridge
    # sections. Scaling the full generated sheet at once makes both circles
    # elliptical or pulls them away from the actual resource-orb centers.
    left_ring = image.crop((0, 0, int(width * 0.33), height)).resize((205, 180), Image.Resampling.LANCZOS)
    right_ring = image.crop((int(width * 0.67), 0, width, height)).resize((205, 180), Image.Resampling.LANCZOS)
    left_bridge = image.crop((int(width * 0.20), int(height * 0.28), int(width * 0.51), int(height * 0.82))).resize((310, 96), Image.Resampling.LANCZOS)
    right_bridge = image.crop((int(width * 0.49), int(height * 0.28), int(width * 0.80), int(height * 0.82))).resize((310, 96), Image.Resampling.LANCZOS)

    canvas.alpha_composite(left_bridge, (135, 58))
    canvas.alpha_composite(right_bridge, (395, 58))
    canvas.alpha_composite(left_ring, (18, 0))
    canvas.alpha_composite(right_ring, (617, 0))
    canvas.save(output_path, optimize=True)
    print(f"GOTHIC_BOTTOM_CHASSIS={output_path}")


if __name__ == "__main__":
    build_slot_frame()
    build_chassis()
