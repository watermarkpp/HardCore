"""Candidate final-export verifier. Reads ZIPs; never runs Godot/build/install."""
import argparse
import json
from pathlib import Path

from build_android_seal import COLLECTOR_SHA, bound_read, load_module, require, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('seal-json', 'expected-seal-json-sha256', 'seal-gd', 'expected-seal-gd-sha256',
                 'source-plan', 'expected-source-plan-sha256', 'source-root', 'apk', 'expected-apk-sha256',
                 'template', 'expected-template-sha256', 'source-commit', 'output'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    seal = json.loads(bound_read(args.seal_json, args.expected_seal_json_sha256))
    bound_read(args.seal_gd, args.expected_seal_gd_sha256)
    collector = load_module(Path(__file__).parent.parent / 'export_identity_tool/collector.py', 'frozen_final_export_collector', COLLECTOR_SHA)
    capture = collector.collect(apk_path=args.apk, plan_path=args.source_plan, source_root=args.source_root,
                                expected_plan_sha256=args.expected_source_plan_sha256,
                                expected_apk_sha256=args.expected_apk_sha256,
                                source_commit=args.source_commit, engine_commit=seal['engine_commit'],
                                template_path=args.template, expected_template_sha256=args.expected_template_sha256)
    require(capture['nodes'] == seal['nodes'] and capture['source_context'] == seal['source_context'], 'final_export_closure_or_context_changed')
    require(capture['engine_template_binding']['apk_native_library']['sha256'] == seal['build_verified_native_sha'], 'final_native_changed')
    metadata_path = 'res://scripts/features/generated/internal_code_android_export_data.gd'
    require(metadata_path not in capture['nodes'], 'seal_self_hash_cycle')
    with collector.ZipView(args.apk) as apk:
        text, remap = apk.small_text('assets/' + metadata_path[6:] + '.remap')
        mapped = collector.parse_remap(text)
        require(mapped == metadata_path[:-3] + '.gdc', 'seal_metadata_remap_changed')
        metadata, prefix = apk.record('assets/' + mapped[6:])
        require(prefix.startswith(b'GDSC'), 'seal_metadata_representation')
    result = {'schema_version':1, 'status':'PASS', 'scope':'final_export_exact_closure_context_native_mapping',
              'source_plan_sha256':args.expected_source_plan_sha256, 'seal_json_sha256':args.expected_seal_json_sha256,
              'generated_seal_gd_sha256':args.expected_seal_gd_sha256,
              'actual_metadata_gdc':metadata, 'actual_metadata_remap':remap,
              'final_apk_sha256':args.expected_apk_sha256, 'first_export_apk_sha256':seal['first_export_apk_sha256'],
              'runtime_native_image_sha':'MISSING', 'build_verified_native_sha':seal['build_verified_native_sha'],
              'native_token_device_acceptance':'NOT_RUN', 'metadata_source_to_gdc_semantics':'NOT_RUN'}
    # Exact fixed official exporter + frozen source/command receipt supplies
    # source-to-token provenance. This tool cannot decode token semantic identity.
    output = Path(args.output).resolve()
    require(not output.exists() and not output.is_relative_to(Path(args.source_root).resolve()), 'unsafe_output')
    output.write_text(json.dumps(result, sort_keys=True, separators=(',', ':')), encoding='utf-8')
    print(json.dumps({'status':'PASS', 'output':str(output), 'sha256':sha(output.read_bytes()), 'native_token_device_acceptance':'NOT_RUN'}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({'status':'FAIL', 'error':str(error), 'native_token_device_acceptance':'NOT_RUN'}))
        raise SystemExit(2)
