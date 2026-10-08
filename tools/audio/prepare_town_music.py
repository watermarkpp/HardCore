"""Prepare the one audited town track for native PCM playback, before export."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/audio/town/main_city_bgm.ogg"
SOURCE_RECORD = ROOT / "assets/audio/town/main_city_bgm.source.json"
OUTPUT = ROOT / "assets/audio/town/main_city_bgm.pcm.wav"
RECEIPT = ROOT / "assets/audio/town/main_city_bgm.playback.json"
IMPORT_SETTINGS = OUTPUT.with_suffix(OUTPUT.suffix + ".import")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(ffmpeg: str, check: bool = False) -> dict:
    record = json.loads(SOURCE_RECORD.read_text(encoding="utf-8"))
    source_sha = sha(SOURCE)
    if source_sha != record["conversion"]["runtimeSha256"]:
        raise ValueError("frozen town music source SHA mismatch")
    settings = IMPORT_SETTINGS.read_text(encoding="utf-8").split("[params]", 1)[-1]
    for key, expected in {"compress/mode": "0", "force/8_bit": "false", "force/mono": "false",
                          "force/max_rate": "false", "edit/trim": "false", "edit/normalize": "false",
                          "edit/loop_mode": "0"}.items():
        if re.findall(r"^" + re.escape(key) + r"=(\S+)\s*$", settings, re.MULTILINE) != [expected]:
            raise ValueError("town music import must preserve native PCM: " + key)
    # Decode in a temporary sibling so an interrupted generator leaves the
    # previous validated playable asset intact. Never transcode at runtime.
    with tempfile.TemporaryDirectory(prefix="town_pcm_", dir=OUTPUT.parent) as temp:
        candidate = Path(temp) / OUTPUT.name
        subprocess.run([
            ffmpeg, "-nostdin", "-v", "error", "-i", str(SOURCE),
            "-map", "0:a:0", "-map_metadata", "-1", "-fflags", "+bitexact",
            "-flags:a", "+bitexact", "-c:a", "pcm_s16le", "-rf64", "never",
            str(candidate),
        ], check=True, capture_output=True)
        with wave.open(str(candidate), "rb") as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (2, 2, 44100, "NONE"):
                raise ValueError("PCM must preserve 44100 Hz stereo with no playback compression")
            frames = audio.getnframes()
            duration = frames / audio.getframerate()
        if abs(duration - float(record["conversion"]["runtimeDurationSeconds"])) > 0.01:
            raise ValueError("decoded music duration changed")
        receipt = {
            "schema_version": 1, "contract_id": "audio.town.pcm_playback.v1",
            "source_path": "res://assets/audio/town/main_city_bgm.ogg", "source_sha256": source_sha,
            "source_record_sha256": sha(SOURCE_RECORD),
            "runtime_path": "res://assets/audio/town/main_city_bgm.pcm.wav",
            "runtime_sha256": sha(candidate), "runtime_bytes": candidate.stat().st_size,
            "format": "pcm_s16le", "sample_rate_hz": 44100, "channels": 2,
            "sample_frames": frames, "duration_seconds": duration, "loop": False,
            "generator": "tools/audio/prepare_town_music.py",
            "decode_policy": "build_time_only; native uncompressed playback; original OGG preserved",
        }
        if check:
            if not OUTPUT.is_file() or sha(OUTPUT) != receipt["runtime_sha256"] \
                or not RECEIPT.is_file() or json.loads(RECEIPT.read_text(encoding="utf-8")) != receipt:
                raise ValueError("prepared town music is missing or differs from its exact source decode")
        else:
            candidate.replace(OUTPUT)
            RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = prepare(args.ffmpeg, args.check)
        print(json.dumps({"status": "PASS", **result}))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error)}))
        raise SystemExit(1)
