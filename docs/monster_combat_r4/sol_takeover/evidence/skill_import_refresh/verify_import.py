"""Read-only comparison of authoring bytes and refreshed Godot imports."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
EVIDENCE = Path(__file__).resolve().parent
BASE = Path(r"C:\Users\Administrator\.codex\worktrees\r4-fixed-baseline\HardCore")
backup = json.loads((EVIDENCE.parent / "skill_import_cache_backup.json").read_text(encoding="utf-8-sig"))
before = json.loads((EVIDENCE.parent / "skill_import_cache_scan_before.json").read_text(encoding="utf-8-sig"))

def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()

sources = []
for row in backup["sources"]:
    path = ROOT / row["path"]
    sources.append(dict(row, current_sha256=digest(path), current_mtime_ns=path.stat().st_mtime_ns,
                        status="PASS" if digest(path) == row["sha256"] and path.stat().st_mtime_ns == row["mtime_ns"] else "FAIL"))
translations = []
for row in backup["files"]:
    if row["kind"] == "translation":
        sha = digest(ROOT / row["path"])
        translations.append(dict(row, current_sha256=sha, status="PASS" if sha == row["sha256"] else "FAIL"))
imports = []
laser = []
for row in before["rows"]:
    path = ROOT / row["path"]
    metadata = Path(str(path) + ".import").read_text(encoding="utf-8")
    cache = re.search(r'^path="res://([^"]+)"', metadata, re.M).group(1)
    md5_record = (ROOT / cache).with_suffix(".md5").read_text(encoding="utf-8")
    recorded = re.search(r'source_md5="([^"]+)"', md5_record).group(1)
    actual = digest(path, "md5")
    imports.append(dict(path=row["path"], source_md5=actual, record_source_md5=recorded,
                        cache_path=cache, before_status=row["status"], status="PASS" if actual == recorded else "FAIL"))
    if "/caster_skill_frames/laser/" in row["path"]:
        current_sha = digest(ROOT / cache)
        base_sha = digest(BASE / cache)
        laser.append(dict(path=row["path"], cache_path=cache, current_sha256=current_sha,
                          base_sha256=base_sha, status="PASS" if current_sha == base_sha else "FAIL"))
result = dict(status="PASS" if all(r["status"] == "PASS" for rows in [sources, translations, imports, laser] for r in rows) else "FAIL",
              sources_unchanged=sum(r["status"] == "PASS" for r in sources), source_total=len(sources),
              translations_unchanged=sum(r["status"] == "PASS" for r in translations), translation_total=len(translations),
              imports_valid=sum(r["status"] == "PASS" for r in imports), import_total=len(imports),
              laser_caches_equal_base=sum(r["status"] == "PASS" for r in laser), laser_cache_total=len(laser),
              sources=sources, translations=translations, imports=imports, laser=laser)
(EVIDENCE / "verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in result.items() if not isinstance(v, list)}))
raise SystemExit(0 if result["status"] == "PASS" else 1)
