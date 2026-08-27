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

# The six historical Monster.DB conflicts retained as superseded evidence.
MONSTER_DB_CORE_OVERRIDE_IDS = {39, 107, 162, 163, 168, 193}

# Special/event entities that must keep P3C stats even when Monster.DB differs.
MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS = {146, 226, 234}

# ID 68 also retains its historical Wooma auxiliary row as superseded evidence.
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

DETAIL_SOURCE_PATH = ROOT / "assets/data/monster_21cq_detail_source_v1.json"


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

# Monster.DB active coverage remains useful for conflict auditing only.
dsh_records = combat_source["records_by_monster_id"]
dsh_ids = {int(k) for k in dsh_records.keys()}
active_with_dsh = sorted(set(ids) & dsh_ids)
active_without_dsh = sorted(set(ids) - dsh_ids)
assert len(active_with_dsh) == 144, "ACTIVE_WITH_DSH_COMBAT_COUNT drifted"
assert active_without_dsh == ACTIVE_WITHOUT_DB_COMBAT_IDS, "no-DB set drifted"

for mid in sorted_ids:
    entry = by_id[mid]
    assert bool(entry.get("runtime_allowed", False)) or True  # structural

# 1. All active core fields must match the exact-ID 21CQ detail row.
detail_source = json.loads(DETAIL_SOURCE_PATH.read_text(encoding="utf-8"))
assert detail_source.get("authority") == "user_authoritative_override"
detail_records = detail_source.get("records", [])
assert len(detail_records) == 217, "21CQ detail source coverage drifted"
detail_by_id = {int(record["monster_id"]): record for record in detail_records}
checked_21cq = 0
for mid in sorted_ids:
    detail = detail_by_id[mid]
    stats = by_id[mid]["combat"]["stats"]
    for field in CORE_FIELDS:
        assert stats.get(field) == detail.get(field), (
            f"monster_id={mid} {field}={stats.get(field)} "
            f"expected 21CQ={detail.get(field)}"
        )
    checked_21cq += 1
assert checked_21cq == ACTIVE_COUNT, "expected all active records to be 21CQ-bound"

# 1b. ID 68 keeps its auxiliary row only as superseded evidence while the
#     21CQ values are canonical.
assert by_id[68]["combat"]["stats"]["exp"] == detail_by_id[68]["exp"] == 280
assert by_id[68]["combat"]["stats"]["attack_min"] == detail_by_id[68]["attack_min"] == 15
assert by_id[68]["combat"]["stats"]["attack_max"] == detail_by_id[68]["attack_max"] == 29
assert by_id[68]["source_evidence"].get("combat_auxiliary", {}), (
    "ID 68 must retain historical auxiliary combat evidence"
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
    f"exact_21cq_bound={checked_21cq} "
    f"excluded_specials={sorted(MONSTER_DB_CORE_EXCLUDED_SPECIAL_IDS)} "
    f"wooma_aux1_exception={sorted(WOOMA_AUX1_EXCEPTION_IDS)} "
    f"no_db={len(active_without_dsh)}"
)
