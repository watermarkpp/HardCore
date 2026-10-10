"""B24 helmet generator regressions."""
from __future__ import annotations
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
def test_premultiplied_resize_keeps_transparent_edge_colour_straight() -> None:
    cases = [("holy232", "tools/build_holy_war_helmet_232.py", "premultiplied_lanczos_resize"), ("taoist240", "tools/build_heavenly_taoist_helmet_240.py", "premultiplied_resize")]
    for name, path, helper_name in cases:
        module = load(name, path)
        source = Image.new("RGBA", (2, 1), (0, 0, 0, 0))
        source.putpixel((0, 0), (240, 80, 20, 128))
        result = getattr(module, helper_name)(source, (1, 1))
        red, green, blue, alpha = result.getpixel((0, 0))
        # A 2px -> 1px Lanczos sample has alpha ~= 64.  The straight colour
        # must remain the source colour after unassociation; the old RGBA
        # resize path produced the visibly bright (255, 155, 44) result.
        expected = (240, 80, 20, 64)
        actual = result.getpixel((0, 0))
        assert all(abs(actual[index] - expected[index]) <= 2 for index in range(4)), (
            name,
            actual,
        )
def test_generic_validator_enforces_identity_scale_at_build_variants(monkeypatch) -> None:
    module = load("male_world_b24", "tools/build_male_world_helmet_assets.py")
    assert module.minimum_calibration_scale_for_identity("god_magic") == 47
    assert module.minimum_calibration_scale_for_identity("holy_war") == 50
    recipes = json.loads(
        (ROOT / "assets/data/equipment_male_world_helmet_recipes.json").read_text(
            encoding="utf-8"
        )
    )
    # Keep the formal recipe/cutouts but use a tiny scratch Pillow baseline so
    # this test never regenerates or depends on the catalog output.
    scratch_direction = Image.new("RGBA", (64, 64), (240, 80, 20, 255))
    scratch_opaque_pixels = module.effective_opaque_pixels(scratch_direction)
    baseline = {
        "directionRuntimeTargetSize": {
            direction: list(scratch_direction.size)
            for direction in module.DIRECTIONS
        },
        "directionRuntimeOpaquePixels": {
            direction: scratch_opaque_pixels for direction in module.DIRECTIONS
        },
    }
    identities = {str(item["identityId"]): item for item in recipes["identities"]}
    # build_variants is the real production path; redirect only its generated
    # acceptance-artifact sink so the regression test cannot alter assets.
    monkeypatch.setattr(module, "save_deterministic_atlas", lambda *_args: None)
    god_magic = dict(identities["god_magic"])
    god_magic["calibrationBaseScalePercent"] = 47
    variants, records, acceptance = module.build_variants(god_magic, baseline)
    assert set(variants) == set(module.DIRECTIONS)
    assert set(records) == set(module.DIRECTIONS)
    assert acceptance["sourceGrid"] == god_magic["sourceGrid"]
    assert acceptance["sourceSlotDirectionOrder"] == god_magic["sourceSlotDirectionOrder"]

    for invalid_scale in (46, 201):
        invalid_god_magic = dict(god_magic)
        invalid_god_magic["calibrationBaseScalePercent"] = invalid_scale
        try:
            module.build_variants(invalid_god_magic, baseline)
        except ValueError as error:
            assert "between 47 and 200" in str(error)
        else:
            raise AssertionError(f"god_magic accepted invalid scale {invalid_scale}")

    holy_war = dict(identities["holy_war"])
    holy_war["calibrationBaseScalePercent"] = 47
    try:
        module.build_variants(holy_war, baseline)
    except ValueError as error:
        assert "between 50 and 200" in str(error)
    else:
        raise AssertionError("non-god_magic identity accepted 47 percent")

    result = subprocess.run([sys.executable, str(ROOT / "tools/build_male_world_helmet_assets.py"), "--validate-only"], cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert "EQUIPMENT_MALE_WORLD_HELMET_PASS" in result.stdout
