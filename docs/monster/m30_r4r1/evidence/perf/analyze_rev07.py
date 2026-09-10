import json
import statistics
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

B64 = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\m30r4-v72-baseline\outputs\hc_monster_ai_package")
CAND = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4-flash\outputs\hc_monster_ai_package")

HISTORICAL_OLD_P95 = {
    ("sustained_close_attacks", 30): 11.962,
    ("dense_crowd", 30): 11.720,
}


def load_rounds(directory: Path, prefix: str) -> list[dict]:
    rounds = []
    for index in range(1, 5):
        path = directory / f"rev07_{prefix}_r{index}.json"
        rounds.append(json.loads(path.read_text(encoding="utf-8")))
    return rounds


def percentile(sorted_values: list[float], fraction: float) -> float:
    if not sorted_values:
        return float("nan")
    position = (len(sorted_values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = position - lower
    return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight


def case_map(round_doc: dict) -> dict:
    result = {}
    for row in round_doc["rows"]:
        samples = sorted(float(value) for value in row["full_frame_ms"])
        result[(row["scenario"], int(row["monster_count"]))] = {
            "p50": percentile(samples, 0.50),
            "p95": percentile(samples, 0.95),
            "p99": percentile(samples, 0.99),
            "n": len(samples),
            "over_33": sum(1 for value in samples if value > 33.3),
            "over_50": sum(1 for value in samples if value > 50.0),
        }
    return result


def summarize(rounds: list[dict]) -> dict:
    cases = [case_map(doc) for doc in rounds]
    summary = {}
    for key in sorted(cases[0].keys()):
        summary[key] = {
            "p95_median": statistics.median(case["p95"] for case in cases),
            "p50_median": statistics.median(case["p50"] for case in cases),
            "p99_median": statistics.median(case["p99"] for case in cases),
            "p95_all": [round(case["p95"], 3) for case in cases],
            "over33_median": statistics.median(case["over_33"] for case in cases),
            "over50_median": statistics.median(case["over_50"] for case in cases),
        }
    return summary


base = summarize(load_rounds(B64, "v72"))
cand = summarize(load_rounds(CAND, "cand"))

header = (f"{'scenario':<26}{'n':>3} | {'v72 p95':>9}{'cand p95':>10}{'delta%':>8} | "
          f"{'v72 p50':>8}{'cand p50':>9} | {'v72 p99':>8}{'cand p99':>9} | {'>33ms b/c':>10} | gate")
print(header)
print("-" * 130)
for key in sorted(base.keys()):
    b, c = base[key], cand[key]
    limit = max(b["p95_median"] * 1.05, b["p95_median"] + 0.5)
    delta = (c["p95_median"] - b["p95_median"]) / b["p95_median"] * 100.0 if b["p95_median"] else 0.0
    gate = "PASS" if c["p95_median"] <= limit else "FAIL"
    hist = HISTORICAL_OLD_P95.get(key)
    hist_note = ""
    if hist is not None:
        hist_limit = max(hist * 1.05, hist + 0.5)
        hist_note = f" | hist_gate {hist_limit:.2f}: {'PASS' if c['p95_median'] <= hist_limit else 'FAIL'}"
    print(f"{key[0]:<26}{key[1]:>3} | {b['p95_median']:>9.3f}{c['p95_median']:>10.3f}{delta:>+7.1f}% | "
          f"{b['p50_median']:>8.3f}{c['p50_median']:>9.3f} | {b['p99_median']:>8.3f}{c['p99_median']:>9.3f} | "
          f"{b['over33_median']:>4.0f}/{c['over33_median']:<4.0f} | {limit:.3f} {gate}{hist_note}")

print("\nv72 p95 rounds:", {str(k): base[k]["p95_all"] for k in sorted(base.keys()) if k[1] == 30})
print("cand p95 rounds:", {str(k): cand[k]["p95_all"] for k in sorted(base.keys()) if k[1] == 30})
