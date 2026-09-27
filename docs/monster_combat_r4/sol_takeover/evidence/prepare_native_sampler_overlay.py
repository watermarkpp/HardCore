"""Preserve then replace only the declared BASE test overlay; never production."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BASE = Path(r"C:\Users\Administrator\.codex\worktrees\r4-fixed-baseline\HardCore")
HEAD = "1381d2838a3736f4a06699dd24a8cf4a10714950"
TARGETS = (
    "tests/hc_monster_combat_r4/t6_real_load_probe.gd",
    "tests/hc_monster_combat_r4/t6_real_load_probe.tscn",
    "tools/run_godot_tests.ps1",
)
BACKUP = Path(r"D:\HardCoreAudit\native-sampler-overlay-before-20260928-0525")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backup", type=Path, default=BACKUP)
    args = parser.parse_args()
    backup = args.backup.resolve()
    assert backup.parent == Path(r"D:\HardCoreAudit").resolve(), "backup must be a new direct child of the audit archive"
    assert ROOT == Path(r"C:\Users\Administrator\Documents\HardCore")
    assert BASE.resolve() == BASE and git(BASE, "rev-parse", "HEAD") == HEAD
    assert not git(BASE, "diff", "--name-only", "HEAD", "--", "scripts", "assets", "project.godot", "export_presets.cfg"), "dirty BASE production"
    assert not backup.exists(), "refuse existing backup"
    inputs = {relative: (ROOT / relative).read_bytes() for relative in TARGETS}
    previous = {relative: (BASE / relative).read_bytes() for relative in TARGETS}
    backup.mkdir(parents=True)
    for relative, raw in previous.items():
        path = backup / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as handle:
            handle.write(raw)
        assert path.read_bytes() == raw
    # Preserve both prior index and working patch. The overlay never changes
    # either worktree's index, HEAD, source, runtime inputs or user data.
    for name, args in [("index.patch", ("diff", "--cached", "--binary", "--", *TARGETS)),
                       ("working.patch", ("diff", "--binary", "HEAD", "--", *TARGETS))]:
        patch = subprocess.check_output(["git", "-C", str(BASE), *args])
        with (backup / name).open("xb") as handle:
            handle.write(patch)
    for relative, raw in inputs.items():
        (BASE / relative).write_bytes(raw)
        assert (BASE / relative).read_bytes() == raw == (ROOT / relative).read_bytes()
    assert git(BASE, "rev-parse", "HEAD") == HEAD
    assert not git(BASE, "diff", "--name-only", "HEAD", "--", "scripts", "assets", "project.godot", "export_presets.cfg")
    receipt = {"status": "PASS", "scope": "Declared common test overlay only; native sampling and performance NOT_RUN.",
               "base_head": HEAD, "candidate_head": git(ROOT, "rev-parse", "HEAD"), "backup": str(backup),
               "files": [{"path": relative, "before_sha256": sha(previous[relative]), "common_sha256": sha(inputs[relative])} for relative in TARGETS]}
    with (backup / "receipt.json").open("x", encoding="utf-8") as handle:
        json.dump(receipt, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
