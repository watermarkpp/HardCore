"""Verify protected authoring and pre-takeover copies without modifying them."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BACKUP = Path(r"D:\HardCoreAudit\r4-takeover-20260927-123453")
manifest = json.loads((BACKUP / "manifest.json").read_text(encoding="utf-8-sig"))
previous = json.loads((Path(__file__).parent / "protection/pre_final_hash_check.json").read_text(encoding="utf-8-sig"))
approved = {row["path"]: row["after"] for row in previous["protected_changes"]}

# Exact portal publications are independently proven against their protected
# before snapshots. Accept only these 13 files at the reviewed closure commit;
# never bless every current hash or an entire generated-data directory.
portal_commit = "c9172af201831b9401f5cfcda1aa31804dc41178"
portal_keys = ("chiyue_choice_land", "chiyue_valley_secret_passage_a",
               "chiyue_valley_secret_passage_b")
portal_paths = ["assets/data/runtime/map_editor/map_runtime_release_registry.json"]
for key in portal_keys:
    portal_paths += [
        f"map_editor_workspace/{key}/{key}.editor.json",
        f"assets/data/runtime/map_editor/{key}.runtime.json",
        f"assets/data/runtime/map_editor/{key}.visual.json",
        f"assets/data/runtime/map_editor/wall_render_plans/{key}.wall_render_plan.json",
    ]
portal_identity_errors = []
portal_receipt = json.loads(
    (Path(__file__).parent / "r4_owner_final_e367/protection.json")
    .read_text(encoding="utf-8-sig"))
assert portal_receipt["status"] == "PASS"
portal_raw = {row["path"]: row["after"] for row in portal_receipt["protected_changes"]
              if row["path"] in portal_paths}
assert set(portal_raw) == set(portal_paths), "exact 13 published raw hashes required"
for relative in portal_paths:
    expected_blob = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", f"{portal_commit}:{relative}"],
        text=True).strip()
    current_blob = subprocess.check_output(
        ["git", "-C", str(ROOT), "hash-object", "--path=" + relative, relative],
        text=True).strip()
    current_raw_sha = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
    if current_blob != expected_blob or current_raw_sha != portal_raw[relative]:
        portal_identity_errors.append(relative)
    else:
        approved[relative] = portal_raw[relative]

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
    status="PASS" if not missing and not unexpected and not save_failures and not dirty_backup_failures and rules_unchanged and not portal_identity_errors else "FAIL",
    approved_portal_commit=portal_commit, portal_identity_errors=portal_identity_errors,
    protected_count=len(manifest["protected"]), protected_changes=changes,
    protected_missing=missing, unexpected_protected_changes=unexpected,
    dirty_backup_count=len(manifest["dirty"]), dirty_backup_failures=dirty_backup_failures,
    original_save_count=len(manifest["isolated_local_saves"]), save_backup_failures=save_failures,
    current_isolated_runtime_fixture_changes=runtime_changes, user_AGENTS_unchanged=rules_unchanged,
    scope="Original authoring hashes and all pre-takeover copies; isolated test userdata changes reported separately. No device save touched.",
)
output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "protection/final_hash_check.json"
assert not output.exists() or len(sys.argv) == 1, "never overwrite a distinct evidence snapshot"
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: (len(v) if isinstance(v, list) else v) for k, v in result.items()}, ensure_ascii=False))
raise SystemExit(0 if result["status"] == "PASS" else 1)
