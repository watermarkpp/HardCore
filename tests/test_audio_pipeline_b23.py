"""B23 audio pipeline regression coverage."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIPELINE = ROOT / "tools" / "audio" / "audio_pipeline.py"


def load_pipeline():
    spec = importlib.util.spec_from_file_location("audio_pipeline_b23", PIPELINE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_cp949_invalid_bytes_keep_raw_line_hash_and_decode_status(tmp_path: Path) -> None:
    pipeline = load_pipeline()
    index = tmp_path / "sound.lst"
    raw_line = b"7: \x81\x30\n"
    index.write_bytes(raw_line)
    parsed = pipeline.parse_sound_index(index)
    assert parsed["encoding"] == "cp949_decode_error"
    assert parsed["sha256"]
    assert parsed["entries"][0]["raw_line_sha256"] == __import__("hashlib").sha256(raw_line.rstrip(b"\n")).hexdigest()
    assert parsed["entries"][0]["line_number"] == 1


def test_inventory_cli_allows_missing_optional_sound_indexes(tmp_path: Path) -> None:
    primary = tmp_path / "primary"
    user = tmp_path / "user"
    output = tmp_path / "out"
    primary.mkdir()
    user.mkdir()
    result = subprocess.run(
        [
            sys.executable,
            str(PIPELINE),
            "inventory",
            "--primary-root",
            str(primary),
            "--user-root",
            str(user),
            "--out-dir",
            str(output),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["status"] == "PASS"
    entries = json.loads((output / "sound_index_entries.json").read_text(encoding="utf-8"))
    assert entries["primary"] is None
    assert entries["user_extract"] is None
    assert entries["same_index_sha256"] is False
    inventory = json.loads((output / "source_inventory.json").read_text(encoding="utf-8"))
    assert inventory["sources"][0]["sound_index"] is None
    assert inventory["sources"][1]["sound_index"] is None
