"""Verify protected authoring and pre-takeover copies without modifying them."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BACKUP = Path(r"D:\HardCoreAudit\r4-takeover-20260927-123453")
manifest = json.loads((BACKUP / "manifest.json").read_text(encoding="utf-8-sig"))
previous = json.loads((Path(__file__).parent / "protection/pre_final_hash_check.json").read_text(encoding="utf-8-sig"))
approved = {row["path"]: row["after"] for row in previous["protected_changes"]}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

changes, missing, unexpected = [], [], []
for row in manifest["protected"]:
    path = ROOT / row["path"]
    if not path.is_file():
        missing.append(row["path"])
        continue
    current = sha(path)
    if current != row["sha256"]:
        item = dict(path=row["path"], before=row["sha256"], after=current)
        changes.append(item)
        if approved.get(row["path"]) != current:
            unexpected.append(item)

save_failures, runtime_changes = [], []
for row in manifest["isolated_local_saves"]:
    copied = BACKUP / "saves" / row["path"]
    if not copied.is_file() or sha(copied) != row["sha256"]:
        save_failures.append(row["path"])
    current = ROOT / row["path"]
    if not current.is_file() or sha(current) != row["sha256"]:
        runtime_changes.append(row["path"])

dirty_backup_failures = []
for row in manifest["dirty"]:
    copied = BACKUP / "files" / row["path"]
    if not copied.is_file() or sha(copied) != row["sha256"]:
        dirty_backup_failures.append(row["path"])

user_rules = next(row for row in manifest["dirty"] if row["path"] == "AGENTS.md")
rules_unchanged = sha(ROOT / "AGENTS.md") == user_rules["sha256"]
result = dict(
    source_head=subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
    status="PASS" if not missing and not unexpected and not save_failures and not dirty_backup_failures and rules_unchanged else "FAIL",
    protected_count=len(manifest["protected"]), protected_changes=changes,
    protected_missing=missing, unexpected_protected_changes=unexpected,
    dirty_backup_count=len(manifest["dirty"]), dirty_backup_failures=dirty_backup_failures,
    original_save_count=len(manifest["isolated_local_saves"]), save_backup_failures=save_failures,
    current_isolated_runtime_fixture_changes=runtime_changes, user_AGENTS_unchanged=rules_unchanged,
    scope="Original authoring hashes and all pre-takeover copies; isolated test userdata changes reported separately. No device save touched.",
)
(Path(__file__).parent / "protection/final_hash_check.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: (len(v) if isinstance(v, list) else v) for k, v in result.items()}, ensure_ascii=False))
raise SystemExit(0 if result["status"] == "PASS" else 1)
