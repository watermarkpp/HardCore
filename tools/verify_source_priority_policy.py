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


def main() -> None:
    policy = load_json(POLICY_PATH)
    catalog = load_json(CATALOG_PATH)
    catalog_entries = {entry["distributionKey"]: entry for entry in catalog["distributions"]}
    expected_weights = policy["weights"]
    checks: dict[str, bool] = {}

    checks["fourLanesPresent"] = set(policy["lanes"]) == {"client_assets", "client_rules", "server_data", "server_rules"}
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
        all_cataloged &= all(source["distribution"] in catalog_entries for source in sources)
        exactly_one_primary &= sum(source["tier"] == "primary" for source in sources) == 1
        weights_match &= all(int(source["weight"]) == int(expected_weights[source["tier"]]) for source in sources)
        orders = [int(source["order"]) for source in sources]
        order_strict &= orders == sorted(set(orders))
    checks["allEligibleSourcesCataloged"] = all_cataloged
    checks["exactlyOnePrimaryPerLane"] = exactly_one_primary
    checks["tierWeightsMatch"] = weights_match
    checks["strictOrderPerLane"] = order_strict

    checks["clientPrimaryIsAcceptedClassic"] = active_sources(policy, "client_assets")[0]["distribution"] == "client.classic_raw_complete"
    checks["serverPrimaryIsCleanDatabase"] = active_sources(policy, "server_data")[0]["distribution"] == "server.crystal.cjlaaa"
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
