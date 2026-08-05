"""HC-P1-015: scan project for res:// references and verify existence."""
import json, os, sys, hashlib
from pathlib import Path

ROOT = Path(r'C:\Users\Administrator\Documents\HardCore')

def scan_file(f: Path) -> list[dict]:
    refs = []
    try:
        text = f.read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return refs
    for lineno, line in enumerate(text.split('\n'), 1):
        if 'res://' in line:
            import re
            for m in re.finditer(r'res://([^"\'\s]+)', line):
                path = 'res://' + m.group(1).rstrip('"\'')
                refs.append({'source_file': str(f.relative_to(ROOT)), 'line': lineno, 'path': path})
    return refs

def classify(path: str) -> str:
    if any(x in path for x in ['project.godot','export_presets','skill_visual_profiles','caster_skill_visuals','game_data']):
        return 'BLOCKER'
    if any(x in path for x in ['scripts/','assets/data/','tests/','scenes/']):
        return 'REQUIRED'
    if any(x in path for x in ['assets/art/','assets/ui/','assets/branding/']):
        return 'REQUIRED'
    return 'OPTIONAL'

refs = []
for ext in ['*.gd','*.tscn','*.tres','*.json','*.cfg']:
    for f in ROOT.rglob(ext):
        if '.godot' in str(f) or '.git' in str(f):
            continue
        refs.extend(scan_file(f))

# Deduplicate
seen = set()
unique = []
for r in refs:
    if r['path'] not in seen:
        seen.add(r['path'])
        r['level'] = classify(r['path'])
        full = ROOT / r['path'].replace('res://','')
        r['exists'] = full.exists()
        r['sha256'] = ''
        if r['exists']:
            try:
                r['sha256'] = hashlib.sha256(full.read_bytes()).hexdigest()
            except: pass
        unique.append(r)

blocker_missing = [r for r in unique if r['level']=='BLOCKER' and not r['exists']]
required_missing = [r for r in unique if r['level']=='REQUIRED' and not r['exists']]

print(f'Total unique references: {len(unique)}')
print(f'BLOCKER: {len([r for r in unique if r["level"]==\"BLOCKER\"])} ({len([r for r in unique if r[\"level\"]==\"BLOCKER\" and r[\"exists\"]])} exist)')
print(f'REQUIRED: {len([r for r in unique if r[\"level\"]==\"REQUIRED\"])} ({len([r for r in unique if r[\"level\"]==\"REQUIRED\" and r[\"exists\"]])} exist)')
print(f'BLOCKER missing: {len(blocker_missing)}')
print(f'REQUIRED missing: {len(required_missing)}')

if blocker_missing:
    print('BLOCKER MISSING:')
    for r in blocker_missing[:10]:
        print(f'  {r["path"]} (from {r["source_file"]}:{r["line"]})')

with open(str(ROOT / 'artifacts/test_evidence/resource_manifest.json'), 'w') as f:
    json.dump({'total': len(unique), 'blocker_missing': len(blocker_missing), 'required_missing': len(required_missing), 'items': unique[:500]}, f, indent=2)

sys.exit(0 if len(blocker_missing)==0 and len(required_missing)==0 else 1)
