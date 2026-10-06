"""Read-only source-closure to Android APK representation collector.

No extraction, Godot, dependency discovery, signing, installation or runtime load.
Expected hashes are supplied by the caller's frozen-source/build authority.
"""
import argparse
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import re
import stat
import zipfile

MAX_NODES = 64
MAX_OUTPUT_BYTES = 1 << 20
MAX_PLAN_BYTES = 1 << 20
MAX_MEMBER_BYTES = 64 << 20
MAX_NATIVE_BYTES = 512 << 20
MAX_ZIP_MEMBERS = 100000
PRODUCER = 'hc.code_preparation.lexical_subset.candidate.v1'
SCOPE = 'supported_gdscript_compile_inputs'
CONTEXT = {'res://project.godot': ('assets/project.binary', 'project_binary'),
           'res://.godot/global_script_class_cache.cfg':
           ('assets/.godot/global_script_class_cache.cfg', 'filtered_global_class_cache')}


class Refusal(ValueError):
    pass


def demand(condition, reason):
    if not condition:
        raise Refusal(reason)


def digest_file(path):
    hasher = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def hex_hash(value, length=64):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{' + str(length) + '}', value) is not None


def canonical_relative(value):
    return (isinstance(value, str) and bool(value) and '\\' not in value and ':' not in value
            and not value.startswith('/') and not any(ord(c) < 32 or ord(c) == 127 for c in value)
            and all(part not in ('', '.', '..') for part in value.split('/')))


def logical_path(value):
    return isinstance(value, str) and value.startswith('res://') and canonical_relative(value[6:])


def unique_json(pairs):
    result = {}
    for key, value in pairs:
        demand(key not in result, 'duplicate_json_key:' + key)
        result[key] = value
    return result


def read_plan(path, expected_hash, max_nodes):
    demand(hex_hash(expected_hash), 'source_plan_expected_sha256_invalid')
    demand(Path(path).stat().st_size <= MAX_PLAN_BYTES, 'source_plan_capacity')
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_PLAN_BYTES + 1)
    demand(len(raw) <= MAX_PLAN_BYTES, 'source_plan_capacity')
    demand(hashlib.sha256(raw).hexdigest() == expected_hash, 'source_plan_sha256_mismatch')
    try:
        plan = json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique_json)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise Refusal('source_plan_parse:' + str(error)) from error
    demand(isinstance(plan, dict) and plan.get('schema_version') == 1
           and plan.get('producer_id') == PRODUCER and plan.get('scope') == SCOPE
           and plan.get('status') == 'PASS' and plan.get('errors') == [], 'source_plan_contract')
    nodes = plan.get('nodes')
    demand(isinstance(nodes, dict) and 0 < len(nodes) <= max_nodes, 'source_nodes_capacity_or_shape')
    for path_name, record in nodes.items():
        demand(logical_path(path_name) and isinstance(record, dict), 'source_node_path_or_shape')
        kind = record.get('kind')
        supported = ((kind in ('script', 'resident_script') and record.get('type') == 'GDScript'
                      and path_name.endswith('.gd')) or
                     (kind == 'asset' and record.get('type') == 'Shader' and path_name.endswith('.gdshader')))
        demand(supported, 'unsupported_source_representation:' + path_name)
        validate_record(record)
    target = plan.get('target_path')
    demand(target in nodes and nodes[target].get('kind') == 'script', 'target_contract')
    fingerprints = plan.get('source_fingerprints')
    demand(isinstance(fingerprints, dict) and hex_hash(fingerprints.get('producer')), 'source_fingerprints_contract')
    context = fingerprints.get('source_context')
    demand(isinstance(context, dict) and set(context) == set(CONTEXT), 'source_context_contract')
    for record in context.values():
        validate_record(record)
    demand(context['res://project.godot']['sha256'] == fingerprints.get('project.godot')
           and context['res://.godot/global_script_class_cache.cfg']['sha256'] == fingerprints.get('class_cache'),
           'source_context_fingerprint_conflict')
    edges = plan.get('edges')
    demand(isinstance(edges, list) and len(edges) <= 512, 'edge_capacity_or_shape')
    destinations = {target}
    adjacency = {}
    for edge in edges:
        demand(isinstance(edge, dict) and edge.get('from') in nodes and edge.get('to') in nodes
               and edge.get('kind') in ('preload', 'extends_script', 'named_class', 'autoload_symbol')
               and type(edge.get('line')) is int and edge['line'] > 0, 'edge_contract')
        adjacency.setdefault(edge['from'], set()).add(edge['to'])
    pending = [target]
    while pending:
        for path_name in adjacency.get(pending.pop(), set()):
            if path_name not in destinations:
                destinations.add(path_name)
                pending.append(path_name)
    demand(destinations == set(nodes), 'unreachable_source_node')
    assets = {path_name for path_name, record in nodes.items() if record['kind'] == 'asset'}
    prepared = plan.get('prepared_inputs')
    demand(isinstance(prepared, list) and all(isinstance(p, str) for p in prepared)
           and len(set(prepared)) == len(prepared) and set(prepared) == assets, 'prepared_inputs_contract')
    resident = {path_name for path_name, record in nodes.items() if record['kind'] == 'resident_script'}
    requirements = plan.get('runtime_residency_requirements')
    demand(isinstance(requirements, list) and len(requirements) == len(resident), 'residency_contract')
    declared = set()
    names = set()
    for requirement in requirements:
        demand(isinstance(requirement, dict), 'residency_contract')
        path_name = requirement.get('script_path')
        name = requirement.get('autoload_name')
        demand(path_name in resident and path_name not in declared and isinstance(name, str)
               and re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', name) and name not in names
               and requirement.get('kind') == 'autoload_residency'
               and requirement.get('stage') == 'before_code_request'
               and requirement.get('source_sha256') == nodes[path_name]['sha256'], 'residency_contract')
        declared.add(path_name)
        names.add(name)
    return plan


def validate_record(record):
    demand(isinstance(record, dict) and hex_hash(record.get('sha256'))
           and type(record.get('bytes')) is int and 0 < record['bytes'] <= MAX_MEMBER_BYTES,
           'source_record_contract')


def verify_source_files(plan, source_root):
    root = Path(source_root).resolve(strict=True)
    records = dict(plan['nodes'])
    records.update(plan['source_fingerprints']['source_context'])
    source = {}
    for path_name, record in sorted(records.items()):
        candidate = (root / path_name[6:]).resolve(strict=True)
        demand(candidate.is_relative_to(root) and candidate.is_file(), 'source_path_escape:' + path_name)
        demand(candidate.stat().st_size == record['bytes'] and digest_file(candidate) == record['sha256'],
               'source_bytes_mismatch:' + path_name)
        source[path_name] = {'sha256': record['sha256'], 'bytes': record['bytes']}
    canonical = json.dumps(source, separators=(',', ':'), sort_keys=True).encode()
    return hashlib.sha256(canonical).hexdigest()


class ZipView:
    """Checks the whole central directory, reads only requested members."""
    def __init__(self, path):
        self.archive = zipfile.ZipFile(path, 'r')
        try:
            entries = self.archive.infolist()
            demand(len(entries) <= MAX_ZIP_MEMBERS, 'zip_directory_capacity')
            self.entries = {}
            for entry in entries:
                name = entry.filename
                test_name = name[:-1] if entry.is_dir() else name
                demand(canonical_relative(test_name), 'unsafe_member:' + name)
                demand(name not in self.entries, 'duplicate_member:' + name)
                demand(not stat.S_ISLNK(entry.external_attr >> 16), 'symlink_member:' + name)
                demand(not (entry.flag_bits & 1), 'encrypted_member:' + name)
                self.entries[name] = entry
            self.member_count = len(entries)
        except BaseException:
            self.archive.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.archive.close()

    def record(self, name, max_bytes=MAX_MEMBER_BYTES):
        demand(name in self.entries, 'missing_member:' + name)
        entry = self.entries[name]
        demand(not entry.is_dir() and 0 < entry.file_size <= max_bytes, 'member_capacity_or_empty:' + name)
        hasher = hashlib.sha256()
        prefix = b''
        actual_size = 0
        with self.archive.open(entry) as stream:
            for chunk in iter(lambda: stream.read(1 << 20), b''):
                actual_size += len(chunk)
                demand(actual_size <= max_bytes, 'member_inflation_capacity:' + name)
                hasher.update(chunk)
                if len(prefix) < 16:
                    prefix += chunk[:16 - len(prefix)]
        demand(actual_size == entry.file_size, 'member_size_mismatch:' + name)
        return {'member': name, 'bytes': actual_size, 'sha256': hasher.hexdigest()}, prefix

    def small_text(self, name):
        record, _ = self.record(name)
        demand(record['bytes'] <= 4096, 'remap_capacity:' + name)
        try:
            return self.archive.read(name).decode('utf-8-sig'), record
        except UnicodeError as error:
            raise Refusal('remap_contract:' + name) from error


def parse_remap(text):
    # Exact supported ConfigFile subset; no escapes, duplicate assignments,
    # extra sections/keys, UID indirection, or multiple representation paths.
    match = re.fullmatch(r'\s*\[remap\]\s+path\s*=\s*"([^"\\\r\n]+)"\s*', text)
    demand(match is not None and logical_path(match[1]), 'remap_contract')
    return match[1]


def map_node(archive, path_name, source_record):
    result = {'source': {'sha256': source_record['sha256'], 'bytes': source_record['bytes']},
              'kind': source_record['kind'], 'type': source_record['type']}
    logical_member = 'assets/' + path_name[6:]
    if source_record['kind'] in ('script', 'resident_script'):
        demand(logical_member not in archive.entries, 'unsupported_dual_script_representation:' + path_name)
        text, remap = archive.small_text(logical_member + '.remap')
        mapped = parse_remap(text)
        expected = path_name[:-3] + '.gdc'
        demand(mapped == expected, 'conflicting_remap:' + path_name)
        exported, prefix = archive.record('assets/' + mapped[6:])
        demand(prefix.startswith(b'GDSC'), 'unsupported_gdc:' + mapped)
        result.update(representation='gdscript_binary_tokens', remap=remap, mapped_path=mapped, export=exported)
    else:
        demand(logical_member + '.remap' not in archive.entries and logical_member + '.import' not in archive.entries,
               'unsupported_shader_remap:' + path_name)
        exported, _ = archive.record(logical_member)
        demand(exported['sha256'] == source_record['sha256'] and exported['bytes'] == source_record['bytes'],
               'shader_source_export_mismatch:' + path_name)
        result.update(representation='shader_utf8_source', mapped_path=path_name, export=exported)
    return result


def collect(*, apk_path, plan_path, source_root, expected_plan_sha256, expected_apk_sha256,
            source_commit, engine_commit, template_path, expected_template_sha256,
            abi='arm64-v8a', max_nodes=MAX_NODES, max_output_bytes=MAX_OUTPUT_BYTES):
    demand(type(max_nodes) is int and 1 <= max_nodes <= MAX_NODES, 'max_nodes_contract')
    demand(type(max_output_bytes) is int and 1 <= max_output_bytes <= MAX_OUTPUT_BYTES, 'output_capacity_contract')
    demand(hex_hash(source_commit, 40) and hex_hash(engine_commit, 40), 'commit_binding_contract')
    demand(abi == 'arm64-v8a', 'unsupported_abi')
    plan = read_plan(plan_path, expected_plan_sha256, max_nodes)
    source_closure = verify_source_files(plan, source_root)
    for label, path, expected in [('apk', apk_path, expected_apk_sha256),
                                  ('template', template_path, expected_template_sha256)]:
        demand(hex_hash(expected) and digest_file(path) == expected, label + '_sha256_mismatch')
    with ExitStack() as stack:
        apk = stack.enter_context(ZipView(apk_path))
        template = stack.enter_context(ZipView(template_path))
        native_name = 'lib/' + abi + '/libgodot_android.so'
        native, _ = apk.record(native_name, MAX_NATIVE_BYTES)
        template_native, _ = template.record(native_name, MAX_NATIVE_BYTES)
        demand(native['sha256'] == template_native['sha256'] and native['bytes'] == template_native['bytes'],
               'template_native_mismatch')
        mapped = {path_name: map_node(apk, path_name, record) for path_name, record in sorted(plan['nodes'].items())}
        contexts = {}
        for path_name, (member, representation) in CONTEXT.items():
            exported, prefix = apk.record(member)
            if representation == 'project_binary':
                demand(prefix.startswith(b'ECFG'), 'unsupported_project_binary')
            else:
                demand(prefix.lstrip().startswith(b'list'), 'unsupported_class_cache')
            contexts[path_name] = {'source': plan['source_fingerprints']['source_context'][path_name],
                                   'representation': representation, 'export': exported}
        result = {'schema_version': 1, 'contract_id': 'hc.android.export_identity.capture.v1',
                  'status': 'PASS', 'scope': 'source_closure_to_actual_apk_byte_mapping',
                  'source_binding': {'declared_git_commit': source_commit, 'git_commit_verified_by_collector': 'NOT_RUN',
                                     'source_plan_sha256': expected_plan_sha256, 'source_closure_sha256': source_closure,
                                     'producer_id': plan['producer_id'], 'producer_sha256': plan['source_fingerprints']['producer'],
                                     'target_path': plan['target_path']},
                  'apk_binding': {'path': str(Path(apk_path).resolve()), 'sha256': expected_apk_sha256,
                                  'bytes': Path(apk_path).stat().st_size, 'zip_member_count': apk.member_count},
                  'engine_template_binding': {'declared_engine_commit': engine_commit,
                                              'engine_commit_verified_from_native_library': 'NOT_RUN',
                                              'template_path': str(Path(template_path).resolve()),
                                              'template_sha256': expected_template_sha256,
                                              'template_bytes': Path(template_path).stat().st_size,
                                              'abi': abi, 'apk_native_library': native, 'template_native_library': template_native},
                  'nodes': mapped, 'source_context': contexts, 'edges': plan['edges'],
                  'prepared_inputs': plan['prepared_inputs'],
                  'runtime_residency_requirements': plan['runtime_residency_requirements'],
                  'android_namespace_capability': 'NOT_RUN', 'runtime_acceptance': 'NOT_RUN',
                  'apk_signing_verification': 'NOT_RUN', 'source_to_gdc_semantic_equivalence': 'NOT_RUN'}
    # Reject a changing input; no writes to source, APK or template.
    demand(digest_file(plan_path) == expected_plan_sha256
           and verify_source_files(plan, source_root) == source_closure, 'source_snapshot_changed')
    demand(digest_file(apk_path) == expected_apk_sha256, 'apk_snapshot_changed')
    demand(digest_file(template_path) == expected_template_sha256, 'template_snapshot_changed')
    payload = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
    demand(len(payload) <= max_output_bytes, 'output_capacity')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('apk', 'source-plan', 'source-root', 'expected-source-plan-sha256', 'expected-apk-sha256',
                   'source-commit', 'engine-commit', 'template', 'expected-template-sha256', 'output'):
        parser.add_argument('--' + option, required=True)
    parser.add_argument('--max-nodes', type=int, default=MAX_NODES)
    parser.add_argument('--max-output-bytes', type=int, default=MAX_OUTPUT_BYTES)
    args = parser.parse_args()
    try:
        output = Path(args.output).resolve()
        protected = {Path(args.apk).resolve(), Path(args.source_plan).resolve(), Path(args.template).resolve()}
        demand(output not in protected and not output.is_relative_to(Path(args.source_root).resolve()), 'unsafe_output_path')
        result = collect(apk_path=args.apk, plan_path=args.source_plan, source_root=args.source_root,
                         expected_plan_sha256=args.expected_source_plan_sha256,
                         expected_apk_sha256=args.expected_apk_sha256, source_commit=args.source_commit,
                         engine_commit=args.engine_commit, template_path=args.template,
                         expected_template_sha256=args.expected_template_sha256,
                         max_nodes=args.max_nodes, max_output_bytes=args.max_output_bytes)
        encoded = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
        demand(not output.exists(), 'output_exists')
        with output.open('xb') as stream:
            stream.write(encoded)
        print(json.dumps({'status': 'PASS', 'output': str(output), 'bytes': len(encoded),
                          'sha256': hashlib.sha256(encoded).hexdigest(), 'runtime_acceptance': 'NOT_RUN'}))
        return 0
    except (Refusal, OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error), 'runtime_acceptance': 'NOT_RUN'}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
