#!/usr/bin/env python3
"""Promote one manually saved UI calibration profile into the runtime contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess


RUNTIME_OWNED_PREFIXES = {
    "inventory": ("BagPanel/InventoryScroll/ItemGrid/",),
}


def compact_profile(profile_id: str, profile: dict) -> tuple[dict, int]:
    """Remove transient runtime collection members from a saved UI profile."""
    compacted = json.loads(json.dumps(profile))
    nodes = compacted.get("nodes", {})
    prefixes = RUNTIME_OWNED_PREFIXES.get(profile_id, ())
    removed = [path for path in nodes if path.startswith(prefixes)] if prefixes else []
    for path in removed:
        nodes.pop(path, None)
    return compacted, len(removed)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", help="profile id to promote, for example: skill")
    parser.add_argument(
        "--saved",
        type=Path,
        default=Path("outputs/ui_calibration/manual_layout_overrides.json"),
    )
    parser.add_argument(
        "--runtime",
        type=Path,
        default=Path("assets/data/ui/manual_layout_overrides.json"),
    )
    parser.add_argument(
        "--base-revision",
        help="read the runtime contract from this Git revision before promotion",
    )
    parser.add_argument(
        "--rewrite-saved",
        action="store_true",
        help="also rewrite the manual saved profile without runtime-owned members",
    )
    args = parser.parse_args()

    saved = json.loads(args.saved.read_text(encoding="utf-8"))
    if args.base_revision:
        source = subprocess.run(
            ["git", "show", f"{args.base_revision}:{args.runtime.as_posix()}"],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        ).stdout
    else:
        source = args.runtime.read_text(encoding="utf-8")
    runtime = json.loads(source)
    saved_profiles = saved.get("profiles", {})
    runtime_profiles = runtime.get("profiles", {})
    if args.profile not in saved_profiles:
        raise SystemExit(f"saved profile not found: {args.profile}")
    if saved.get("schemaVersion") != runtime.get("schemaVersion"):
        raise SystemExit("schemaVersion mismatch")
    if saved.get("coordinateSpace") != runtime.get("coordinateSpace"):
        raise SystemExit("coordinateSpace mismatch")
    if saved.get("deviceProfile") != runtime.get("deviceProfile"):
        raise SystemExit("deviceProfile mismatch")

    compacted_profile, removed_count = compact_profile(
        args.profile, saved_profiles[args.profile]
    )
    runtime_profiles[args.profile] = compacted_profile
    with args.runtime.open("w", encoding="utf-8", newline="\n") as output:
        json.dump(runtime, output, ensure_ascii=False, indent="\t")
        output.write("\n")
    if args.rewrite_saved:
        saved_profiles[args.profile] = compacted_profile
        with args.saved.open("w", encoding="utf-8", newline="\n") as output:
            json.dump(saved, output, ensure_ascii=False, indent="\t")
            output.write("\n")
    print(
        f"UI_CALIBRATION_PROFILE_PROMOTED profile={args.profile} "
        f"nodes={len(compacted_profile.get('nodes', {}))} "
        f"runtime_owned_removed={removed_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
