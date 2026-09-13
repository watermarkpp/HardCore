"""Read-only, fixed-commit GitHub MCP bridge for the approved mechanical scanner.

No shell execution, local data reads, repository mutation, credentials or generic
URL fetching is exposed. The only local input is the reviewed audit program,
whose bytes must match the same file at the pinned remote commit before use.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
from types import SimpleNamespace
import urllib.request
import urllib.error

SHA = '191958eaa194639b1072149cd23e34a389d8a7e4'
REPO = 'watermarkpp/HardCore'
REFS = {SHA, 'e38215978c481b988df3203410bb1dda6b5b0968', '342891ab884150c0e81084c932df8205484e6388'}
FILES = {
    '.gitattributes',
    'assets/data/source_priority_policy.json',
    'assets/data/canonical_monster_drop_source_v2.json',
    'assets/data/runtime/canonical_monster_catalog.json',
    'scripts/game_data.gd', 'scripts/layers/runtime/loot_runtime_service.gd',
    'scripts/drop/dpv2_repair_v5_contract.gd',
    'tools/audit_current_drop_tables.py',
    'tests/test_dpv2_repair_v5.gd', 'tests/dpv2_21cq_direct_runtime_test.gd',
    'docs/repair_20260913/evidence/current_drop_audit.json',
    'docs/repair_20260913/evidence/drop_preservation.json',
}
DROP_NAMES = {
    'dpv2_direct_baseline_v2', 'dpv2_direct_baseline_manifest_v2',
    'dpv2_single_player_drop_boost_v1', 'dpv2_single_player_effective_probability_v1',
    'dpv2_single_player_item_boost_classification_v1',
    'dpv2_21cq_verified_profile_authority_v1', 'dpv2_21cq_source_provenance_v1',
    'dpv2_21cq_item_mapping_v1', 'dpv2_21cq_monster_mapping_v1',
    'dpv2_21cq_overflow_authority_v1', 'dpv2_21cq_source_corrections_v1',
    'dpv2_monster_drop_semantic_authority_v1', 'dpv2_global_drop_rate_authority_v1',
    'dpv2_drop_runtime_authority_v1',
}
FILES.update('assets/data/drop/' + name + '.json' for name in DROP_NAMES)
CACHE = {}
CHECKOUT_BYTES = {}


def fetch(path, ref=SHA):
    if ref not in REFS or not (path in FILES or re.fullmatch(r'docs/drop/v5/source/monster_[0-9]+\.bin', path)):
        raise ValueError('Path/ref is outside the fixed read-only drop scan allowlist')
    key = (ref, path)
    if key not in CACHE:
        url = f'https://raw.githubusercontent.com/{REPO}/{ref}/{path}'
        # This host has returned truncated HTTPS bodies and SSL EOF errors.
        # Never cache an incomplete/invalid response; retry only these reads.
        for attempt in range(3):
            try:
                with urllib.request.urlopen(url, timeout=30) as response:
                    if response.status != 200:
                        raise ValueError(f'HTTP {response.status}: {path}')
                    data = response.read(16000001)
                    if len(data) > 16000000:
                        raise ValueError('Remote file exceeds scan size limit')
                    length = response.headers.get('Content-Length')
                    if length is not None and len(data) != int(length):
                        raise OSError(f'Incomplete HTTP body: {len(data)}/{length}')
                    if path.endswith('.json'):
                        json.loads(data)
                    CACHE[key] = data
                    break
            except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
                if attempt == 2:
                    raise ValueError(f'Remote read failed at {ref}:{path}: {error}') from error
    return CACHE[key]


class RemotePath:
    def __init__(self, path=''):
        self.path = path

    def __truediv__(self, path):
        return RemotePath(path)

    def read_bytes(self):
        return CHECKOUT_BYTES.get(self.path, fetch(self.path))

    def read_text(self, encoding='utf-8'):
        return self.read_bytes().decode(encoding)

    def is_file(self):
        return bool(self.read_bytes())


def remote_git_show(args, cwd=None):
    if len(args) != 3 or args[:2] != ['git', 'show']:
        raise ValueError('Only pinned remote git-show reads are supported')
    ref, path = args[2].split(':', 1)
    return fetch(path, ref)


def scan_tables():
    audit_path = Path(__file__).with_name('audit_current_drop_tables.py')
    if fetch('tools/audit_current_drop_tables.py') != audit_path.read_bytes().replace(b'\r\n', b'\n'):
        raise ValueError('Local reviewed audit program differs from pinned remote bytes')
    authority = json.loads(fetch('assets/data/drop/dpv2_21cq_verified_profile_authority_v1.json'))
    captures = []
    for record in authority['records']:
        capture = record.get('source_evidence', record)
        if capture.get('raw_path') and capture.get('raw_sha256'):
            captures.append(capture['raw_path'])
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(fetch, sorted(FILES - {'scripts/game_data.gd'} | set(captures))))
    spec = importlib.util.spec_from_file_location('drop_audit_readonly', audit_path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    # Replace the audit's file/Git readers with allowlisted remote byte readers.
    # No commands are executed and no checkout or temporary data files are used.
    audit.ROOT = RemotePath()
    audit.subprocess = SimpleNamespace(check_output=remote_git_show)
    result = audit.audit()
    # Git stores normalized LF text. The recorded raw source SHA contracts were
    # made from Windows checkout bytes. Prove each reversible CRLF restoration
    # against that exact recorded SHA; never ignore another kind of mismatch.
    raw_errors = result['errors'][:]
    manifest = json.loads(fetch('assets/data/drop/dpv2_direct_baseline_manifest_v2.json'))
    logical = manifest['tracked_logical_source']
    attributes = fetch('.gitattributes').decode('utf-8-sig')
    if logical['path'] + ' text eol=crlf' not in attributes:
        raise ValueError('Remote attributes do not declare logical source CRLF')
    expected_hashes = {logical['path']: logical['sha256_raw']}
    for record in authority['records']:
        capture = record.get('source_evidence', record)
        if capture.get('raw_path') and capture.get('raw_sha256'):
            expected_hashes[capture['raw_path']] = capture['raw_sha256']
    restorations = []
    for path, expected in expected_hashes.items():
        raw = fetch(path)
        actual = hashlib.sha256(raw).hexdigest().upper()
        if actual == expected:
            continue
        restored = raw.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
        restored_sha = hashlib.sha256(restored).hexdigest().upper()
        if restored_sha == expected:
            CHECKOUT_BYTES[path] = restored
            restorations.append({'path': path, 'git_blob_sha256': actual,
                                 'checkout_sha256': restored_sha, 'expected': expected,
                                 'operation': 'LF to CRLF; complete raw SHA match'})
    if restorations:
        result = audit.audit()
    result['raw_git_representation_errors'] = raw_errors
    result['checkout_byte_restorations'] = restorations
    samples = result.pop('elite_boss_potions')
    result['solar_examples'] = [r for r in samples if r['item_id'] in [920014, 920016]][:24]
    result['profile_sample'] = result.pop('profiles')[:12]
    result['remote_proof'] = {
        'repository': REPO, 'commit': SHA, 'transport': 'HTTPS raw.githubusercontent.com',
        'cached_remote_files': len(CACHE), 'source_captures_checked': len(captures),
        'all_checks_read_remote_bytes': True,
        'auditor_sha256': hashlib.sha256(fetch('tools/audit_current_drop_tables.py')).hexdigest(),
        'historical_refs': sorted(REFS - {SHA}),
    }
    return result


TOOLS = [
    {'name': 'scan_remote_drop_tables', 'description': 'Enumerate ALL pinned remote drop JSON tables with exact rational, UID, provenance, remote source capture hash and frozen-history checks. Reads remote bytes only; returns computed evidence, not game/device acceptance.', 'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False}},
    {'name': 'read_remote_drop_file', 'description': 'Read numbered text lines from an allowlisted drop file at fixed remote commit 191958e. No local filesystem or moving branch access.', 'inputSchema': {'type': 'object', 'properties': {'path': {'type': 'string'}, 'start_line': {'type': 'integer', 'minimum': 1}, 'line_count': {'type': 'integer', 'minimum': 1, 'maximum': 400}}, 'required': ['path'], 'additionalProperties': False}},
]
RESOURCE_BASE = f'hardcore-drop://{SHA}/'
RESOURCES = [
    {'uri': RESOURCE_BASE + 'manifest.json', 'name': 'Pinned remote drop manifest', 'mimeType': 'application/json'},
    {'uri': RESOURCE_BASE + 'baseline_summary.json', 'name': 'Pinned remote production table metadata and first profile', 'mimeType': 'application/json'},
    {'uri': RESOURCE_BASE + 'complete_audit.json', 'name': 'Full remote 7611-slot computed audit, hashes and frozen history', 'mimeType': 'application/json'},
]


def handle(message):
    method, params = message.get('method'), message.get('params', {})
    if method == 'initialize':
        return {'protocolVersion': params.get('protocolVersion', '2024-11-05'), 'capabilities': {'tools': {}, 'resources': {}}, 'serverInfo': {'name': 'hardcore-fixed-remote-drop-readonly', 'version': '1.0'}}
    if method == 'ping':
        return {}
    if method == 'tools/list':
        return {'tools': TOOLS}
    if method == 'resources/list':
        return {'resources': RESOURCES}
    if method == 'resources/templates/list':
        return {'resourceTemplates': []}
    if method == 'resources/read':
        uri = params['uri']
        if uri == RESOURCE_BASE + 'manifest.json':
            result = json.loads(fetch('assets/data/drop/dpv2_direct_baseline_manifest_v2.json'))
        elif uri == RESOURCE_BASE + 'baseline_summary.json':
            result = json.loads(fetch('assets/data/drop/dpv2_direct_baseline_v2.json'))
            result['profiles'] = result['profiles'][:1]
            result['coverage'] = 'Metadata and first profile only; complete_audit.json enumerates all remote records.'
        elif uri == RESOURCE_BASE + 'complete_audit.json':
            result = scan_tables()
            restorations = result.pop('checkout_byte_restorations')
            raw_errors = result.pop('raw_git_representation_errors')
            result['git_checkout_representation'] = {
                'raw_git_hash_differences': len(raw_errors),
                'exact_recorded_hash_matches_after_CRLF_restoration': len(restorations),
                'all_differences_explained': len(raw_errors) == len(restorations),
                'examples': restorations[:6],
                'complete_restoration_evidence_sha256': hashlib.sha256(
                    json.dumps(restorations, sort_keys=True).encode()).hexdigest(),
            }
        else:
            raise ValueError('Unknown resource URI; use resources/list')
        return {'contents': [{'uri': uri, 'mimeType': 'application/json', 'text': json.dumps(result, ensure_ascii=False)}]}
    if method == 'tools/call':
        try:
            if params['name'] == 'scan_remote_drop_tables':
                result = scan_tables()
            elif params['name'] == 'read_remote_drop_file':
                args = params.get('arguments', {})
                start, count = int(args.get('start_line', 1)), int(args.get('line_count', 100))
                if start < 1 or not 1 <= count <= 400:
                    raise ValueError('Invalid line range')
                path = args['path']
                data = fetch(path)
                lines = data.decode('utf-8-sig').splitlines()
                result = {'url': f'https://raw.githubusercontent.com/{REPO}/{SHA}/{path}', 'sha256': hashlib.sha256(data).hexdigest(), 'total_lines': len(lines), 'lines': [{'line': i + 1, 'text': lines[i]} for i in range(start - 1, min(start - 1 + count, len(lines)))]}
            else:
                raise ValueError('Unknown read-only tool')
            return {'content': [{'type': 'text', 'text': json.dumps(result, ensure_ascii=False)}], 'isError': False}
        except Exception as error:
            return {'content': [{'type': 'text', 'text': f'{type(error).__name__}: {error}'}], 'isError': True}
    raise ValueError('Unsupported MCP method')


if __name__ == '__main__':
    if hasattr(sys.stdin, 'reconfigure'):
        sys.stdin.reconfigure(encoding='utf-8')
        sys.stdout.reconfigure(encoding='utf-8')
    for line in sys.stdin:
        message = json.loads(line)
        if 'id' not in message:
            continue
        try:
            reply = {'jsonrpc': '2.0', 'id': message['id'], 'result': handle(message)}
        except Exception as error:
            reply = {'jsonrpc': '2.0', 'id': message['id'], 'error': {'code': -32603, 'message': str(error)}}
        print(json.dumps(reply, ensure_ascii=False), flush=True)
