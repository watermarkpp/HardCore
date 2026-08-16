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
    """The user Excel (217 records / 9590 slots) is the canonical drop authority.

    Old Crystal Drops must not be a primary runtime drop source.
    """
    entries = catalog.get("entries", [])
    entries_by_id = catalog.get("entries_by_id", {})
    drop_profiles = catalog.get("drop_profiles", {})
    assert len(entries) == 217, len(entries)

    anchors = {76: 33, 239: 54, 240: 54}
    for monster_id, expected in anchors.items():
        entry = entries_by_id.get(str(monster_id), {})
        profile = drop_profiles.get(str(entry.get("drop_profile_id", "")), {})
        assert int(profile.get("entry_count", 0)) == expected, (monster_id, profile.get("entry_count"))
        assert profile.get("status") == "exact_slots", (monster_id, profile.get("status"))

    snowman = entries_by_id.get("33", {})
    assert drop_profiles.get(str(snowman.get("drop_profile_id", "")), {}).get("status") == "no_drop_confirmed"

    # 21CQ stable Mob.aspx?ID identity: 鸡=14, 鹿=16, 鹿1=17.
    assert entries_by_id.get("14", {}).get("canonical_name") == "鸡", entries_by_id.get("14")
    assert entries_by_id.get("16", {}).get("canonical_name") == "鹿", entries_by_id.get("16")
    assert entries_by_id.get("17", {}).get("canonical_name") == "鹿1", entries_by_id.get("17")
    # The Excel audit sequence IDs 1/2/3 are NOT canonical monster IDs.
    for forbidden in ("1", "2", "3"):
        assert forbidden not in entries_by_id, forbidden

    # 鹿1 (17) is a hidden-suffix high-attribute variant from the Excel/21CQ
    # offline audit; its classification evidence must not claim an attachment
    # exact ID override (the attachment has no exactIdOverrides entry for 17).
    deer1_classification = entries_by_id.get("17", {}).get("source_evidence", {}).get("classification", {})
    assert deer1_classification.get("resolution") == "excel_offline_audit_hidden_suffix_variant", deer1_classification

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
    assert excel_primary_count == 217, excel_primary_count
    assert crystal_primary_count == 0, crystal_primary_count

    total = sum(int(p.get("entry_count", 0)) for p in drop_profiles.values())
    assert total == 9590, total


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
    entries_by_id = catalog.get("entries_by_id", {})
    assert entries_by_id.get("39", {}).get("editor_placement", {}).get(
        "placement_kind"
    ) == "boss_spawn", entries_by_id.get("39", {}).get("editor_placement", {})

    print(
        "CANONICAL_MONSTER_CATALOG_HASH_PASS: "
        "lf_crlf_equivalent=1 binary_raw=1 source_metadata=1 "
        "excel_drop_authority=1 classification_placement_kind=1 "
        "local_from_res_portable=1 excel_source_sha=1 crystal_primary_zero=1 "
        "deer1_provenance=1"
    )


if __name__ == "__main__":
    main()
