"""Run the repository runner and bind immutable evidence to actual file bytes."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def command(*args):
    return subprocess.check_output(args, cwd=ROOT).decode("utf-8", errors="replace").strip()
def fingerprint():
    files = {}
    for name in ("scripts", "tests", "scenes", "assets/data", "shaders"):
        for p in sorted((ROOT / name).rglob("*")):
            if p.is_file() and p.suffix.lower() in {".gd", ".tscn", ".tres", ".json", ".gdshader"}:
                files[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    for name in ("project.godot", "tools/run_godot_tests.ps1", "tools/source176_r3_validation.py"):
        files[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    for name in ("tools/test_framework_receipt.ps1",):
        if (ROOT / name).is_file():
            files[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    engine = ROOT / "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
    return {"time_utc": datetime.now(timezone.utc).isoformat(), "tested_sha": command("git", "rev-parse", "HEAD"),
            "branch": command("git", "branch", "--show-current"), "dirty": command("git", "status", "--short"),
            "files": files, "content_set_sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
            "engine_version": command(str(engine), "--version"), "engine_sha256": hashlib.sha256(engine.read_bytes()).hexdigest()}
def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("label")
    ap.add_argument("--suite")
    ap.add_argument("--tests", nargs="+")
    ap.add_argument("--timeout", type=int, default=30)
    args = ap.parse_args()
    if bool(args.suite) == bool(args.tests):
        ap.error("select exactly one of --suite and --tests")
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.label):
        ap.error("invalid label")
    dest = ROOT / "outputs/r3_takeover/20260930/validation" / (args.label + "_" + datetime.now().strftime("%H%M%S_%f"))
    dest.mkdir(parents=True)
    before = fingerprint()
    write(dest / "before.json", before)
    env = os.environ.copy()
    env["HARDCORE_R3_TESTED_SHA"] = before["tested_sha"]
    env["HARDCORE_R3_CONTENT_SHA256"] = before["content_set_sha256"]
    # Fixed shell script takes literal arguments. No user text evaluated as code.
    runner = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
              "& './tools/run_godot_tests.ps1' " + ("-Suite '"+args.suite+"'" if args.suite else
              "-TestPaths " + ",".join("'"+p+"'" for p in args.tests)) + " -TimeoutSeconds " + str(args.timeout)]
    for p in ([args.suite] if args.suite else args.tests):
        if not re.fullmatch(r"[a-zA-Z0-9_./-]+", p):
            ap.error("invalid suite/path")
    with (dest / "runner.log").open("wb") as log:
        result = subprocess.run(runner, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    raw = (dest / "runner.log").read_text(encoding="utf-8-sig", errors="replace")
    matches = re.findall(r"RUNNER_RESULTS_JSON=(.+)", raw)
    report = {}
    if matches:
        source = Path(matches[-1].strip())
        shutil.copy2(source, dest / "runner_results.json")
        report = json.loads(source.read_text(encoding="utf-8-sig"))
        for row in report.get("results", []):
            name = row.get("name", row.get("test_name", ""))
            for p in (ROOT / "outputs/test_logs").glob(name+".*.log"):
                (dest / "raw").mkdir(exist_ok=True)
                shutil.copy2(p, dest / "raw" / p.name)
    trace_root = ROOT / "outputs/test_logs/source176_r3"
    if trace_root.exists():
        shutil.copytree(trace_root, dest / "traces")
    # Copy only outputs owned by tests in this invocation; unrelated stale
    # feedback traces must not become evidence for the current run.
    feedback_outputs = {
        "consumable_icon_surfaces_test": "consumable_icon_surfaces.json",
        "player_blocked_locomotion_test": "player_blocked_locomotion.json",
        "monster_blocked_locomotion_test": "monster_blocked_locomotion.json",
        "warrior_toggle_camera_native_test": "warrior_toggle_camera_native.json",
        "surround_vacancy_refill_test": "surround_vacancy_refill.json",
        "full_surround_native_test": "full_surround_one_side_24.json",
        "full_surround_prefilled_test": "full_surround_prefilled_24.json",
        "full_surround_64_test": "full_surround_one_side_64.json",
        "full_surround_89_test": "full_surround_one_side_89.json",
        "full_surround_89_prefilled_test": "full_surround_prefilled_89.json",
        "full_surround_mixed_test": "full_surround_one_side_24_fractional_mixed.json",
        "full_surround_moving_test": "full_surround_one_side_89_moving.json",
        "full_surround_west_wall_test": "full_surround_one_side_24_west_wall.json",
        "full_surround_89_fractional_test": "full_surround_one_side_89_fractional.json",
        "full_surround_24_fractional_test": "full_surround_one_side_24_fractional.json",
        "surround_vacancy_refill_89_test": "surround_vacancy_refill_89.json",
        "crowd_recovery_test": "crowd_recovery_24_2.json",
        "crowd_recovery_4_test": "crowd_recovery_64_4.json",
        "crowd_recovery_8_test": "crowd_recovery_89_8.json",
        "crowd_recovery_30_test": "crowd_recovery_24_30.json",
    }
    invocation_start = datetime.fromisoformat(before["time_utc"]).timestamp()
    for row in report.get("results", []):
        feedback_name = feedback_outputs.get(row.get("test_name", ""))
        if feedback_name:
            source = ROOT / "outputs/test_logs" / feedback_name
            if source.exists() and source.stat().st_mtime >= invocation_start:
                (dest / "feedback").mkdir(exist_ok=True)
                shutil.copy2(source, dest / "feedback" / source.name)
    for row in report.get("results", []):
        if not row.get("test_path", "").startswith("tests/framework/"):
            continue
        source = ROOT / "outputs/test_logs/framework" / (row["test_name"] + ".result.json")
        if source.is_file() and source.stat().st_mtime >= invocation_start:
            (dest / "framework").mkdir(exist_ok=True)
            shutil.copy2(source, dest / "framework" / source.name)
    # Archive only this invocation's runner-owned association and producer
    # artifacts. A failed live run may leave older files, which are not proof.
    owned = ROOT / "outputs/test_logs/framework"
    handoff_path = owned / "native_handoffs.json"
    if handoff_path.is_file():
        handoff = json.loads(handoff_path.read_text(encoding="utf-8-sig"))
        if handoff.get("invocation_id") == report.get("invocation_id"):
            (dest / "framework").mkdir(exist_ok=True)
            shutil.copy2(handoff_path, dest / "framework" / handoff_path.name)
    for row in report.get("results", []):
        for suffix, id_field in (("_trace.json", "run_id"), ("_expected.json", "producer_run_id")):
            source = owned / (row["test_name"].removesuffix("_test") + suffix)
            if source.is_file():
                artifact = json.loads(source.read_text(encoding="utf-8-sig"))
                if artifact.get(id_field) == row.get("framework_run_id"):
                    (dest / "framework").mkdir(exist_ok=True)
                    shutil.copy2(source, dest / "framework" / source.name)
    after = fingerprint()
    write(dest / "after.json", after)
    stable = before["files"] == after["files"] and before["engine_sha256"] == after["engine_sha256"]
    summary = {"command": runner, "timeout_seconds": args.timeout, "exit_code": result.returncode,
               "source_stable_during_run": stable, "passed": report.get("passed"), "failed": report.get("failed"),
               "status": "PASS" if stable and result.returncode == 0 and report.get("failed") == 0 else "FAIL"}
    write(dest / "validation.json", summary)
    print(json.dumps({"evidence": str(dest), **summary}, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 1
if __name__ == "__main__":
    raise SystemExit(main())
