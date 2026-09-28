"""Verify the full APK inherits v94 + its installed patch and this source."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--apk", type=Path, required=True)
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--stage", type=Path, required=True)
parser.add_argument("--commit", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*params):
    return subprocess.check_output(["git", *params], cwd=ROOT)

patch = json.loads((ROOT / "docs/performance_20260928/evidence/previous_installed_patch.json").read_text())
for ancestor in (patch["baseCommit"], patch["patchCommit"]):
    subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, args.commit], cwd=ROOT, check=True)
patch_path = ROOT / "outputs/device_hotpatch_20260928" / patch["file"]
assert sha(patch_path.read_bytes()).upper() == patch["sha256"]
spec = importlib.util.spec_from_file_location("pck_verifier", ROOT / "tools/hotfix_patch_closure_verify.py")
pck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pck)
parsed = pck.parse_pck(patch_path, verify_payload_md5=True)
assert not parsed["payload_md5_mismatches"] and not parsed["duplicate_paths"]
old_rows = {r["path"]:r for r in parsed["rows"] if r["flags"] == 0}
changed = git("diff", "--name-only", patch["baseCommit"], args.commit, "--", "scripts").decode().splitlines()
scripts = []
unchanged_patch_scripts = []
with zipfile.ZipFile(args.apk, metadata_encoding="utf-8") as apk, zipfile.ZipFile(args.baseline, metadata_encoding="utf-8") as base:
    assert apk.testzip() is None
    names = set(apk.namelist())
    assert len(names) == len(apk.namelist()), "duplicate APK entries"
    assert not any(n.startswith(("assets/tests/", "assets/docs/", "assets/tools/")) for n in names)
    info = json.loads(apk.read("assets/assets/generated/build_info.json").rstrip(b"\0"))
    assert info["git_head"] == args.commit and info["git_dirty"] is False
    assert info["version_code"] == 95
    old_info = json.loads(base.read("assets/assets/generated/build_info.json").rstrip(b"\0"))
    assert old_info["git_head"] == patch["baseCommit"]
    for path in changed:
        if not path.endswith(".gd"):
            continue
        normalized = (args.stage / path).read_bytes().replace(b"\r\n", b"\n")
        assert normalized == git("show", args.commit + ":" + path).replace(b"\r\n", b"\n"), path
        entry = "assets/" + path[:-3] + ".gdc"
        content = apk.read(entry)
        assert content and (entry not in base.namelist() or content != base.read(entry)), path
        scripts.append({"source":path, "source_sha256_lf":sha(normalized), "entry":entry, "compiled_sha256":sha(content)})
    for resource in patch["resources"]:
        path = resource.removeprefix("res://")
        if git("show", patch["patchCommit"]+":"+path) != git("show", args.commit+":"+path):
            continue
        entry = path[:-3] + ".gdc"
        row = old_rows[entry]
        with patch_path.open("rb") as f:
            f.seek(row["absolute_offset"])
            old_compiled = f.read(row["size"])
        assert apk.read("assets/"+entry) == old_compiled, "earlier patch bytecode lost: " + path
        unchanged_patch_scripts.append(path)
    assert set(unchanged_patch_scripts) == {"scripts/character_select.gd", "scripts/hud.gd"}
    assert not git("diff", "--name-only", patch["baseCommit"], args.commit, "--", "assets", "map_editor_workspace").strip()
    frozen = []
    for name in sorted(names & set(base.namelist())):
        if name.startswith("assets/assets/data/") or (name.startswith("assets/.godot/imported/") and name.endswith(".ctex")):
            a, b = apk.read(name), base.read(name)
            assert a == b, "frozen packaged asset changed: " + name
            frozen.append({"entry":name, "sha256":sha(a)})
report = {"result":"PASS", "source_commit":args.commit, "apk":str(args.apk),
          "size_bytes":args.apk.stat().st_size, "sha256":sha(args.apk.read_bytes()),
          "build_info":info, "previous_patch":patch, "patch_inheritance":"PASS",
          "unchanged_patch_bytecode_verified":unchanged_patch_scripts,
          "changed_runtime_scripts":scripts, "frozen_packaged_entries":frozen,
          "zip_crc":"PASS", "test_tools_docs_exclusion":"PASS", "device_test":"NOT_RUN"}
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"result":"PASS", "scripts":len(scripts), "unchanged_patch_scripts":len(unchanged_patch_scripts),
                  "frozen_packaged_entries":len(frozen), "output":str(args.output)}))
