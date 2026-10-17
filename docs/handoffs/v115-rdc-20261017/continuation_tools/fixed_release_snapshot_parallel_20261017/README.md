# Fixed release source objects — frozen component delivery

Implemented tools are in this directory only. Production R, engine E, original
userdata, real Git index/refs/HEAD/commonobjects were not modified. The actual
private-Git test finished with **41 checks / 0 failed / 0 NOT_RUN, exit 0**.
`COMPONENT_RESULT.json` is explicitly scoped to private Git objects and archive;
it is not World, build, APK, SourceSave or device evidence.

Files:

- `isolated_git.py`: byte-identical copy of the reviewed chunk11 helper. Every
  Git subprocess has explicit GIT_DIR/WORK_TREE/INDEX/CEILING, cleared ambient
  Git redirections, complete local config/refs/HEAD and resolved-path verification.
- `fixed_release_objects.py`: component API for raw object construction,
  actual Git archive verification and additive loose-object publication.
- `fixed_release_snapshot.py`: formal CLI with mandatory real World three-file
  gate, exact protected root/HEAD/index, current58a Native169/five seals and
  actual Windows pair gates. There is no force/mock/component gate override.
- `test_fixed_release_objects.py`: actual private Git positive/negative tests.

The original design considered one `hash-object --stdin` process per blob.
The implementation instead encodes the standard raw Git object header, SHA1
and zlib loose object directly in the validated private DB, then proves actual
Git interpretation via `cat-file` and streaming `git archive`. This avoids
thousands of Git subprocesses for assets. No clean filter, autocrlf conversion,
index update, git commit command or ref move occurs during construction.
All actual Git calls retain the four explicit isolation bindings.

The source selection includes scripts, scenes, all permitted asset files,
Native source, tools, tests, addons and required root project/export/attribute
configuration. It scans raw current filesystem contents, so dirty and untracked
sources are included and tracked deletions remain absent. Baseline executable
modes are preserved; symlink/submodule modes are rejected. Symlinks/reparse
entries under selected roots are rejected. Local engines/downloads, caches,
outputs, known credentials, archives and compiled binaries are excluded.
The formal gate additionally refuses any measured World source/scene/asset/tool/
test file absent from the selected tree. It cannot silently omit a measured
binary/archive. Any such policy conflict is BLOCKED for review, with no force.

Original file bytes and the full selected roster are rechecked after object
construction and again before formal publication. Actual Git archive is streamed
and every member/byte count/SHA256 compared to the captured inventory. Thus any
`.gitattributes` export-ignore/export-subst alteration also fails. Archive does
not extract to a worktree and does not apply checkout newline filters.

Additive publication validates each source object's encoded type/size/SHA1 and
uses a temporary file plus atomic no-overwrite hardlink. Existing loose objects
must decode identically; a corrupt existing object is rejected, never replaced.
No destination ref, HEAD, config or index is written. Objects present only in a
pack may acquire a same-content loose duplicate; this is additive, not replacement.

## Actual verification

Executed once:

```powershell
python C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/fixed_release_snapshot_parallel_20261017/test_fixed_release_objects.py
```

It created complete private source/destination Git repositories under
`component_run/`, preserved an actual private baseline parent, modified raw LF/
CRLF/project/scene/PNG inputs, deleted a tracked file, added untracked sources,
constructed a real immutable commit, and verified actual Git blobs/archive.
It then published into the second private object DB and archived that commit
without using source alternates. Repeat publication added no objects.
Actual drift, path escape, wrong marker/root, symlink, credentials, changed refs/
index and corrupt-existing-object negatives were exercised. Ambient Git
redirection was explicitly cleared. Test data labeled component-secret is a
synthetic negative fixture, not a real signing credential.

The actual R index was only read by its absolute path and remained
`3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22`.
No real R Git command was executed. Per-subprocess raw Git logs were not retained;
the complete executable test, exact command, actual resulting Git DBs/objects,
archive checks, custody facts and 41-case receipt are retained.

## Formal production use: NOT_RUN

Actual World/normal-exit still has known failures. No production snapshot or
commit object was created or published, no real index/ref moved, and no push,
build/export/install/device run was performed by this block. Formal CLI runtime
and its complete production selection have not been exercised. The component
positive does not certify those gates. The five sealed GDS and Native are unchanged.

After a true World normal-exit PASS, prepare a JSON gate with these three pinned
facts (each `{ "path": "absolute-path", "sha256": "actual64hex" }`):
`runner_result`, `protection`, `source_manifest`. No example PASS receipt is
generated. Then the parent may run:

```powershell
python C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/fixed_release_snapshot_parallel_20261017/fixed_release_snapshot.py --world-gate <real-pinned-gate.json> --output C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/fixed_release_snapshot_parallel_20261017/production_review_01
```

That writes private objects only. For explicitly authorized actual additive
publication, use a new output name and add `--publish-common-objects`. The CLI
rechecks World, source, Native and real custody before publication. Its receipt
supplies the immutable commit for the existing `build_android_isolated.ps1
-Commit <actual-object-id>`; package/signing/content/device gates remain separate.
Do not change the fixed58a/manifest/PE constants without a separately reviewed
identity update if future Native or actual World binaries change.

## Explicit handoff-only reuse

Parent has separately authorized a remote handoff branch, which is not a
release and need not pretend World PASS. Keep the formal CLI gate unchanged.
The low-level component API can construct that explicitly labeled source object:

```python
from isolated_git import GitSandbox
from fixed_release_objects import inventory, build_from_rows, verify_archive, publish_additive
box = GitSandbox(new_private_child, authorized_output)
box.initialize("45170d0eaf4d2c642d4a03de392f64fa2b1e25bf", exact_common / "objects")
rows = inventory(R)
built = build_from_rows(box, R, rows, "45170d0eaf4d2c642d4a03de392f64fa2b1e25bf",
                        message="HardCore v115 handoff snapshot; World FAIL; not release")
verify_archive(box, built["commit"], rows)
# Parent approval and its real custody protection precede this actual write:
publish_additive(box, exact_common / "objects", exact_common / "objects")
```

This selector excludes docs/outputs. Any remote handoff document or evidence
must be explicitly reviewed and added by the parent's separate handoff tree
policy (raw `object_write` is available); do not claim they were included here.
Parent alone handles the authorized handoff ref and push. This worker did neither.

Read-only finding for parent's delivery helper: its
`delivery_current_source_binding_20261017.py` expected archive subset currently
uses `assets/data/`. It should verify **all tested `assets/`**, plus scripts,
scenes and project. This block did not edit that parent-owned helper.

The requested viewport map-arrival identity block was **not started**, per the
user's stop-and-handoff instruction. SourceSave six stages remain **NOT_RUN**.
