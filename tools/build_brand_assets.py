#!/usr/bin/env python3
"""Build deterministic game branding assets from the user-approved master image."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ARCHIVE = ROOT / "dev_art_sources/user_provided/branding/game_icon_master_20260715.png"
RUNTIME_DIR = ROOT / "assets/branding"
ICON_PATH = RUNTIME_DIR / "game_icon.png"
ANDROID_ICON_PATH = RUNTIME_DIR / "android_icon_192.png"
BOOT_SPLASH_PATH = RUNTIME_DIR / "boot_splash.png"
MANIFEST_PATH = RUNTIME_DIR / "brand_manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def build(source: Path) -> dict:
    if not source.is_file():
        raise FileNotFoundError(source)
    SOURCE_ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    if source.resolve() != SOURCE_ARCHIVE.resolve():
        shutil.copy2(source, SOURCE_ARCHIVE)

    with Image.open(SOURCE_ARCHIVE) as opened:
        master = opened.convert("RGB")
        source_size = list(master.size)
        if master.width != master.height:
            raise ValueError(f"Brand master must be square, got {master.size}")

        icon = master.resize((1024, 1024), Image.Resampling.LANCZOS)
        icon.save(ICON_PATH, format="PNG", optimize=True)

        android_icon = master.resize((192, 192), Image.Resampling.LANCZOS)
        android_icon.save(ANDROID_ICON_PATH, format="PNG", optimize=True)

        splash = Image.new("RGB", (1280, 720), (0, 0, 0))
        splash_logo = master.resize((720, 720), Image.Resampling.LANCZOS)
        splash.paste(splash_logo, ((1280 - 720) // 2, 0))
        splash.save(BOOT_SPLASH_PATH, format="PNG", optimize=True)

    manifest = {
        "schemaVersion": 1,
        "brandId": "MY-BRUSH-GAME-ICON-1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "policy": {
            "userApprovedMaster": True,
            "generativeModification": False,
            "deterministicResizeOnly": True,
            "introText": "刷是一种状态，刷没有目的没有终点",
        },
        "source": {
            "path": relative(SOURCE_ARCHIVE),
            "originalInput": str(source.resolve()),
            "size": source_size,
            "sha256": sha256(SOURCE_ARCHIVE),
        },
        "outputs": [
            {"path": relative(ICON_PATH), "size": [1024, 1024], "sha256": sha256(ICON_PATH)},
            {"path": relative(ANDROID_ICON_PATH), "size": [192, 192], "sha256": sha256(ANDROID_ICON_PATH)},
            {"path": relative(BOOT_SPLASH_PATH), "size": [1280, 720], "sha256": sha256(BOOT_SPLASH_PATH)},
        ],
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the approved game icon and boot splash")
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
