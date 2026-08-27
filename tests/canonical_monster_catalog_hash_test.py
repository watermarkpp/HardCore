"""Lock the canonical generator's checkout-independent text hash contract."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "tools" / "build_canonical_monster_catalog.py"
SPEC = importlib.util.spec_from_file_location("canonical_monster_catalog_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def _assert_excel_drop_authority(catalog: dict[str, object]) -> None:
    """The user Excel (217 source records / 9590 source slots) is the canonical
    drop authority.  The P3C active runtime universe carries 156 entries /
    7032 drop slots.  Old Crystal Drops must not be a primary runtime drop
    source.  The 217 source record count is a source-table truth, not a
    runtime count.
    """
    entries = catalog.get("entries", [])
    entries_by_id = catalog.get("entries_by_id", {})
    drop_profiles = catalog.get("drop_profiles", {})
    # Active runtime identities: P3C active universe = 156.
    assert len(entries) == 156, len(entries)

    anchors = {76: 33, 239: 54, 240: 54}
    for monster_id, expected in anchors.items():
        entry = entries_by_id.get(str(monster_id), {})
        profile = drop_profiles.get(str(entry.get("drop_profile_id", "")), {})
        assert _base_drop_row_count(profile) == expected, (monster_id, profile.get("entry_count"))
        assert profile.get("status") == "exact_slots", (monster_id, profile.get("status"))

    snowman = entries_by_id.get("33", {})
    assert drop_profiles.get(str(snowman.get("drop_profile_id", "")), {}).get("status") == "no_drop_confirmed"

    # Retired IDs 14 (鸡), 16 (鹿), 17 (鹿1) must NOT appear in active runtime.
    for retired_id in ("14", "16", "17"):
        assert retired_id not in entries_by_id, f"retired ID {retired_id} must not be in active canonical"
    # The Excel audit sequence IDs 1/2/3 are NOT canonical monster IDs.
    for forbidden in ("1", "2", "3"):
        assert forbidden not in entries_by_id, forbidden

    workbook_sha = "6902A37DB839577D2CE440B9EFDC4628430CF063BF9DF505F03B41E24A5D67EE"
    excel_primary_count = 0
    crystal_primary_count = 0
    for profile in drop_profiles.values():
        for source in profile.get("source_evidence", {}).get("sources", []):
            if not isinstance(source, dict):
                continue
            distribution = str(source.get("distribution", ""))
            role = str(source.get("role", ""))
            if distribution == "user.excel.217_monster_drop_slots" and role == "drop_profile_primary":
                # Excel source SHA provenance must be non-empty and equal to
                # the locked workbook SHA256 (never a duplicate empty string).
                assert str(source.get("sha256", "")).upper() == workbook_sha, source
                excel_primary_count += 1
            if distribution == "server.crystal.cjlaaa" and role.startswith("drop_profile_primary"):
                crystal_primary_count += 1
    # Active runtime drop profiles: P3C active universe = 156.
    assert excel_primary_count == 156, excel_primary_count
    assert crystal_primary_count == 0, crystal_primary_count

    total = sum(_base_drop_row_count(p) for p in drop_profiles.values())
    # Active runtime base drop slots: P3C active universe total = 7032.
    # Authoring overlay rows are excluded from the base count so future
    # authoring additions do not break the Excel authority anchor.
    assert total == 7032, total


def _base_drop_row_count(profile: dict[str, object]) -> int:
    count = 0
    for raw_row in profile.get("entries", []):
        if isinstance(raw_row, dict) and "authoring_entry_key" not in raw_row:
            count += 1
    return count


def _assert_classification_placement_kind() -> None:
    """classification_for() must read the formal snake_case field, not the
    retired camelCase spelling, so an authored ``placement_kind`` survives."""
    classification_ids = GENERATOR.load_json(GENERATOR.CLASSIFICATION_ID_PATH)
    policy = GENERATOR.load_json(GENERATOR.POLICY_PATH)
    classification_name, placement_allowed, placement_kind, _, _ = (
        GENERATOR.classification_for(39, classification_ids, policy)
    )
    assert classification_name == "special", classification_name
    assert placement_allowed is True
    assert placement_kind == "boss_spawn", placement_kind


def _assert_variant_visual_pairs(catalog: dict[str, object]) -> None:
    """Active variants must share appearance_profile_id with their base,
    while retaining their own distinct monster_id and combat data.

    P3C pruned the retired duplicate variants (48/49/51/53/80/82/84/86/88), so
    only the remaining active pairs are asserted here.
    """
    entries_by_id = catalog.get("entries_by_id", {})
    variant_pairs = [
        (55, 54), (57, 56), (59, 56),
        (77, 76), (78, 76),
        (90, 89), (91, 89),
        (161, 160),
    ]
    for variant_id, base_id in variant_pairs:
        v = entries_by_id.get(str(variant_id), {})
        b = entries_by_id.get(str(base_id), {})
        assert v, f"variant id={variant_id} missing from canonical"
        assert b, f"base id={base_id} missing from canonical"
        assert int(v.get("monster_id", -1)) == variant_id, f"variant {variant_id} monster_id mismatch"
        assert int(b.get("monster_id", -1)) == base_id, f"base {base_id} monster_id mismatch"
        assert variant_id != base_id, f"variant {variant_id} == base"
        v_profile = v.get("appearance_profile_id", "")
        b_profile = b.get("appearance_profile_id", "")
        assert v_profile and v_profile == b_profile, (
            f"variant {variant_id} profile '{v_profile}' != base {base_id} profile '{b_profile}'"
        )


def _assert_undead_exact_id_authority() -> None:
    """bich_undead runtimeMappingsByMonsterId must have exactly 25 string-ref
    entries and zero full-dict duplication."""
    undead = GENERATOR.load_json(ROOT / "assets" / "data" / "bich_undead_client_art_sources.json")
    by_id = undead.get("runtimeMappingsByMonsterId", {})
    assert len(by_id) == 25, f"undead by_id count={len(by_id)} expected 25"
    full_dict_count = sum(1 for v in by_id.values() if isinstance(v, dict))
    string_ref_count = sum(1 for v in by_id.values() if isinstance(v, str))
    assert full_dict_count == 0, f"undead full dict duplication={full_dict_count} expected 0"
    assert string_ref_count == 25, f"undead string refs={string_ref_count} expected 25"


def _assert_boss_variant_mappings() -> None:
    """classic_boss must map 77->沃玛教主, 78->沃玛教主, 161->祖玛教主."""
    boss = GENERATOR.load_json(ROOT / "assets" / "data" / "classic_boss_client_art_sources.json")
    by_id = boss.get("runtimeMappingsByMonsterId", {})
    assert by_id.get("77") == "沃玛教主", by_id.get("77")
    assert by_id.get("78") == "沃玛教主", by_id.get("78")
    assert by_id.get("161") == "祖玛教主", by_id.get("161")


def _assert_retired_ids() -> None:
    """Retired IDs 14/16/17 must be preserved in vanilla source with
    recordStatus=retired, but absent from active canonical runtime."""
    vanilla = GENERATOR.load_json(ROOT / "assets" / "data" / "vanilla_176" / "monsters.json")
    records = {int(r.get("monsterId", -1)): r for r in vanilla.get("records", [])}
    for rid, name in [(14, "鸡"), (16, "鹿"), (17, "鹿1")]:
        r = records.get(rid)
        assert r is not None, f"retired id={rid} ({name}) missing from vanilla source"
        assert r.get("recordStatus") == "retired", f"id={rid} recordStatus={r.get('recordStatus')} expected retired"


def _assert_no_generic_fallback() -> None:
    """Generator art_profiles() must not perform name-based fallback.
    Verify by checking that only runtimeMappingsByMonsterId is consumed."""
    import inspect
    source = inspect.getsource(GENERATOR.art_profiles)
    assert "vanilla_name_by_id" not in source, "generic name fallback still present in art_profiles()"
    assert "for monster_id, name in vanilla_name_by_id" not in source, "name->ID promotion loop present"


def _assert_local_from_res_portable() -> None:
    """res:// paths must resolve through pathlib, not a hardcoded ``\\``."""
    resolved = GENERATOR.local_from_res("res://assets/art/monsters/fixture.png")
    assert resolved == ROOT / "assets" / "art" / "monsters" / "fixture.png", resolved


def main() -> None:
    source = ROOT / "assets" / "data" / "canonical_monster_catalog_policy_v1.json"
    source_bytes = source.read_bytes()
    source_text = source_bytes.decode("utf-8")
    lf_bytes = source_text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    crlf_bytes = lf_bytes.replace(b"\n", b"\r\n")

    temp_parent = ROOT / "outputs"
    temp_parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(dir=temp_parent, prefix="canonical_hash_") as temp:
        temp_root = Path(temp)
        lf_copy = temp_root / "policy_lf.json"
        crlf_copy = temp_root / "policy_crlf.json"
        lf_copy.write_bytes(lf_bytes)
        crlf_copy.write_bytes(crlf_bytes)

        assert GENERATOR.sha256_file(lf_copy) == GENERATOR.sha256_file(crlf_copy)
        assert GENERATOR.hash_normalization_for(lf_copy) == "lf_text"
        assert GENERATOR.hash_normalization_for(crlf_copy) == "lf_text"
        assert json.loads(lf_copy.read_text(encoding="utf-8")) == json.loads(
            crlf_copy.read_text(encoding="utf-8")
        )
        evidence = GENERATOR.source_ref(
            crlf_copy,
            role="hash_contract_test",
            distribution="test",
            tier="test",
        )
        assert evidence["hash_normalization"] == "lf_text"

        binary_lf = temp_root / "atlas.png"
        binary_crlf = temp_root / "atlas_crlf.png"
        binary_lf.write_bytes(b"PNG\nfixture")
        binary_crlf.write_bytes(b"PNG\r\nfixture")
        assert GENERATOR.hash_normalization_for(binary_lf) == "raw_bytes"
        assert GENERATOR.sha256_file(binary_lf) != GENERATOR.sha256_file(binary_crlf)

    catalog = json.loads(
        (ROOT / "assets" / "data" / "runtime" / "canonical_monster_catalog.json").read_text(
            encoding="utf-8"
        )
    )
    for path, evidence in catalog.get("sources", {}).items():
        expected = "lf_text" if path.lower().endswith(".json") else "raw_bytes"
        assert evidence.get("hash_normalization") == expected, (path, evidence)

    _assert_excel_drop_authority(catalog)
    _assert_classification_placement_kind()
    _assert_local_from_res_portable()
    _assert_variant_visual_pairs(catalog)
    _assert_undead_exact_id_authority()
    _assert_boss_variant_mappings()
    _assert_retired_ids()
    _assert_no_generic_fallback()
    entries_by_id = catalog.get("entries_by_id", {})
    special_normal_ids = {39, 57, 74, 77, 90, 121, 137, 142}
    assert {
        int(monster_id)
        for monster_id, entry in entries_by_id.items()
        if entry.get("spawn_classification") == "special_normal"
    } == special_normal_ids
    for monster_id in special_normal_ids:
        entry = entries_by_id[str(monster_id)]
        assert entry.get("editor_placement", {}).get("placement_kind") == "monster_spawn"
        assert entry.get("spawn_authority", {}).get("respawn_policy_id") == "special_normal"
        assert entry.get("spawn_authority", {}).get("respawn_seconds") == 900
    assert entries_by_id["74"].get("classification") == "elite"

    print(
        "CANONICAL_MONSTER_CATALOG_HASH_PASS: "
        "lf_crlf_equivalent=1 binary_raw=1 source_metadata=1 "
        "excel_drop_authority=1 classification_placement_kind=1 "
        "local_from_res_portable=1 excel_source_sha=1 crystal_primary_zero=1 "
        "variant_visual_pairs=8 undead_exact_id=25 boss_variants=3 "
        "retired_source_preserved=3 retired_active_absent=3 "
        "no_generic_fallback=1 special_normal_exact_ids=8"
    )


if __name__ == "__main__":
    main()
