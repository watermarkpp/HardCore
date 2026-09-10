import json
import statistics
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

B64 = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\m30r4-v72-baseline\outputs\hc_monster_ai_package")
CAND = Path(r"C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4-flash\outputs\hc_monster_ai_package")

HIST = {("sustained_close_attacks", 30): 11.962, ("dense_crowd", 30): 11.720}


def rounds(d: Path, prefix: str) -> list[dict]:
    out = []
    for index in range(1, 7):
        path = d / f"rev07_{prefix}_r{index}.json"
        if path.exists():
            out.append(json.loads(path.read_text(encoding="utf-8")))
    return out


def cmap(doc: dict) -> dict:
    result = {}
    for row in doc["rows"]:
        result[(row["scenario"], int(row["monster_count"]))] = row["full_frame_ms"]
    return result


def summ(rs: list[dict]) -> dict:
    cases = [cmap(x) for x in rs]
    out = {}
    for key in sorted(cases[0].keys()):
        out[key] = {
            "p95": statistics.median(c[key]["p95"] for c in cases),
            "p50": statistics.median(c[key]["p50"] for c in cases),
            "p95_all": [round(c[key]["p95"], 3) for c in cases],
            "rounds": len(cases),
        }
    return out


base = summ(rounds(B64, "v72"))
cand = summ(rounds(CAND, "cand"))
print(f"baseline rounds={base[('open_pursuit',10)]['rounds']} candidate rounds={cand[('open_pursuit',10)]['rounds']}")
print(f"{'scenario':<26}{'n':>3} | {'v72 p95':>9}{'cand p95':>10}{'delta%':>8} | {'v72 p50':>8}{'cand p50':>9} | gate")
print("-" * 100)
for key in sorted(base.keys()):
    bb, cc = base[key], cand[key]
    limit = max(bb["p95"] * 1.05, bb["p95"] + 0.5)
    delta = (cc["p95"] - bb["p95"]) / bb["p95"] * 100.0 if bb["p95"] else 0.0
    gate = "PASS" if cc["p95"] <= limit else "FAIL"
    hist = HIST.get(key)
    hist_note = ""
    if hist:
        hl = max(hist * 1.05, hist + 0.5)
        hist_note = " | hist %.2f: %s" % (hl, "PASS" if cc["p95"] <= hl else "FAIL")
    print("%-26s%3d | %9.3f%10.3f%+7.1f%% | %8.3f%9.3f | %.3f %s%s" % (
        key[0], key[1], bb["p95"], cc["p95"], delta, bb["p50"], cc["p50"], limit, gate, hist_note))
print()
for key in sorted(base.keys()):
    print(key, "v72:", base[key]["p95_all"], "cand:", cand[key]["p95_all"])
