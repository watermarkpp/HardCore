# Cold report targeted proof and retained native renderer warnings

Source6407fddaaa9ac3e1e388ff866758d91610ea26fd, independent clean checkout. Official runner-created project report dir BEFORE=false AFTER=true. Actual cancelled_release_observation and mp_payment_observation tests 2/2 PASS, normalexit0, no timeout, all actual HP/MP/terminal assertions retained. Raw structured reports written by native tests; no mocked/export-filtered records.

Cancelled release raw log retains `ERROR: Parameter "t" is null` from RendererDummy texture_2d_initialize and one DummyTexture RID leak at engine exit. These exact native headless warnings have existing scoped patterns in runner lines849/853; no classification rules changed by this task (runner diff adds only4 directory-setup lines). PlayerVisual source is identical between fixed BASE1381 and6407, and native actual ledger/cancellation assertions pass; this is a nonblocking headless texture-rendering environment warning for these computational tests, not claimed fixed or silently deleted. Formal reported engine_log_errors counts unallowlisted failures, not all raw ERROR-prefixed lines. No GPU/device/render equivalence claimed.

Full clean103 and valid72 workload matrix remain NOT_RUN until actual completion. Source/codeHEAD fixed6407 while running. No forge merge or package yet.
