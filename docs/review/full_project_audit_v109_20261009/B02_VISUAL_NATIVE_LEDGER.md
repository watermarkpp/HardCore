# B02 visual native evidence ledger

Date: 2026-10-10

This ledger is an offline inventory of retained evidence. No engine, native
test, or wrapper was rerun while assembling it. Every file under
`docs/review/full_project_audit_v109_20261009/evidence/B02_visual/` was copied
from the retained output tree byte-for-byte; `B02_visual_manifest.json` lists
the resulting file sizes and SHA-256 values.

The runner metadata reports `git_head=215f0b2f651a51e6855ee813ddd99221690311a1`.
That is historical dirty-main runner metadata, not an exact source identity
for the frozen candidate. Current source fingerprints are bound separately in
`B02_VISUAL_FINAL_SOURCE_REVIEW.md`.

The native receipt `source_content_sha256` and framework environment labels
are also stale legacy tags. They are retained as raw evidence but must not be
used as the tested-source identity. The authoritative per-run bindings are the
copied freeze records and their candidate-tree identifiers:

| Run | Freeze | Candidate tree | Runner invocation |
|---|---|---|---|
| direct23 | `B02_COMBINED_FREEZE_23.json` | `0eac359b5aeeb12318a6de5492633e82db6c4448` | `8667d57b-a873-479e-8419-09406f8cfc00` |
| direct24 | `B02_COMBINED_FREEZE_24.json` | `dfb7d766cec37bda0d9158df2e15d19b42f2331a` | `3053ef87-333a-4da9-953e-558d0bad41aa` |
| direct25 | `B02_COMBINED_FREEZE_25.json` | `6b67e51ffe5423301697181acc9306f112f72627` | `d655cb9e-abf9-458a-a97e-26f9b57b464e` |
| related26 | `B02_COMBINED_FREEZE_26.json` | `6b67e51ffe5423301697181acc9306f112f72627` | `2bea3888-c5fb-4dab-935a-296c8f774b60` |

The freeze files contain the per-file source SHA-256 set and engine
fingerprint. `B02_visual_manifest.json` repeats these bindings under
`per_run_frozen_tree`; it also records the candidate checkout directory
separately from the per-run candidate tree.

## Retained runs

| Run | Native evidence | Wrapper status | Interpretation |
|---|---|---|---|
| direct23 | `runs/direct23_snapshot_and_visual_negative/` | FAIL | Initial visual fixture parse/lifecycle failure retained. The projectile snapshot companion in the same run is PASS. |
| direct24 | `runs/direct24_visual_negative_parse_fix/` | FAIL | Six visual fixture checks failed; two expected malformed-resource errors remain. This is not promoted. |
| direct25 | `runs/direct25_visual_typed_input/` | native exit 0; raw wrapper FAIL | 35/35 internal checks, valid framework receipt, and the two expected malformed `.res` errors. Classified separately in `NEGATIVE_CASE_CLASSIFICATION.json`. |
| related26 | `runs/related26_visual_positive/` | PASS | Three existing positive lease/cache tests, native exit 0, stderr 0, engine errors 0. |

## direct25 negative classification

`NEGATIVE_CASE_CLASSIFICATION.json` is deliberately separate from the raw
runner receipt. It records `PASS` only for the bounded negative-case scope:

- native effective exit code 0;
- pass marker present;
- framework receipt valid;
- 35 internal checks and zero internal check failures;
- no timeout;
- exactly the two retained test-owned malformed-resource errors in stderr and
  the engine log.

The raw wrapper remains `FAIL` with
`stderr_failures_2;engine_log_failures_2`. The classification does not turn
that wrapper result green and does not classify a production asset failure.

## Freeze and provenance files

The retained freeze files are copied without alteration:

- `B02_COMBINED_FREEZE_23.json`
- `B02_COMBINED_FREEZE_24.json`
- `B02_COMBINED_FREEZE_25.json`
- `B02_COMBINED_FREEZE_26.json`

Each direct/related run retains its native result, native handoff metadata,
stdout, stderr, Godot log, full framework result where produced, and raw
adhoc runner receipt. The direct23 and direct24 failures remain present for
regression history; they are not replaced by direct25.

## Scope limits

The ledger proves the terminal-resource ownership seam and the related cache
lease positives at their recorded source/run boundaries. It does not prove a
real production PNG/art corruption through a full spell submission, damage,
HP/MP, cooldown, and gameplay settlement chain. That E2E scope remains
`NOT_RUN`. It also contains no Android/device evidence.
