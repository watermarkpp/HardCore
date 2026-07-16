"""Freeze the user-authored sandbox as the official single-player Bich workspace."""
from __future__ import annotations
import json, shutil, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "map_editor_workspace/sandbox_64"
TARGET = ROOT / "map_editor_workspace/bich_province"
READY_MARKER = ROOT / "assets/data/runtime/map_editor/bich_province.manual_ready.json"
ARCHIVE = ROOT / "map_editor_workspace/_delivery_backups" / f"bich_{time.strftime('%Y%m%d_%H%M%S')}"

if not SOURCE.exists(): raise SystemExit("sandbox_64 workspace missing")
source_doc_path = SOURCE / "sandbox_64.editor.json"
source_doc = json.loads(source_doc_path.read_text(encoding="utf-8"))
source_instances = {
    entry.get("instance_id"): entry
    for layer in ("terrain_base", "terrain_front", "object_base", "object_front")
    for entry in source_doc["layers"].get(layer, [])
    if entry.get("instance_id")
}
for door in source_doc["layers"].get("door_points", []):
    linked = source_instances.get(door.get("linked_visual_instance_id"))
    if linked is not None:
        door["tile"] = list(linked.get("tile", door.get("tile", [0, 0])))
source_doc_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
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
instances = {
    entry.get("instance_id"): entry
    for layer in ("terrain_base", "terrain_front", "object_base", "object_front")
    for entry in doc["layers"].get(layer, [])
    if entry.get("instance_id")
}
for door in doc["layers"].get("door_points", []):
    linked = instances.get(door.get("linked_visual_instance_id"))
    if linked is not None:
        door["tile"] = list(linked.get("tile", door.get("tile", [0, 0])))
    if str(door.get("target_map_id", "")) in ("", "待配置"):
        door["target_map_id"] = -1
        door["target_configured"] = False
        door["display_name"] = "待配置地图传送门"
doc_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
old_doc.unlink()
for relative in ["ground/ground_manifest.json", "ground/ground_state.json"]:
    path=TARGET/relative; data=json.loads(path.read_text(encoding="utf-8")); data["map_id"]="bich_province"; path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
READY_MARKER.parent.mkdir(parents=True, exist_ok=True)
READY_MARKER.write_text(json.dumps({
    "schema_version": 1,
    "map_id": "bich_province",
    "runtime_map_id": 4,
    "source_workspace": "map_editor_workspace/bich_province",
    "status": "user_confirmed_ready",
    "content": {
        "design_size": doc["design"]["design_size"],
        "instances": len(instances),
        "monster_spawns": len(doc["layers"].get("monster_spawn", [])),
        "npcs": len(doc["layers"].get("npc_points", [])),
        "doors": len(doc["layers"].get("door_points", [])),
        "doors_pending_target_configuration": sum(not bool(door.get("target_configured", False)) for door in doc["layers"].get("door_points", [])),
    },
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"BICH_WORKSPACE_PROMOTION_PASS archive={ARCHIVE if ARCHIVE.exists() else 'new'}")
