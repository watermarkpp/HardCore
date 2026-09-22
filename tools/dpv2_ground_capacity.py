"""User-authorized 2026-09-13 post-RNG capacity; probabilities stay frozen.

This focused generator updates only capacity and its dependent file hashes.
It does not run the historical balance solver or rebuild authored drop rows.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

GROUND_SLOT_LIMIT = 15
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets/data/drop"


def focused_outputs() -> dict[Path, str]:
    outputs: dict[Path, str] = {}
    baseline = DATA / "dpv2_direct_baseline_v2.json"
    runtime = DATA / "dpv2_drop_runtime_authority_v1.json"
    for path, parent, key in [
        (baseline, "probability_policy", "post_rng_ground_slot_limit"),
        (runtime, "ground_overflow_policy", "maximum_ground_slots"),
    ]:
        original = path.read_text(encoding="utf-8")
        expected = copy.deepcopy(json.loads(original))
        assert type(expected[parent][key]) is int
        expected[parent][key] = GROUND_SLOT_LIMIT
        rendered, count = re.subn(r'("' + key + r'"\s*:\s*)\d+',
                                  lambda m: m[1] + str(GROUND_SLOT_LIMIT), original)
        assert count == 1 and json.loads(rendered) == expected, path
        outputs[path] = rendered
    digest = hashlib.sha256(outputs[baseline].encode("utf-8")).hexdigest().upper()
    manifest = DATA / "dpv2_direct_baseline_manifest_v2.json"
    original = manifest.read_text(encoding="utf-8")
    expected = json.loads(original)
    old_digest = expected["artifacts"]["direct_baseline_authority"]["sha256"]
    expected["artifacts"]["direct_baseline_authority"]["sha256"] = digest
    rendered = original.replace('"' + old_digest + '"', '"' + digest + '"')
    assert json.loads(rendered) == expected
    outputs[manifest] = rendered
    for name in ["dpv2_single_player_drop_boost_v1.json", "dpv2_single_player_effective_probability_v1.json"]:
        path = DATA / name
        original = path.read_text(encoding="utf-8")
        rendered, count = re.subn(r'("direct_baseline_sha256_raw"\s*:\s*")[A-Fa-f0-9]{64}(\")',
                                  lambda m: m[1] + digest + m[2], original)
        assert count == 1, path
        # Every non-binding field must remain byte-for-byte identical.
        outputs[path] = rendered
    seal = ROOT / "scripts/drop/dpv2_repair_v5_contract.gd"
    rendered = seal.read_text(encoding="utf-8")
    for constant, path in [
        ("AUTHORITY_SHA256", DATA / "dpv2_single_player_drop_boost_v1.json"),
        ("EFFECTIVE_SHA256", DATA / "dpv2_single_player_effective_probability_v1.json"),
        ("BASELINE_SHA256", baseline),
    ]:
        digest = hashlib.sha256(outputs[path].encode("utf-8")).hexdigest().upper()
        rendered, count = re.subn(r'(const ' + constant + r' := ")[A-Fa-f0-9]{64}(\")',
                                  lambda m: m[1] + digest + m[2], rendered)
        assert count == 1, constant
    outputs[seal] = rendered
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--write", action="store_true")
    modes.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = focused_outputs()
    if args.write:
        for path, rendered in outputs.items():
            path.write_text(rendered, encoding="utf-8", newline="\n")
    else:
        assert all(path.read_text(encoding="utf-8") == text for path, text in outputs.items()), "capacity/hash drift"
    print(f"DPV2_GROUND_CAPACITY_PASS cap={GROUND_SLOT_LIMIT} probabilities_and_priorities_unchanged=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
