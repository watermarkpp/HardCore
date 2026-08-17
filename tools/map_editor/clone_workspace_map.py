#!/usr/bin/env python3
"""Clone an editable map workspace without carrying portal links across maps."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_ROOT = ROOT / "map_editor_workspace"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_map_id(value: Any, source_map_id: str, target_map_id: str) -> Any:
    if isinstance(value, str):
        return value.replace(source_map_id, target_map_id)
    if isinstance(value, list):
        return [replace_map_id(item, source_map_id, target_map_id) for item in value]
    if isinstance(value, dict):
        return {
            replace_map_id(key, source_map_id, target_map_id): replace_map_id(
                item, source_map_id, target_map_id
            )
            for key, item in value.items()
        }
    return value


def clone_workspace(
    source_map_id: str,
    target_map_id: str,
    runtime_map_id: int,
    display_name: str,
) -> Path:
    source_root = (WORKSPACE_ROOT / source_map_id).resolve()
    target_root = (WORKSPACE_ROOT / target_map_id).resolve()
    workspace_root = WORKSPACE_ROOT.resolve()
    if source_root.parent != workspace_root or target_root.parent != workspace_root:
        raise RuntimeError("map workspace escaped map_editor_workspace")
    if not source_root.is_dir():
        raise FileNotFoundError(f"source workspace missing: {source_root}")
    if target_root.exists():
        raise FileExistsError(f"target workspace already exists: {target_root}")

    source_document = source_root / f"{source_map_id}.editor.json"
    if not source_document.is_file():
        raise FileNotFoundError(f"source document missing: {source_document}")
    source_document_sha256 = sha256(source_document)

    shutil.copytree(
        source_root,
        target_root,
        ignore=shutil.ignore_patterns("*.bak"),
    )
    copied_document = target_root / f"{source_map_id}.editor.json"
    target_document = target_root / f"{target_map_id}.editor.json"
    copied_document.rename(target_document)

    for json_path in sorted(target_root.rglob("*.json")):
        payload = json.loads(json_path.read_text(encoding="utf-8"))
        payload = replace_map_id(payload, source_map_id, target_map_id)
        if json_path == target_document:
            payload["map_id"] = target_map_id
            payload["runtime_map_id"] = runtime_map_id
            payload["display_name"] = display_name
            payload["source_reference"] = {
                "audit_status": "derived_editor_clone",
                "source_authority": "user_saved_editor_document",
                "clone_source_map_id": source_map_id,
                "clone_source_document": (
                    f"res://map_editor_workspace/{source_map_id}/"
                    f"{source_map_id}.editor.json"
                ),
                "clone_source_document_sha256": source_document_sha256,
                "clone_policy": "full_workspace_clone_without_exit_links_v1",
            }
            editor_meta = payload.setdefault("editor_meta", {})
            editor_meta["blank_template_id"] = f"blank.{target_map_id}"
            editor_meta["workspace"] = f"res://map_editor_workspace/{target_map_id}"
            editor_meta["template_kind"] = "existing_map_or_empty_template"
            editor_meta["content_policy"] = "open_existing_workspace_first"
            editor_meta["workspace_status"] = "ready"
            editor_meta["clone_source_map_id"] = source_map_id
            editor_meta["clone_source_document_sha256"] = source_document_sha256
            editor_meta["clone_policy"] = "full_workspace_clone_without_exit_links_v1"
            editor_meta["exit_link_status"] = "intentionally_unlinked"
            layers = payload.setdefault("layers", {})
            layers["map_exit_points"] = []
        json_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    loaded = json.loads(target_document.read_text(encoding="utf-8"))
    if loaded.get("map_id") != target_map_id:
        raise RuntimeError("cloned map_id validation failed")
    if loaded.get("runtime_map_id") != runtime_map_id:
        raise RuntimeError("cloned runtime_map_id validation failed")
    if loaded.get("display_name") != display_name:
        raise RuntimeError("cloned display_name validation failed")
    if loaded.get("layers", {}).get("map_exit_points") != []:
        raise RuntimeError("cloned map retained exit links")
    if loaded.get("source_reference", {}).get("clone_source_map_id") != source_map_id:
        raise RuntimeError("cloned source provenance validation failed")
    return target_document


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_map_id")
    parser.add_argument("target_map_id")
    parser.add_argument("runtime_map_id", type=int)
    parser.add_argument("display_name")
    args = parser.parse_args()
    target_document = clone_workspace(
        args.source_map_id,
        args.target_map_id,
        args.runtime_map_id,
        args.display_name,
    )
    print(f"MAP_WORKSPACE_CLONE_PASS {target_document.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
