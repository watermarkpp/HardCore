from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tools" / "loot_sheet_compiler" / "test_write_set_repair.ps1"
PWsh = "pwsh"


def run(args: list[str], timeout: float = 5.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [PWsh, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HARNESS), *args],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
    )


def helper_args(root: Path, out: Path, mode: str, lock: Path, ready: Path, release: Path) -> list[str]:
    return [
        "-ProjectRoot", str(root), "-OutputRoot", str(out), mode,
        "-LockPath", str(lock), "-ReadyPath", str(ready), "-ReleasePath", str(release),
        "-DeadlineMilliseconds", "300",
    ]


def test_bounded_write_set_failure_and_cleanup() -> None:
    with tempfile.TemporaryDirectory(prefix="b25_write_set_harness_") as raw:
        root = Path(raw) / "project"
        out = Path(raw) / "out"
        root.mkdir()
        out.mkdir()
        lock = out / "lock"
        ready = out / "ready"
        release = out / "release"

        # BoundaryLock and ConflictWatcher both terminate on a missing transient
        # stage instead of waiting forever.
        for mode in ("-BoundaryLock", "-ConflictWatcher"):
            result = run(helper_args(root, out, mode, lock, ready, release))
            assert result.returncode != 0
            assert "WRITE_SET_HARNESS_TIMEOUT" in ((result.stdout or "") + (result.stderr or ""))

        # Invalid helper setup fails immediately, and a cancelled lock wait
        # releases its handle in finally so the parent can take the lock again.
        bad = run(helper_args(root, out, "-LockOnly", out / "missing" / "lock", ready, release))
        assert bad.returncode != 0
        proc = subprocess.Popen(
            [PWsh, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HARNESS),
             "-ProjectRoot", str(root), "-OutputRoot", str(out), "-LockOnly",
             "-LockPath", str(lock), "-ReadyPath", str(ready), "-ReleasePath", str(release),
             "-DeadlineMilliseconds", "1000"],
            cwd=ROOT, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        deadline = time.time() + 3
        while not ready.exists() and time.time() < deadline:
            time.sleep(0.01)
        assert ready.exists()
        release.write_text("RELEASE", encoding="utf-8")
        assert proc.wait(timeout=3) == 0
        with lock.open("r+b"):
            pass

        # Parent/compiler early failure is reported and does not hang. This is
        # a scratch compiler stub, not a production compiler execution.
        compiler = root / "tools" / "loot_sheet_compiler"
        compiler.mkdir(parents=True)
        (compiler / "compile_authority.ps1").write_text(
            "param([string]$ProjectRoot,[string]$OutputDir); Write-Error 'STUB_EARLY_FAILURE'; exit 17\n",
            encoding="utf-8",
        )
        early = run(["-ProjectRoot", str(root), "-OutputRoot", str(out / "early"), "-DeadlineMilliseconds", "300"])
        assert early.returncode != 0
        assert "baseline compiler failed" in (early.stdout + early.stderr)


def test_parent_helper_lifecycle_and_paths_with_spaces() -> None:
    with tempfile.TemporaryDirectory(prefix="b25 write set harness ") as raw:
        base = Path(raw)
        root = base / "project with spaces"
        out = base / "output with spaces"
        compiler = root / "tools" / "loot_sheet_compiler"
        compiler.mkdir(parents=True)
        names = ["dpv2_user_loot_sheet_authority_v1.json", "compile_disambiguation.json", "armor_single_slot_audit.json"]
        lines = [
            "param([string]$ProjectRoot,[string]$OutputDir)",
            "$names = @(" + ",".join("'" + n + "'" for n in names) + ")",
            "New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null",
            "if ($OutputDir -notmatch 'lock-first|lock-second|manual-conflict') { foreach ($name in $names) { Set-Content -LiteralPath (Join-Path $OutputDir $name) -Value ('FIXTURE_' + $name) -Encoding UTF8 } }",
            "if ($OutputDir -match 'lock-first|lock-second|manual-conflict') { foreach ($n in 1..3) { New-Item -ItemType File -Path (Join-Path $OutputDir ('.txn.' + $n)) -Force | Out-Null }; if ($OutputDir -match 'manual-conflict') { Start-Sleep -Milliseconds 150; Get-ChildItem -LiteralPath $OutputDir -Filter '.txn.*' -File | Remove-Item -Force }; exit 17 }",
            "exit 0",
        ]
        (compiler / "compile_authority.ps1").write_text("\n".join(lines) + "\n", encoding="utf-8")
        result = run(["-ProjectRoot", str(root), "-OutputRoot", str(out), "-DeadlineMilliseconds", "1000"], timeout=10)
        text = (result.stdout or "") + (result.stderr or "")
        assert result.returncode == 0, text
        assert "WRITE_SET_REPAIR_PASS" in text


if __name__ == "__main__":
    test_bounded_write_set_failure_and_cleanup()
    test_parent_helper_lifecycle_and_paths_with_spaces()
    print("B25 S3-R02 PASS")
