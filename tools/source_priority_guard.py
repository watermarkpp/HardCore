#!/usr/bin/env python3
"""List source priority or authorize a documented fallback.

This tool never searches source content.  It enforces which already-cataloged
distribution may be consulted after a higher-priority distribution has been
proved missing, unusable or incompatible for one concrete requirement.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICY = ROOT / "assets/data/source_priority_policy.json"
DEFAULT_CATALOG = ROOT / "outputs/resource_catalog/complete_local_mir_sources/manifest.json"
ALLOWED_FAILURES = {"missing", "unusable", "incompatible"}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def active_sources(policy: dict, lane: str) -> list[dict]:
    lanes = policy.get("lanes", {})
    if lane not in lanes:
        raise ValueError(f"unknown lane: {lane}")
    return sorted(
        (source for source in lanes[lane].get("sources", []) if source.get("eligible", False)),
        key=lambda source: (int(source.get("order", 999)), -int(source.get("weight", 0))),
    )


def list_lane(policy: dict, lane: str) -> dict:
    lane_data = policy["lanes"][lane]
    return {
        "lane": lane,
        "description": lane_data.get("description", ""),
        "sources": [
            {
                "distribution": source["distribution"],
                "tier": source["tier"],
                "order": source["order"],
                "weight": source["weight"],
                "eligible": source.get("eligible", False),
                "allowedScopes": source.get("allowedScopes", []),
                "reason": source.get("reason", ""),
            }
            for source in sorted(lane_data.get("sources", []), key=lambda item: int(item.get("order", 999)))
        ],
    }


def authorize(policy: dict, catalog: dict, lane: str, candidate_key: str, evidence: dict | None) -> dict:
    sources = active_sources(policy, lane)
    candidate = next((source for source in sources if source.get("distribution") == candidate_key), None)
    if candidate is None:
        raise ValueError(f"candidate is not eligible in {lane}: {candidate_key}")

    catalog_keys = {entry.get("distributionKey") for entry in catalog.get("distributions", [])}
    if candidate_key not in catalog_keys:
        raise ValueError(f"candidate is absent from accepted catalog: {candidate_key}")

    allowed_scopes = candidate.get("allowedScopes", [])
    evidence_scope = str((evidence or {}).get("scope", ""))
    if allowed_scopes and evidence_scope not in allowed_scopes:
        raise ValueError(f"candidate scope must be one of {allowed_scopes}, got {evidence_scope!r}")

    higher = [source for source in sources if int(source["order"]) < int(candidate["order"])]
    if not higher:
        return {
            "authorized": True,
            "lane": lane,
            "selected": candidate_key,
            "tier": candidate["tier"],
            "weight": candidate["weight"],
            "fallbackUsed": False,
            "higherPriorityRejected": [],
        }

    if not evidence:
        raise ValueError("fallback evidence is required for every non-primary source")
    if str(evidence.get("candidate", "")) != candidate_key:
        raise ValueError("evidence candidate does not match requested candidate")
    if not str(evidence.get("requirement", "")).strip():
        raise ValueError("evidence requirement is empty")

    checks = {str(check.get("distribution", "")): check for check in evidence.get("checks", [])}
    rejected: list[dict] = []
    for source in higher:
        key = str(source["distribution"])
        check = checks.get(key)
        if not check:
            raise ValueError(f"missing higher-priority check: {key}")
        status = str(check.get("status", ""))
        if status not in ALLOWED_FAILURES:
            raise ValueError(f"invalid fallback status for {key}: {status}")
        if not str(check.get("query", "")).strip():
            raise ValueError(f"missing query description for {key}")
        proof = check.get("proof", [])
        if not isinstance(proof, list) or not proof or not all(str(item).strip() for item in proof):
            raise ValueError(f"missing proof for {key}")
        rejected.append({"distribution": key, "status": status, "query": check["query"], "proof": proof})

    return {
        "authorized": True,
        "lane": lane,
        "requirement": evidence["requirement"],
        "scope": evidence_scope,
        "selected": candidate_key,
        "tier": candidate["tier"],
        "weight": candidate["weight"],
        "fallbackUsed": True,
        "higherPriorityRejected": rejected,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce MIR client/server source priority")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="show one ordered source lane")
    list_parser.add_argument("--lane", required=True)

    authorize_parser = subparsers.add_parser("authorize", help="authorize primary use or an evidence-backed fallback")
    authorize_parser.add_argument("--lane", required=True)
    authorize_parser.add_argument("--candidate", required=True)
    authorize_parser.add_argument("--evidence", type=Path)
    authorize_parser.add_argument("--output", type=Path)

    args = parser.parse_args()
    try:
        policy = load_json(args.policy)
        if args.command == "list":
            payload = list_lane(policy, args.lane)
        else:
            catalog = load_json(args.catalog)
            evidence = load_json(args.evidence) if args.evidence else None
            payload = authorize(policy, catalog, args.lane, args.candidate, evidence)
            if args.output:
                output = args.output.resolve()
                if not output.is_relative_to(ROOT):
                    raise ValueError("output must stay inside the project")
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"authorized": False, "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
