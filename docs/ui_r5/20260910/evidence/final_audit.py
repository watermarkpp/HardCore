#!/usr/bin/env python3
"""Final audit: distinguish install state / supplemental state / final test state.

Reads BASE_MANIFEST + receipt.json + package payload + worktree files.
Writes outputs/ui_r5_install/final_audit.json. Never modifies receipt or
installed_audit.txt.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
PACKAGE = Path(r"C:\Users\Administrator\Documents\HardCore_UI_R5_package\HardCore_UI_R5_Complete_20260910")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    data = data.replace(b"\r\n", b"\n")
    return hashlib.sha1(b"blob %d\x00" % len(data) + data).hexdigest()


def git(path_args: list) -> str:
    return subprocess.check_output(["git", "-C", str(REPO)] + path_args, text=True).strip()


manifest = json.loads((PACKAGE / "BASE_MANIFEST.json").read_text(encoding="utf-8"))
receipt = json.loads((REPO / "outputs/ui_r5_install/receipt.json").read_text(encoding="utf-8"))
modified = sorted(manifest["base_blobs"])
new_files = sorted(manifest["new_files"])
extra_files = ["tests/inventory_equipment_ui_test.gd", "tests/system_menu_gothic_ui_test.gd",
               "tests/ui_r5_panels_test.gd", "tests/ui_r5_core_test.gd",
               "tests/ui_r5_audio_test.gd", "tests/ui_r5_delete_test.gd"]

audit = {
    "audit_kind": "UI_R5_FINAL_AUDIT_R1",
    "repo_head": git(["rev-parse", "HEAD"]),
    "head_branch": git(["rev-parse", "--abbrev-ref", "HEAD"]),
    "worktree_clean_for_task_paths": None,
    "states": {
        "original_install_state": {"source": "receipt.json after_sha256 (package apply)", "files": {}},
        "package_payload_state": {"source": "payload files", "files": {}},
        "final_test_state": {"source": "worktree files at final HEAD", "files": {}},
    },
    "protected_dependencies": {"expected": manifest.get("dependency_blobs", {}), "actual": {}, "all_match": None},
    "supplemental_deviation_paths": [],
}

deviations = []
for name in modified + new_files:
    final_path = REPO / name
    payload_path = PACKAGE / "payload" / name
    final_sha = sha256_file(final_path)
    receipt_after = receipt["files"][name]["after_sha256"]
    payload_sha = sha256_file(payload_path) if payload_path.is_file() else None
    entry = {
        "receipt_after_sha256": receipt_after,
        "payload_sha256": payload_sha,
        "final_sha256": final_sha,
        "final_git_blob": git_blob(final_path),
        "matches_install_state": final_sha == receipt_after,
        "matches_payload": payload_sha is not None and final_sha == payload_sha,
    }
    audit["states"]["original_install_state"]["files"][name] = receipt_after
    audit["states"]["package_payload_state"]["files"][name] = payload_sha
    audit["states"]["final_test_state"]["files"][name] = final_sha
    if final_sha != receipt_after:
        deviations.append(name)

for name in extra_files:
    path = REPO / name
    audit["states"]["final_test_state"]["files"][name] = sha256_file(path)
    audit["states"]["final_test_state"][name + ".git_blob"] = git_blob(path)

audit["supplemental_deviation_paths"] = deviations
deps_match = True
for name, expected_blob in manifest.get("dependency_blobs", {}).items():
    actual = git_blob(REPO / name)
    audit["protected_dependencies"]["actual"][name] = actual
    if actual != expected_blob:
        deps_match = False
        audit["protected_dependencies"].setdefault("mismatch", []).append(name)
audit["protected_dependencies"]["all_match"] = deps_match
audit["worktree_clean_for_task_paths"] = git(["status", "--short"]) == ""

out = REPO / "outputs/ui_r5_install/final_audit.json"
out.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("FINAL_AUDIT deviations_from_install:", deviations)
print("protected_dependencies_all_match:", deps_match)
print("worktree_clean:", audit["worktree_clean_for_task_paths"])
print("written:", out)
