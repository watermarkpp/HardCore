"""Exact source-only role repair. All runtime/wall outputs use native publishers."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).parent
KEYS = ["chiyue_choice_land", "chiyue_valley_secret_passage_a", "chiyue_valley_secret_passage_b"]
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert not (OUT / "before_role_publication.json").exists(), "one-shot: never overwrite protected originals"
before = dict(sources={}, source_raw_utf8={}, runtime={}, visual={}, registry=read(ROOT / "assets/data/runtime/map_editor/map_runtime_release_registry.json"),
              plans={}, wall_store_hashes={}, formal_file_hashes={})
for key in KEYS:
    before["sources"][key] = read(ROOT / f"map_editor_workspace/{key}/{key}.editor.json")
    before["source_raw_utf8"][key] = (ROOT / f"map_editor_workspace/{key}/{key}.editor.json").read_bytes().decode("utf-8")
    before["runtime"][key] = read(ROOT / f"assets/data/runtime/map_editor/{key}.runtime.json")
    before["visual"][key] = read(ROOT / f"assets/data/runtime/map_editor/{key}.visual.json")
for entry in before["registry"]["maps"]:
    key = entry["map_key"]
    for relative in [f"map_editor_workspace/{key}/{key}.editor.json", f"assets/data/runtime/map_editor/{key}.runtime.json", f"assets/data/runtime/map_editor/{key}.visual.json"]:
        before["formal_file_hashes"][relative] = sha(ROOT / relative)
for path in sorted((ROOT / "assets/data/runtime/map_editor/wall_render_plans").glob("*.wall_render_plan.json")):
    plan = read(path)
    before["plans"][plan["map_key"]] = dict(path=path.relative_to(ROOT).as_posix(), sha256=sha(path), value=plan)
    for record in plan["atlas_pages"] + plan["shadow_chunks"]:
        relative = record["path"].removeprefix("res://")
        before["wall_store_hashes"][relative] = sha(ROOT / relative)
(OUT / "before_role_publication.json").write_text(json.dumps(before, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for key, revision in [(KEYS[1], 77), (KEYS[2], 65)]:
    source = ROOT / f"map_editor_workspace/{key}/{key}.editor.json"
    doc = read(source)
    assert doc == before["sources"][key] and doc["editor_meta"]["revision"] == revision
    endpoints = doc["layers"]["map_exit_points"]
    assert len(endpoints) == 2
    endpoint = next(e for e in endpoints if e["semantic_id"] == "map_exit_000002")
    assert endpoint["connection_mode"] == "one_way" and endpoint["one_way"] is True
    assert endpoint["portal_role"] == "bidirectional_endpoint" and endpoint["explicit_one_way_reason"]
    endpoint["portal_role"] = "one_way_endpoint"
    doc["editor_meta"]["revision"] += 1
    # Preserve every unrelated byte, including authored decimal spellings.
    raw = before["source_raw_utf8"][key].encode("utf-8")
    marker = b'"connection_mode": "one_way"'
    assert raw.count(marker) == 1
    start = raw.index(marker)
    role = b'"portal_role": "bidirectional_endpoint"'
    position = raw.index(role, start)
    assert raw.index(b'"semantic_id": "map_exit_000002"', start) > position
    raw = raw[:position] + raw[position:].replace(role, b'"portal_role": "one_way_endpoint"', 1)
    old_revision = ('"revision": %d' % revision).encode()
    assert raw.count(old_revision) == 1
    raw = raw.replace(old_revision, ('"revision": %d' % (revision + 1)).encode(), 1)
    assert json.loads(raw) == doc
    source.write_bytes(raw)
print("PORTAL_ROLE_AUTHORING_REPAIR exact2 role fields plus revision; all source snapshots and wall PNG hashes protected")
