#!/usr/bin/env python3
"""Build/check the side-by-side 21CQ direct drop baseline data.

Phase A deliberately stops at the tracked logical-source audit.  Later phases
extend this same entrypoint with explicit mappings and compiled V2 outputs.
Production runtime files are outside this tool's write set.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
CORRECTIONS_PATH = (
    ROOT / "assets/data/drop/dpv2_21cq_source_corrections_v1.json"
)
IMPORT_AUDIT_PATH = ROOT / "docs/dpv2_21cq_import_audit.md"

EXPECTED_SOURCE_SCHEMA = "canonical_monster_drop_source_excel_v1"
EXPECTED_SOURCE_RECORDS = 217
EXPECTED_SOURCE_ROWS = 9590
EXPECTED_WORKBOOK_SHA256 = (
    "6902A37DB839577D2CE440B9EFDC4628430CF063BF9DF505F03B41E24A5D67EE"
)
EXPECTED_SOURCE_SHA256 = (
    "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"
)
CHANCE_RE = re.compile(r"^1/([1-9][0-9]*)$")


class DirectBaselineError(RuntimeError):
    """Raised when an Authority or source closure is invalid."""


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise DirectBaselineError(f"{path.relative_to(ROOT)} is not a JSON object")
    return value


def sha256_raw(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def sha256_lf(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper()


def correction_key(row: dict[str, Any], monster_id: int) -> tuple[Any, ...]:
    return (
        monster_id,
        int(row.get("line_number", -1)),
        str(row.get("slot_index", "")),
        str(row.get("item", "")),
        str(row.get("chance", "")),
    )


def load_corrections(source: dict[str, Any]) -> dict[tuple[Any, ...], dict[str, Any]]:
    authority = load_json(CORRECTIONS_PATH)
    if authority.get("schema") != "hardcore.dpv2.21cq_source_corrections.v1":
        raise DirectBaselineError("source correction schema mismatch")
    source_binding = authority.get("source", {})
    if not isinstance(source_binding, dict):
        raise DirectBaselineError("source correction binding missing")
    if (
        source_binding.get("path")
        != SOURCE_PATH.relative_to(ROOT).as_posix()
        or source_binding.get("sha256") != sha256_raw(SOURCE_PATH)
    ):
        raise DirectBaselineError("source correction binding drift")

    result: dict[tuple[Any, ...], dict[str, Any]] = {}
    for raw in authority.get("corrections", []):
        if not isinstance(raw, dict):
            raise DirectBaselineError("source correction record is not an object")
        key = (
            int(raw.get("stable_monster_id", -1)),
            int(raw.get("source_line_number", -1)),
            str(raw.get("source_slot_index", "")),
            str(raw.get("source_item_label", "")),
            str(raw.get("original_chance", "")),
        )
        if key in result:
            raise DirectBaselineError(f"duplicate correction key: {key}")
        numerator = raw.get("corrected_base_numerator")
        denominator = raw.get("corrected_base_denominator")
        if type(numerator) is not int or numerator <= 0:
            raise DirectBaselineError(f"invalid corrected numerator: {key}")
        if type(denominator) is not int or denominator <= 0:
            raise DirectBaselineError(f"invalid corrected denominator: {key}")
        result[key] = raw
    return result


def parse_source() -> dict[str, Any]:
    source = load_json(SOURCE_PATH)
    if source.get("schema") != EXPECTED_SOURCE_SCHEMA:
        raise DirectBaselineError("tracked logical source schema mismatch")
    if source.get("authority") != "user_locked":
        raise DirectBaselineError("tracked logical source is not user_locked")
    if source.get("workbook_sha256") != EXPECTED_WORKBOOK_SHA256:
        raise DirectBaselineError("upstream workbook SHA drift")
    if sha256_raw(SOURCE_PATH) != EXPECTED_SOURCE_SHA256:
        raise DirectBaselineError("tracked logical source SHA drift")

    records = source.get("records")
    if not isinstance(records, list) or len(records) != EXPECTED_SOURCE_RECORDS:
        raise DirectBaselineError("logical source record count mismatch")
    corrections = load_corrections(source)

    status_counts: Counter[str] = Counter()
    source_kind_counts: Counter[str] = Counter()
    seen_ids: set[int] = set()
    seen_slots: set[tuple[int, str]] = set()
    item_rows_by_monster: defaultdict[tuple[int, str], int] = defaultdict(int)
    exact_rows_by_monster: defaultdict[tuple[Any, ...], int] = defaultdict(int)
    invalid_source_rows: list[dict[str, Any]] = []
    corrected_rows: list[dict[str, Any]] = []
    parsed_rows: list[dict[str, Any]] = []

    for record in records:
        if not isinstance(record, dict):
            raise DirectBaselineError("source record is not an object")
        monster_id = int(record.get("stable_monster_id", -1))
        if monster_id <= 0 or monster_id in seen_ids:
            raise DirectBaselineError(f"invalid/duplicate stable monster id: {monster_id}")
        seen_ids.add(monster_id)
        rows = record.get("rows", [])
        if not isinstance(rows, list):
            raise DirectBaselineError(f"monster_id={monster_id} rows is not an array")
        if int(record.get("line_count", -1)) != len(rows):
            raise DirectBaselineError(f"monster_id={monster_id} line_count drift")
        status_counts[str(record.get("status", ""))] += 1

        for row in rows:
            if not isinstance(row, dict):
                raise DirectBaselineError(f"monster_id={monster_id} row is not an object")
            slot_index = str(row.get("slot_index", ""))
            slot_key = (monster_id, slot_index)
            if not slot_index or slot_key in seen_slots:
                raise DirectBaselineError(f"invalid/duplicate source slot: {slot_key}")
            seen_slots.add(slot_key)
            item = str(row.get("item", ""))
            chance = str(row.get("chance", ""))
            if not item:
                raise DirectBaselineError(f"empty item label: {slot_key}")
            source_kind_counts[str(row.get("source_kind", ""))] += 1

            match = CHANCE_RE.fullmatch(chance)
            correction = corrections.get(correction_key(row, monster_id))
            if match is not None:
                numerator = 1
                denominator = int(match.group(1))
                if correction is not None:
                    raise DirectBaselineError(
                        f"correction targets already-valid source row: {slot_key}"
                    )
            elif correction is not None:
                invalid_source_rows.append({
                    "monster_id": monster_id,
                    "monster_name": str(record.get("name", "")),
                    "line_number": int(row.get("line_number", -1)),
                    "slot_index": slot_index,
                    "item": item,
                    "chance": chance,
                })
                corrected_rows.append(correction)
                numerator = int(correction["corrected_base_numerator"])
                denominator = int(correction["corrected_base_denominator"])
            else:
                invalid_source_rows.append({
                    "monster_id": monster_id,
                    "monster_name": str(record.get("name", "")),
                    "line_number": int(row.get("line_number", -1)),
                    "slot_index": slot_index,
                    "item": item,
                    "chance": chance,
                })
                continue

            parsed = {
                "monster_id": monster_id,
                "monster_name": str(record.get("name", "")),
                "line_number": int(row.get("line_number", -1)),
                "slot_index": slot_index,
                "item": item,
                "gold": int(row["gold"]) if "gold" in row else None,
                "source_chance": chance,
                "base_numerator": numerator,
                "base_denominator": denominator,
                "correction_id": (
                    str(correction.get("correction_id", ""))
                    if correction is not None else None
                ),
            }
            parsed_rows.append(parsed)
            item_rows_by_monster[(monster_id, item)] += 1
            exact_rows_by_monster[
                (monster_id, item, chance, parsed["gold"])
            ] += 1

    if len(seen_slots) != EXPECTED_SOURCE_ROWS:
        raise DirectBaselineError(
            f"source row count={len(seen_slots)} expected={EXPECTED_SOURCE_ROWS}"
        )
    unused_corrections = set(corrections) - {
        correction_key(row, int(record.get("stable_monster_id", -1)))
        for record in records
        for row in record.get("rows", [])
        if isinstance(row, dict)
    }
    if unused_corrections:
        raise DirectBaselineError(f"correction keys missing in source: {unused_corrections}")

    duplicate_item_groups = sum(1 for value in item_rows_by_monster.values() if value > 1)
    duplicate_item_rows = sum(value - 1 for value in item_rows_by_monster.values() if value > 1)
    exact_duplicate_groups = sum(1 for value in exact_rows_by_monster.values() if value > 1)
    exact_duplicate_rows = sum(value - 1 for value in exact_rows_by_monster.values() if value > 1)
    uncorrected_invalid = len(invalid_source_rows) - len(corrected_rows)
    if uncorrected_invalid != 0:
        raise DirectBaselineError(
            f"uncorrected invalid source rows={uncorrected_invalid}"
        )
    if len(parsed_rows) != EXPECTED_SOURCE_ROWS:
        raise DirectBaselineError("parsed row ledger does not close")

    return {
        "source": source,
        "records": records,
        "parsed_rows": parsed_rows,
        "metrics": {
            "physical_raw_monitems_files_in_git": 0,
            "logical_monster_records": len(records),
            "logical_source_rows": len(seen_slots),
            "parsed_rows_after_correction": len(parsed_rows),
            "zero_slot_records": sum(1 for record in records if not record.get("rows", [])),
            "status_counts": dict(sorted(status_counts.items())),
            "source_kind_counts": dict(sorted(source_kind_counts.items())),
            "source_invalid_probability_rows": len(invalid_source_rows),
            "explicitly_corrected_rows": len(corrected_rows),
            "uncorrected_invalid_probability_rows": uncorrected_invalid,
            "duplicate_item_groups_within_monster": duplicate_item_groups,
            "duplicate_item_rows_beyond_first": duplicate_item_rows,
            "exact_duplicate_groups_within_monster": exact_duplicate_groups,
            "exact_duplicate_rows_beyond_first": exact_duplicate_rows,
            "tracked_source_sha256_raw": sha256_raw(SOURCE_PATH),
            "tracked_source_sha256_lf": sha256_lf(SOURCE_PATH),
            "upstream_workbook_sha256": str(source.get("workbook_sha256", "")),
            "tracked_encoding": "UTF-8 JSON",
            "physical_monitems_encoding": "NOT_AVAILABLE_IN_GIT",
        },
        "invalid_source_rows": invalid_source_rows,
        "corrected_rows": corrected_rows,
    }


def render_import_audit(audit: dict[str, Any]) -> str:
    metrics = audit["metrics"]
    invalid_rows = audit["invalid_source_rows"]
    status_counts = metrics["status_counts"]
    return f"""# DPV2-21CQ-X1 Phase 1 Import Audit

Status: `SOURCE_AUDIT_CLOSED / PRODUCTION_STILL_V1`

## Source identity

- Physical raw `MonItems` files tracked in Git: `{metrics['physical_raw_monitems_files_in_git']}`.
- Reproducible tracked logical source: `assets/data/canonical_monster_drop_source_v2.json`.
- Logical monster records: `{metrics['logical_monster_records']}`.
- Logical meaningful source rows: `{metrics['logical_source_rows']}`.
- Tracked encoding: `{metrics['tracked_encoding']}`.
- Physical MonItems encoding: `{metrics['physical_monitems_encoding']}`; it cannot be inferred from the derived JSON.
- Tracked source raw SHA-256: `{metrics['tracked_source_sha256_raw']}`.
- Tracked source LF-normalized SHA-256: `{metrics['tracked_source_sha256_lf']}`.
- Recorded upstream workbook SHA-256: `{metrics['upstream_workbook_sha256']}`.

The direct source is described as `LEGACY_21CQ_MONITEMS`, not as an official
Shanda/Shengqu table. The tracked JSON is a logical, user-locked reconstruction;
this report does not claim that physical MonItems files exist in the repository.

## Structural closure

| Metric | Count |
| --- | ---: |
| available records | {status_counts.get('available', 0)} |
| confirmed no-drop records | {status_counts.get('no_drop_confirmed', 0)} |
| no-MonItems records | {status_counts.get('no_monitems_file', 0)} |
| zero-slot records | {metrics['zero_slot_records']} |
| meaningful source rows | {metrics['logical_source_rows']} |
| parsed rows after explicit correction | {metrics['parsed_rows_after_correction']} |
| invalid source probability tokens | {metrics['source_invalid_probability_rows']} |
| explicitly corrected rows | {metrics['explicitly_corrected_rows']} |
| uncorrected invalid rows | {metrics['uncorrected_invalid_probability_rows']} |
| duplicate item groups within a monster | {metrics['duplicate_item_groups_within_monster']} |
| duplicate item rows beyond first | {metrics['duplicate_item_rows_beyond_first']} |
| exact duplicate groups within a monster | {metrics['exact_duplicate_groups_within_monster']} |
| exact duplicate rows beyond first | {metrics['exact_duplicate_rows_beyond_first']} |

Every logical row remains an independent row. Duplicate counts are audit facts;
no row is merged and no aggregate probability is calculated.

## Explicit probability correction

The source contains exactly one malformed probability token:

| monster_id | monster | source line | slot | item | source | frozen correction |
| ---: | --- | ---: | --- | --- | --- | --- |
| {invalid_rows[0]['monster_id']} | {invalid_rows[0]['monster_name']} | {invalid_rows[0]['line_number']} | {invalid_rows[0]['slot_index']} | {invalid_rows[0]['item']} | `{invalid_rows[0]['chance']}` | `1/2800` |

The tracked historical row is not rewritten. The correction is frozen in
`assets/data/drop/dpv2_21cq_source_corrections_v1.json`, with evidence URL,
retrieval date, exact slot identity and original value. Silent correction and
silent skipping are forbidden.

## Accounting gate

```text
meaningful_source_rows = 9590
parsed_rows_after_explicit_correction = 9590
uncorrected_invalid_probability_rows = 0
```

No Production Runtime, canonical catalog, current Tier/Role Authority or actual
drop probability was changed in this phase.
"""


def desired_outputs() -> dict[Path, str]:
    audit = parse_source()
    return {IMPORT_AUDIT_PATH: render_import_audit(audit)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        outputs = desired_outputs()
        if args.write:
            for path, rendered in outputs.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(rendered, encoding="utf-8", newline="\n")
        else:
            mismatches = [
                path for path, rendered in outputs.items()
                if not path.is_file() or path.read_text(encoding="utf-8") != rendered
            ]
            if mismatches:
                for path in mismatches:
                    print(f"ERROR: generated output drift: {path.relative_to(ROOT)}")
                return 1
        audit = parse_source()
        metrics = audit["metrics"]
        print(
            "DPV2_21CQ_SOURCE_AUDIT_PASS: "
            f"logical_records={metrics['logical_monster_records']} "
            f"source_rows={metrics['logical_source_rows']} "
            f"corrected={metrics['explicitly_corrected_rows']} "
            f"uncorrected_invalid={metrics['uncorrected_invalid_probability_rows']}"
        )
        return 0
    except (DirectBaselineError, KeyError, ValueError, TypeError) as exc:
        print(f"DPV2_21CQ_SOURCE_AUDIT_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
