"""Verify the 1.0 APK against its exact source and the accepted v77 package."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CHANGED_SCRIPTS = [
    "caster_skill_visual_effect", "game_root", "hud", "inventory_panel",
    "item_attribute_help", "loot_feedback_layer", "loot_visual_effect",
    "skills/caster_spell_geometry", "skills/skill_footprint_snapshot",
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parsed(data):
    return json.loads(data.rstrip(b"\x00").decode("utf-8-sig"))


def main():
    parser = argparse.ArgumentParser()
    for arg in ("apk", "baseline", "commit", "output"):
        parser.add_argument("--" + arg, required=True)
    args = parser.parse_args()
    apk = Path(args.apk)
    changed_entries = {"assets/scripts/" + name + ".gdc" for name in CHANGED_SCRIPTS}
    with zipfile.ZipFile(apk) as current, zipfile.ZipFile(args.baseline) as baseline:
        build = parsed(current.read("assets/assets/generated/build_info.json"))
        assert build["git_head"] == args.commit and build["git_dirty"] is False
        assert build["version_code"] == 78 and build["version_name"] == "hardcore 1.0 正式版"
        assert parsed(baseline.read("assets/assets/generated/build_info.json"))["version_code"] == 77
        names = set(current.namelist())
        old_names = set(baseline.namelist())
        changed = []
        frozen_count = 0
        for entry in sorted(old_names):
            if entry.startswith("assets/scripts/") and entry.endswith(".gdc"):
                assert entry in names, "Missing old runtime script: " + entry
                different = current.read(entry) != baseline.read(entry)
                assert different == (entry in changed_entries), "Unexpected script change state: " + entry
                if different:
                    changed.append(entry)
                else:
                    frozen_count += 1
        assert set(changed) == changed_entries
        frozen_data = []
        allowed_data = {"assets/assets/data/ui/item_name_rarity_v1.json"}
        for entry in sorted(old_names):
            if entry.startswith("assets/assets/data/") and entry not in allowed_data:
                assert entry in names and current.read(entry) == baseline.read(entry), "Frozen data changed: " + entry
                frozen_data.append(entry)
        for relative in ("assets/data/ui/item_name_rarity_v1.json", "assets/data/ui/item_name_rarity_policy_v2.json"):
            expected = subprocess.check_output(["git", "-C", str(ROOT), "show", args.commit + ":" + relative])
            assert parsed(current.read("assets/" + relative)) == parsed(expected), relative
        assert not any(name.startswith(("assets/tests/", "assets/docs/")) for name in names)
        report = {
            "status": "PASS", "apk": str(apk), "size_bytes": apk.stat().st_size,
            "sha256": digest(apk.read_bytes()), "build_info": build,
            "changed_runtime_scripts": changed,
            "unchanged_runtime_script_count": frozen_count,
            "unchanged_data_entry_count": len(frozen_data),
            "unchanged_data_entries": frozen_data,
            "device": "NOT_RUN: no connected Android device",
        }
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("status", "size_bytes", "sha256", "unchanged_runtime_script_count", "unchanged_data_entry_count")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
