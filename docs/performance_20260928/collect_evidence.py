"""Freeze this serial bugfix's existing results; does not run/alter tests."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "evidence"
OUT.mkdir(exist_ok=True)
logs = ROOT / "outputs/test_logs"
runners = sorted(p for p in logs.glob("runner_results_adhoc_20260928_*.json")
                 if p.name >= "runner_results_adhoc_20260928_221000")
latest = {}
for path in runners:
    doc = json.loads(path.read_text(encoding="utf-8-sig"))
    shutil.copy2(path, OUT / path.name)
    for result in doc["results"]:
        latest[result["test_path"]] = dict(result, runner=path.name)
for result in latest.values():
    for suffix in ("stdout.log", "stderr.log", "godot.log"):
        name = result["test_name"] + "." + suffix
        if (logs / name).is_file():
            shutil.copy2(logs / name, OUT / name)
assert all(r["result"] == "PASS" and not r["timeout"] for r in latest.values())
(OUT / "latest_results.json").write_text(json.dumps(sorted(latest.values(), key=lambda r:r["test_path"]),
    indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
for source, dest in [("outputs/async_ui_20260928/warehouse_before.json", "warehouse_before.json"),
                     ("outputs/test_logs/warehouse_prepared_latency.json", "warehouse_after.json")]:
    shutil.copy2(ROOT / source, OUT / dest)
paths = subprocess.check_output(["git", "diff", "21b40ddae663997f8e9f267585988e6a7c63db6a", "--name-only"], cwd=ROOT, text=True).splitlines()
paths += ["scripts/warehouse_commit_operation.gd", "scripts/world_camera_follow.gd"]
hashes = {}
for name in sorted(set(paths)):
    if name.startswith(("scripts/", "tests/", "tools/")) and name != "tests/cangyue_area_test.gd":
        data = (ROOT / name).read_bytes().replace(b"\r\n", b"\n")
        hashes[name] = hashlib.sha256(data).hexdigest()
(OUT / "verified_source_sha256_lf.json").write_text(json.dumps(hashes, indent=2)+"\n", encoding="utf-8")
protected = ["assets", "map_editor_workspace", "project.godot", "export_presets.cfg"]
assert not subprocess.check_output(["git", "diff", "HEAD", "--name-only", "--", *protected], cwd=ROOT).strip()
print(json.dumps({"latest_unique_tests":len(latest), "result":"PASS", "source_files":len(hashes),
                  "protected_tracked_paths_unchanged":protected}))
