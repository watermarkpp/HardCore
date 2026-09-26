#!/usr/bin/env python3
"""Execute the audited verifier against synthetic files, never production data.

Default mode records the actual results (exit 0 means the probe ran).
--expect-fixed exits 1 whenever the verifier violates an expected outcome.
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

ORIGINAL_BLOB = '7c6251500bb0b206e1b2acf93ae8f852477032bf'


def base_catalog() -> dict:
    rows = [
        {'monster_id': mid, 'classification': 'ordinary',
         'combat': {'stats': {'hp': 100, 'attack_min': 2, 'attack_max': 5}},
         'drop_policy': {'allowed': True, 'rule': 'original'},
         'source_evidence': {'combat_stats': {'hp': {'value': 100, 'source': 'approved'}}}}
        for mid in (24, 33)
    ]
    return {'entries': copy.deepcopy(rows), 'entries_by_id': {str(x['monster_id']): copy.deepcopy(x) for x in rows},
            'sources': {'assets/data/vanilla_176/monsters.json': {'sha256': 'a'*64, 'role': 'generator_input'}},
            'summary': {'identity_count': 2}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--verifier', type=Path, default=Path(__file__).resolve().parents[1] / 'evidence/verify_catalog_reswap.original.py')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--expect-fixed', action='store_true')
    args = parser.parse_args()
    code = args.verifier.read_bytes()
    blob = hashlib.sha1(f'blob {len(code)}\0'.encode() + code).hexdigest()
    if not args.expect_fixed and blob != ORIGINAL_BLOB:
        raise SystemExit('Audited-source hash mismatch; use --expect-fixed for a modified implementation.')
    old = base_catalog()
    cases = []
    cases.append(('unchanged_positive_control', copy.deepcopy(old), True))
    a = copy.deepcopy(old); a['entries'][0]['combat']['stats']['hp'] = 999999
    cases.append(('entries_only_combat_tamper', a, False))
    a = copy.deepcopy(old); a['sources'] = {}
    cases.append(('remove_all_source_bindings', a, False))
    a = copy.deepcopy(old); a['entries_by_id']['33']['source_evidence']['combat_stats']['hp']['value'] = 999999
    a['entries'][1] = copy.deepcopy(a['entries_by_id']['33'])
    cases.append(('exempt_id_unrelated_combat_evidence_tamper', a, False))
    a = copy.deepcopy(old); a['entries_by_id']['24']['combat']['stats']['hp'] = 999999
    a['entries'][0] = copy.deepcopy(a['entries_by_id']['24'])
    cases.append(('by_id_combat_negative_control', a, False))
    results = []
    with tempfile.TemporaryDirectory(prefix='hc_r2_reswap_review_') as tmp:
        root = Path(tmp)
        old_file = root / 'old.json'; new_file = root / 'new.json'
        old_file.write_text(json.dumps(old, ensure_ascii=False), encoding='utf-8')
        for name, candidate, should_accept in cases:
            new_file.write_text(json.dumps(candidate, ensure_ascii=False), encoding='utf-8')
            old_before = old_file.read_bytes(); new_before = new_file.read_bytes()
            run = subprocess.run([sys.executable, str(args.verifier.resolve()), str(old_file), str(new_file)],
                                 text=True, capture_output=True, timeout=10)
            accepted = run.returncode == 0
            results.append({'case': name, 'should_accept': should_accept, 'exit_code': run.returncode,
                            'accepted': accepted, 'contract_satisfied': accepted == should_accept,
                            'input_files_unchanged': old_before == old_file.read_bytes() and new_before == new_file.read_bytes(),
                            'stdout': run.stdout, 'stderr': run.stderr})
    result = {'source_commit': '2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a',
              'source_path': 'tools/verify_catalog_reswap.py', 'source_git_blob': blob,
              'source_matches_audited_blob': blob == ORIGINAL_BLOB,
              'scope': 'Original Python verifier executed on synthetic inputs; not a Godot/game/runtime test.',
              'results': results, 'contract_failures': sum(not r['contract_satisfied'] for r in results)}
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True); args.out.write_text(text, encoding='utf-8')
    print(text)
    return int(args.expect_fixed and result['contract_failures'] > 0)


if __name__ == '__main__':
    raise SystemExit(main())
