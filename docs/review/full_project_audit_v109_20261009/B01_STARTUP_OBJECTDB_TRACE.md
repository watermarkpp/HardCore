# B01 startup ObjectDB shutdown trace

## Evidence binding

This is a read-only trace of the cited `startup_loading_terminal_get_contract`
case on Godot `4.7.stable.official.5b4e0cb0f`. No additional test was run.

- Direct13 receipt: `outputs/wake_drop_v108_review_followup_20261009/direct13_resource_owners_fix/logs/runner_results_adhoc_20261009_224951_367_13948.json`
- Direct13 stdout: `.../startup_loading_terminal_get_contract_test.stdout.log`
- Direct13 stderr: `.../startup_loading_terminal_get_contract_test.stderr.log`
- Related14 receipt: `outputs/wake_drop_v108_review_followup_20261009/related14_resource_lifecycle/logs/runner_results_adhoc_20261009_225354_473_6892.json`
- Related14 verbose stdout: `.../startup_loading_terminal_get_contract_test.stdout.log`
- Related14 engine log: `.../startup_loading_terminal_get_contract_test.godot.log`

Both receipts report native exit `0`, pass marker, zero engine-log errors, and
the expected `STARTUP_LOADING_TERMINAL_GET_CONTRACT_PASS` marker. Direct13
stderr reports `118 ObjectDB instances were leaked at exit`; related14 reports
`94 ObjectDB instances were leaked at exit`. Related14 was run with verbose
ObjectDB output: its stdout contains 94 lines of `Leaked instance:
RefCounted:<id> - Reference count: 0`, followed by the engine hint about
removed scene nodes that were not freed. The IDs are concrete, but the engine
reports only generic `RefCounted` and reference count zero, with no script,
owner path, or resource type. Direct13 retained output exposes only the
aggregate count, not individual IDs.

## Owner path checked

`tests/framework/startup_loading_terminal_get_contract_test.gd:20-49` creates a
real `StartupLoading` owner, starts the target scene request, records whether
the request was accepted or cached, calls the owner’s public retirement seam,
waits for the ContentLayers diagnostics to close an accepted claim, checks
idempotence, and then calls `owner.free()`.

The production owner path is:

- `scripts/startup_loading.gd:448-458`: request and explicit OK ownership;
- `scripts/startup_loading.gd:477-529`: terminal polling/get behavior;
- `scripts/startup_loading.gd:862-899`: shutdown retirement for target and
  main-scene prefetch claims;
- `scripts/startup_loading.gd:814-821`: `_exit_tree()` calls the same retirement
  seam before releasing code retention.

The test does not instantiate `character_select.tscn`; it only requests the
PackedScene path. The related14 verbose stdout confirms the scene and its
script resource were loaded before the 94 generic RefCounted leak lines. It
contains no `resource in use` warning. This rules out a demonstrated
unconsumed ResourceLoader claim, but the generic RefCounted IDs cannot be
matched to the startup owner or a particular resource from the retained
source/log evidence.

## Disposition

`BLOCKED`: the available logs prove 94 concrete leaked IDs in related14, all
reported only as `RefCounted` with reference count zero, plus an aggregate 118
count in direct13. The IDs cannot be mapped to a source owner or resource type
from the retained evidence. The direct13/related14 count difference is not
sufficient to infer ownership, especially because the suites and runtime
profiles differ. Do not classify it as a startup claim leak or clear caches
based on this evidence.

The next useful evidence is a source-bound comparison control of the same scene
without the owner handoff, retaining the already-enabled verbose enumeration.
A normal integration startup READY pass does not identify shutdown ownership.
No production cache cleanup or ownership change is justified by the current
receipts.
