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


DROP_EQUIVALENCE_BASELINE_COMMIT = "f938510ce35d42845bd15bbe363e151361171a82"


def _normalised_json_hash(value: object) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return GENERATOR.sha256_bytes(payload.encode("utf-8"))


def _assert_drop_equivalence_scope(catalog: dict[str, object]) -> None:
    """Only Wooma 68/69 may change drop rows in the audited equivalence fix."""
    baseline_bytes = subprocess.check_output(
        [
            "git",
            "show",
            f"{DROP_EQUIVALENCE_BASELINE_COMMIT}:assets/data/runtime/canonical_monster_catalog.json",
        ],
        cwd=ROOT,
    )
    baseline = json.loads(baseline_bytes.decode("utf-8"))
    current_profiles = catalog.get("drop_profiles", {})
    baseline_profiles = baseline.get("drop_profiles", {})
    assert isinstance(current_profiles, dict) and isinstance(baseline_profiles, dict)
    assert set(current_profiles) == set(baseline_profiles)

    for profile_id, profile in current_profiles.items():
        if profile_id in {"drop.68", "drop.69"}:
            continue
        baseline_profile = baseline_profiles[profile_id]
        assert profile.get("entry_count") == baseline_profile.get("entry_count"), profile_id
        assert _normalised_json_hash(profile) == _normalised_json_hash(baseline_profile), profile_id

    for profile_id, expected_count in (("drop.68", 58), ("drop.69", 62)):
        profile = current_profiles[profile_id]
        assert profile.get("entry_count") == expected_count
        assert profile.get("status") == "formal_id_keyed_cross_distribution_equivalence"
        items = {str(row.get("item", "")) for row in profile.get("entries", [])}
        assert "LongBow" not in items and "SilverBow" not in items

    assert current_profiles["drop.68"].get("entry_count") + current_profiles["drop.69"].get("entry_count") == 120


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

    _assert_drop_equivalence_scope(catalog)
    _assert_classification_placement_kind()
    _assert_local_from_res_portable()
    entries_by_id = catalog.get("entries_by_id", {})
    assert entries_by_id.get("39", {}).get("editor_placement", {}).get(
        "placement_kind"
    ) == "boss_spawn", entries_by_id.get("39", {}).get("editor_placement", {})

    print(
        "CANONICAL_MONSTER_CATALOG_HASH_PASS: "
        "lf_crlf_equivalent=1 binary_raw=1 source_metadata=1 "
        "drop_equivalence_scope=1 classification_placement_kind=1 "
        "local_from_res_portable=1"
    )


if __name__ == "__main__":
    main()
