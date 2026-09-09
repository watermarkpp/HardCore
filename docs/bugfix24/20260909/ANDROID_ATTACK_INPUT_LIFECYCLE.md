# Android attack input lifecycle guard

`input.attack.fresh_down.v1` requires a neutral state followed by a new `attack`
DOWN inside the current GameRoot lifecycle before the polled action may repeat.
Entry, Loading, pause, and focus-loss boundaries revoke that ownership. Touch
buttons retain their existing per-touch tokens, so one unrelated finger release
does not cancel another held attack.

The confirmed software defect was the direct per-frame
`Input.is_action_pressed("attack")` fallback, which accepted an action already
pressed before entry or resume without a new DOWN. The bounded in-memory
`attack_action_lifecycle_snapshot()` records at most 16 state transitions for APK
diagnosis. It does not write per-frame logs.

This is a lifecycle defense for the reproducible stale-action path. Whether it
is the sole cause on every affected phone remains pending device reproduction.
