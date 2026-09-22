"""Serial A/B runtime sampling; temporarily replace only two controller-owned files.
Candidates are byte-backed up and restored in finally before returning. No Git
mutation, no data/asset changes, no overlapping runners. Run from project root.
"""
import hashlib
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "outputs" / "performance_v82"
BASE = "643d4185cfb3c67f86c0821d5c2393ba0c1581e2"
PATHS = ("scripts/enemy.gd", "scripts/caster_skill_visual_registry.gd")
def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modes", default="crowd,aoe", choices=("crowd", "aoe", "crowd,aoe"))
    parser.add_argument("--prefix", default="v82_ab")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    candidate = {p: (ROOT / p).read_bytes() for p in PATHS}
    baseline = {p: subprocess.check_output(["git", "show", BASE + ":" + p], cwd=ROOT) for p in PATHS}
    receipt = {"baseline_commit": BASE,
               "candidate_sha256": {p: digest(b) for p, b in candidate.items()}, "runs": []}
    for p, b in candidate.items():
        (OUT / ("candidate_backup_" + Path(p).name)).write_bytes(b)
    (OUT / (args.prefix + "_inputs.json")).write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    try:
        for round_id in range(1, 4):
            for mode in args.modes.split(","):
                for version in ("baseline", "candidate"):
                    files = baseline if version == "baseline" else candidate
                    for p, data in files.items():
                        (ROOT / p).write_bytes(data)
                    label = f"{args.prefix}_{mode}_{version}_r{round_id}"
                    env = os.environ.copy()
                    env.update(HARDCORE_REV07_LABEL=label, HARDCORE_REV07_HEAD=BASE + ":" + version,
                               HARDCORE_REV07_COUNTS="30", HARDCORE_V82_DETAIL_PROBE="0",
                               HARDCORE_V82_FIRE_WALL="1" if mode == "aoe" else "0",
                               HARDCORE_REV07_SCENARIOS="sustained_close_attacks" if mode == "aoe" else
                               "open_pursuit,sustained_close_attacks,dense_crowd")
                    print("V82_AB_BEGIN", label, flush=True)
                    result = subprocess.run(["powershell", "-NoProfile", "-File",
                        "tools/run_godot_tests.ps1", "-TestPaths",
                        "tests/hc_monster_ai/m30_sampling_copy.tscn", "-TimeoutSeconds", "60"],
                        cwd=ROOT, env=env)
                    receipt["runs"].append({"label": label, "exit_code": result.returncode})
                    if result.returncode != 0:
                        raise RuntimeError("Failed measurement: " + label)
    finally:
        for p, data in candidate.items():
            (ROOT / p).write_bytes(data)
        receipt["candidate_restored"] = all((ROOT / p).read_bytes() == data for p, data in candidate.items())
        (OUT / (args.prefix + "_receipt.json")).write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print("V82_AB_CANDIDATE_RESTORED", receipt["candidate_restored"], flush=True)

if __name__ == "__main__":
    main()
