# B06 repair and validation boundary

External reports are preserved at `external/B06/`, received from report commit
`d309409df1f1f5f0b57e9b66b0afe9096fb65b60`, audited source
`d145826b7305ad918893ba0098db2595ae01f53a`. Current review branch includes B05
repairs at `96d593370eb8a962f932cdc1d5e99ea64b054519`. These are distinct source
stages. Original integration HEAD and index are preserved.

## Authorized repairs

- B06-001: GroundService remains the sole ground JSON authority. A verified
  exact-target write set binds chunks, manifest and state before any promotion.
  Recovery admits only proven base/new bytes and scoped paths. A third manual
  version, corrupt identity or ambiguous backup fails closed without overwriting
  the user's later work. Bake images remain with their existing owner.
- B06-002: BuildRuntimeService binds formal runtime and release registry to one
  durable exact-map publish intent. Runtime/registry readiness and approved hashes
  remain mandatory. Recovery must not report another map's publication as success
  for the current request, and must preserve unrelated registry bytes.
- B06-003: App build/publish requires a durable document proof matching all current
  document content and ground inputs. Save stages revision changes, verifies the
  persisted document and commits into the existing document owner only on success.
  Polygon undo/redo captures that owner; replacing it would detach those commands.
- B06-004: RuntimeBridge validates raw numeric source identity before injecting the
  requested runtime ID. Invalid types, nonintegral values and mismatches fail closed.

## Boundaries retained

- B06-005: abnormal termination before loot generation/pickup has no durable loot
  plan contract. No probability change or second reward journal is introduced.
- B06-006: metadata source-hash differences do not prove stale art when current
  formal PNG bytes match. No bulk regeneration or authoring replacement.
- B06-007: validate all 132 current portal endpoint footprints through the existing
  formal geometry query. Do not relocate approved endpoints without a proven defect.
- B04 summoned bat ID127 drop policy remains pending the user's choice.
- B07A/B07B/B08 external dispatch remains pending a continuation conversation after
  the original GPT thread reached its platform length limit. Whole semantic audit
  closure remains MISSING. Android109 export and DEVICE TEST remain NOT_RUN.

## Necessary verification, not repeated acceptance

Freeze exact raw source/input hashes and a private Git index before native tests.
Run four direct production-path contracts, then changed-dependency regressions for
save isolation, candidate binding, publish rollback/restart, sibling invariance and
portal footprints. Every failed attempt, source stage and native exit remains in
the verification ledger. Existing B01-B05 evidence is reused for unchanged scopes;
none is relabeled as Android or whole-project acceptance. Simulated interruption
boundaries do not prove actual process kill or power-loss durability.

Status at plan creation: implementations under review; native validation NOT_RUN.
