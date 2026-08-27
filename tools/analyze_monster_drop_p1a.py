#!/usr/bin/env python3
"""P1A runtime snapshot analyzer.

Important semantic boundary:
- This analyzer does NOT parse chance strings.
- It does NOT resolve item authority.
- It consumes the classifications exported by Godot after calling the real
  LootRuntime provenance chance parser, GameData reward resolver, and DPV2
  probability authority resolver.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

SNAPSHOT_SCHEMA = "monster_drop_p1a_runtime_snapshot_v2"

EXPECTED_DROP_PROFILE_COUNT = 156
EXPECTED_BASE_DROP_ROW_COUNT = 7032
EXPECTED_FINAL_DROP_ROW_COUNT = 7032
EXPECTED_AUDIT_ONLY_COUNT = 7032
EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT = 7032
EXPECTED_INVALID_CHANCE_COUNT = 1

EXPECTED_ANOMALY = {
    "drop_profile_id": "drop.168",
    "monster_id": 168,
    "line_number": 20,
    "profile_entry_ordinal_zero_based": 19,
    "profile_entry_ordinal_one_based": 20,
    "slot_index": "slot_020",
    "chance_raw": "1/00",
    "raw_text": "1/00 灵魂战衣(男)",
}


class SnapshotValidationError(RuntimeError):
    pass


def _as_bool(value: Any) -> bool:
    return bool(value)


def _counter_dict(values: Iterable[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def runtime_semantics_key(slot: dict[str, Any]) -> tuple[Any, ...]:
    """Return only runtime-derived semantics; provenance is intentionally absent."""
    return (
        slot.get("chance_valid"),
        slot.get("chance_denominator"),
        slot.get("reward_resolvable"),
        slot.get("reward_resolution_status"),
        slot.get("reward_resolution_reason"),
        slot.get("runtime_reward_attempted"),
        slot.get("probability_authority_resolvable"),
        slot.get("slot_runtime_rollable"),
        slot.get("runtime_rollable"),
        slot.get("non_rollable_reason"),
        slot.get("runtime_rejection_reason"),
    )


def validate_slot_contract(slot: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    prefix = (
        f"{slot.get('drop_profile_id', '<profile?>')}"
        f":{slot.get('line_number', '<line?>')}"
    )

    chance_valid = _as_bool(slot.get("chance_valid", False))
    reward_resolvable = _as_bool(slot.get("reward_resolvable", False))
    probability_resolvable = _as_bool(
        slot.get("probability_authority_resolvable", False)
    )
    slot_rollable = _as_bool(slot.get("slot_runtime_rollable", False))
    runtime_rollable_alias = _as_bool(slot.get("runtime_rollable", False))
    runtime_reward_attempted = _as_bool(
        slot.get("runtime_reward_attempted", False)
    )
    non_rollable_reason = slot.get("non_rollable_reason")
    runtime_rejection_reason = slot.get("runtime_rejection_reason")
    reward_status = str(slot.get("reward_resolution_status", ""))
    reward_reason = slot.get("reward_resolution_reason")
    monster_allowed = _as_bool(slot.get("monster_runtime_allowed", False))
    runtime_reachable = _as_bool(slot.get("runtime_reachable", False))

    if chance_valid:
        denominator = slot.get("chance_denominator")
        if not isinstance(denominator, int) or denominator <= 0:
            errors.append(
                f"{prefix} chance_valid=true requires positive integer denominator"
            )
    elif slot.get("chance_denominator") is not None:
        errors.append(
            f"{prefix} chance_valid=false requires chance_denominator=null"
        )

    # Source chance is provenance only. Every source row reaches canonical
    # reward resolution before the DPV2 role/tier probability authority.
    if not runtime_reward_attempted:
        errors.append(
            f"{prefix} runtime_reward_attempted must be true"
        )

    if reward_resolvable:
        if reward_status != "resolved":
            errors.append(
                f"{prefix} reward_resolvable=true requires status=resolved"
            )
        if reward_reason not in (None, ""):
            errors.append(
                f"{prefix} resolved reward must not carry rejection reason"
            )
    else:
        if reward_status != "unresolved":
            errors.append(
                f"{prefix} reward_resolvable=false requires status=unresolved"
            )
        if not isinstance(reward_reason, str) or not reward_reason:
            errors.append(
                f"{prefix} unresolved reward requires a concrete reason"
            )

    expected_rollable = reward_resolvable and probability_resolvable
    if slot_rollable != expected_rollable:
        errors.append(
            f"{prefix} slot_runtime_rollable={slot_rollable} "
            f"expected={expected_rollable}"
        )
    if runtime_rollable_alias != slot_rollable:
        errors.append(
            f"{prefix} runtime_rollable compatibility alias drifted"
        )

    if not reward_resolvable:
        expected_non_rollable = "unresolved_reward"
        expected_runtime_rejection = reward_reason
    elif not probability_resolvable:
        expected_non_rollable = "probability_authority_blocked"
        policy = slot.get("probability_policy", {})
        expected_runtime_rejection = (
            policy.get("reason", "drop_probability_authority_invalid")
            if isinstance(policy, dict)
            else "drop_probability_authority_invalid"
        )
    else:
        expected_non_rollable = None
        expected_runtime_rejection = None

    if non_rollable_reason != expected_non_rollable:
        errors.append(
            f"{prefix} non_rollable_reason={non_rollable_reason!r} "
            f"expected={expected_non_rollable!r}"
        )
    if runtime_rejection_reason != expected_runtime_rejection:
        errors.append(
            f"{prefix} runtime_rejection_reason="
            f"{runtime_rejection_reason!r} "
            f"expected={expected_runtime_rejection!r}"
        )

    expected_reachable = monster_allowed and slot_rollable
    if runtime_reachable != expected_reachable:
        errors.append(
            f"{prefix} runtime_reachable={runtime_reachable} "
            f"expected={expected_reachable}"
        )

    source_entry = slot.get("source_entry")
    if not isinstance(source_entry, dict):
        errors.append(f"{prefix} source_entry must be an object")
    else:
        # Provenance fields are presence/audit data only. They are never used
        # above to derive rollability.
        if "rate_policy" not in source_entry:
            errors.append(f"{prefix} source_entry.rate_policy missing")
        if "slot_status" not in source_entry:
            errors.append(f"{prefix} source_entry.slot_status missing")

    return errors


def _recompute_summary(slots: list[dict[str, Any]]) -> dict[str, Any]:
    rate_policy = []
    slot_status = []
    non_rollable = []
    runtime_rejections = []
    reward_reasons = []

    chance_valid = 0
    reward_resolvable = 0
    rollable = 0
    reachable = 0

    for slot in slots:
        source = slot.get("source_entry", {})
        if isinstance(source, dict):
            rate_policy.append(str(source.get("rate_policy", "<missing>")))
            slot_status.append(str(source.get("slot_status", "<missing>")))
        else:
            rate_policy.append("<invalid-source-entry>")
            slot_status.append("<invalid-source-entry>")

        if _as_bool(slot.get("chance_valid", False)):
            chance_valid += 1
        if _as_bool(slot.get("reward_resolvable", False)):
            reward_resolvable += 1
        else:
            reward_reasons.append(
                str(slot.get(
                    "reward_resolution_reason",
                    "unresolved_unspecified",
                ))
            )
        if _as_bool(slot.get("slot_runtime_rollable", False)):
            rollable += 1
        else:
            non_rollable.append(
                str(slot.get(
                    "non_rollable_reason",
                    "non_rollable_unspecified",
                ))
            )
            runtime_rejections.append(
                str(slot.get(
                    "runtime_rejection_reason",
                    "runtime_rejection_unspecified",
                ))
            )
        if _as_bool(slot.get("runtime_reachable", False)):
            reachable += 1

    total = len(slots)
    return {
        "slot_count": total,
        "rate_policy_counts": _counter_dict(rate_policy),
        "slot_status_counts": _counter_dict(slot_status),
        "chance_valid_count": chance_valid,
        "chance_invalid_count": total - chance_valid,
        "reward_resolvable_count": reward_resolvable,
        "reward_unresolved_count": total - reward_resolvable,
        "slot_runtime_rollable_count": rollable,
        "slot_runtime_non_rollable_count": total - rollable,
        "runtime_reachable_count": reachable,
        "runtime_unreachable_count": total - reachable,
        "non_rollable_reason_counts": _counter_dict(non_rollable),
        "runtime_rejection_reason_counts": _counter_dict(runtime_rejections),
        "reward_resolution_reason_counts": _counter_dict(reward_reasons),
    }


def validate_snapshot(
    snapshot: dict[str, Any],
    *,
    enforce_current_corpus: bool = True,
) -> list[str]:
    errors: list[str] = []

    if snapshot.get("schema") != SNAPSHOT_SCHEMA:
        errors.append(
            f"schema={snapshot.get('schema')!r} expected={SNAPSHOT_SCHEMA!r}"
        )

    authority = snapshot.get("authority")
    if not isinstance(authority, dict):
        errors.append("authority must be an object")
        authority = {}

    sha_before = authority.get("catalog_sha256_before")
    sha_after = authority.get("catalog_sha256_after")
    if not sha_before or not sha_after:
        errors.append("catalog SHA-256 before/after is required")
    elif sha_before != sha_after:
        errors.append(
            "canonical catalog changed during export "
            f"before={sha_before} after={sha_after}"
        )

    slots_raw = snapshot.get("slots")
    if not isinstance(slots_raw, list):
        errors.append("slots must be an array")
        return errors

    slots: list[dict[str, Any]] = []
    for index, slot in enumerate(slots_raw):
        if not isinstance(slot, dict):
            errors.append(f"slots[{index}] is not an object")
            continue
        slots.append(slot)
        errors.extend(validate_slot_contract(slot))

    observed = _recompute_summary(slots)
    reported = snapshot.get("summary")
    if not isinstance(reported, dict):
        errors.append("summary must be an object")
        reported = {}

    # Only compare fields that are deterministic from slot rows. Monster gate
    # counter is diagnostic and is allowed to be richer than this recomputation.
    for key, value in observed.items():
        if reported.get(key) != value:
            errors.append(
                f"summary.{key}={reported.get(key)!r} "
                f"recomputed={value!r}"
            )

    if enforce_current_corpus:
        catalog_summary = snapshot.get("catalog_summary")
        if not isinstance(catalog_summary, dict):
            errors.append("catalog_summary must be an object")
            catalog_summary = {}

        expected_scalar = {
            "drop_base_row_count": EXPECTED_BASE_DROP_ROW_COUNT,
            "drop_final_row_count": EXPECTED_FINAL_DROP_ROW_COUNT,
            "drop_authoring_enabled_global_count": 0,
            "drop_authoring_global_expanded_row_count": 0,
            "drop_authoring_enabled_monster_count": 0,
            "drop_authoring_monster_added_row_count": 0,
        }
        for key, expected in expected_scalar.items():
            if int(catalog_summary.get(key, -1)) != expected:
                errors.append(
                    f"catalog_summary.{key}="
                    f"{catalog_summary.get(key)!r} expected={expected}"
                )

        reported_profile_count = int(
            reported.get("drop_profile_count", -1)
        )
        if reported_profile_count != EXPECTED_DROP_PROFILE_COUNT:
            errors.append(
                f"summary.drop_profile_count={reported_profile_count} "
                f"expected={EXPECTED_DROP_PROFILE_COUNT}"
            )
        if len(slots) != EXPECTED_FINAL_DROP_ROW_COUNT:
            errors.append(
                f"slot count={len(slots)} "
                f"expected={EXPECTED_FINAL_DROP_ROW_COUNT}"
            )
        if (
            observed["rate_policy_counts"].get("AUDIT_ONLY", 0)
            != EXPECTED_AUDIT_ONLY_COUNT
        ):
            errors.append(
                "AUDIT_ONLY count="
                f"{observed['rate_policy_counts'].get('AUDIT_ONLY', 0)} "
                f"expected={EXPECTED_AUDIT_ONLY_COUNT}"
            )
        if (
            observed["slot_status_counts"].get(
                "CONFIRMED_SOURCE_SLOT",
                0,
            )
            != EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT
        ):
            errors.append(
                "CONFIRMED_SOURCE_SLOT count="
                f"{observed['slot_status_counts'].get('CONFIRMED_SOURCE_SLOT', 0)} "
                f"expected={EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT}"
            )
        if (
            observed["chance_invalid_count"]
            != EXPECTED_INVALID_CHANCE_COUNT
        ):
            errors.append(
                f"chance_invalid_count={observed['chance_invalid_count']} "
                f"expected={EXPECTED_INVALID_CHANCE_COUNT}"
            )

        invalid = [
            slot
            for slot in slots
            if not _as_bool(slot.get("chance_valid", False))
        ]
        if len(invalid) == 1:
            anomaly = invalid[0]
            for key, expected in EXPECTED_ANOMALY.items():
                if anomaly.get(key) != expected:
                    errors.append(
                        f"anomaly.{key}={anomaly.get(key)!r} "
                        f"expected={expected!r}"
                    )
            if not _as_bool(anomaly.get("runtime_reward_attempted", False)):
                errors.append(
                    "anomaly runtime_reward_attempted must be true"
                )
            if not _as_bool(anomaly.get("slot_runtime_rollable", False)):
                errors.append(
                    "anomaly slot_runtime_rollable must be true"
                )
            if anomaly.get("runtime_rejection_reason") is not None:
                errors.append("anomaly must not have a runtime rejection")

    return errors


def analyze_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    slots = [
        slot
        for slot in snapshot.get("slots", [])
        if isinstance(slot, dict)
    ]
    summary = _recompute_summary(slots)

    monsters: dict[int, dict[str, Any]] = {}
    grouped: defaultdict[int, list[dict[str, Any]]] = defaultdict(list)
    for slot in slots:
        grouped[int(slot.get("monster_id", -1))].append(slot)

    for monster_id in sorted(grouped):
        rows = grouped[monster_id]
        first = rows[0]
        closure = first.get("monster_runtime_closure", {})
        if not isinstance(closure, dict):
            closure = {}
        monsters[monster_id] = {
            "monster_id": monster_id,
            "drop_profile_id": first.get("drop_profile_id"),
            "slot_count": len(rows),
            "chance_invalid_count": sum(
                1 for row in rows
                if not _as_bool(row.get("chance_valid", False))
            ),
            "reward_unresolved_count": sum(
                1 for row in rows
                if not _as_bool(row.get("reward_resolvable", False))
            ),
            "slot_runtime_rollable_count": sum(
                1 for row in rows
                if _as_bool(row.get("slot_runtime_rollable", False))
            ),
            "runtime_reachable_count": sum(
                1 for row in rows
                if _as_bool(row.get("runtime_reachable", False))
            ),
            "monster_runtime_allowed": _as_bool(
                first.get("monster_runtime_allowed", False)
            ),
            "monster_runtime_reason": first.get("monster_runtime_reason"),
            "resolved_reward_count_from_closure": closure.get(
                "resolved_reward_count"
            ),
        }

    invalid_slots = [
        slot for slot in slots
        if not _as_bool(slot.get("chance_valid", False))
    ]
    unresolved_slots = [
        slot for slot in slots
        if not _as_bool(slot.get("reward_resolvable", False))
    ]

    return {
        "schema": "monster_drop_p1a_analysis_v2",
        "snapshot_schema": snapshot.get("schema"),
        "authority": snapshot.get("authority", {}),
        "catalog_summary": snapshot.get("catalog_summary", {}),
        "summary": summary,
        "invalid_chance_slots": invalid_slots,
        "unresolved_reward_slots": unresolved_slots,
        "monsters": [
            monsters[key] for key in sorted(monsters)
        ],
    }


def _slot_csv_row(slot: dict[str, Any]) -> dict[str, Any]:
    source = slot.get("source_entry", {})
    if not isinstance(source, dict):
        source = {}
    return {
        "drop_profile_id": slot.get("drop_profile_id"),
        "monster_id": slot.get("monster_id"),
        "ordinal_zero_based": slot.get(
            "profile_entry_ordinal_zero_based"
        ),
        "ordinal_one_based": slot.get(
            "profile_entry_ordinal_one_based"
        ),
        "line_number": slot.get("line_number"),
        "slot_index": slot.get("slot_index"),
        "raw_text": slot.get("raw_text"),
        "chance_raw": slot.get("chance_raw"),
        "chance_denominator": slot.get("chance_denominator"),
        "chance_valid": slot.get("chance_valid"),
        "rate_policy": source.get("rate_policy"),
        "slot_status": source.get("slot_status"),
        "item_resolution_status": slot.get("item_resolution_status"),
        "reward_resolution_status": slot.get(
            "reward_resolution_status"
        ),
        "reward_resolvable": slot.get("reward_resolvable"),
        "reward_resolution_reason": slot.get(
            "reward_resolution_reason"
        ),
        "runtime_reward_attempted": slot.get(
            "runtime_reward_attempted"
        ),
        "slot_runtime_rollable": slot.get(
            "slot_runtime_rollable"
        ),
        "non_rollable_reason": slot.get("non_rollable_reason"),
        "runtime_rejection_reason": slot.get(
            "runtime_rejection_reason"
        ),
        "monster_runtime_allowed": slot.get(
            "monster_runtime_allowed"
        ),
        "monster_runtime_reason": slot.get(
            "monster_runtime_reason"
        ),
        "runtime_reachable": slot.get("runtime_reachable"),
        "item": source.get("item", source.get("item_name")),
        "item_id": source.get("item_id"),
        "kind": source.get("kind"),
        "source_ref": source.get("source_ref"),
        "source_rate": source.get("source_rate"),
        "source_note": source.get("source_note"),
    }


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _markdown_report(analysis: dict[str, Any]) -> str:
    summary = analysis["summary"]
    invalid = analysis["invalid_chance_slots"]
    unresolved = analysis["unresolved_reward_slots"]

    lines = [
        "# MONSTER-DROP-P1A Runtime Audit",
        "",
        "## Runtime contract",
        "",
        "- `rate_policy` / `slot_status` are provenance metadata only.",
        "- Slot gate order mirrors production: chance -> reward authority -> RNG.",
        "- `runtime_rollable` is a compatibility alias of `slot_runtime_rollable`.",
        "- `runtime_reachable` additionally requires the monster-level GameData gate.",
        "",
        "## Summary",
        "",
        "| Metric | Count |",
        "|---|---:|",
    ]
    for key in (
        "slot_count",
        "chance_valid_count",
        "chance_invalid_count",
        "reward_resolvable_count",
        "reward_unresolved_count",
        "slot_runtime_rollable_count",
        "slot_runtime_non_rollable_count",
        "runtime_reachable_count",
        "runtime_unreachable_count",
    ):
        lines.append(f"| `{key}` | {summary.get(key, 0)} |")

    lines.extend([
        "",
        "### `rate_policy` distribution",
        "",
        "```json",
        json.dumps(
            summary.get("rate_policy_counts", {}),
            ensure_ascii=False,
            indent=2,
        ),
        "```",
        "",
        "### Non-rollable reasons",
        "",
        "```json",
        json.dumps(
            summary.get("non_rollable_reason_counts", {}),
            ensure_ascii=False,
            indent=2,
        ),
        "```",
        "",
        "### Exact LootRuntime rejection reasons",
        "",
        "```json",
        json.dumps(
            summary.get("runtime_rejection_reason_counts", {}),
            ensure_ascii=False,
            indent=2,
        ),
        "```",
        "",
        "## Invalid chance rows",
        "",
    ])

    if not invalid:
        lines.append("_None._")
    else:
        for slot in invalid:
            lines.append(
                "- "
                f"`{slot.get('drop_profile_id')}` "
                f"line={slot.get('line_number')} "
                f"slot={slot.get('slot_index')} "
                f"chance=`{slot.get('chance_raw')}` "
                f"raw=`{slot.get('raw_text')}` "
                f"reason=`{slot.get('runtime_rejection_reason')}`"
            )

    lines.extend([
        "",
        "## Runtime reward resolver failures",
        "",
    ])
    if not unresolved:
        lines.append("_None._")
    else:
        lines.append(
            f"{len(unresolved)} row(s); see `monster_drop_p1a_slots.csv` "
            "and `analysis.json` for complete details."
        )

    lines.extend([
        "",
        "## Important semantic result",
        "",
        "`AUDIT_ONLY` is not a non-rollable flag. The analyzer never uses "
        "`rate_policy` to derive chance validity, reward resolution, "
        "rollability, or runtime reachability.",
        "",
    ])
    return "\n".join(lines)


def write_outputs(
    snapshot: dict[str, Any],
    output_dir: Path,
) -> dict[str, Path]:
    analysis = analyze_snapshot(snapshot)
    output_dir.mkdir(parents=True, exist_ok=True)

    analysis_path = output_dir / "analysis.json"
    slots_path = output_dir / "monster_drop_p1a_slots.csv"
    monsters_path = output_dir / "monster_drop_p1a_monsters.csv"
    report_path = output_dir / "report.md"

    analysis_path.write_text(
        json.dumps(analysis, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    slot_rows = [
        _slot_csv_row(slot)
        for slot in snapshot.get("slots", [])
        if isinstance(slot, dict)
    ]
    _write_csv(slots_path, slot_rows)
    _write_csv(monsters_path, analysis["monsters"])
    report_path.write_text(
        _markdown_report(analysis),
        encoding="utf-8",
    )

    return {
        "analysis": analysis_path,
        "slots_csv": slots_path,
        "monsters_csv": monsters_path,
        "report": report_path,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--snapshot",
        type=Path,
        default=Path(
            "outputs/monster_drop_p1a/runtime_snapshot.json"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("outputs/monster_drop_p1a"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.snapshot.is_file():
        print(f"P1A_ANALYZER_FAIL: missing snapshot {args.snapshot}")
        return 2

    with args.snapshot.open("r", encoding="utf-8") as handle:
        snapshot = json.load(handle)
    if not isinstance(snapshot, dict):
        print("P1A_ANALYZER_FAIL: snapshot root is not an object")
        return 2

    errors = validate_snapshot(snapshot, enforce_current_corpus=True)
    if errors:
        for error in errors:
            print(f"P1A_ANALYZER_FAIL: {error}")
        print(f"P1A_ANALYZER_FAIL_COUNT={len(errors)}")
        return 2

    paths = write_outputs(snapshot, args.output_dir)
    summary = _recompute_summary(snapshot["slots"])
    print(
        "P1A_ANALYZER_PASS: "
        f"slots={summary['slot_count']} "
        f"invalid_chance={summary['chance_invalid_count']} "
        f"reward_unresolved={summary['reward_unresolved_count']} "
        f"slot_rollable={summary['slot_runtime_rollable_count']} "
        f"reachable={summary['runtime_reachable_count']}"
    )
    for key, path in paths.items():
        print(f"P1A_OUTPUT {key}={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
