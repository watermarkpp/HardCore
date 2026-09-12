import json, glob, os, statistics

RAW = r'C:\Users\Administrator\Documents\HardCore-m30-campaign\raw'
OUT = r'C:\Users\Administrator\Documents\HardCore-m30-campaign'

def pct(sorted_vals, ratio):
    if not sorted_vals:
        return None
    idx = min(len(sorted_vals) - 1, max(0, int(round(ratio * (len(sorted_vals) - 1)))))
    return sorted_vals[idx]

def tails(vals):
    return {'over_16_67ms': sum(1 for v in vals if v > 16.67),
            'over_25ms': sum(1 for v in vals if v > 25.0),
            'over_33_3ms': sum(1 for v in vals if v > 33.3),
            'over_50ms': sum(1 for v in vals if v > 50.0)}

records = {}
problems = []
for path in sorted(glob.glob(os.path.join(RAW, '*.json'))):
    name = os.path.basename(path)[len('rev07_'):-len('.json')]
    side, rnd, rest = name.split('_', 2)
    scenario, count = rest.rsplit('_', 1)
    d = json.load(open(path, encoding='utf-8'))
    if len(d['rows']) != 1:
        problems.append([name, 'rows=%d' % len(d['rows'])]); continue
    r = d['rows'][0]
    raw = r['full_frame_ms_raw']
    ff = r['full_frame_ms']
    checks = {
        'ticks_320': r['sample_physics_ticks'] == 320,
        'raw_matches_samples': len(raw) == ff['samples'],
        'actor_count_ok': r['actual_actor_count'] == int(count),
        'hashes_present': len(d.get('source_hashes_sha256', {})) >= 4,
        'actors_with_motion': r.get('actors_with_motion', 0) > 0,
    }
    s = sorted(raw)
    re_ = {'min': s[0], 'p50': pct(s, .50), 'p95': pct(s, .95), 'p99': pct(s, .99), 'max': s[-1]}
    key = (side, scenario, int(count))
    records.setdefault(key, []).append({
        'round': int(rnd[1:]), 'fixture': {'p50': ff['p50'], 'p95': ff['p95'], 'p99': ff['p99'],
        'min': ff['min'], 'max': ff['max'], 'samples': ff['samples']},
        'recomputed': re_, 'tails': tails(raw), 'tail_fixture': r['tail_frame_counts'],
        'checks': checks, 'label': name,
    })
    if not all(checks.values()):
        problems.append([name, [k for k, v in checks.items() if not v]])

summary = {'schema': 'hardcore.m30_320frame_summary.v1',
           'sides': {'before': '8dd1d092 (m30-r3-integration M30 frozen baseline)',
                     'after': 'bf887623 (current production)'},
           'engine': 'Godot 4.7 stable, same exe, headless, isolated appdata per tree',
           'sampling': '320 physics frames per case (fixture contract), full process-interval raw array kept',
           'cases': {}, 'problems': problems}

for key in sorted(records):
    side, scenario, count = key
    rounds = sorted(records[key], key=lambda x: x['round'])
    summary['cases']['%s_%s_%d' % (side, scenario, count)] = rounds

# Paired per-round comparison for p95/p99/max
pairs = []
for scenario in ('open_pursuit', 'sustained_close_attacks'):
    for count in (12, 15, 30):
        b = {r['round']: r for r in records.get(('before', scenario, count), [])}
        a = {r['round']: r for r in records.get(('after', scenario, count), [])}
        for rnd in (1, 2, 3):
            if rnd in b and rnd in a:
                bb, aa = b[rnd], a[rnd]
                pairs.append({
                    'scenario': scenario, 'count': count, 'round': rnd,
                    'p95_before': bb['recomputed']['p95'], 'p95_after': aa['recomputed']['p95'],
                    'p95_gate_pass': aa['recomputed']['p95'] <= max(bb['recomputed']['p95'] * 1.05, bb['recomputed']['p95'] + 0.5),
                    'p99_before': bb['recomputed']['p99'], 'p99_after': aa['recomputed']['p99'],
                    'max_before': bb['recomputed']['max'], 'max_after': aa['recomputed']['max'],
                    'tails_before': bb['tails'], 'tails_after': aa['tails'],
                })
summary['paired'] = pairs

json.dump(summary, open(os.path.join(OUT, 'campaign_summary.json'), 'w', encoding='utf-8'), indent=1)
print('cases=%d pairs=%d problems=%s' % (len(summary['cases']), len(pairs), problems))
for p in pairs:
    print('%s x%02d r%d p95 %.2f->%.2f gate=%s p99 %.2f->%.2f max %.2f->%.2f tails16 %d->%d' % (
        p['scenario'][:8], p['count'], p['round'], p['p95_before'], p['p95_after'], p['p95_gate_pass'],
        p['p99_before'], p['p99_after'], p['max_before'], p['max_after'],
        p['tails_before']['over_16_67ms'], p['tails_after']['over_16_67ms']))
