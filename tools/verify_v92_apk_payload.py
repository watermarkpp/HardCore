"""Read-only v92 payload verification against its fixed build checkout and v91."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "stage", "apk", "baseline-apk", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--baseline-commit", required=True)
    args = parser.parse_args()

    def git(*params: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(args.root), *params], encoding="utf-8"
        ).strip()

    assert git("-C", str(args.stage), "rev-parse", "HEAD") == args.commit
    changed_scripts = git(
        "diff", "--name-only", args.baseline_commit, args.commit, "--", "scripts"
    ).splitlines()
    added_wall_textures = git(
        "diff", "--name-only", "--diff-filter=A", args.baseline_commit, args.commit,
        "--", "assets/data/runtime/map_editor/wall_render_store"
    ).splitlines()
    texture_results: dict[str, dict] = {}
    # Android export writes UTF-8 path bytes even for members whose ZIP UTF-8
    # flag is unset (for example the authored 3×3 palette directory). Decode
    # those bytes explicitly; CP437 would invent a different resource path.
    with zipfile.ZipFile(args.apk, metadata_encoding="utf-8") as apk, zipfile.ZipFile(args.baseline_apk, metadata_encoding="utf-8") as baseline:
        names = set(apk.namelist())
        assert len(names) == len(apk.namelist()), "Duplicate APK entries"
        assert apk.testzip() is None, "APK CRC failure"
        assert not any(n.startswith(("assets/tests/", "assets/docs/", "assets/tools/",
                                     "assets/outputs/", "assets/dev_art_sources/")) for n in names)

        def payload(path: str) -> bytes:
            return apk.read("assets/" + path.removeprefix("res://"))

        def document(path: str) -> dict:
            return json.loads(payload(path).rstrip(b"\x00").decode("utf-8-sig"))

        def texture(path: str) -> None:
            path = path.removeprefix("res://")
            if path in texture_results:
                return
            imports = payload(path + ".import").decode("utf-8-sig")
            refs = set(re.findall(r'res://([^"\s,\]]+\.ctex)', imports))
            assert refs, path
            imported = []
            for ref in sorted(refs):
                data = payload(ref)
                assert data and data == (args.stage / ref).read_bytes(), ref
                imported.append({"path": ref, "sha256": sha(data)})
            texture_results[path] = {"path": path, "compiled": imported}

        build = document("assets/generated/build_info.json")
        assert build["git_head"] == args.commit and build["git_dirty"] is False
        assert build["version_code"] == 92

        plans = sorted((args.stage / "assets/data/runtime/map_editor/wall_render_plans").glob("*.wall_render_plan.json"))
        assert len(plans) == 60
        plan_results = []
        for file in plans:
            path = file.relative_to(args.stage).as_posix()
            raw = payload(path)
            assert raw == file.read_bytes(), path
            plan = json.loads(raw)
            runtime = "assets/data/runtime/map_editor/" + plan["map_key"] + ".runtime.json"
            # This is the actual packaged runtime byte hash, not a semantic JSON comparison.
            assert sha(payload(runtime)) == plan["source_runtime_json_sha256"], runtime
            bindings = []
            for entry in plan["atlas_pages"] + plan["shadow_chunks"]:
                resource = entry["path"].removeprefix("res://")
                assert sha((args.stage / resource).read_bytes()) == entry["sha256"]
                texture(resource)
                bindings.append(resource)
            for resource, expected in plan["source_image_sha256"].items():
                resource = resource.removeprefix("res://")
                assert sha((args.stage / resource).read_bytes()) == expected
                texture(resource)
            plan_results.append({"map": plan["map_key"], "plan_sha256": sha(raw),
                                 "runtime_sha256": sha(payload(runtime)), "render_bindings": len(bindings)})
        new_textures = [p for p in added_wall_textures if p.endswith(".png")]
        assert len(new_textures) == 48
        assert all(p in texture_results for p in new_textures)

        authority_path = "assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"
        authority_raw = payload(authority_path)
        assert authority_raw == (args.stage / authority_path).read_bytes()
        authority = json.loads(authority_raw)
        total = sum(len(m["slots"]) for m in authority["monsters"])
        assert total == authority["summary"]["total_effective_slots"] == 6042
        assert authority["summary"]["user_directive_overlay_slots"] == 168
        assert authority["summary"]["armor_single_slot_removed_slots"] == 102

        scripts = []
        for path in changed_scripts:
            if not path.endswith(".gd"):
                continue
            entry = "assets/" + path[:-3] + ".gdc"
            compiled = apk.read(entry)
            assert compiled, entry
            old = baseline.read(entry) if entry in baseline.namelist() else None
            assert old != compiled, "Changed source exported stale bytecode: " + path
            scripts.append({"path": entry, "sha256": sha(compiled)})
        for path in ("scripts/device_lab_runtime.gd", "scripts/system_menu_panel.gd"):
            assert path in changed_scripts
        assert "记录帧率30秒" in (args.stage / "scripts/system_menu_panel.gd").read_text(encoding="utf-8")
        assert "记录CPU30秒" in (args.stage / "scripts/system_menu_panel.gd").read_text(encoding="utf-8")

        frozen = []
        for path in ("assets/data/equipment_attribute_master.json",
                     "assets/data/runtime/canonical_monster_catalog.json",
                     "assets/data/canonical_monster_classification_v1.json",
                     "assets/data/map_editor_monster_spawn_classification_v1.json"):
            raw = payload(path)
            assert raw == baseline.read("assets/" + path), path
            frozen.append({"path": path, "sha256": sha(raw)})
        report = {"status": "PASS", "source_commit": args.commit,
                  "apk": str(args.apk), "size_bytes": args.apk.stat().st_size,
                  "sha256": sha(args.apk.read_bytes()), "build_info": build,
                  "zip_crc": "PASS", "test_and_tool_exclusion": "PASS",
                  "plans": plan_results, "plan_count": len(plan_results),
                  "texture_count": len(texture_results), "textures": list(texture_results.values()),
                  "new_wall_textures": new_textures, "changed_compiled_scripts": scripts,
                  "authority_sha256": sha(authority_raw), "slots": total, "overlay_slots": 168,
                  "frozen_against_v91": frozen, "device_test": "NOT_RUN"}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("status", "source_commit", "size_bytes", "sha256", "plan_count", "texture_count", "slots")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
