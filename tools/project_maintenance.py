#!/usr/bin/env python3
"""Audit and safely trim generated project clutter.

The maintenance boundary is deliberately conservative: original client/server
evidence, map-editor workspaces, Godot tools, formal acceptance artifacts and
documents are never removed by this tool.
"""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SAFE_CLEAN_RELATIVE = (
    "tools/__pycache__",
    "tools/map_assets/__pycache__",
    "tools/map_design/__pycache__",
    "tools/map_editor/__pycache__",
    "tools/vendor/__pycache__",
    "tests/__pycache__",
    "outputs/resource_catalog/complete_local_mir_sources_smoke",
    "outputs/resource_catalog/complete_local_mir_sources_server_smoke",
    "outputs/resource_catalog/smoke_multi_client",
    "outputs/resource_catalog/smoke_multi_lib",
    "outputs/resource_catalog/smoke_multi_server",
    "outputs/resource_catalog/smoke_multi_server_identity",
    "outputs/device",
    "outputs/test",
    "outputs/test_logs",
)


def folder_stats(path: Path) -> dict[str, int | str]:
    files = [item for item in path.rglob("*") if item.is_file()]
    return {"path": path.relative_to(ROOT).as_posix(), "files": len(files), "bytes": sum(item.stat().st_size for item in files)}


def audit() -> dict:
    roots = [
        "assets", "scripts", "scenes", "tests", "tools", "docs", "map_editor_workspace",
        "import_server_data", "dev_art_sources", "outputs",
    ]
    report = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "projectRoot": str(ROOT),
        "policy": {
            "sourceEvidenceImmutable": True,
            "mapEditorBackupsPreserved": True,
            "formalAcceptanceArtifactsPreserved": True,
            "safeCleanupOnly": True,
        },
        "roots": [folder_stats(ROOT / item) for item in roots if (ROOT / item).exists()],
        "safeCleanupCandidates": [item for item in SAFE_CLEAN_RELATIVE if (ROOT / item).exists()],
    }
    return report


def clean() -> list[str]:
    removed: list[str] = []
    for relative in SAFE_CLEAN_RELATIVE:
        target = (ROOT / relative).resolve()
        if not target.exists() or not target.is_relative_to(ROOT):
            continue
        shutil.rmtree(target)
        removed.append(relative)
    return removed


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit or safely trim generated MIR project clutter")
    parser.add_argument("--clean", action="store_true", help="remove only documented caches and smoke outputs")
    parser.add_argument("--json", type=Path, help="write audit JSON under the project root")
    args = parser.parse_args()
    report = audit()
    if args.clean:
        report["removed"] = clean()
        report["roots"] = [folder_stats(ROOT / item) for item in (
            "assets", "scripts", "scenes", "tests", "tools", "docs", "map_editor_workspace",
            "import_server_data", "dev_art_sources", "outputs",
        ) if (ROOT / item).exists()]
    payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.json:
        destination = (ROOT / args.json).resolve()
        if not destination.is_relative_to(ROOT):
            raise ValueError("audit output must stay inside the project")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(payload, encoding="utf-8")
    print(payload, end="")


if __name__ == "__main__":
    main()
