# B06 native verification ledger

This is the readable index for the exact JSON ledger and retained raw bundle. Each run uses the official isolated console/headless runner and a 30-second per-scene deadline. Freeze records bind the actual source tree, inputs and engine binary; raw receipts bind invocation, scene, run and native producer. Private indexes, engine binaries, browser screenshots and player saves are excluded from the published bundle.

| Stage | Native result | Why another stage was necessary |
|---|---|---|
| direct42 | 2 PASS / 2 FAIL | Ground and numeric identity passed. Release had an actual empty-hash update engine error; App fixture had a type-inference parse error. |
| direct43 | 1 PASS / 1 FAIL | Release fixed and passed. App adoption revealed missing map-type fixture precondition. |
| direct44 | 1 FAIL | Correct fixture reached real official save/load normalization and exposed durable binding mismatch. |
| direct45 | 1 PASS | App canonical save and original root owner preserved; all 18 formal checks passed. |
| related46 | 8 PASS / 1 FAIL | Related publish/save/consumer/portal checks passed. Old restart recovery exposed over-strict legacy runtime backup handling. |
| direct47 | 3 PASS / 1 FAIL | New runtime backup recovery, rollback and App boundary passed. Old restart progressed and exposed selected registry backup left after successful restoration. |
| direct48 | 5 PASS / 1 FAIL | Release 60 checks, old restart, source preservation, fail-closed and approval counterexamples passed. Identical dual backup restoration still blocked a subsequent publish. |
| direct49 | 1 PASS | Only the failed 19-check real registry restoration scene rerun after exact duplicate cleanup; both backup protocols and conflicts passed. |

Unchanged Ground/Bridge evidence is reused from direct42. App evidence is reused from direct45/direct47. Source49 changes only byte-identical dual backup cleanup; direct48 positive branches and related46 unchanged positive branches retain their original source bindings. They are not presented as source49 reruns. No original failure evidence or assertions were removed.

The passing authoring footprint artifact checks 132 endpoints in 67 maps and is retained byte-for-byte. This is not a device traversal or complete portal runtime admission proof.

The JSON ledger explicitly retains source-stage differences, framework receipt presence or absence, native exit state, error counts and cleanup classification. Forced terminations leave cleanup `NOT_RUN`. See `B06_FINAL_DISPOSITION.md` for final file hashes and outstanding boundaries. Whole-project audit `MISSING`; formal109 build `NOT_RUN`; DEVICE TEST `NOT_RUN`.
