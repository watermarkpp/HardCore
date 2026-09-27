# Final inspection candidate: incomplete admission identity

Source head: f88825cc74ba624bffc6600710b7d27b72a9a52a. Read-only static observation; behavioral status NOT_RUN.

The verifier builds a parent with -1 defaults for missing source_life/parent_action_id/map_id/generation. Its admission guard only checks release string and source instance. A coherently incomplete admission, delivery and mutation can therefore match sentinel defaults instead of proving a complete parent identity. Existing mismatch tests alter only one side; they do not test omission on both admission and derived child.

After the active full run ends: add a narrow intact-positive/incomplete-negative test to observer_integrity, run RED using the existing verifier, then require explicit typed admission and child identity fields while preserving intentionally declared standalone target_generation=-1. Do not write HP, add production context or modify runtime clocks. This is a verifier acceptance gap within original R4, not a new gameplay refactor. No source or test edited during full run.
