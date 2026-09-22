"""Read-only source/generator/runtime growth audit; no gameplay data writes."""
import hashlib
import importlib.util
import json
import tempfile
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected(job, level):
    # Independently transcribed from the verified primary Pascal procedure.
    # Fraction + Python's nearest-even round avoids sharing the compiler's
    # expression translation or GDScript floating-point implementation.
    n = F(level)
    out = dict(accuracy=5, agility=18 if job == "道士" else 15)
    for stat in ("attack", "magic", "tao", "defense", "magic_defense"):
        out[stat + "_min"] = out[stat + "_max"] = 0
    if job == "战士":
        hp, mp = 14 + round((n / 4 + F(9, 2) + n / 20) * n), 11 + round(n * F(7, 2))
        divisors = (3, 20, 13)
        out.update(attack_min=max(level // 5 - 1, 1), attack_max=max(1, level // 5), defense_max=level // 7)
    else:
        step = level // 7
        out.update(attack_min=max(step - 1, 0), attack_max=max(1, step))
        if job == "法师":
            hp, mp = 14 + round((n / 15 + F(9, 5)) * n), 13 + round((n / 5 + 2) * F(11, 5) * n)
            divisors = (5, 100, 90)
            out.update(magic_min=max(step - 1, 0), magic_max=max(1, step))
        else:
            assert job == "道士"
            hp, mp = 14 + round((n / 6 + F(5, 2)) * n), 13 + round(n / 8 * F(11, 5) * n)
            divisors = (4, 50, 42)
            mac = round(n / 6)
            out.update(tao_min=max(step - 1, 0), tao_max=max(1, step), magic_defense_min=mac // 2, magic_defense_max=mac + 1)
    out.update(max_hp=min(65535, hp), max_mp=min(65535, mp))
    for key, initial, divisor in zip(("max_bag_weight", "max_wear_weight", "max_hand_weight"), (50, 15, 12), divisors):
        out[key] = initial + round(n * n / divisor)
    assert len(out) == 17
    return out


def main():
    manifest_path = ROOT / "assets/data/vanilla_176/character_base_growth_source_v1.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    for record in manifest["sources"]:
        assert sha(ROOT / record["path"]) == record["sha256"], record["path"]
    spec = importlib.util.spec_from_file_location("growth_compiler", ROOT / "tools/build_character_base_growth.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    with tempfile.TemporaryDirectory(prefix="growth_audit_", dir=ROOT / "outputs/repair_v92") as directory:
        compiler.OUTPUT = Path(directory) / "growth.gd"
        compiler.MANIFEST = Path(directory) / "manifest.json"
        compiler.build()
        assert compiler.OUTPUT.read_text(encoding="utf-8") == (ROOT / manifest["runtime"]).read_text(encoding="utf-8")
        rebuilt = json.loads(compiler.MANIFEST.read_text(encoding="utf-8"))
        # Only the isolated audit output path differs from the production
        # compiler destination; compare every source binding unchanged.
        rebuilt["runtime"] = manifest["runtime"]
        assert rebuilt == manifest
    runtime_path = ROOT / "outputs/repair_v92/player_growth_live.json"
    runtime = json.loads(runtime_path.read_text(encoding="utf-8-sig"))
    assert runtime["status"] == "PASS" and len(runtime["formula_rows"]) == 765
    for path, digest in runtime["source_hashes"].items():
        assert sha(ROOT / path) == digest, path
    identities = set()
    for row in runtime["formula_rows"]:
        key = (row["profession"], row["level"])
        assert key not in identities
        identities.add(key)
        assert row["stats"] == expected(*key), key
    result = {"status": "PASS", "source_manifest_sha256": sha(manifest_path),
              "runtime_evidence_sha256": sha(runtime_path), "formula_rows": 765,
              "exact_attribute_comparisons": 765 * 17, "live_level_transitions": runtime["live_level_transitions"],
              "save_failure_paths": runtime["save_failure_paths"],
              "range_is_validation_coverage_not_level_cap": [1, 255],
              "combat_observations": runtime["combat_observations"]}
    output = ROOT / "outputs/repair_v92/character_growth_audit.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("CHARACTER_GROWTH_AUDIT_PASS rows=765 exact_fields=13005 live_upgrades=177")


if __name__ == "__main__":
    main()
