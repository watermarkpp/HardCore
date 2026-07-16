#!/usr/bin/env python3
"""Verify that Godot only imports runtime assets, not research/build outputs."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    required_ignores = [
        "dev_art_sources/.gdignore",
        "map_editor_workspace/.gdignore",
        "outputs/.gdignore",
        "tools/godot-4.7/.gdignore",
        "tests/fixtures/mir2_server/.gdignore",
    ]
    checks = {
        "requiredIgnoreFiles": all((ROOT / path).is_file() for path in required_ignores),
        "noOutputImportSidecars": not any((ROOT / "outputs").rglob("*.import")),
        "bundledGodotExists": (ROOT / "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe").is_file(),
        "projectConfigExists": (ROOT / "project.godot").is_file(),
    }
    cache = ROOT / ".godot/editor/filesystem_cache10"
    checks["noOutputsInGodotFilesystemCache"] = not cache.exists() or "res://outputs/" not in cache.read_text(encoding="utf-8", errors="ignore")
    result = {"passed": all(checks.values()), "checks": checks, "requiredIgnoreFiles": required_ignores}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
