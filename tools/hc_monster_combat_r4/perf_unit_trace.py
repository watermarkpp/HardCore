#!/usr/bin/env python3
"""Arithmetic trace of the two conversions in the pinned GDScript probe.
This is NOT GDScript execution or a measured game/phone benchmark.
"""
from __future__ import annotations
import json
from pathlib import Path

rows = []
for monitor_seconds in (0.001, 0.010, 0.080, 0.167):
    stored = monitor_seconds * 1000.0
    reported = round((stored / 1000.0) / 0.001) * 0.001
    rows.append({"synthetic_monitor_seconds": monitor_seconds,
                 "stored_milliseconds": stored,
                 "reported_value_labeled_ms": reported,
                 "correct_value_ms": stored,
                 "understatement_factor": stored / reported})
assert all(abs(r["understatement_factor"] - 1000.0) < 1e-7 for r in rows)
output = Path(__file__).resolve().parents[1] / "evidence/perf_unit_trace.json"
output.write_text(json.dumps({"status": "ARITHMETIC_TRACE_EXECUTED_NOT_ENGINE_TEST",
    "source": "tests/hc_monster_combat_r3/paired_load_realism_test.gd",
    "source_blob": "c995c2926753e7a2fa15ce71353bee111d13acb8",
    "warning": "Monitor refresh/window semantics still invalidate per-frame percentiles after fixing the unit. Do not infer phone FPS.",
    "cases": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(rows, indent=2))
