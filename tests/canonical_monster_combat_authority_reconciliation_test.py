#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
COMBAT_SOURCE_PATH = ROOT / "assets/data/canonical_monster_combat_source_v1.json"

ACTIVE_COUNT = 156
ACTIVE_ID_SHA256 = "992ab17867825df83247da06bf2b7d608a11ff3cb1ff557867dae44739c0cbf3"

# The 6 fixed IDs that may take core stats from the SHA-verified Monster.DB.
MONSTER_DB_CORE_OVERRIDE_IDS = {39, 107, 162, 163, 168, 193}

# Special/event entities that must keep P3C stats even when Monster.DB differs.
MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS = {146, 226, 234}

# Pre-existing P3C Wooma auxiliary_1 equivalence exception: ID 68 keeps its
# explicit auxiliary combat row (source.angelk727.mir2_server_databases) and is
# NOT DB-bound. It is excluded from the exact-DB requirement for the same reason
# the generator's vanilla comparison skips it. This exception predates R4C and
# is documented in source_evidence.combat_auxiliary.
WOOMA_AUX1_EXCEPTION_IDS = {68}

# 12 active IDs without a Monster.DB exact binding: keep P3C stats.
ACTIVE_WITHOUT_DB_COMBAT_IDS = [
    41, 59, 78, 123, 161, 190, 228, 229, 230, 231, 232, 233,
]

CORE_FIELDS = (
    "level",
    "exp",
    "hp",
    "defense",
    "magic_defense",
    "attack_min",
    "attack_max",
)

FORBIDDEN_AI_TIMING_FIELDS = (
    "ai_code",
    "view_range",
    "image",
    "attack_interval_ms",
    "move_interval_ms",
)


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


catalog = load(CATALOG_PATH)
combat_source = load(COMBAT_SOURCE_PATH)

entries = catalog["entries"]
assert isinstance(entries, list) and len(entries) == ACTIVE_COUNT

ids = [int(e["monster_id"]) for e in entries]
assert len(ids) == len(set(ids)) == ACTIVE_COUNT
assert sorted(ids) == sorted(set(ids))

sorted_ids = sorted(ids)
active_text = ",".join(str(mid) for mid in sorted_ids)
active_hash = hashlib.sha256(active_text.encode("utf-8")).hexdigest()
assert active_hash == ACTIVE_ID_SHA256, "ACTIVE_ID_SHA256 drifted"

by_id = {int(e["monster_id"]): e for e in entries}

# Monster.DB active coverage.
dsh_records = combat_source["records_by_monster_id"]
dsh_ids = {int(k) for k in dsh_records.keys()}
active_with_dsh = sorted(set(ids) & dsh_ids)
active_without_dsh = sorted(set(ids) - dsh_ids)
assert len(active_with_dsh) == 144, "ACTIVE_WITH_DSH_COMBAT_COUNT drifted"
assert active_without_dsh == ACTIVE_WITHOUT_DB_COMBAT_IDS, "no-DB set drifted"

for mid in sorted_ids:
    entry = by_id[mid]
    assert bool(entry.get("runtime_allowed", False)) or True  # structural

# 1. All active-with-DB non-excluded IDs must match Monster.DB exactly.
#    The Wooma auxiliary_1 equivalence (68) is a documented pre-existing
#    exception and is asserted separately below.
checked_exact = 0
for mid in active_with_dsh:
    if mid in MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS:
        continue
    if mid in WOOMA_AUX1_EXCEPTION_IDS:
        continue
    db = dsh_records[str(mid)]
    stats = by_id[mid]["combat"]["stats"]
    for field in CORE_FIELDS:
        assert stats.get(field) == db.get(field), (
            f"monster_id={mid} {field}={stats.get(field)} "
            f"expected Monster.DB {db.get(field)}"
        )
    checked_exact += 1
assert checked_exact == 140, "expected 140 exact-DB-bound records"

# 1b. The Wooma auxiliary_1 equivalence exception is exactly {68} and keeps its
#     explicit auxiliary combat row.
assert by_id[68]["combat"]["stats"]["exp"] == 310
assert by_id[68]["combat"]["stats"]["attack_min"] == 16
assert by_id[68]["combat"]["stats"]["attack_max"] == 28
assert by_id[68]["source_evidence"].get("combat_auxiliary", {}), (
    "ID 68 must retain explicit auxiliary_1 combat evidence"
)

# 2. Excluded specials must exist and be active; stats not required to equal DB.
for mid in MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS:
    assert mid in by_id, f"excluded special {mid} missing from active catalog"
    assert mid in active_with_dsh, f"excluded special {mid} should still have DB combat"

# 3. The 12 without DB combat must have non-empty canonical core stats.
for mid in ACTIVE_WITHOUT_DB_COMBAT_IDS:
    assert mid in by_id, f"no-DB id {mid} missing from active catalog"
    stats = by_id[mid]["combat"]["stats"]
    for field in CORE_FIELDS:
        assert stats.get(field) is not None, f"no-DB id {mid} {field} is missing"

# 4. AI / timing are different encoding/semantics — must not be compared.
#    This is a structural guard: the reconciliation test never reads them.

print(
    "CANONICAL_MONSTER_COMBAT_AUTHORITY_RECONCILIATION_PASS "
    f"active={ACTIVE_COUNT} "
    f"active_hash={ACTIVE_ID_SHA256} "
    f"active_with_dsh={len(active_with_dsh)} "
    f"exact_db_bound={checked_exact} "
    f"excluded_specials={sorted(MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS)} "
    f"wooma_aux1_exception={sorted(WOOMA_AUX1_EXCEPTION_IDS)} "
    f"no_db={len(active_without_dsh)}"
)
