# DPV2 V5.0.5 Review Candidate

This is a review candidate, not an integration merge certificate.

- MIGRATION_BASE_SHA: 342891ab884150c0e81084c932df8205484e6388
- ORIGINAL_GAMEPLAY_BASE_SHA: fcdc76b360d5976eef2ce17a45664ddaf550590
- CODE_SHA: $codeSha
- REVIEW_BRANCH: $branch

## Source migration
- source status: $sourceJson
- compiled slots: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.compiled_slots)
- UID reused: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.migration_reused_uids)
- added slots: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.migration_added_slots)
- removed legacy-only slots: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.migration_removed_slots)

## Balance
- verified book monsters: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.verified_book_monsters)
- book rules: $bookJson
- Boss K status: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.boss_k_status)
- Boss K: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.boss_k)
- Woma final no-equipment: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.woma_no_equipment_after)
- four-boss no-equipment before/after: $bossJson
- armor 1/60 proofs: $(@{schema=hardcore.dpv2.v505.acceptance.v1; pass=True; errors=System.Object[]; compiled_slots=7611; source_status_counts=; migration_added_slots=1463; migration_removed_slots=661; migration_reused_uids=5889; verified_book_monsters=42; book_rule_counts=; boss_k_status=NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET; boss_k=1; woma_no_equipment_after=2.13638839330004E-07; boss_no_equipment=; armor_1_over_60_proofs=6; gd_uid_worktree_paths=System.Object[]}.armor_1_over_60_proofs)

## SHA semantics
A Git commit cannot contain its own final SHA without changing that SHA. The
actual FINAL_SHA and independently verified REMOTE_HEAD_SHA are therefore
recorded in the post-push receipt outside the repository. They must be equal.
