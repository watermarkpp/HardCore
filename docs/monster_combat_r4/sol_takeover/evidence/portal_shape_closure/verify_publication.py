"""Read-only exact publication/protection verification against protected bytes."""
import hashlib
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[4]
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = read(OUT / "before_role_publication.json")
keys = set(before["sources"])
failures = []


def expect(condition, message):
    if not condition:
        failures.append(message)


def changes(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        return sum((changes(a.get(k), b.get(k), path + "/" + k)
                    for k in a.keys() | b.keys()), [])
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [path + ":length"]
        return sum((changes(x, y, path + "/" + str(i))
                    for i, (x, y) in enumerate(zip(a, b))), [])
    return [] if a == b else [path]


rows = []
registry = read(ROOT / "assets/data/runtime/map_editor/map_runtime_release_registry.json")
old_registry = {x["map_key"]: x for x in before["registry"]["maps"]}
new_registry = {x["map_key"]: x for x in registry["maps"]}
expect(old_registry.keys() == new_registry.keys(), "registry membership changed")
for key in sorted(keys):
    source_path = ROOT / f"map_editor_workspace/{key}/{key}.editor.json"
    raw = before["source_raw_utf8"][key].encode("utf-8")
    if key.endswith(("_a", "_b")):
        old_revision = int(before["sources"][key]["editor_meta"]["revision"])
        marker = b'"connection_mode": "one_way"'
        expect(raw.count(marker) == 1, key + ": exact one-way source required")
        start = raw.index(marker)
        role = b'"portal_role": "bidirectional_endpoint"'
        position = raw.index(role, start)
        raw = raw[:position] + raw[position:].replace(role, b'"portal_role": "one_way_endpoint"', 1)
        raw = raw.replace(f'"revision": {old_revision}'.encode(),
                          f'"revision": {old_revision + 1}'.encode(), 1)
    expect(source_path.read_bytes() == raw, key + ": unrelated authoring byte changed")
    runtime_path = ROOT / f"assets/data/runtime/map_editor/{key}.runtime.json"
    runtime = read(runtime_path)
    runtime_delta = changes(before["runtime"][key], runtime)
    allowed_runtime = {
        "/source/revision", "/source/candidate_binding/document_revision",
        "/source/candidate_binding/authoring_sha256",
        "/source/candidate_binding/document_sha256", "/build_sha256",
    } if key.endswith(("_a", "_b")) else set()
    expect(set(runtime_delta) == allowed_runtime, key + ": unexpected runtime delta " + str(runtime_delta))
    visual_delta = changes(before["visual"][key], read(ROOT / f"assets/data/runtime/map_editor/{key}.visual.json"))
    expect(set(visual_delta) == ({"/source_editor_document_sha256"} if allowed_runtime else set()),
           key + ": unexpected visual delta " + str(visual_delta))
    old_plan = before["plans"][key]
    plan = read(ROOT / old_plan["path"])
    wall_delta = changes(old_plan["value"], plan)
    expect(wall_delta == ["/source_runtime_json_sha256"], key + ": wall geometry or pixel metadata changed")
    expect(plan["source_runtime_json_sha256"] == sha(runtime_path), key + ": stale wall binding")
    registry_delta = changes(old_registry[key], new_registry[key])
    allowed_registry = {"/approval_revision"}
    if allowed_runtime:
        allowed_registry |= {"/ui_presentation/runtime_build_sha256", "/approved_build_sha256"}
    expect(set(registry_delta) == allowed_registry, key + ": unexpected registry delta")
    expect(new_registry[key]["approval_revision"] == old_registry[key]["approval_revision"] + 1,
           key + ": publication revision must advance once")
    expect(new_registry[key]["approved_build_sha256"] == runtime["build_sha256"], key + ": registry build binding")
    rows.append(dict(map=key, runtime_changes=runtime_delta, visual_changes=visual_delta,
                     wall_changes=wall_delta, registry_changes=registry_delta))

for relative, digest in before["formal_file_hashes"].items():
    if not any(key in relative for key in keys):
        expect(sha(ROOT / relative) == digest, "sibling file changed: " + relative)
for key, record in before["plans"].items():
    if key not in keys:
        expect(sha(ROOT / record["path"]) == record["sha256"], "sibling wall plan changed: " + key)
for relative, digest in before["wall_store_hashes"].items():
    expect(sha(ROOT / relative) == digest, "protected wall PNG changed: " + relative)
for key in old_registry.keys() - keys:
    expect(old_registry[key] == new_registry[key], "sibling registry changed: " + key)

# The first launch never started the project. Retry1 did publish Choice, but
# the wrapper erroneously treated an empty stderr ($null) as a failed match.
# Keep both original FAIL records; separately evaluate the native evidence.
native_rows = []
for folder in ("publication_retry1", "publication_remaining"):
    raw_rows = read(OUT / folder / "runs.json")
    for record in raw_rows if isinstance(raw_rows, list) else [raw_rows]:
        key = record["map"]
        stdout_path = OUT / folder / f"{key}.stdout.log"
        stderr_path = OUT / folder / f"{key}.stderr.log"
        stdout = stdout_path.read_text(encoding="utf-8-sig")
        stderr = stderr_path.read_text(encoding="utf-8-sig")
        valid = (record["native_exit_code"] == 0 and not record["timeout"]
                 and record["engine_remaining"] == 0
                 and f"PUBLISH_SINGLE_FORMAL_MAP_RELEASE_PASS map={key} " in stdout
                 and not stderr.strip())
        expect(valid, key + ": native publication evidence failed")
        native_rows.append(dict(map=key, directory=folder, native_status="PASS" if valid else "FAIL",
                                original_wrapper_status=record["status"], stdout_sha256=sha(stdout_path)))
expect({x["map"] for x in native_rows} == keys and len(native_rows) == 3, "native publication exact set")
result = dict(status="FAIL" if failures else "PASS", failures=failures, rows=rows,
              protected_sibling_maps=len(old_registry) - len(keys),
              protected_sibling_wall_plans=len(before["plans"]) - len(keys),
              protected_wall_pngs=len(before["wall_store_hashes"]), native_publications=native_rows)
(OUT / "publication_protection.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
raise SystemExit(bool(failures))
