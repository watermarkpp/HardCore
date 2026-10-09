# Contact diagnostic patch source review

Status: **PASS** for the requested source-only contract review.

Reviewed frozen worker source:

- `scripts/enemy.gd` SHA256 `5B96AC26F42D189700DEAE7C75344FC405C6E87C6728537955B10C7B9A7D031A`
- `tests/crowd_attack_contact_diagnostic_20261009.gd` SHA256 `F5C8AFFC41896797864C55A714E4C368957AC089F07D12A350E031E26CDD543D`
- `tests/crowd_attack_contact_diagnostic_20261009.tscn` SHA256 `1C2A57F103518D0E08E7A0B68DE08C2F122339668094D6A0F3C705508A6403F4`
- preimage `scripts/enemy.gd` SHA256 `A987D8CC087DB65F40D053EA0CD19C9C0F0EB5611D9DAFAA5F672178DCA1EE93`

The Enemy delta is limited to a disabled-by-default diagnostic table, stack markers, and wrappers around the eight requested functions: `_hc_target_usable`, `_hc_access`, `_hc_frontline_at`, `_hc_try_start`, `_hc_tick_melee`, `_hc_step_can_end`, `_hc_world_between`, and `_hc_refresh_observation`. Each original body was moved intact to an `_internal` function and the public function retains the original signature, return type, callback order, state writes, early returns, and arguments. The wrappers return the internal result directly; the tick and observation wrappers preserve `void` behavior.

When disabled, `_contact_diag_enter` returns before reading the clock or touching diagnostic dictionaries, `_contact_diag_exit` is a no-op, and the access result observer is gated. The production path therefore retains its original state and return behavior. When enabled, the stack marker is checked on exit, inclusive durations are recorded per wrapper, nested parent relationships are retained, and result counts are attached without adding nested durations to a separate total. The snapshot exposes `open_contexts` and `stack_balanced` for fixture verification.

The diagnostic fixture extends the frozen A/B fixture directly. Its `_start_ab_window()` calls `super._start_ab_window()` first, then resets and enables contact diagnostics. It does not create a second boundary node, alter `process_physics_priority`, replace the inherited 300-tick loop, or change the existing sample collection. The inherited `SampleBoundary` remains the sole window arming boundary. The fixture snapshots before disabling diagnostics and records a diagnostic-only contract marker; it does not alter attack, movement, clock, budget, or acceptance state.

This is a source review only. No Godot parse, engine run, native load, or runtime test was performed here.
