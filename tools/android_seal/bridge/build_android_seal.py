"""Build-chain candidate: bind approved source catalogue to actual Android export.

CLI re-runs the frozen collector against inputs; a JSON PASS is never authority.
No engine invocation, APK writing, installation or signing occurs here.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

COLLECTOR_SHA = '684c2df187116bb39b2d684a09732a942d8eb8d4ca640f927b0c4d214c227b5b'
MAX_SEAL_BYTES = 65536


class Refusal(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise Refusal(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def bound_read(path, expected, limit=1048576):
    require(re.fullmatch('[0-9a-f]{64}', expected or '') is not None, 'expected_fingerprint_invalid')
    require(Path(path).stat().st_size <= limit, 'input_capacity')
    raw = Path(path).read_bytes()
    require(sha(raw) == expected, 'input_fingerprint_changed:' + str(path))
    return raw


def load_module(path, name, expected):
    bound_read(path, expected)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def source_bundle_text(source):
    match = re.search(r'^const BUNDLE_JSON := (".*")$', source, re.MULTILINE)
    require(match is not None, 'generated_source_catalogue_format')
    return json.loads(match[1])


def seal_from_verified_inputs(*, source_bundle_json, plan, capture, entry_id, plan_artifact_sha256, capabilities):
    """Pure packaging checks; callers must establish trusted inputs as the CLI does."""
    bundle = json.loads(source_bundle_json)
    require(bundle.get('schema_version') == 1
            and bundle.get('contract_id') == 'hc.internal_code_preparation.catalogue.candidate.v1'
            and bundle.get('runtime_mode') == 'pc_editor_text'
            and bundle.get('entries') == {entry_id: plan}
            and bundle.get('producer_sha256') == plan['source_fingerprints']['producer'], 'registered_source_catalogue')
    require(bundle.get('plan_artifact_sha256') == plan_artifact_sha256, 'registered_plan_artifact_binding')
    require(capture.get('contract_id') == 'hc.android.export_identity.capture.v1'
            and capture.get('source_binding', {}).get('source_plan_sha256') == plan_artifact_sha256
            and capture['source_binding'].get('producer_sha256') == bundle['producer_sha256']
            and capture['source_binding'].get('target_path') == plan['target_path'], 'capture_source_authority_binding')
    require(set(capture.get('nodes', {})) == set(plan['nodes'])
            and set(capture.get('source_context', {})) == set(plan['source_fingerprints']['source_context']), 'source_export_set')
    require('res://scripts/features/generated/internal_code_android_export_data.gd' not in plan['nodes'], 'seal_self_hash_cycle')
    records = []
    for logical, record in sorted(capture['nodes'].items()):
        source = plan['nodes'][logical]
        require(record.get('source') == {k: source[k] for k in ('sha256', 'bytes')}
                and record.get('kind') == source['kind'] and record.get('type') == source['type'], 'source_export_binding')
        exported = dict(record['export'])
        exported['path'] = 'res://' + exported['member'].removeprefix('assets/')
        exported['capture_text'] = source['kind'] == 'asset'
        require(exported['member'].startswith('assets/') and exported['path'] == (logical[:-3] + '.gdc' if source['kind'] != 'asset' else logical), 'export_path_binding')
        records.append(exported)
        if source['kind'] != 'asset':
            require(record.get('mapped_path') == logical[:-3] + '.gdc', 'remap_identity_binding')
            remap = dict(record['remap'])
            remap['path'] = 'res://' + remap['member'].removeprefix('assets/')
            remap['capture_text'] = False
            require(remap['member'] == 'assets/' + logical[6:] + '.remap', 'remap_identity_binding')
            records.append(remap)
    context_records = []
    for logical, record in sorted(capture['source_context'].items()):
        require(record.get('source') == plan['source_fingerprints']['source_context'][logical], 'source_export_binding')
        exported = dict(record['export'])
        exported['path'] = 'res://' + exported['member'].removeprefix('assets/')
        exported['capture_text'] = False
        expected = 'assets/project.binary' if logical.endswith('project.godot') else 'assets/.godot/global_script_class_cache.cfg'
        require(exported['member'] == expected, 'context_representation_binding')
        context_records.append(exported)
    require(len(records) <= 128 and len({r['path'] for r in records + context_records}) == len(records + context_records), 'packed_record_capacity_or_alias')
    native = capture['engine_template_binding']
    require(native['apk_native_library']['sha256'] == native['template_native_library']['sha256']
            and native['apk_native_library']['bytes'] == native['template_native_library']['bytes'], 'native_build_binding')
    require(native['declared_engine_commit'] == bundle['engine']['version']['hash'], 'engine_commit_binding')
    required_fields = {'classes', 'constructors', 'class_methods', 'singletons', 'singleton_methods', 'variant_types', 'coverage'}
    require(set(capabilities) == required_fields and capabilities['classes']
            and len(capabilities['classes']) <= 128 and len(capabilities['constructors']) <= 128 and len(capabilities['class_methods']) <= 256
            and len(capabilities['singletons']) <= 64 and len(capabilities['singleton_methods']) <= 256
            and len(capabilities['variant_types']) <= 64, 'capability_contract')
    require(set(capabilities['constructors']).issubset(set(capabilities['classes']))
            and len(set(capabilities['constructors'])) == len(capabilities['constructors']), 'capability_constructor_binding')
    result = {'schema_version': 1, 'contract_id': 'hc.android.controller_sealed_export.candidate.v1',
              'runtime_mode': 'android_controller_sealed_export', 'entry_id': entry_id,
              'source_bundle_json_sha256': sha(source_bundle_json.encode()),
              'source_plan_artifact_sha256': plan_artifact_sha256, 'producer_sha256': bundle['producer_sha256'],
              'source_binding': capture['source_binding'], 'engine_commit': native['declared_engine_commit'],
              'build_verified_native_sha': native['apk_native_library']['sha256'],
              'runtime_native_image_sha': 'MISSING', 'template_sha256': native['template_sha256'],
              'first_export_apk_sha256': capture['apk_binding']['sha256'],
              'nodes': capture['nodes'], 'source_context': capture['source_context'],
              'packed_records': records, 'context_records': context_records, 'capabilities': capabilities,
              'native_token_device_acceptance': 'NOT_RUN', 'android_runtime_execution': 'NOT_RUN'}
    require(len(json.dumps(result, ensure_ascii=False, separators=(',', ':')).encode()) <= MAX_SEAL_BYTES, 'seal_capacity')
    return result


def lexical_capabilities(plan, root, namespace, producer):
    """Reuse the approved lexer; no new dependency closure or type analyzer."""
    classes = set(namespace['object_classes'])
    singletons = set(namespace['singletons'])
    variants = set(namespace['variant_type_names'])
    used_classes, used_singletons, used_variants = set(), set(), set()
    methods, singleton_methods, constructors = set(), set(), set()
    for logical, record in plan['nodes'].items():
        if record['kind'] not in ('script', 'resident_script'):
            continue
        tokens = [t for t in producer.lex((Path(root) / logical[6:]).read_text(encoding='utf-8-sig')) if t.kind != 'NL']
        for index, token in enumerate(tokens):
            if token.kind != 'IDENT':
                continue
            if token.value in classes:
                used_classes.add(token.value)
            if token.value in singletons:
                used_singletons.add(token.value)
            if token.value in variants:
                used_variants.add(token.value)
            if index + 3 < len(tokens) and tokens[index + 1].value == '.' and tokens[index + 2].kind == 'IDENT' and tokens[index + 3].value == '(':
                if token.value in singletons:
                    singleton_methods.add((token.value, tokens[index + 2].value))
                elif token.value in classes:
                    if tokens[index + 2].value == 'new':
                        # GDScript native construction is not a MethodBind named
                        # "new". Check ClassDB instantiability without constructing.
                        constructors.add(token.value)
                    else:
                        methods.add((token.value, tokens[index + 2].value))
    # These exact APIs are used by the existing preparation service and bridge.
    for name, names in {'ResourceLoader': ['get_cached_ref', 'load_threaded_request', 'load_threaded_get_status', 'load_threaded_get'],
                        'ClassDB': ['class_exists', 'class_get_method_list', 'class_has_method', 'can_instantiate'],
                        'Engine': ['get_version_info', 'has_singleton', 'get_singleton']}.items():
        used_classes.add(name)
        methods.update((name, method) for method in names)
    return {'classes': sorted(used_classes), 'constructors': sorted(constructors), 'class_methods': [{'class':c, 'method':m} for c,m in sorted(methods)],
            'singletons': sorted(used_singletons), 'singleton_methods': [{'singleton':c, 'method':m} for c,m in sorted(singleton_methods)],
            'variant_types': sorted(used_variants), 'coverage':'lexical_direct_native_uses_plus_exact_preparation_APIs; dynamic_receiver_and_token_semantics_NOT_RUN'}


def emit_source(seal):
    encoded = json.dumps(seal, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    return ('extends RefCounted\n\n# Generated candidate: controller-sealed export byte identity, never author/player JSON.\n'
            'const AVAILABLE := true\nconst SEAL_SHA256 := ' + json.dumps(sha(encoded.encode())) + '\n'
            'const SEAL_JSON := ' + json.dumps(encoded, ensure_ascii=False) + '\n'
            'static func read_bundle() -> Dictionary:\n\tvar value: Variant = JSON.parse_string(SEAL_JSON)\n\treturn value if value is Dictionary else {}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-catalogue', 'expected-source-catalogue-sha256', 'source-plan', 'expected-source-plan-sha256',
                 'producer', 'expected-producer-sha256', 'namespace', 'expected-namespace-sha256', 'source-root',
                 'apk', 'expected-apk-sha256', 'template', 'expected-template-sha256', 'source-commit', 'entry-id',
                 'output-gd', 'output-json'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    collector_path = Path(__file__).parent.parent / 'export_identity_tool/collector.py'
    collector = load_module(collector_path, 'frozen_android_export_collector', COLLECTOR_SHA)
    source = bound_read(args.source_catalogue, args.expected_source_catalogue_sha256).decode('utf-8-sig')
    bundle_json = source_bundle_text(source)
    bundle = json.loads(bundle_json)
    plan = collector.read_plan(args.source_plan, args.expected_source_plan_sha256, 64)
    producer = load_module(args.producer, 'approved_subset_producer_for_android_seal', args.expected_producer_sha256)
    require(plan['source_fingerprints']['producer'] == args.expected_producer_sha256, 'producer_binding')
    namespace_raw = bound_read(args.namespace, args.expected_namespace_sha256)
    namespace = json.loads(namespace_raw)
    artifacts = bundle.get('input_artifacts', [])
    require(any(row.get('kind') == 'namespace' and row.get('sha256') == args.expected_namespace_sha256 for row in artifacts), 'source_namespace_artifact_binding')
    actual_capture = collector.collect(apk_path=args.apk, plan_path=args.source_plan, source_root=args.source_root,
                                       expected_plan_sha256=args.expected_source_plan_sha256,
                                       expected_apk_sha256=args.expected_apk_sha256,
                                       source_commit=args.source_commit, engine_commit=bundle['engine']['version']['hash'],
                                       template_path=args.template, expected_template_sha256=args.expected_template_sha256)
    capabilities = lexical_capabilities(plan, args.source_root, namespace, producer)
    collector.verify_source_files(plan, args.source_root)
    seal = seal_from_verified_inputs(source_bundle_json=bundle_json, plan=plan, capture=actual_capture,
                                     entry_id=args.entry_id, plan_artifact_sha256=args.expected_source_plan_sha256,
                                     capabilities=capabilities)
    protected = {Path(p).resolve() for p in (args.source_catalogue, args.source_plan, args.producer, args.namespace, args.apk, args.template)}
    outputs = [Path(args.output_gd).resolve(), Path(args.output_json).resolve()]
    require(len(set(outputs)) == 2 and not any(path in protected or path.exists() for path in outputs), 'output_collision')
    for path, text in zip(outputs, (emit_source(seal), json.dumps(seal, ensure_ascii=False, sort_keys=True, separators=(',', ':')))):
        with path.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
    print(json.dumps({'status':'PASS', 'scope':'candidate build-sealed mapping generated',
                      'runtime_native_image_sha':'MISSING', 'native_token_device_acceptance':'NOT_RUN',
                      'outputs':[{'path':str(p), 'sha256':sha(p.read_bytes())} for p in outputs]}))


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, ValueError, KeyError) as error:
        print(json.dumps({'status':'FAIL', 'error':str(error), 'android_runtime_execution':'NOT_RUN'}))
        raise SystemExit(2)
