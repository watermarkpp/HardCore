"""Bind the revised workbook to the activated authority without running Godot."""
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def run():
    root = Path("outputs/repair_v92/excel/armor_single_slot")
    authority_path = Path("assets/data/drop/dpv2_user_loot_sheet_authority_v1.json")
    directive_path = Path("tools/loot_sheet_compiler/evidence/armor_single_slot_directive_v92.json")
    before = read("outputs/repair_v92/armor/before_authority.json")
    after = read(authority_path)
    directive = read(directive_path)
    old = read("outputs/repair_v92/excel/exact_ground_probabilities.json")
    new = read(root / "exact_ground_probabilities.json")
    authority_sha = hashlib.sha256(authority_path.read_bytes()).hexdigest()
    assert authority_sha == "9f6e27418c742c9338ce4b60d752202e50549b48bbc2e066d91c760e6ef43b56"
    compiled_products = []
    for path in (Path("outputs/repair_v92/armor/final_prepared_a/dpv2_user_loot_sheet_authority_v1.json"),
                 Path("outputs/repair_v92/armor/source_only/out/dpv2_user_loot_sheet_authority_v1.json")):
        product_sha = hashlib.sha256(path.read_bytes()).hexdigest()
        assert product_sha == authority_sha
        compiled_products.append({"path": str(path), "sha256": product_sha})
    before_by_id = {m["monster_id"]: m for m in before["monsters"]}
    after_by_id = {m["monster_id"]: m for m in after["monsters"]}
    assert list(before_by_id) == list(after_by_id) and len(after_by_id) == 126
    removed = {u for g in directive["groups"] for u in g["remove_slot_uids"]}
    assert len(removed) == 102 and len(directive["groups"]) == 102
    assert len({g["monster_id"] for g in directive["groups"]}) == 37
    for mid, m in before_by_id.items():
        expected = [s for s in m["slots"] if s["slot_uid"] not in removed]
        assert expected == after_by_id[mid]["slots"], mid
    for g in directive["groups"]:
        slots = {s["slot_uid"]: s for s in after_by_id[g["monster_id"]]["slots"]}
        keep = next(s for s in g["expected_slots"] if s["slot_uid"] == g["keep_slot_uid"])
        assert slots[g["keep_slot_uid"]] == keep
        assert all(u not in slots for u in g["remove_slot_uids"])
    armor_ids = {s["source_item_id"] for s in directive["armor_output_identities"]}
    def rows(payload, predicate):
        return [{"monster_id": m["monster_id"], "slot": s} for m in payload["monsters"]
                for s in m["slots"] if predicate(s)]
    nonarmor_before = rows(before, lambda s: s.get("canonical_item_id") not in armor_ids)
    nonarmor_after = rows(after, lambda s: s.get("canonical_item_id") not in armor_ids)
    overlays_before = rows(before, lambda s: s.get("origin") == "user_directive_overlay")
    overlays_after = rows(after, lambda s: s.get("origin") == "user_directive_overlay")
    assert nonarmor_before == nonarmor_after and len(nonarmor_after) == 5791
    assert overlays_before == overlays_after and len(overlays_after) == 168
    exceptions = []
    for exception in directive["frozen_exceptions"]:
        mid = exception["monster_id"]
        uids = {s["slot_uid"] for s in exception["expected_slots"]}
        b = [s for s in before_by_id[mid]["slots"] if s["slot_uid"] in uids]
        a = [s for s in after_by_id[mid]["slots"] if s["slot_uid"] in uids]
        assert a == b == exception["expected_slots"]
        exceptions.append({"monster_id": mid, "before_sha256": digest(b), "after_sha256": digest(a), "slots": a})
    assert len(exceptions) == 6
    old_live = {m["monster_id"]: m for m in old["monsters"]}
    assert len(new["monsters"]) == 120 and new["slot_count"] == 5802
    changed_output_rows = 0
    changed_nonarmor_output_rows = 0
    live_removed = []
    for m in new["monsters"]:
        previous = old_live[m["monster_id"]]
        assert m["slots"] == [s for s in previous["slots"] if s["slot_uid"] not in removed]
        assert m["maps"] == previous["maps"] and m["classification"] == previous["classification"]
        live_removed += [s["slot_uid"] for s in previous["slots"] if s["slot_uid"] in removed]
        old_outputs = {tuple(r["key"]): r for r in previous["outputs"]}
        assert len(m["outputs"]) == len(old_outputs)
        for r in m["outputs"]:
            if r["actual_probability"] != old_outputs[tuple(r["key"])]["actual_probability"]:
                changed_output_rows += 1
                changed_nonarmor_output_rows += r["item_id"] not in armor_ids
    assert len(live_removed) == 95
    report = {"status": "PASS", "formal_authority_sha256": authority_sha,
              "recompiled_products": compiled_products,
              "source_sha256": new["source_sha256"],
              "directive_file_sha256": hashlib.sha256(directive_path.read_bytes()).hexdigest(),
              "directive_authority_recorded_sha256": after["source"]["armor_single_slot_directive_sha256"],
              "hash_contract": "UTF-8 JSON ensure_ascii=false sort_keys=true compact separators; list order retained",
              "authority_monsters": 126, "authority_before_slots": sum(len(m["slots"]) for m in before["monsters"]),
              "authority_after_slots": sum(len(m["slots"]) for m in after["monsters"]),
              "directive_removed_slots": len(removed), "directive_affected_monsters": 37,
              "all_retained_slot_records_and_order_unchanged": True,
              "retained_armor_original_probability_unchanged": True,
              "nonarmor_slots_unchanged": len(nonarmor_after),
              "nonarmor_before_sha256": digest(nonarmor_before), "nonarmor_after_sha256": digest(nonarmor_after),
              "overlay_slots_unchanged": len(overlays_after),
              "overlay_before_sha256": digest(overlays_before), "overlay_after_sha256": digest(overlays_after),
              "frozen_exceptions": exceptions,
              "live_removed_slots": len(live_removed), "live_removed_slot_uids": live_removed,
              "live_maps_and_classifications_unchanged": True,
              "actual_probability_changed_rows": changed_output_rows,
              "actual_probability_changed_nonarmor_rows": changed_nonarmor_output_rows,
              "actual_probability_change_note": "Removing competing armor slots may change other output inclusion probabilities under the unchanged cap15; their per-slot probabilities and priorities are unchanged."}
    (root / "armor_revision_verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in ("frozen_exceptions", "live_removed_slot_uids")}, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    run()
