"""Keep runner outcomes and literal assertion signatures separate from verdicts."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/monster_combat_r4/sol_takeover/evidence/historical_final_pairs"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    base_path = next((EVIDENCE / "BASE/runner").glob("runner_results_*.json"))
    cand_path = next((EVIDENCE / "CAND/runner").glob("runner_results_*.json"))
    base, cand = read(base_path), read(cand_path)
    current = {row["test_path"]: row for row in cand["results"]}
    assert len(current) == 25 and set(current) == {r["test_path"] for r in base["results"]}
    explicit = {
        "caster_skill_visual_factory_entry_test": ("fixture resource ownership", "Unattached factory nodes were not freed at exit; preserve type assertions and release caller-owned resources."),
        "enemy_snapshot_v2_production_test": ("fixture geometry", "2GU fixture cannot admit through frozen 1.5GU center gate; set 1.499GU, retain V2, strict same-map, cross-map rejection and no-legacy assertions."),
        "production_snapshot_no_legacy_test": ("fixture geometry", "Same 2GU admission error; remove artificial compatibility range override, keep strict schema/no-legacy checks."),
        "complete_client_resource_catalog_test": ("generated audit prerequisite", "BASE lacks outputs/resource_catalog manifest. CAND passes using existing local audit artifact, not a production repair. Independent helmet/catalog audit; clean R4 source tests must not copy this cache to claim reproducibility."),
        "warrior_skill_state_machine_test": ("fixture formal-world readiness", "Wait actual world readiness and use official mapped position, including the later geometry block; preserve toggle/resource/cooldown assertions."),
        "live_attack_resolution_test": ("fixture formal-world readiness", "Wait formal world, use official mapped ground anchor instead of screen ZERO; preserve release-frame projectile and tracking checks."),
        "melee_lock_fallback_test": ("fixture mapped geometry", "Use formal ready world and mapped anchor; retain continuous-axis near/far hit expectations."),
        "warrior_thrust_defense_runtime_test": ("fixture mapped geometry", "Wait formal world and official position; retain actual damage/defense assertions."),
        "all_monster_loading_test": ("production explicit-zero interpretation", "Raw183/241=0 exists; original native loader floors valid integer ATTACK_SPD to200ms. Preserve raw/type checks; missing remains invalid."),
        "monster_mfc1_attribute_timing_audit_test": ("production generation/loading", "Formal exact-ID generator repairs33/183/241 movement authority; explicit0 attack parsed with native200ms floor and independent expected formula. Special entity behaviors remain NOT_RUN."),
        "audio_w4_actor_service_test": ("obsolete presentation fixture", "Rendered frame assignment no longer advances authoritative audio action age; exercise owning combat-clock age and retain real service sound-count assertions. This isolated fixture is not a natural-cadence proof."),
        "armor_single_slot_authority_test": ("authoring artifact identity", "BASE compiler directive digest differs from current shared compiled authority metadata. Current directive matches unchanged primary loot/equipment data; original identity/slot/group assertions retained. No loot authority regeneration in R4."),
        "loot_async_durability_test": ("generated report directory", "BASE completed save assertions then failed opening absent generated report directory. Original CAND PASS used existing directory; now fixture creates it and asserts file open. Clean-checkout test still required."),
    }
    rows = []
    for old in base["results"]:
        name = old["test_name"]
        classification, resolution = explicit.get(name, (
            "production visual initialization lifecycle",
            "Old _ready adds BackBufferCopy as sibling while parent is busy; preserved local fix0c10 owns it as child behind effect with same relative lane. Original gameplay/identity assertions unchanged.",
        ))
        signatures = []
        for suffix in ("stdout", "stderr"):
            log = EVIDENCE / "BASE/runner" / f"{name}.{suffix}.log"
            if log.exists():
                signatures += [line.strip() for line in log.read_text(encoding="utf-8-sig", errors="replace").splitlines()
                               if "ERROR:" in line or "Assertion failed" in line]
        rows.append({"test_path": old["test_path"], "base_runner_result": old, "candidate_runner_result": current[old["test_path"]],
                     "literal_base_signatures": signatures, "classification": classification, "resolution": resolution,
                     "current_blocking_failure": current[old["test_path"]]["result"] != "PASS"})
    result = {"base_head": base["git_head"], "candidate_head": cand["git_head"], "rows": rows,
              "status": "PASS" if not any(r["current_blocking_failure"] for r in rows) else "FAIL",
              "scope": "Actual same25 historical runner outcomes with per-assertion classification. Does not replace final critical or clean checkout; cached audit prerequisite explicitly distinguished."}
    (EVIDENCE / "assertion_review.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"HISTORICAL_ASSERTION_REVIEW {result['status']} rows={len(rows)}")


if __name__ == "__main__":
    main()
