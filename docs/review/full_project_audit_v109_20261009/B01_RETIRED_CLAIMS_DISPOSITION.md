# B01 retired threaded claims disposition

## Scope

This change covers the owner handoff boundary for an already accepted
`ResourceLoader.load_threaded_request` claim. The production owner remains the
existing `FeatureResourcePreparation` service and its existing three-class
frame-budget scheduler. No second loader, request path, cache, or autoload was
introduced.

`ContentLayers.retire_threaded_resource_claims(path, claim_count)` accepts only
a nonempty path and positive claim count. It records the claims in the service
retirement FIFO without calling `load_threaded_request` again. Each service
quantum polls one queued claim entry. `IN_PROGRESS` is rotated behind other
retirements; `LOADED` and `FAILED` each consume at most one claim with one
`load_threaded_get`; `INVALID` records the remaining claims as missing and
never calls `get`. The diagnostics expose `accepted`, `transferred`, `get`,
`missing`, and live `pending` claim counts.

Normal scene cancellation does not join an in-progress claim. The existing
service exit path remains the only global shutdown path allowed to join its own
claims, as required by the engine contract recorded in
`B01_RESOURCELOADER_ENGINE_CONTRACT.md`.

## Behavior fixture

`tests/retired_threaded_resource_claims_20261009.tscn` exercises two accepted
claims for one path, transfers one claim while retaining the other owner’s
claim, then transfers a separate two-claim pair and observes one-get-per-
quantum consumption until both claims are joined. It also verifies an invalid
path is recorded without a `get`. It is a behavior test: it uses the actual
`ResourceLoader` and `ContentLayers` APIs and does not inspect source text.

The fixture separately attempts a missing path and records synchronous engine
rejection. That is explicitly not counted as an accepted `FAILED` claim: a
terminal failed-claim case requires an engine-accepted request that later
reports `THREAD_LOAD_FAILED`, and this fixture does not claim to create one
from a path the engine rejects synchronously.

## Validation status

The frozen candidate was exercised in the retained B01 runs. The direct12
receipt recorded three PASS and two FAIL results. The two failures were the
old visual-coordinator disposal path (null-instance notification, with its
PASS marker already printed) and the startup handoff probe (the two expected
contract checks failed and the process exited 1). This is retained as a
historical negative receipt; it is not reclassified as a successful run.

Direct13 reran the two changed functional probes and both passed with native
exit 0, pass markers, and zero engine-log failures. Related14 passed all six
resource/lifecycle probes, including the actual two-claim/foreign-owner and
INVALID paths, with native exit 0 and zero engine-log failures. Integration15
passed the real initial-world bootstrap with native exit 0 and no ObjectDB
leak warning. Exact receipt and log bindings are in
`B01_NATIVE_VERIFICATION_LEDGER.md`.

The direct13 startup process still emitted an aggregate `118 ObjectDB`
shutdown warning. Related14 emitted `94` `RefCounted` leak lines, each with
reference count 0. These are cleanup observations, not functional claim
handoff failures, and remain explicitly visible in the ledger. The startup
loading probe's two `push_error` lines in direct12 are likewise retained with
their failed receipt.

An engine-accepted request that later reaches `THREAD_LOAD_FAILED` was not
demonstrated: the fixture's missing path is synchronously rejected and is
recorded as INVALID without calling `get`. The separate 60-second
asynchronous timeout/race scenario is also `NOT_RUN`. Neither is upgraded by
the positive lifecycle receipts.
