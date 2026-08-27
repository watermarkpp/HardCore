#!/usr/bin/env python3
"""Verify source tiers against the accepted 58-distribution catalog."""

from __future__ import annotations

import json
from pathlib import Path

from source_priority_guard import active_sources, authorize, load_json


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "assets/data/source_priority_policy.json"
CATALOG_PATH = ROOT / "outputs/resource_catalog/complete_local_mir_sources/manifest.json"
EXAMPLE_PATH = ROOT / "assets/data/source_priority_fallback_evidence.example.json"

EXPECTED_LANES = {
    "combat_units",
    "skills",
    "equipment_attributes",
    "client_assets",
    "client_rules",
    "server_data",
    "server_rules",
    "monster_drop_probability",
}

MONSTER_DROP_ROUTING_KEY = "monster_drop_probability_and_post_rng_overflow"
MONSTER_DROP_PRIMARY = {
    "distribution": "project.hardcore.dpv2_21cq_direct_baseline.v2",
    "tier": "primary",
    "order": 0,
    "weight": 100,
    "catalogRequired": False,
    "rootPrefix": "assets/data/canonical_monster_drop_source_v2.json",
    "contractId": "dpv2.21cq.direct_baseline.v2",
    "authority": "user_authoritative_override",
    "sourceKind": "tracked_user_locked_logical_21cq_artifact",
    "originalPath": "assets/data/canonical_monster_drop_source_v2.json",
    "directRuntimeArtifact": "assets/data/drop/dpv2_direct_baseline_v2.json",
    "evidenceSha256": "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013",
}
MONSTER_DROP_SCOPE_EXCLUSIONS = {
    "server_data": {
        "monster_identity",
        "monster_stats",
        "monster_ai",
        "monster_combat",
        "monster_respawn",
        "monster_spawn",
        "monster_map_placement",
        "item_identity",
        "item_attributes",
    },
    "server_rules": {
        "monster_ai",
        "monster_combat",
        "monster_respawn",
    },
}


def _matches_exact_scope(actual: object, expected: set[str]) -> bool:
    """Require the drop lane's exclusions to contain no omissions or extras."""

    if not isinstance(actual, list) or not all(isinstance(item, str) for item in actual):
        return False
    return len(actual) == len(expected) and set(actual) == expected


def _check_monster_drop_lane(policy: dict, checks: dict[str, bool]) -> None:
    """Validate the DPV2 lane's routing, authority, and drop-only exclusions."""

    lanes = policy.get("lanes", {})
    routing = policy.get("routing", {})
    lane = lanes.get("monster_drop_probability") if isinstance(lanes, dict) else None
    if not isinstance(lane, dict):
        checks["monsterDropProbabilityRouting"] = False
        checks["monsterDropProbabilityPrimaryIsProjectMaster"] = False
        checks["monsterDropProbabilityScopeIsDropOnly"] = False
        return

    checks["monsterDropProbabilityRouting"] = (
        isinstance(routing, dict)
        and routing.get(MONSTER_DROP_ROUTING_KEY) == "monster_drop_probability"
    )

    scope_exclusions = lane.get("scopeExclusions")
    checks["monsterDropProbabilityScopeIsDropOnly"] = (
        isinstance(scope_exclusions, dict)
        and set(scope_exclusions) == set(MONSTER_DROP_SCOPE_EXCLUSIONS)
        and all(
            _matches_exact_scope(scope_exclusions.get(scope), expected)
            for scope, expected in MONSTER_DROP_SCOPE_EXCLUSIONS.items()
        )
    )

    sources = lane.get("sources", [])
    if not isinstance(sources, list):
        sources = []
    eligible_sources = [
        source
        for source in sources
        if isinstance(source, dict) and source.get("eligible", False)
    ]
    eligible_sources.sort(
        key=lambda source: (
            int(source.get("order", 999)),
            -int(source.get("weight", 0)),
        )
    )
    primary = eligible_sources[0] if len(eligible_sources) == 1 else {}
    checks["monsterDropProbabilityPrimaryIsProjectMaster"] = (
        bool(primary)
        and all(primary.get(key) == value for key, value in MONSTER_DROP_PRIMARY.items())
    )


def main() -> None:
    policy = load_json(POLICY_PATH)
    catalog = load_json(CATALOG_PATH)
    catalog_entries = {entry["distributionKey"]: entry for entry in catalog["distributions"]}
    expected_weights = policy["weights"]
    checks: dict[str, bool] = {}

    checks["requiredLanesPresent"] = set(policy["lanes"]) == EXPECTED_LANES
    checks["strictFallbackRules"] = all([
        policy["rules"].get("singleSourceFirst") is True,
        policy["rules"].get("crossDistributionMergeByDefault") is False,
        policy["rules"].get("fallbackRequiresEvidence") is True,
        policy["rules"].get("fallbackMustRejectEveryHigherPrioritySource") is True,
    ])

    all_cataloged = True
    exactly_one_primary = True
    weights_match = True
    order_strict = True
    for lane in policy["lanes"]:
        sources = active_sources(policy, lane)
        all_cataloged &= all(
            source.get("catalogRequired", True) is False
            or source["distribution"] in catalog_entries
            for source in sources
        )
        exactly_one_primary &= sum(source["tier"] == "primary" for source in sources) == 1
        weights_match &= all(int(source["weight"]) == int(expected_weights[source["tier"]]) for source in sources)
        orders = [int(source["order"]) for source in sources]
        order_strict &= orders == sorted(set(orders))
    checks["allEligibleSourcesCataloged"] = all_cataloged
    checks["exactlyOnePrimaryPerLane"] = exactly_one_primary
    checks["tierWeightsMatch"] = weights_match
    checks["strictOrderPerLane"] = order_strict

    _check_monster_drop_lane(policy, checks)

    checks["clientPrimaryIsAcceptedClassic"] = active_sources(policy, "client_assets")[0]["distribution"] == "client.classic_raw_complete"
    checks["serverPrimaryIsCleanDatabase"] = active_sources(policy, "server_data")[0]["distribution"] == "server.crystal.cjlaaa"
    equipment_primary = active_sources(policy, "equipment_attributes")[0]
    checks["equipmentPrimaryIsProjectMaster"] = (
        equipment_primary["distribution"] == "project.hardcore.equipment_attribute_master.v2"
        and equipment_primary.get("catalogRequired") is False
        and equipment_primary.get("contractId") == "equipment.attribute.master.v2"
        and equipment_primary.get("sourceKind") == "explicit_user_primary_override"
        and equipment_primary.get("evidenceSha256")
        == "CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D"
        and len(str(equipment_primary.get("evidenceSha256", ""))) == 64
    )
    checks["equipmentAttributesExcludedFromServerData"] = set(
        policy["lanes"]["equipment_attributes"]["scopeExclusions"]["server_data"]
    ) == {
        "equipment_attributes",
        "equipment_requirements",
        "equipment_job_affinity",
        "equipment_gender_restrictions",
        "equipment_hand_weight",
        "equipment_wear_weight",
    }
    skill_primary = active_sources(policy, "skills")[0]
    checks["skillsPrimaryIsUserAuthorizedContract"] = all([
        skill_primary["distribution"] == "project.hardcore.mir2_176_skill_sot.v1.0.1",
        skill_primary.get("catalogRequired") is False,
        skill_primary.get("contractId") == "skills.mir2_176.vanilla_33.v1.0.1",
        skill_primary.get("sourceKind") == "explicit_user_primary_override",
        skill_primary.get("packageEvidenceSha256")
        == "2DAC78D285DFF8D5F1BA36A8B83E0E8F11C70B76ACE15A34EE7FBFB802862A22",
        skill_primary.get("contractEvidenceSha256")
        == "6C4A4B447787EB6AD9F9F44C6C24CF6CA23C952673797226C66541008B25C516",
        len(str(skill_primary.get("packageEvidenceSha256", ""))) == 64,
        len(str(skill_primary.get("contractEvidenceSha256", ""))) == 64,
    ])
    checks["skillsExcludedFromGenericSources"] = all([
        set(policy["lanes"]["skills"]["scopeExclusions"]["server_data"]) == {
            "vanilla_skill_membership",
            "vanilla_skill_progression",
            "vanilla_skill_mp",
            "vanilla_skill_targeting",
            "vanilla_skill_resources",
        },
        set(policy["lanes"]["skills"]["scopeExclusions"]["server_rules"]) == {
            "vanilla_skill_formula_identity",
            "vanilla_skill_geometry",
            "vanilla_skill_timing",
            "vanilla_skill_proficiency",
            "vanilla_skill_state_machine",
        },
    ])
    checks["rulePrimariesAreARated"] = all(
        catalog_entries[active_sources(policy, lane)[0]["distribution"]]["confidence"] == "A-rule-source"
        for lane in ["client_rules", "server_rules"]
    )

    primary_result = authorize(policy, catalog, "client_assets", "client.classic_raw_complete", None)
    checks["primaryNeedsNoFallbackEvidence"] = primary_result["authorized"] and not primary_result["fallbackUsed"]
    try:
        authorize(policy, catalog, "client_assets", "client.mir2opensource_2013_complete", None)
        checks["unprovedFallbackRejected"] = False
    except ValueError:
        checks["unprovedFallbackRejected"] = True
    example_result = authorize(policy, catalog, "client_assets", "archive_extract.mirfiles_hum.bfae8696c79f", load_json(EXAMPLE_PATH))
    checks["completeFallbackChainAccepted"] = example_result["authorized"] and len(example_result["higherPriorityRejected"]) == 3

    result = {
        "schemaVersion": 1,
        "passed": all(checks.values()),
        "checks": checks,
        "primaries": {lane: active_sources(policy, lane)[0]["distribution"] for lane in policy["lanes"]},
        "weights": expected_weights,
    }
    report_path = ROOT / "outputs/validation/source_priority_policy_acceptance.json"
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
