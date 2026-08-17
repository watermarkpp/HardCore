"""Lock the shared appearance authority contract (R3C).

R3C proves via exact 1.76 evidence that multiple canonical monster ids may
legally reference the same exact client appearance profile. Anchors: ID77
沃玛教主1 and ID239 暗之沃玛教主 share (RaceImg=21, Appr=34, MA19,
Mon4.wil base=1440). Sharing is bounded to explicit exact-ID manifest
bindings; identity, combat, drops, classification and runtime semantics stay
independent, and IDs without an explicit binding are never auto-attached.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
MANIFEST_PATH = ROOT / "assets/data/complete_monster_client_art_sources.json"


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    by_id = {int(e["monster_id"]): e for e in catalog["entries"]}
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    man_by_id = manifest["runtimeMappingsByMonsterId"]

    # 1. ID77 and ID239 may legally reference the same exact appearance profile.
    p77 = str(by_id[77].get("appearance_profile_id", ""))
    p239 = str(by_id[239].get("appearance_profile_id", ""))
    assert p77 and p239 and p77 == p239, f"77/239 must share profile: {p77} vs {p239}"
    # The shared profile is the explicit Wooma slug (not a name-derived one).
    assert "dark_wooma_taurus" in p239, f"239 profile slug drifted: {p239}"

    # 2. Canonical ids remain distinct monsters.
    assert int(by_id[77]["monster_id"]) != int(by_id[239]["monster_id"])
    assert str(by_id[77].get("canonical_name", "")) != str(by_id[239].get("canonical_name", ""))

    # 3. Combat is not shared.
    c77 = by_id[77].get("combat", {})
    c239 = by_id[239].get("combat", {})
    assert c77.get("stats") != c239.get("stats"), "77/239 combat stats must differ"
    assert int(c77.get("stats", {}).get("attack_min", -1)) == 0, "ID77 attack_min must stay 0 (frozen)"
    assert int(c239.get("stats", {}).get("attack_min", -1)) > 0, "ID239 attack must remain positive"

    # 4. Drops are not shared.
    d77 = by_id[77].get("drop_policy", {})
    d239 = by_id[239].get("drop_policy", {})
    assert int(d77.get("entry_count", 0)) != int(d239.get("entry_count", 0)), "77/239 drop counts must differ"
    assert int(d239.get("entry_count", 0)) == 54, "ID239 drop slots must stay 54"

    # 5. ID239 runtime must not regress.
    assert bool(by_id[239].get("runtime_allowed", False)), "ID239 runtime regressed"
    assert by_id[239].get("source_evidence", {}).get("status", {}).get("art_status") == "formal"

    # 6. No automatic attachment: only explicitly bound ids share this profile.
    sharing = [mid for mid, e in by_id.items()
               if str(e.get("appearance_profile_id", "")) == p239]
    assert set(sharing) == {77, 239}, f"profile {p239} unexpectedly shared by {sharing}"

    # Manifest exact bindings are explicit and ID-keyed.
    m77 = man_by_id.get("77", {})
    assert int(m77.get("appearance", -1)) == 34 and int(m77.get("raceImg", -1)) == 21
    assert str(m77.get("actionTable", "")) == "MA19"
    assert str(m77.get("databaseName", "")) == "沃玛教主1"
    assert str(m77.get("resolutionStatus", "")) == "exact_monster_db_name"

    print("CANONICAL_MONSTER_SHARED_APPEARANCE_PASS: shared_profile=yes ids=[77,239] "
          "combat_independent=yes drops_independent=yes id239_runtime=true no_auto_attach=yes")


if __name__ == "__main__":
    main()
