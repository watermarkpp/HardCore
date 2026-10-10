# B08 — Mode and expansion reload consumer trace

本次只读审查固定当前已修 GameData 源，未修改生产或测试文件。`GameData.load_database()` 当前 SHA256 为 `56F77940DC2994BCCEE1257EF3E1AFF21016D6B68BA0844755071BAE60CCDD8A`。

## 已确认的状态顺序

启动路径由 `scripts/startup_loading.gd:154-168` 串行执行 `ContentLayers.ensure_loaded()`、世界内容、展示资源，最后执行 `GameData.ensure_loaded()`，每一步都检查返回值。这是 Android/autoload 尚未就绪时的合法启动边界。

模式切换走 `scripts/layers/runtime/game_mode_service.gd:17-29`。它先让 `ContentLayers.set_expansion_enabled()` 提交扩展集合和 merged database，再写 `PlayerState.game_mode_id`，最后调用 `GameData.load_database()`，但忽略返回值并始终返回 true。扩展提交已经发出 `expansion_state_changed`，因此失败时不存在自动回滚。

运行时 facade 走 `scripts/layers/runtime/runtime_service_facade.gd:16-22`。它同样先提交 ContentLayers，再调用 `GameData.load_database()` 并忽略结果；`later_176_content` 还会进入 `PlayerState.set_later_content_enabled()`，该函数写入字段、发出 `profile_changed` 并提交存档。

GameData 当前 `scripts/game_data.gd:220-245,313-320` 已经是状态所有者：未准备好时返回 `content_layers_not_ready`，直接重载开始时清除 loaded 标志，完整索引和掉落准备成功后才设置 loaded 并发出 `database_reloaded`。因此当前缺口在消费者提交顺序和失败传播，不在 GameData 的成功信号。

读档路径 `scripts/player_state.gd:7096-7100` 先写入 `game_mode_id`，调用 `GameModes.apply_mode()`，随后再次设置 later expansion，然后继续恢复经验、背包、装备等数据。该路径没有把模式重载失败提升为读档失败，也没有在目录未就绪时阻止后续存档对象恢复。

## 风险分类

这些是源码确认的静态风险和可复现触发链，不是已经完成设备复现的运行 BUG：只要扩展已经发生改变且 GameData 随后的加载返回 false，facade 或 mode service 仍会返回成功；模式字段/ContentLayers 集合可能已经改变，GameData 则保持 unloaded。B07A 负例已经证明 GameData 的 false/load_error 和 loaded-state 清除，但没有证明这些消费者会回滚。

## 最小完整修复建议

沿现有唯一状态所有者处理，不新增第二套目录或缓存：

1. `GameModeService.apply_mode()` 暂存旧 mode，只有所有扩展变更后 `GameData.load_database()` 成功才提交 `active_mode` 和 `PlayerState.game_mode_id`；失败时通过 ContentLayers 现有 owner 恢复原扩展集合并返回 false。
2. `RuntimeServiceFacade.set_expansion_enabled()` 对非 later 扩展传播 GameData 失败；later 分支也应先确认目录重载策略，再让 `PlayerState.set_later_content_enabled()` 写存档。
3. `PlayerState` 读档在 `apply_mode()` 失败时停在现有 `last_load_result` 错误边界，不继续把背包、装备和经验发布为已恢复状态。
4. 启动的 ContentLayers → GameData 顺序保持不变，不能用重试或 reset 掩盖失败。

这次未施工，因为该改变会影响模式切换、扩展状态和读档产品行为，需要主控确认并安排独立负例。B07A 的 GameData 专项证据可复用；本审计状态为 `NATIVE TEST: NOT_RUN`，`NO_PRODUCTION_CHANGE`。
