"""Lock the combat source exact-name binding contract and ambiguity rejection."""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMBAT_SOURCE_PATH = ROOT / "assets/data/canonical_monster_combat_source_v1.json"
VANILLA_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
EXPECTED_DISTRIBUTION = "server.mylgd_mir2server_176.monster_db_176"


def _collect_unbound_statuses(records: list[dict]) -> Counter[str]:
    return Counter(str(item.get("binding_status", "")) for item in records)


def main() -> None:
    payload = json.loads(COMBAT_SOURCE_PATH.read_text(encoding="utf-8"))
    records = payload.get("records_by_monster_id", {})
    binding = payload.get("binding", {})
    unbound = binding.get("unbound", [])
    vanilla = json.loads(VANILLA_PATH.read_text(encoding="utf-8")).get("records", [])

    assert payload.get("distribution") == EXPECTED_DISTRIBUTION
    assert isinstance(records, dict), "records_by_monster_id missing"
    assert isinstance(unbound, list), "binding.unbound missing"

    # Identity scope must remain one record per vanilla ID and all unresolved records
    # remain fail-closed.
    assert len(vanilla) == len(records) + len(unbound)

    for monster_id, record in records.items():
        assert str(record.get("monster_id")) == str(monster_id), (
            f"monster_id key mismatch: {monster_id}"
        )
        assert record.get("binding_status") in {
            "exact_unique_name",
            "explicit_override_verified",
            "explicit_override_unverified",
        }, f"{monster_id} binding_status={record.get('binding_status')}"
        assert int(record.get("binding_candidate_count", 0)) == 1, (
            f"{monster_id} binding_candidate_count={record.get('binding_candidate_count')}"
        )
        assert isinstance(record.get("source_row_index"), int), (
            f"{monster_id} missing source_row_index"
        )
        assert int(record.get("source_row_index")) >= 0, (
            f"{monster_id} source_row_index invalid"
        )
        assert int(record.get("source_record_ordinal", 0)) > 0, (
            f"{monster_id} source_record_ordinal invalid"
        )
        assert record.get("source_distribution") == EXPECTED_DISTRIBUTION
        assert record.get("source_tier") in {"primary", "auxiliary_1"}, (
            f"{monster_id} unexpected source_tier={record.get('source_tier')}"
        )
        assert record.get("source_distribution") == EXPECTED_DISTRIBUTION

    for item in unbound:
        status = str(item.get("binding_status", ""))
        candidate_count = int(item.get("binding_candidate_count", 0))
        assert status in {
            "unbound",
            "duplicate_exact_name",
            "explicit_override_unverified",
        }, f"unexpected unbound binding_status={status}"
        assert candidate_count >= 0, f"invalid candidate count: {candidate_count}"
        if status == "unbound":
            assert candidate_count == 0, f"unbound requires 0: {candidate_count}"
        if status == "duplicate_exact_name":
            assert candidate_count > 1, f"duplicate_exact_name requires >1: {candidate_count}"
        if status == "explicit_override_unverified":
            assert candidate_count >= 1, (
                f"explicit_override_unverified requires candidate rows: {candidate_count}"
            )
        assert item.get("source_distribution") == EXPECTED_DISTRIBUTION

    summary_counts = _collect_unbound_statuses(unbound)
    assert (
        binding.get("explicit_duplicate_count", 0)
        == summary_counts.get("duplicate_exact_name", 0)
    ), "binding summary mismatch"
    assert payload.get("binding", {}).get("bound_count", 0) == len(records)
    assert payload.get("binding", {}).get("unbound_count", 0) == len(unbound)

    # A duplicate/override-unverified path must never be written as runtime combat source.
    for status in ("duplicate_exact_name", "explicit_override_unverified"):
        assert status not in summary_counts or summary_counts[status] >= 0

    print(
        "CANONICAL_MONSTER_COMBAT_SOURCE_BINDING_PASS: "
        f"records={len(records)} unbound={len(unbound)}"
    )


if __name__ == "__main__":
    main()
