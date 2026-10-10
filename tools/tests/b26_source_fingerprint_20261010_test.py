"""Scoped B26 proof that dot-sourced helper bytes affect the formal fingerprint."""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "source176_r3_validation.py"


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location("b26_source176_scratch", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load source176 validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def helper_digest(module, helper: Path) -> str:
    # Use the production fingerprint function and compare the exact entry it
    # publishes, rather than reimplementing its source set in this test.
    return module.fingerprint()["files"][helper.relative_to(module.ROOT).as_posix()]


def main() -> int:
    with tempfile.TemporaryDirectory(dir=ROOT / "outputs") as raw_scratch:
        scratch = Path(raw_scratch)
        (scratch / "tools").mkdir()
        for directory in ("scripts", "tests", "scenes", "assets/data", "shaders"):
            (scratch / directory).mkdir(parents=True)
        shutil.copy2(MODULE_PATH, scratch / "tools" / "source176_r3_validation.py")
        shutil.copy2(ROOT / "tools" / "run_godot_tests.ps1", scratch / "tools" / "run_godot_tests.ps1")
        for name in ("test_windows_process_ownership.ps1", "test_native_log_evidence.ps1",
                     "test_framework_receipt.ps1", "run_godot_tests_request.ps1", "test_cloud_validation.py"):
            shutil.copy2(ROOT / "tools" / name, scratch / "tools" / name)
        shutil.copy2(ROOT / "project.godot", scratch / "project.godot")
        engine = scratch / "fake-godot.exe"
        shell = scratch / "fake-powershell.exe"
        engine.write_bytes(b"B26 scratch engine")
        shell.write_bytes(b"B26 scratch shell")
        module = load_module(scratch / "tools" / "source176_r3_validation.py")
        module.engine_path = lambda: engine
        module.shell_path = lambda: shell
        module.command = lambda *args: "4.7.stable.official.5b4e0cb0f" if len(args) > 1 and args[1] == "--version" else "7.4.0"
        helpers = [scratch / "tools" / "test_windows_process_ownership.ps1",
                   scratch / "tools" / "test_native_log_evidence.ps1"]
        original = {path: path.read_bytes() for path in helpers}
        records = []
        try:
            for path in helpers:
                before = helper_digest(module, path)
                path.write_bytes(original[path] + b"\n# B26 fingerprint scratch\n")
                after = helper_digest(module, path)
                if before == after:
                    raise AssertionError(f"helper was not bound by fingerprint: {path}")
                records.append({"helper": path.relative_to(scratch).as_posix(),
                                "before": before, "after": after, "status": "PASS"})
                path.write_bytes(original[path])
        finally:
            for path, data in original.items():
                path.write_bytes(data)
    print(json.dumps({"status": "PASS", "scope": "source176_r3_validation.fingerprint", "records": records,
                      "command": "python tools/tests/b26_source_fingerprint_20261010_test.py"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
