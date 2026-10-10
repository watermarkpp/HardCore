# B07A source-priority and check-only disposition

Fixed reviewed baseline: `684824ac7bb59ac903054b26b3435441b8a2f152`. These are two authoring/build-tool defects, not gameplay balance changes.

The controller reproduced both defects by loading the exact old Git blobs: real `authorize()` incorrectly authorized `unusable` under a missing-only policy; the real `main()`/argument path rewrote both valid temporary authority copies despite `--female-armor-correction-only --check-only`. The original real authority inputs remained unchanged. Source blobs, commands, native exit0 and byte hashes are retained under `evidence/B07A_TOOLS`.

The original worker `pre_fix_replay.py` only calculated a literal membership and manually listed write paths. It did not run the baseline entrypoints. Its raw bytes and original disposition are preserved, but it is explicitly NOT_RUN for actual baseline behavior; the controller reproduction supersedes that claim.

The guard now validates policy controls and uses the authority `fallbackStatuses`; missing/invalid controls reject rather than widen the policy. The bounded twelve-record correction accepts `write_outputs`, and the real CLI passes the check-only flag. Audit report destinations cannot resolve to, or hardlink-alias, the master/vanilla files; validation occurs before writes in build, correction and current-master projection.

Seven retained post-fix Python tests passed with exit0, including actual CLI, check-only nonmutation and non-target record preservation. The final guard edit changes only its module docstring; the controller verified exact equality of all non-docstring AST nodes to the tested version. Builder and fixture source hashes match the seven-test stage. No unchanged gameplay regression was rerun.

Final source fingerprints:

- `tools/source_priority_guard.py`: `e89c99e8bb9b59c19ab9945c9d3419c3c7fb0c3795891514ab00f7f0d393fb54`
- `tools/build_equipment_attribute_master.py`: `522d3c16304a7734ef25d58e8a3df1995bc0da991a3c9a78e3bcff4ae5eb4ea0`
- `tests/source_priority_guard_authority_test.py`: `a6b3fdf4357f7459c491e5c15e49bf734ba8f02e0eb6a24870c115efcef99473`
- `tests/equipment_correction_check_only_test.py`: `d5e1898a4bd27b6909cce628323f82835c3001d021873b417a8764cbe5b7fc7b`

Authority input fingerprints (unchanged):

- `assets\data\source_priority_policy.json`: `58adf6e75eea5549c4a535098e568505408efa621901a1dadb868798739ac3c7`
- `assets\data\equipment_attribute_master.json`: `8d692d0f7bc1aeb4295ddd040aa760003e399c633b87876d93e3674fb8ced0b9`
- `assets\data\vanilla_176\items.json`: `236c88d075be409682ae77d5a51a775550e4fb192e3d0233edc1d3c38d0f226e`
- `assets\data\equipment_female_armor_attribute_evidence.json`: `5a36630e53fe0363994e54c6c9e97079f19da17a62b8e1ad9e4dc2168ef44667`

Limits: no generated or real authoring writes, no Godot/Android/export/device result. Whole-project audit remains MISSING until later batches and remaining responsibilities are reviewed.
