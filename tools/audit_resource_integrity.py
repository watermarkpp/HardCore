"""HC-P1-015: scan project for res:// references and verify existence."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIPPED_ROOTS = {
    '.git',
    '.godot',
    'artifacts',
    'dev_art_sources',
    'map_editor_workspace',
    'outputs',
}
INTENTIONAL_MISSING_REFERENCES = {
    'res://tests/fixtures/runtime_release/does_not_exist.runtime.json',
    'res://tests/fixtures/runtime_release/missing_registry.json',
}
RESOURCE_REFERENCE_RE = re.compile(r'(["\'])(res://[^"\'\r\n]+)\1')

def scan_file(f: Path) -> list[dict]:
    refs = []
    try:
        text = f.read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return refs
    for lineno, line in enumerate(text.split('\n'), 1):
        for match in RESOURCE_REFERENCE_RE.finditer(line):
            path = match.group(2)
            if any(marker in path for marker in ('%', '{', '}')):
                continue
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
        relative_parts = f.relative_to(ROOT).parts
        if relative_parts and relative_parts[0] in SKIPPED_ROOTS:
            continue
        refs.extend(scan_file(f))

# Deduplicate
seen = set()
unique = []
for r in refs:
    if r['path'] not in seen:
        seen.add(r['path'])
        r['level'] = classify(r['path'])
        resource_path = r['path'].split('#', 1)[0]
        full = ROOT / resource_path.removeprefix('res://')
        r['exists'] = full.exists()
        if not r['exists'] and not Path(resource_path).suffix:
            continue
        if r['path'] in INTENTIONAL_MISSING_REFERENCES:
            r['exists'] = True
            r['intentional_missing_fixture'] = True
        r['sha256'] = ''
        if r['exists']:
            try:
                r['sha256'] = hashlib.sha256(full.read_bytes()).hexdigest()
            except: pass
        unique.append(r)

blocker_missing = [r for r in unique if r['level']=='BLOCKER' and not r['exists']]
required_missing = [r for r in unique if r['level']=='REQUIRED' and not r['exists']]

print(f'Total unique references: {len(unique)}')
blocker_count = sum(r['level'] == 'BLOCKER' for r in unique)
blocker_existing = sum(r['level'] == 'BLOCKER' and r['exists'] for r in unique)
required_count = sum(r['level'] == 'REQUIRED' for r in unique)
required_existing = sum(r['level'] == 'REQUIRED' and r['exists'] for r in unique)
print(f'BLOCKER: {blocker_count} ({blocker_existing} exist)')
print(f'REQUIRED: {required_count} ({required_existing} exist)')
print(f'BLOCKER missing: {len(blocker_missing)}')
print(f'REQUIRED missing: {len(required_missing)}')

if blocker_missing:
    print('BLOCKER MISSING:')
    for r in blocker_missing[:10]:
        print(f'  {r["path"]} (from {r["source_file"]}:{r["line"]})')

if required_missing:
    print('REQUIRED MISSING (first 20):')
    for r in required_missing[:20]:
        print(f'  {r["path"]} (from {r["source_file"]}:{r["line"]})')

manifest_path = ROOT / 'artifacts/test_evidence/resource_manifest.json'
manifest_path.parent.mkdir(parents=True, exist_ok=True)
with manifest_path.open('w', encoding='utf-8') as f:
    json.dump(
        {
            'total': len(unique),
            'blocker_missing': len(blocker_missing),
            'required_missing': len(required_missing),
            'missing_items': blocker_missing + required_missing,
            'items': unique[:500],
        },
        f,
        indent=2,
    )

sys.exit(0 if len(blocker_missing)==0 and len(required_missing)==0 else 1)
