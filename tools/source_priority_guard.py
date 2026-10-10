#!/usr/bin/env python3
"""List source priority or authorize a documented fallback.

This tool never searches source content.  It enforces which already-cataloged
distribution may be consulted after a higher-priority distribution has been
proved missing for one concrete requirement under the authority policy.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICY = ROOT / "assets/data/source_priority_policy.json"
DEFAULT_CATALOG = ROOT / "outputs/resource_catalog/complete_local_mir_sources/manifest.json"
OUTPUT_ROOT = ROOT / "outputs"
KNOWN_FAILURES = {"missing", "unusable", "incompatible"}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _is_reparse_or_link(path: Path) -> bool:
    # is_symlink() also detects a broken link; do not gate this on exists().
    if path.is_symlink():
        return True
    try:
        attributes = os.stat(path, follow_symlinks=False).st_file_attributes
    except (AttributeError, OSError):
        return False
    return bool(attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT


def write_owned_output(path: Path, content: bytes) -> str:
    """Write only inside the physical project outputs tree, without clobbering."""
    raw = Path(os.path.abspath(path))
    probe = raw
    while True:
        if _is_reparse_or_link(probe):
            raise ValueError("output path must not contain a reparse point or link")
        if probe.parent == probe:
            break
        probe = probe.parent
    outputs_root = OUTPUT_ROOT.resolve()
    output = path.resolve(strict=False)
    try:
        output.relative_to(outputs_root)
    except ValueError as exc:
        raise ValueError("output must stay inside the project outputs directory") from exc
    if _is_reparse_or_link(outputs_root):
        raise ValueError("project outputs directory is a reparse point or link")
    current = outputs_root
    for part in output.relative_to(outputs_root).parts[:-1]:
        current /= part
        if current.exists() and _is_reparse_or_link(current):
            raise ValueError("output parent must not be a reparse point or link")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Re-check after creating the parent: another process may have introduced
    # a link or reparse point between the first walk and mkdir.
    probe = Path(os.path.abspath(path))
    while True:
        if _is_reparse_or_link(probe):
            raise ValueError("output path must not contain a reparse point or link")
        if probe.parent == probe:
            break
        probe = probe.parent
    try:
        with output.open("xb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    except FileExistsError:
        try:
            existing = output.read_bytes()
        except OSError as exc:
            raise ValueError(f"existing output cannot be read safely: {output}") from exc
        if existing == content:
            return "reused"
        raise ValueError("refusing to overwrite existing output with different content")
    except OSError as exc:
        # Leave any partial file in place; it is safer than deleting a path
        # after ownership may have changed. The next call will fail closed.
        raise ValueError(f"owned output write failed: {output}") from exc
    try:
        written = output.read_bytes()
    except OSError as exc:
        raise ValueError(f"owned output readback failed: {output}") from exc
    if written != content:
        raise ValueError("owned output readback differs from requested bytes")
    return "created"


def validate_policy(policy: dict) -> dict:
    """Validate the fail-closed policy controls before using any lane."""
    if not isinstance(policy, dict):
        raise ValueError("source-priority policy must be an object")
    rules = policy.get("rules")
    if not isinstance(rules, dict):
        raise ValueError("source-priority policy is missing rules")
    statuses = rules.get("fallbackStatuses")
    if not isinstance(statuses, list) or not statuses:
        raise ValueError("source-priority policy fallbackStatuses must be a non-empty list")
    if any(not isinstance(status, str) or status not in KNOWN_FAILURES for status in statuses):
        raise ValueError("source-priority policy contains an illegal fallback status")
    if rules.get("fallbackRequiresEvidence") is not True:
        raise ValueError("source-priority policy must require fallback evidence")
    if rules.get("fallbackMustRejectEveryHigherPrioritySource") is not True:
        raise ValueError("source-priority policy must reject every higher source")
    return rules


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
    rules = validate_policy(policy)
    sources = active_sources(policy, lane)
    candidate = next((source for source in sources if source.get("distribution") == candidate_key), None)
    if candidate is None:
        raise ValueError(f"candidate is not eligible in {lane}: {candidate_key}")

    catalog_keys = {entry.get("distributionKey") for entry in catalog.get("distributions", [])}
    catalog_required = candidate.get("catalogRequired", True) is not False
    if catalog_required and candidate_key not in catalog_keys:
        raise ValueError(f"candidate is absent from accepted catalog: {candidate_key}")
    if not catalog_required:
        contract_path = ROOT / str(candidate.get("rootPrefix", ""))
        if not contract_path.is_file():
            raise ValueError(f"project master contract is missing: {contract_path}")
        if not str(candidate.get("contractId", "")).strip():
            raise ValueError("project master source is missing contractId")
        if not str(candidate.get("evidenceSha256", "")).strip():
            raise ValueError("project master source is missing evidenceSha256")

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
        if status not in rules["fallbackStatuses"]:
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
        validate_policy(policy)
        if args.command == "list":
            payload = list_lane(policy, args.lane)
        else:
            candidate = next(
                (source for source in active_sources(policy, args.lane)
                 if source.get("distribution") == args.candidate),
                None,
            )
            catalog = (
                {}
                if candidate is None or candidate.get("catalogRequired", True) is False
                else load_json(args.catalog)
            )
            evidence = load_json(args.evidence) if args.evidence else None
            payload = authorize(policy, catalog, args.lane, args.candidate, evidence)
            if args.output:
                serialized = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
                payload["outputDisposition"] = write_owned_output(args.output, serialized)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"authorized": False, "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
