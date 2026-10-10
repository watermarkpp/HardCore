# B08 已核实与待验证边界

fixed_source_sha: dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5

## 检查状态
- PASS: exact fixed Git commit/tree, B01–B07原始报告读取、B07A/B07B主控台账读取、71个本轮重点固定生产/测试工具 blob 和函数目录；仅文件级静态。
- STATIC_PARTIAL: 多段主流程实际函数体已读，包括模式切换/读档、真实攻击/HP/受击/怪物唤醒、death queue/持久化/掉落、地图READY/async、构建Java consumer。目标函数超过100行只阅读所列前100行，后续函数体和调用者在 COVERAGE 保留。
- MISSING: 全项目语义覆盖、全部敌人Boss特殊法术每条负例、完整所有者多层取消、全 UI/存档消费者、装备/技能/掉落跨人工源的所有动态版本联接。此前外部B01–B07不是本dbb1全量语义PASS。
- NOT_RUN: 本轮Godot/headless、真实30怪CPU/FPS/服务时延、process kill/断电、Windows测试Assign/PID-reuse、新109 APK真实构建和Android设备升级/存档兼容。
- BLOCKED: B04 ID127召唤蝙蝠掉落概率/非掉落选择，B05同按键长按产品规则，B06 XP与随机奖励异常掉电策略。

## 必须优先验证的新负例
- Mode known valid -> merge invalid after setting expansion: GameModes.active_mode, ContentLayers enabled flags/merged DB/expansion_state_changed, PlayerState.game_mode_id, GameData is_loaded/loaded indexes and database_reloaded must all agree; no partial success.
- RuntimeServices nonlater rejected reload must report failure, later-only visibility toggles must first confirm intended authority and save/error before UI announcement. No guessed second fallback/reload.
- PlayerState.load_save with valid JSON and failed GameModes/apply fallback: last_load_result false and save-block, no early inventory/equipment/world XP publication, no automatic migration/commit_save, no CharacterSelect success; subsequent repaired catalog recovers cleanly.
- PlayerState invalid skill_progression after preflight with prior active character: old memory/live save untouched, shared warehouse owned separately, no partial save.
- GameData rejected after public maps/items/index preliminaries: all getters unavailable or atomic prior valid snapshot, PlayerVisual/FeatureResource cannot read mixed content.

## B01–B07真实剩余职责
- B01 startup FAILED/CANCELLED/ERR_BUSY and accepted claim handoff/owner retirement; old world abort and audio preload; real negative receipt NOT_RUN.
- B02 attack windup/MP/shield/struck + projectile contact and target metadata; one-shot canonical AOE no clipping; Android 60FPS not proven.
- B03 summon wall/teleport landing/stale life serial, positive external wake and optional CPU fairness/catch-up; Android absent.
- B04 XP/event durable receipt -> deferred authorized loot -> actual pickup inventory item journal -> save ABA; process kill between phases remains product BLOCKED; current slot6/9/12+RNG guard unchanged.
- B05 audio session and UI callbacks, asynchronous old generation fanout, Android startup BGM/SFX and multi-touch press policy.
- B06 map editor authoring -> build candidate -> publish registry transaction and raw numeric IDs; native headless failure only, no crash/powerkill/Android/real portal traversal.
- B07A source priority/identity/master/build I/O native final scoped only; newest consumer mode reload negative missing; retained fixed B07A 684 historical source cannot be used as dbb1 consumer evidence.
- B07B Windows job/receipt/log final scope retains old missing failure lists; old oracle tests and 75 m30/31 wall/45 UI workbench functions need purpose-based semantic mapping, not identical 3279 scene PASS; source/engine/input/scene/invocation binding per new109 still NOT_RUN.

## Source-precise per function responsibility list
See COVERAGE.json paths[].functions[].remaining_responsibility, CROSS_BATCH_CLOSURE.json rows[].remaining_concrete_duty. Counts are NOT testing outcomes.

