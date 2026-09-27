#!/usr/bin/env python3
"""Run the audited R3 verifier on isolated synthetic catalogs. Never writes a repo.

Exit 0 means the probe ran, not that the verifier passed its contract.
--expect-fixed makes any wrong verdict fail the command for a future R4 gate.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any


def seed() -> dict[str, Any]:
    row = {
        "monster_id": 33, "canonical_name": "synthetic-fixture-33",
        "combat": {"stats": {"hp": 100}},
        "drop_policy": {"allowed": True, "reason": "synthetic_control"},
        "source_evidence": {"combat_stats": {"source": "pinned-control"}},
    }
    return {"schema_version": 1, "entries": [row],
            "entries_by_id": {"33": copy.deepcopy(row)},
            "sources": {"fixture.json": {"sha256": "a" * 64}}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verifier", type=Path, default=Path(__file__).resolve().parents[1] / "evidence/verify_catalog_reswap_R3_original.py")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-fixed", action="store_true")
    args = parser.parse_args()
    if not args.verifier.is_file():
        parser.error("verifier does not exist")
    data = args.verifier.read_bytes()
    blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    cases: list[tuple[str, dict[str, Any], dict[str, Any], bool]] = []
    old = seed()
    cases.append(("unchanged_positive_control", old, copy.deepcopy(old), True))
    new = copy.deepcopy(old); new["entries"][0]["combat"]["stats"]["hp"] = 1
    cases.append(("old_blindspot_entries_only_hp", old, new, False))
    new = copy.deepcopy(old); new["sources"] = {}
    cases.append(("old_blindspot_sources_removed", old, new, False))
    new = copy.deepcopy(old)
    for row in [new["entries"][0], new["entries_by_id"]["33"]]:
        row["source_evidence"]["combat_stats"]["source"] = "unapproved"
    cases.append(("old_blindspot_combat_evidence", old, new, False))
    new = copy.deepcopy(old)
    for row in [new["entries"][0], new["entries_by_id"]["33"]]:
        row["combat"]["stats"]["hp"] = 1
    cases.append(("both_views_hp_negative_control", old, new, False))
    new = copy.deepcopy(old); new["entries"].append(copy.deepcopy(new["entries"][0]))
    cases.append(("duplicate_identical_entry", old, new, False))
    empty = copy.deepcopy(old); empty["entries"] = []; empty["entries_by_id"] = {}
    cases.append(("both_inputs_empty_identity_views", empty, copy.deepcopy(empty), False))
    new = copy.deepcopy(old)
    for row in [new["entries"][0], new["entries_by_id"]["33"]]:
        del row["drop_policy"]
    cases.append(("exempt_id_drop_policy_deleted", old, new, False))
    results = []
    with tempfile.TemporaryDirectory(prefix="hc-r3-verifier-") as directory:
        root = Path(directory)
        for name, before, after, expected in cases:
            a, b = root / "old.json", root / "new.json"
            a.write_text(json.dumps(before, ensure_ascii=False), encoding="utf-8")
            b.write_text(json.dumps(after, ensure_ascii=False), encoding="utf-8")
            result = subprocess.run([sys.executable, str(args.verifier), str(a), str(b)],
                                    capture_output=True, text=True, timeout=10)
            observed = result.returncode == 0
            results.append({"case": name, "expected_accept": expected,
                            "observed_accept": observed,
                            "contract_satisfied": observed == expected,
                            "exit_code": result.returncode,
                            "stdout": result.stdout, "stderr": result.stderr})
    payload = {"scope": "exact-original-Python-verifier on synthetic temporary files; not Godot or production catalog",
               "verifier_git_blob": blob, "audited_head": "2aede2fba4cf312a7251cc3db0c395a92428c5a9",
               "total": len(results), "contract_satisfied": sum(r["contract_satisfied"] for r in results),
               "results": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for r in results:
        print(f"{r['case']}: expected_accept={r['expected_accept']} observed_accept={r['observed_accept']} contract_satisfied={r['contract_satisfied']}")
    return int(args.expect_fixed and not all(r["contract_satisfied"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
