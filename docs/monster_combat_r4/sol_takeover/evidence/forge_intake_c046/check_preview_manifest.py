"""Read only committed Git objects. Preview evidence is not an integration result."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[5]
out = Path(__file__).parent
main = "c0461f25ab2d02f2ea304dcf43be36cb868ab9d0"
forge = "da41da3642123c180723ef03dec193ef1fc4cb1b"
preview = "2cd9c40169fcb41bd403f5a33103d411a9667c82"
forge_worktree = Path(r"C:\Users\Administrator\.codex\worktrees\forge-ui-20260923\HardCore")

def git(*args):
    return subprocess.check_output(["git", "-C", str(root), *args])

manifest = json.loads(git("show", forge+":docs/forge/source_manifest.json"))
base = manifest["base_head"]
shared = set(git("diff", "--name-only", base, main).decode().splitlines())
rows, errors = [], []
for entry in manifest["files"]:
    path = entry["path"]
    original = git("show", manifest["source_head"]+":"+path)
    tip = git("show", forge+":"+path)
    candidate = git("show", preview+":"+path)
    original_sha = hashlib.sha256(original).hexdigest()
    tip_sha = hashlib.sha256(tip).hexdigest()
    candidate_sha = hashlib.sha256(candidate).hexdigest()
    worktree_sha = hashlib.sha256((forge_worktree / path).read_bytes()).hexdigest()
    original_blob = git("rev-parse", manifest["source_head"]+":"+path).decode().strip()
    tip_blob = git("rev-parse", forge+":"+path).decode().strip()
    cleaned_blob = subprocess.check_output(["git", "-C", str(forge_worktree), "hash-object",
                                           "--path="+path, str(forge_worktree / path)]).decode().strip()
    source_valid = (original_sha == tip_sha and worktree_sha == entry["sha256"]
                    and original_blob == tip_blob == cleaned_blob == entry["git_blob"])
    is_shared = path in shared
    if not source_valid:
        errors.append(path+":manifest_source")
    if not is_shared and candidate_sha != tip_sha:
        errors.append(path+":unshared_preview_changed")
    rows.append(dict(path=path, git_source_sha256=tip_sha, source_worktree_sha256=worktree_sha,
                     git_blob=tip_blob, cleaned_worktree_blob=cleaned_blob, preview_sha256=candidate_sha,
                     manifest_valid=source_valid, shared_with_main=is_shared,
                     preview_equals_forge=candidate_sha == tip_sha))
assert len(rows) == manifest["file_count"] == 180
result = dict(status="FAIL" if errors else "PASS", main_head=main, forge_head=forge,
              preview_tree=preview, manifest_source_head=manifest["source_head"],
              files=len(rows), shared=sum(r["shared_with_main"] for r in rows),
              unchanged_nonshared=sum(not r["shared_with_main"] and r["preview_equals_forge"] for r in rows),
              errors=errors, rows=rows,
              scope="Manifest raw SHA checks actual source worktree bytes; provided Git blob is checked against source/tip and official Git clean conversion (core.autocrlf=true). Preview compares committed Git bytes. Conflict markers/automatic merge semantics remain unaccepted; no worktree/index/HEAD mutation or integration claim.")
(out / "preview_manifest_check.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({k:v for k,v in result.items() if k != "rows"},ensure_ascii=False))
raise SystemExit(bool(errors))
