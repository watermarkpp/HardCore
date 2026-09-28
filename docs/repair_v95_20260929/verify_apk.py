"""Check v96 exact source, v95/patch inheritance and frozen packaged art/data."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
for key in ('apk', 'baseline', 'stage', 'output'):
    p.add_argument('--' + key, type=Path, required=True)
p.add_argument('--commit', required=True)
a = p.parse_args()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def sha(content):
    return hashlib.sha256(content).hexdigest()

baseline_commit = '7076bc465dbf7dc837381f267fa8eb9e151bf001'
patch_commit = '21b40ddae663997f8e9f267585988e6a7c63db6a'
for ancestor in (baseline_commit, patch_commit):
    subprocess.run(['git', 'merge-base', '--is-ancestor', ancestor, a.commit], cwd=ROOT, check=True)
assert not git('diff', '--name-only', baseline_commit, a.commit, '--', 'assets', 'map_editor_workspace', 'project.godot', 'export_presets.cfg').strip()
changed = set(git('diff', '--name-only', baseline_commit, a.commit, '--', 'scripts').decode().splitlines())
rows, frozen, unchanged_scripts = [], [], []
with zipfile.ZipFile(a.apk, metadata_encoding='utf-8') as apk, zipfile.ZipFile(a.baseline, metadata_encoding='utf-8') as base:
    assert apk.testzip() is None
    names, old_names = set(apk.namelist()), set(base.namelist())
    assert len(names) == len(apk.namelist())
    assert not any(n.startswith(('assets/tests/', 'assets/docs/', 'assets/tools/')) for n in names)
    info = json.loads(apk.read('assets/assets/generated/build_info.json').rstrip(b'\0'))
    old_info = json.loads(base.read('assets/assets/generated/build_info.json').rstrip(b'\0'))
    assert info['git_head'] == a.commit and info['git_dirty'] is False and info['version_code'] == 96
    assert old_info['git_head'] == baseline_commit and old_info['version_code'] == 95
    for path in sorted(changed):
        if not path.endswith('.gd'): continue
        content = (a.stage / path).read_bytes().replace(b'\r\n', b'\n')
        assert content == git('show', a.commit + ':' + path).replace(b'\r\n', b'\n'), path
        entry = 'assets/' + path[:-3] + '.gdc'
        compiled = apk.read(entry)
        assert compiled and (entry not in old_names or compiled != base.read(entry)), path
        rows.append({'source': path, 'source_sha256_lf': sha(content), 'entry': entry, 'compiled_sha256': sha(compiled)})
    for entry in sorted(old_names):
        if entry.startswith('assets/assets/data/') or (entry.startswith('assets/.godot/imported/') and entry.endswith('.ctex')):
            assert entry in names and apk.read(entry) == base.read(entry), 'frozen packaged resource lost/changed: ' + entry
            frozen.append({'entry': entry, 'sha256': sha(apk.read(entry))})
        elif entry.startswith('assets/scripts/') and entry.endswith('.gdc'):
            source = entry.removeprefix('assets/')[:-4] + '.gd'
            if source not in changed:
                assert apk.read(entry) == base.read(entry), 'unchanged bytecode changed: ' + entry
                unchanged_scripts.append(entry)
with a.apk.open('rb') as f:
    apk_hash = hashlib.file_digest(f, 'sha256').hexdigest()
report = {'result': 'PASS', 'source_commit': a.commit, 'apk': str(a.apk),
          'size_bytes': a.apk.stat().st_size, 'sha256': apk_hash, 'build_info': info,
          'baseline_commit': baseline_commit, 'previous_patch_commit': patch_commit,
          'inheritance': 'PASS', 'changed_runtime_scripts': rows,
          'unchanged_compiled_scripts': unchanged_scripts, 'frozen_packaged_entries': frozen,
          'zip_crc': 'PASS', 'test_tools_docs_exclusion': 'PASS', 'device_test': 'NOT_RUN'}
a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'result': 'PASS', 'scripts': len(rows), 'unchanged_scripts': len(unchanged_scripts),
                  'frozen_packaged_entries': len(frozen), 'sha256': apk_hash, 'output': str(a.output)}))
