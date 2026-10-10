# B07A GameData 五个函数职责补审

审查基线固定为 `b09ac5c2c41517ed516f11b91d09e435813465f2`，只读取该 Git 对象，
没有使用当前工作树或其他代理的施工文件。该补审不是全项目 PASS，也没有重复
B07A 已闭合的装备字段和哈希核验。

## 初始化短链

`GameData.load_database()` 在 `scripts/game_data.gd:236-316` 依次加载运行物品权威、
DPV2 直接基线，然后进入 `_build_indexes()`。前两个加载失败会立即返回 `false`，
并由 `initial_load()` 保持初始化失败。`_build_indexes()` 清理索引后构造物品目录，
再构造技能书索引；装备面板、掉落解析和存档身份最终都通过 `get_item_record()`、
`item_entity_id()` 或 DPV2 的已加载门控读取。

## 关键结论

### `_load_item_runtime_authority()`（456–514）

已经检查文件存在、JSON 字典、精确 contract ID、5 个别名、13 个 newItems、稳定
ID／名称唯一性和对 service runtime 的 ID 碰撞。它在失败前先清空
`item_runtime_authority`，调用者在 285–286 行 fail-closed。

仍缺少完整 schemaVersion、alias 目标最终身份、newItems 完整字段以及跨数据库／
圣物／黑铁等来源的稳定 ID 碰撞语义。`_build_item_catalog()` 的注册器对重复名称
静默跳过，对重复稳定 ID 不直接报致命错误，这条链需要单独失败测试。

### `_load_dpv2_direct_baseline()`（517–1073）

这是掉落初始化的主要门控：要求六个文件存在，校验 manifest 的路径、LF SHA256、
生产状态和直接基线／全局概率／物品映射／语义记录的精确数量与身份。运行时索引
在入口清空，成功到最后才设置 `dpv2_direct_baseline_loaded=true`。

尚未证明重复初始化中途失败的私有索引生命周期，也未证明已 hash 绑定的
`verified_profile_authority` 在运行时具有独立语义一致性。公开掉落入口有 loaded 门控，
所以本次静态审查没有把部分私有索引直接认定为已发生生产泄漏。

### `_validate_dpv2_semantic_authority()`（1551–1916）

它严格检查 schema、权威 ID、生产状态、身份键、禁用 name/fuzzy fallback 的策略、
汇总计数、来源账、冻结决策和 156 条记录的逐条状态／来源计数／原因。它把语义
权威交给后续 canonical monster drop closure 使用。

仍缺少汇总摘要到下游最终 reward catalog 的独立绑定证据；当前是硬编码计数和逐条
字段校验，不能把它扩大解释为完整的跨消费者验证。

### `_build_item_catalog()`（2589–2692）

它清空并重建名称、item ID、service index、currency index 和 `item_catalog`，接入
装备、service items、specials、runtime authority newItems、黑铁、圣物、掉落名称和
技能名。类别错误会被 `_build_indexes()` 清空并返回失败。

发现一个待修逻辑缺口：`_register_catalog_item()` 对重复名称静默跳过，重复稳定 ID
不设置致命错误，可能造成“名称索引看到记录、稳定 ID 索引仍指向另一记录”的双身份
状态。当前没有通过真实数据证明已经触发，因此标为 `LIKELY_LOGIC_GAP`，不能直接
宣称现行数据已经坏掉。

### `_build_skill_book_index()`（2695–2738）

它检查 canonical skill ID、装备授予技能、技能书目标、目标唯一性和完整覆盖数，
但是失败时只 `push_error()` 后无返回值。`_build_indexes()` 也没有检查该失败，仍可
返回 `true`；随后 `load_database()` 可把初始化标记为完成，而
`_skill_books_by_skill` 为空或不完整。

这是本次确认的静态逻辑 bug。最小修复是让函数返回 `bool`，设置稳定 `load_error`，
并让 `_build_indexes()` fail-closed；需要补充错误目标、重复目标、缺目标和不完整索引
回归。当前子任务按要求只读，未施工。

## 真实消费者短链

- 装备面板：`inventory_panel.gd` 的代表性入口 574、1016、1093、1164、1315、1640，
  以及 `item_detail_presenter.gd:523`，通过 `GameData.get_item_record()` 读取。
- 技能书：`player_state.gd:2322–2338` 使用 `skill_book_skill_id()`，学习路径
  `3224–3241` 使用 `skill_book_entity_id()` 和稳定 item identity。
- 掉落：`loot_runtime_service.gd:93–110` 要求 DPV2 loaded，278–294 解析 reward，
  375–430 再用 DPV2 canonical item identity 和 `get_item_record()` 生成实际物品。
- 存档身份：`item_identity_codec.gd:17–36` 与 PlayerState 的身份写入／读取路径通过
  `GameData.item_entity_id()` 拒绝未知或冲突身份。

## 范围和后续

本次只读补审没有查看真实存档或凭据，没有运行 Godot、Android、设备测试，也没有
修改生产文件、测试文件或 Git。报告文件和独立 raw 绑定见同目录 JSON 及
`outputs/wake_drop_v108_review_followup_20261009/b07a_gamedata_function_supplement/`。
