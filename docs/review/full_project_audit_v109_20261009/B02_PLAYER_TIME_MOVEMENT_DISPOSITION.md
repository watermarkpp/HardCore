# B02 Player time and movement disposition

审查范围固定为 B02 Player 专项，不能外推为全项目或设备验收。生产 `scripts/player.gd` 的冻结源哈希为 `40CE84D019E1B5770A5749A5384C49572F7F7666A5FF581D3DB9B9BD05E718D3`。direct16 使用的冻结记录为 `B02_PLAYER_FREEZE_16.json`（candidate tree `a0996b7921222fcf89ef70ed63f0aa1982aa368b`）；direct17 使用 `B02_PLAYER_FREEZE_17.json`（candidate tree `e999954641acc49b45c1798bb179578e177fb522`）。两份冻结记录都指向同一 Player SHA 与 Godot 4.7 engine SHA `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。

## B02-001：暂停中的 accepted attack/skill windup

入口仍是 `scripts/player.gd` 的 `_emit_attack_after_windup` 与 `_emit_skill_after_windup`，菜单暂停由 `GameRoot._show_system_menu` / `_hide_system_menu` 正式拥有。Player framework direct16 的真实 receipt 14/14 checks PASS（run_id `598af74c-dde7-4c03-9255-9efe581ec7fa`）。其中包括：accepted attack 在暂停期间不释放、恢复后只释放一次；真实 `hc.skill.wizard.ice_storm` 合法技能在暂停期间保持 windup，目标 HP 不变且没有 release，恢复后只释放一次并产生真实 HP 下降。该 receipt 位于 `evidence/B02_player/direct16_player_pause_stealth/framework_receipt_player_pause_movement_contract_20261009_test.result.json`，原始 stdout/stderr 与 runner JSON 同目录保留。

该结果支持本轮已接受的 pause contract：windup 使用暂停感知的 gameplay timer；已提交动作、生命周期取消和实际技能伤害边界仍由原有 Player/GameRoot 链维护。它不证明所有技能、所有玩家输入和所有设备平台。

## B02-003：collision recovery movement publication

同一 direct16 receipt 的 checks 11-14 PASS：零输入真实碰撞 recovery 产生位移；该位移进入 `actual_ground_motion`；最终发布位置等于本物理步最终位置；同一物理步只发布一个 movement event。相关生产边界在 `scripts/player.gd` 的 `_physics_process` recovery、directional sweep 与最终 movement publication，GameRoot 被动唤醒仍只消费最终移动事件。此验证把 recovery displacement 计入实际 locomotion publication；它不把 recovery 位移重新算作额外输入，也不证明每种碰撞形状的完整矩阵。

## B02-004：装备隐身 re-arm

direct16 的 equipment case 在脚本解析阶段失败，失败证据保留：`equipment_stealth_rearm_contract_20261009_test.gd:25` 的 Variant 类型推导错误，runner 以 `FAIL`、early script error、missing pass marker 退出；这不是有效的功能结论。direct17 对同一正式 fixture 重跑后 10/10 checks PASS（run_id `0d1ffaee-b0de-450a-940f-9dc3dda26f0a`）。检查覆盖正式装备存在、装备/卸下、和平状态隐身、accepted combat submission 破隐、战斗中换装不重新武装隐身，以及目标离开后由 GameRoot 正式 combat-exit recovery 恢复隐身。该结果支持 `_apply_profile_stats` 不再清除 active break flag，并保留 GameRoot recovery 作为唯一 re-arm owner；不等于所有装备属性或存档重载通过。

## Related18 边界回归

`related18_player_boundaries` 共 5 个真实场景，runner failed=0、engine_log_errors=0：

- `player_combat_release_lifecycle_test`：PASS
- `player_struck_release_order_test`：PASS
- `player_walk_run_locomotion_test`：PASS
- `special_equipment_actor_policy_test`：PASS
- `hc_monster_combat_r2/body_pair_eight_direction_test`：PASS

它们分别保留 combat release/lifecycle、受击释放顺序、walk/run locomotion、特殊装备 actor policy 与 body-pair 八方向边界；证据按场景 UUID 分目录保存。

## 证据界限

当前 native 专项证据为 direct16 Player PASS、direct16 equipment parse FAIL（保留原失败）、direct17 equipment PASS、related18 五项 PASS。direct16/direct17/related18 runner JSON 的 `git_head` 为主树 `215f0b2f651a51e6855ee813ddd99221690311a1`，而冻结记录使用 candidate tree `a099...` / `e999...`；runner receipt 的 `source_content_sha256` 为空。因此 `B02_PLAYER_NATIVE_LEDGER.md` 将两者分开记录，不能把 runner 自身误写成完整 source binding。设备验收、全项目验收和 APK 验收均未在本专项完成：`DEVICE TEST: NOT_RUN`。
