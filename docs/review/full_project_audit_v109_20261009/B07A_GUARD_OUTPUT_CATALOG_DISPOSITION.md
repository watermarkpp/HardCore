# B07A-004 / B07A-005 source-priority guard disposition

Baseline fixed source: `684824ac7bb59ac903054b26b3435441b8a2f152`. The old source was obtained and executed from `git show` into an isolated evidence file; no production checkout was replaced. The current repair is bound to the working source hash below.

## B07A-004 output authority

The repaired `tools/source_priority_guard.py` accepts output only below the physical project `outputs` directory. It rejects path components that are symlinks or Windows reparse points, refuses an existing file with different bytes, and returns `reused` for an identical existing file. Creation uses exclusive `xb`, flush/fsync, close, and exact readback; a create/write/readback error leaves the path untouched by cleanup and fails closed. This keeps report output from becoming a second authority or overwriting human data.

The old fixed-684 `main()` was executed against a temporary empty catalog and temporary output. It accepted two different primary payloads at the same output path and changed the output SHA (`7ce96ed799a6f03dd42a9b3dac54c71cd4e333c4841792e3c9a55ba7f5b5421f` to `4f6acf9f9e44b488f3eb59c17203e480211ffe74e3ae8a0fe01a6d1dad60ec0b`). That is the retained **OLD_FAIL_CONFIRMED** evidence.

The repaired current CLI was then run with an output outside `outputs`, an owned new output, an identical repeat, and a different payload at the same owned path. Results were respectively reject, create, reuse, and reject. Raw stdout/stderr and runner files are under `outputs/wake_drop_v108_review_followup_20261009/b07a_guard_output_catalog/`.

## B07A-005 catalog loading

`main()` now identifies the requested eligible source before loading the catalog. For a `catalogRequired=false` primary source it passes an empty catalog to `authorize`; all primary contract, identity, scope, policy, and fallback checks remain in `authorize`. For catalog-required sources it still loads the catalog first and therefore preserves an explicit failure when the catalog is absent.

The fixed-684 old `main()` was executed with the real policy and a missing catalog: the `hardcore.identity.categories` primary returned exit 2 because the old code unconditionally loaded the catalog. The repaired current CLI returned exit 0 for that same catalog-free primary. The current test also covers an auxiliary catalog-required candidate, unknown candidate, and ineligible candidate; those reject explicitly. The closeout run passed 9 tests, including preexisting-different preservation and a real symlink boundary on this host. A separate three-test I/O sink fault-injection run then passed: an actual `xb` race with a different writer, injected fsync failure, and injected readback failure. The historical 9-test stdout and hash remain separate from this three-test receipt.

## Evidence and validation

- Old-blob runner: `run_old_blob.py`, exit 0; old primary-without-catalog exit 2; old output overwrite demonstrated.
- Current-case runner: `run_current_cases.py`, exit 0; outside output rejected, same owned output reused, different owned output rejected, catalog-free primary exit 0.
- Current focused test: `python -m py_compile tools/source_priority_guard.py tests/source_priority_guard_authority_test.py; python -m unittest -v tests/source_priority_guard_authority_test.py`, 7 tests, exit 0.
- Old blob SHA: `3445c735ac0fb470440de50fd228cd000a2364c6bccc72be2a15e37ea235025b`.
- Current source SHA: `d517894e85e31cd09075c730c87e52098681793f37135edfe503550ae5fa04a2`.

Scope limits: no authoring or generated data changed; no build-equipment file or unrelated test changed; no Godot, Android, or native run. The old/current raw evidence and per-file hashes are enumerated in `B07A_GUARD_OUTPUT_CATALOG_DISPOSITION.json`.
