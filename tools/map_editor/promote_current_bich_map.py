"""Freeze the user-authored sandbox as the official single-player Bich workspace."""
from __future__ import annotations
import json, shutil, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "map_editor_workspace/sandbox_64"
TARGET = ROOT / "map_editor_workspace/bich_province"
ARCHIVE = ROOT / "map_editor_workspace/_delivery_backups" / f"bich_{time.strftime('%Y%m%d_%H%M%S')}"

if not SOURCE.exists(): raise SystemExit("sandbox_64 workspace missing")
ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
if TARGET.exists(): shutil.copytree(TARGET, ARCHIVE)
if TARGET.exists(): shutil.rmtree(TARGET)
shutil.copytree(SOURCE, TARGET)

old_doc = TARGET / "sandbox_64.editor.json"
doc_path = TARGET / "bich_province.editor.json"
doc = json.loads(old_doc.read_text(encoding="utf-8"))
doc.update({"map_id":"bich_province","runtime_map_id":4,"display_name":"比奇省（单机重制）"})
doc["design"]["map_type"] = "outdoor_province"
doc["editor_meta"]["workspace"] = "res://map_editor_workspace/bich_province"
doc["editor_meta"]["milestone"] = "BICH-USER-MAP-READY"
doc["editor_meta"]["runtime_approved"] = False
for door in doc["layers"].get("door_points", []):
    if str(door.get("target_map_id", "")) in ("", "待配置"):
        door["target_map_id"] = -1
        door["target_configured"] = False
        door["display_name"] = "待配置地图传送门"
doc_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
old_doc.unlink()
for relative in ["ground/ground_manifest.json", "ground/ground_state.json"]:
    path=TARGET/relative; data=json.loads(path.read_text(encoding="utf-8")); data["map_id"]="bich_province"; path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"BICH_WORKSPACE_PROMOTION_PASS archive={ARCHIVE if ARCHIVE.exists() else 'new'}")
