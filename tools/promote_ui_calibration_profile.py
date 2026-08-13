#!/usr/bin/env python3
"""Promote one manually saved UI calibration profile into the runtime contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess


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

    runtime_profiles[args.profile] = saved_profiles[args.profile]
    with args.runtime.open("w", encoding="utf-8", newline="\n") as output:
        json.dump(runtime, output, ensure_ascii=False, indent="\t")
        output.write("\n")
    print(
        f"UI_CALIBRATION_PROFILE_PROMOTED profile={args.profile} "
        f"nodes={len(saved_profiles[args.profile].get('nodes', {}))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
