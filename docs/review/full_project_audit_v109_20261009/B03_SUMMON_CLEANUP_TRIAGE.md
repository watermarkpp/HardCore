# B03 summon landing cleanup triage

Date: 2026-10-10

## Evidence

Direct31 retained native evidence is under
`outputs/test_logs/v109_direct31_summon_landing/` with framework run
`4c81bd9b-f742-4a37-949a-145d70aad48d`. The runner receipt reports 26/26
checks, native exit 0, no engine-log errors, and wrapper PASS. The only
cleanup diagnostic is in
`logs/summon_follow_landing_contract_20261010_test.stdout.log:2820` onward:

```
Leaked instance: RefCounted:9223372921500613885 - Reference count: 0
WARNING: 1 ObjectDB instance was leaked at exit
```

The stderr log contains the same one cleanup warning and no resource-in-use
or functional error. This is a test cleanup FAIL classification attached to a
functional PASS, not evidence of a production summon or claim leak.

## Ownership trace

The fixture owns `_proof: Proof`, where `Proof` is a `RefCounted` helper, plus
the `_game`, `_summon`, ignored summons, and temporary occupying summons. The
main async path calls `_cleanup_and_finish()` with `await`; that method queues
the temporary nodes and GameRoot, awaits one `process_frame`, writes the
receipt, prints the PASS marker, and calls `get_tree().quit()` from inside the
continuation. Early failure paths use the same awaited cleanup function.

The warning is therefore consistent with a RefCounted object held by the
still-live GDScript continuation or a bound callback at process shutdown,
with `_proof` the directly identifiable test-owned RefCounted candidate. The
numeric ObjectDB ID cannot prove that identity, and the retained log does not
include a type backtrace. The production `ContentLayers`/retired-claim
service is not implicated by this single generic `RefCounted` line; there are
no resource-in-use messages and the functional receipt is complete.

No arbitrary global cache flush or manual free of an unknown RefCounted is
justified. The existing node teardown is already explicit for the temporary
summon and GameRoot nodes.

## Bounded disposition

Status: `FAIL` for fixture teardown hygiene; `PASS` for the 26 summon landing
contract checks; production leak: `NOT_PROVEN`.

The minimal follow-up should move final receipt/quit scheduling out of the
active `_cleanup_and_finish()` await continuation: complete node retirement,
then use one finite deferred finish boundary so the coroutine can unwind
before process exit. The change must preserve all 26 checks and receipt data.
If a repeat still reports the same RefCounted ID, the next diagnostic should
be a verbose ObjectDB attribution for this fixture only. Do not broaden the
scope to global cache clearing, claim-service reset, or production ownership
changes.

## Direct32 follow-up (2026-10-10)

Direct32 is retained at
`outputs/test_logs/v109_direct32_summon_landing_cleanup/`, framework run
`d80027a6-7146-4ea3-8d69-8feb23ddb013`, with runner receipt
`logs/runner_results_adhoc_20261010_010416_557_11896.json`. The receipt reports
native exit 0, no engine-log errors, no timeout, wrapper PASS, and the test
receipt reports 26/26 checks. The functional result therefore remains PASS.
The exit log still contains one ObjectDB warning:

```
Leaked instance: RefCounted:9223372921735494909 - Reference count: 0
```

The deferred-finish change did not remove the warning. Its numeric ID differs
from Direct31's `9223372921500613885`; that difference means the warning cannot
be attributed to `_proof` by ID, and does not establish a production owner.
Direct31 and Direct32 consequently remain cleanup FAIL / production
NOT_PROVEN rather than a confirmed summon or retired-claim leak.

## Static ownership boundary

The known fixture-owned RefCounted candidate is still `_proof: Proof` in
`tests/framework/summon_follow_landing_contract_20261010_test.gd:12`.
`_cleanup_and_finish()` at `:244` awaits node retirement, writes the receipt,
and quits from the asynchronous continuation. That makes the continuation
and any bound callback plausible holders, but the retained warning has no
type backtrace. A changing numeric ID across runs is evidence against naming
one candidate as the owner.

The production static scan found other legitimate RefCounted-bearing paths,
without an ID mapping: `SummonActor` creates its RNG at
`scripts/summon_actor.gd:185`, keeps the static audio service at `:220`, and
advances one ready ResourceLoader result during teardown at `:663`; its
threaded path starts near `:1884`. `GameRoot` owns feature/runtime services
and retires or pumps pending warm textures at
`scripts/game_root.gd:2126-2189`. `ContentLayerRegistry` also has explicit
threaded claim and lease parameters, for example
`scripts/layers/runtime/content_layer_registry.gd:147` and `:162`, but this
generic warning has no resource-in-use message or claim receipt linking it to
that service. These are candidate ownership surfaces, not findings.

The only bounded attribution worth adding in a future authorized fixture
diagnostic is to record `get_instance_id()` for each known fixture-owned
RefCounted at creation and retirement, then compare those exact IDs with the
exit warning while the owner reference is still safely available. A
`RefCounted` cannot be identified by type alone, and global ObjectDB
enumeration or freeing an unknown ID would change the cleanup being measured.
If an exact owner mapping cannot be captured, the correct result remains
cleanup identity BLOCKED; do not convert it into a production leak claim or
add a cache flush.

### Disposition after Direct32

| Scope | Status | Evidence |
| --- | --- | --- |
| Summon landing functional contract | `PASS` | Direct32 receipt, 26/26, native exit 0 |
| Fixture teardown hygiene | `FAIL` | One `RefCounted` warning at exit |
| RefCounted owner identity | `BLOCKED` | No backtrace; Direct31/32 IDs differ |
| Production summon/claim leak | `NOT_PROVEN` | No ownership mapping or resource-in-use evidence |
