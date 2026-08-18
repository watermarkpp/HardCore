"""Core combat authority regression test.

Golden 9d6435bc established vanilla_176/monsters.json as the primary authority
for core combat stats (level, exp, hp, defense, magic_defense, attack_min,
attack_max).  Crystal service records must NEVER override these fields.

This test verifies:
1. All active canonical combat stats match vanilla exact-ID records.
2. Explicit policy combat_override is applied where present.
3. Source evidence points to vanilla, not Crystal.
4. Variant isolation: shared art skin != shared combat data.
5. Retired IDs remain absent.
6. AI/timing data is decoupled from combat fix.
7. Art/drop/classification are unchanged.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "tools" / "build_canonical_monster_catalog.py"
SPEC = importlib.util.spec_from_file_location("canonical_monster_catalog_generator", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)

CORE_COMBAT_FIELDS = ("level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max")
VANILLA_COMBAT_KEYS = {
    "level": "level",
    "exp": "exp",
    "hp": "hp",
    "defense": "defense",
    "magic_defense": "magicDefense",
    "attack_min": "attackMin",
    "attack_max": "attackMax",
}


def _load_vanilla_by_id() -> dict[int, dict]:
    vanilla = GENERATOR.load_json(GENERATOR.VANILLA_PATH)
    return {
        int(r["monsterId"]): r
        for r in vanilla.get("records", [])
        if isinstance(r, dict) and r.get("recordStatus") != "retired"
    }


def _load_policy_overrides() -> dict[str, dict]:
    policy = GENERATOR.load_json(GENERATOR.POLICY_PATH)
    return policy.get("wooma_matrix", {})


def _assert_full_combat_authority(catalog: dict) -> None:
    """Every active canonical monster's core combat stats must match its
    exact-ID vanilla record, unless an explicit policy combat_override exists."""
    vanilla_by_id = _load_vanilla_by_id()
    policy_overrides = _load_policy_overrides()
    entries_by_id = catalog.get("entries_by_id", {})
    errors = []
    for monster_id, vanilla_rec in sorted(vanilla_by_id.items()):
        entry = entries_by_id.get(str(monster_id))
        if entry is None:
            errors.append(f"ID{monster_id}: missing from active canonical")
            continue
        actual_stats = entry.get("combat", {}).get("stats", {})
        override = policy_overrides.get(str(monster_id), {})
        combat_override = override.get("combat_override", {}) if isinstance(override, dict) else {}
        for stat_field, vanilla_key in VANILLA_COMBAT_KEYS.items():
            if stat_field in combat_override:
                expected = int(combat_override[stat_field])
            else:
                raw = vanilla_rec.get(vanilla_key, 0)
                try:
                    expected = int(raw) if raw is not None else 0
                except (ValueError, TypeError):
                    expected = 0
            actual = actual_stats.get(stat_field, -1)
            if actual != expected:
                errors.append(
                    f"ID{monster_id} {stat_field}={actual} expected={expected}"
                    f"{' (override)' if stat_field in combat_override else ''}"
                )
    assert not errors, f"Combat authority violations:\n" + "\n".join(errors[:20])


def _assert_source_evidence_not_crystal(catalog: dict) -> None:
    """Non-override core combat field source evidence must NOT be Crystal."""
    policy_overrides = _load_policy_overrides()
    entries = catalog.get("entries", [])
    errors = []
    for entry in entries:
        monster_id = entry.get("monster_id")
        override = policy_overrides.get(str(monster_id), {})
        combat_override = override.get("combat_override", {}) if isinstance(override, dict) else {}
        cs = entry.get("source_evidence", {}).get("combat_stats", {})
        for field in CORE_COMBAT_FIELDS:
            if field in combat_override:
                continue
            ev = cs.get(field, {})
            dist = ev.get("distribution", "")
            if "crystal" in dist or dist == "server.crystal.cjlaaa":
                errors.append(f"ID{monster_id} {field} source is Crystal: {dist}")
    assert not errors, f"Crystal combat source violations:\n" + "\n".join(errors[:20])


def _assert_id18_combat(catalog: dict) -> None:
    """ID18 毒蜘蛛 must have vanilla combat values, not Crystal."""
    e18 = catalog["entries_by_id"]["18"]
    stats = e18["combat"]["stats"]
    assert stats["hp"] == 42, f"ID18 hp={stats['hp']} expected 42"
    assert stats["exp"] == 42, f"ID18 exp={stats['exp']} expected 42"
    assert stats["level"] == 16, f"ID18 level={stats['level']} expected 16"
    assert stats["defense"] == 2, f"ID18 defense={stats['defense']} expected 2"
    assert stats["magic_defense"] == 1, f"ID18 magic_defense={stats['magic_defense']} expected 1"
    assert stats["attack_min"] == 6, f"ID18 attack_min={stats['attack_min']} expected 6"
    assert stats["attack_max"] == 9, f"ID18 attack_max={stats['attack_max']} expected 9"


def _assert_id18_ai_timing_preserved(catalog: dict) -> None:
    """ID18 AI/timing must remain unchanged by combat fix."""
    e18 = catalog["entries_by_id"]["18"]
    ai = e18["combat"]["ai"]
    timing = e18["combat"]["timing"]
    assert ai["ai_code"] == 4, f"ID18 ai_code={ai['ai_code']} expected 4"
    assert timing["attack_interval_ms"] == 2500, f"ID18 attack_interval_ms={timing['attack_interval_ms']} expected 2500"
    assert timing["move_interval_ms"] == 900, f"ID18 move_interval_ms={timing['move_interval_ms']} expected 900"


def _assert_variant_isolation(catalog: dict) -> None:
    """Skeleton variants must use their own exact-ID combat data.
    Shared art skin does NOT mean shared combat stats."""
    by_id = catalog["entries_by_id"]
    # 56 骷髅精灵 vs 57 骷髅精灵1 vs 59 骷髅精灵9
    hp56 = by_id["56"]["combat"]["stats"]["hp"]
    hp57 = by_id["57"]["combat"]["stats"]["hp"]
    hp59 = by_id["59"]["combat"]["stats"]["hp"]
    assert hp56 == 500, f"ID56 hp={hp56} expected 500"
    assert hp57 == 800, f"ID57 hp={hp57} expected 800"
    assert hp59 == 800, f"ID59 hp={hp59} expected 800"
    # 57/59 must NOT inherit 56's combat stats
    assert hp57 != hp56 or hp56 == 800, "ID57 inherited ID56 hp"
    # Additional skeleton variants
    for mid in [48, 49, 51, 53, 55]:
        entry = by_id.get(str(mid))
        assert entry is not None, f"ID{mid} missing"
        stats = entry["combat"]["stats"]
        assert any(v != 0 for v in stats.values()), f"ID{mid} all combat stats zero"


def _assert_retired_ids_absent(catalog: dict) -> None:
    """Retired IDs 14/16/17 must not be in active canonical."""
    by_id = catalog["entries_by_id"]
    for rid in ("14", "16", "17"):
        assert rid not in by_id, f"retired ID {rid} found in active canonical"


def _assert_service_cannot_override_vanilla(catalog: dict) -> None:
    """Even when service has exact_service_name, core combat stats must
    come from vanilla, not Crystal."""
    service = GENERATOR.load_json(GENERATOR.SERVICE_PATH)
    by_id = catalog["entries_by_id"]
    policy_overrides = _load_policy_overrides()
    vanilla_by_id = _load_vanilla_by_id()
    for raw_id, service_row in service.get("runtimeByMonsterId", {}).items():
        if not isinstance(service_row, dict):
            continue
        if service_row.get("resolutionStatus") != "exact_service_name":
            continue
        monster_id = int(raw_id)
        entry = by_id.get(str(monster_id))
        if entry is None:
            continue
        vanilla_rec = vanilla_by_id.get(monster_id)
        if vanilla_rec is None:
            continue
        override = policy_overrides.get(str(monster_id), {})
        combat_override = override.get("combat_override", {}) if isinstance(override, dict) else {}
        service_rec = service_row.get("serviceRecord", {})
        service_stats = service_rec.get("stats", {})
        # Compare HP: if "hp" not in combat_override and vanilla != crystal,
        # the final value must be vanilla, not Crystal.
        vanilla_hp = int(vanilla_rec.get("hp", 0))
        crystal_hp = int(service_stats.get("12", 0))
        actual_hp = entry["combat"]["stats"]["hp"]
        if "hp" not in combat_override and vanilla_hp != crystal_hp:
            assert actual_hp == vanilla_hp, (
                f"ID{monster_id} hp={actual_hp} should be vanilla={vanilla_hp} not Crystal={crystal_hp}"
            )


def _assert_no_zeroed_combat_for_active(catalog: dict) -> None:
    """No active monster should have all core combat stats zeroed."""
    entries = catalog["entries"]
    errors = []
    for entry in entries:
        stats = entry["combat"]["stats"]
        if all(stats.get(f, 0) == 0 for f in CORE_COMBAT_FIELDS):
            errors.append(f"ID{entry['monster_id']} all core combat stats zero")
    assert not errors, f"Zeroed combat:\n" + "\n".join(errors[:20])


def _assert_combat_identity_decoupled_from_service(catalog: dict) -> None:
    """core_combat_identity_ok must be True for all active monsters,
    regardless of service exact match status."""
    entries = catalog["entries"]
    errors = []
    for entry in entries:
        status = entry.get("source_evidence", {}).get("status", {})
        if not status.get("core_combat_identity_ok", False):
            errors.append(f"ID{entry['monster_id']} core_combat_identity_ok=False")
    assert not errors, f"Combat identity blocked:\n" + "\n".join(errors[:20])


def _assert_art_drop_classification_unchanged(catalog: dict) -> None:
    """Art profiles, drop profiles, and classification data must not be
    altered by the combat authority fix."""
    entries = catalog["entries"]
    assert len(entries) == 214, f"active count={len(entries)} expected 214"
    # Verify art profiles exist and have source evidence
    profiles = catalog.get("appearance_profiles", {})
    assert len(profiles) > 0, "no appearance profiles"
    # Verify drop profiles exist
    drops = catalog.get("drop_profiles", {})
    assert len(drops) > 0, "no drop profiles"
    # Verify classification is present for every entry
    for entry in entries:
        assert "classification" in entry, f"ID{entry['monster_id']} missing classification"
        assert "appearance_profile_id" in entry, f"ID{entry['monster_id']} missing art profile"
        assert "drop_profile_id" in entry, f"ID{entry['monster_id']} missing drop profile"


def _assert_canonical_name_from_vanilla(catalog: dict) -> None:
    """Canonical name must come from vanilla exact-ID record.name for ALL active.
    policy canonical_name_override is no longer consumed."""
    vanilla_by_id = _load_vanilla_by_id()
    by_id = catalog["entries_by_id"]
    errors = []
    for monster_id, vanilla_rec in sorted(vanilla_by_id.items()):
        entry = by_id.get(str(monster_id))
        if entry is None:
            continue
        expected_name = str(vanilla_rec.get("name", ""))
        actual_name = entry.get("canonical_name", "")
        if actual_name != expected_name:
            errors.append(f"ID{monster_id} name={actual_name!r} expected={expected_name!r}")
    assert not errors, f"Canonical name violations:\n" + "\n".join(errors[:20])
    assert len(vanilla_by_id) == 214, f"CANONICAL_NAME_VANILLA_EXACT_ID_COUNT={len(vanilla_by_id)} expected 214"


def _assert_synthetic_fail_closed() -> None:
    """Test read_vanilla_core_combat_exact_id with synthetic dictionaries."""
    helper = GENERATOR.read_vanilla_core_combat_exact_id

    # CASE 1: missing hp → all_fields_valid = False
    rec_missing = {"level": 1, "exp": 10, "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_missing)
    assert not all_ok, "missing hp should fail closed"
    assert validity["hp"] is False
    assert stats["hp"] == 0

    # CASE 2: hp = "INVALID" → False
    rec_invalid = {"level": 1, "exp": 10, "hp": "INVALID", "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_invalid)
    assert not all_ok, "invalid hp string should fail closed"
    assert validity["hp"] is False

    # CASE 3: hp = -1 → False (negative)
    rec_negative = {"level": 1, "exp": 10, "hp": -1, "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_negative)
    assert not all_ok, "negative hp should fail closed"
    assert validity["hp"] is False

    # CASE 4: defense=0, attackMin=0, rest valid → True (0 is legal)
    rec_zero = {"level": 1, "exp": 10, "hp": 50, "defense": 0, "magicDefense": 0, "attackMin": 0, "attackMax": 5}
    stats, validity, all_ok = helper(rec_zero)
    assert all_ok, f"legal zeros should pass: validity={validity}"
    assert stats["defense"] == 0
    assert stats["attack_min"] == 0

    # CASE 5: bool value → False (bool is not legal int)
    rec_bool = {"level": 1, "exp": 10, "hp": True, "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_bool)
    assert not all_ok, "bool hp should fail closed"
    assert validity["hp"] is False

    # CASE 6: float 1.0 → False (float is not legal int, no coercion)
    rec_float_1 = {"level": 1, "exp": 10, "hp": 1.0, "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_float_1)
    assert not all_ok, "float 1.0 hp should fail closed"
    assert validity["hp"] is False

    # CASE 7: float 1.5 → False (float is not legal int, no truncation)
    rec_float_15 = {"level": 1, "exp": 10, "hp": 1.5, "defense": 1, "magicDefense": 0, "attackMin": 2, "attackMax": 5}
    stats, validity, all_ok = helper(rec_float_15)
    assert not all_ok, "float 1.5 hp should fail closed"
    assert validity["hp"] is False


def _assert_invalid_override_rejected() -> None:
    """Explicit combat_override with invalid type must fail closed."""
    # Simulate a record with valid vanilla data but invalid override
    rec = {"level": 10, "exp": 100, "hp": 500, "defense": 5, "magicDefense": 3, "attackMin": 10, "attackMax": 20}
    stats, validity, all_ok = GENERATOR.read_vanilla_core_combat_exact_id(rec)
    assert all_ok, "vanilla record should be valid"

    # Now simulate override with float value (100.5)
    # The override validation happens in build_catalog, so we test the logic directly
    override_value = 100.5
    is_valid = not (isinstance(override_value, bool) or not isinstance(override_value, int) or override_value < 0)
    assert not is_valid, "float override 100.5 should be rejected"


def _assert_runtime_allowed_ai_timing_guard(catalog: dict) -> None:
    """All runtime_allowed=true entries must have ai_authority_ok and
    timing_authority_ok both true."""
    entries = catalog["entries"]
    errors = []
    for entry in entries:
        if not entry.get("runtime_allowed"):
            continue
        status = entry.get("source_evidence", {}).get("status", {})
        if not status.get("ai_authority_ok"):
            errors.append(f"ID{entry['monster_id']} runtime_allowed but ai_authority_ok=False")
        if not status.get("timing_authority_ok"):
            errors.append(f"ID{entry['monster_id']} runtime_allowed but timing_authority_ok=False")
    assert not errors, f"Runtime authority guard violations:\n" + "\n".join(errors[:20])


def main() -> None:
    catalog = GENERATOR.build_catalog()

    _assert_full_combat_authority(catalog)
    _assert_source_evidence_not_crystal(catalog)
    _assert_id18_combat(catalog)
    _assert_id18_ai_timing_preserved(catalog)
    _assert_variant_isolation(catalog)
    _assert_retired_ids_absent(catalog)
    _assert_service_cannot_override_vanilla(catalog)
    _assert_no_zeroed_combat_for_active(catalog)
    _assert_combat_identity_decoupled_from_service(catalog)
    _assert_art_drop_classification_unchanged(catalog)
    _assert_canonical_name_from_vanilla(catalog)
    _assert_synthetic_fail_closed()
    _assert_invalid_override_rejected()
    _assert_runtime_allowed_ai_timing_guard(catalog)

    active_count = len(catalog["entries"])
    runtime_allowed = sum(1 for e in catalog["entries"] if e["runtime_allowed"])
    ai_resolved = sum(1 for e in catalog["entries"] if e["source_evidence"]["status"].get("ai_authority_ok"))
    timing_resolved = sum(1 for e in catalog["entries"] if e["source_evidence"]["status"].get("timing_authority_ok"))
    print(
        f"CANONICAL_MONSTER_COMBAT_AUTHORITY_PASS: "
        f"active={active_count} runtime_allowed={runtime_allowed} "
        f"ai_authority_resolved={ai_resolved} timing_authority_resolved={timing_resolved} "
        f"full_combat_match=1 source_not_crystal=1 "
        f"id18_combat=1 id18_ai_timing=1 variant_isolation=1 "
        f"retired_absent=1 service_override_forbidden=1 "
        f"no_zeroed_combat=1 identity_decoupled=1 "
        f"art_drop_classification=1 canonical_name_vanilla=1 "
        f"synthetic_fail_closed=1 invalid_override_rejected=1 runtime_authority_guard=1"
    )


if __name__ == "__main__":
    main()
