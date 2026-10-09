# Contact diagnostic patch change list

Preimage captured before implementation in the isolated ATTACK_START_FRAME_AB workspace.

- `scripts/enemy.gd`: copied byte for byte to `preimage/enemy.gd`.
- `tests/crowd_attack_start_frame_ab_20261009.gd`: existing AB fixture recorded in `manifest.json`; it will not be edited.
- `tests/crowd_attack_start_frame_ab_20261009.tscn`: existing AB scene recorded in `manifest.json`; it will not be edited.
- New diagnostic files will be limited to `scripts/enemy.gd`, `tests/crowd_attack_contact_diagnostic_20261009.gd`, and `tests/crowd_attack_contact_diagnostic_20261009.tscn` in the isolated workspace.

The diagnostic is default disabled and measures wrapper calls/timing only. It does not alter return values, arguments, gameplay state, admission, movement, clocks, animation, or AB mode.
