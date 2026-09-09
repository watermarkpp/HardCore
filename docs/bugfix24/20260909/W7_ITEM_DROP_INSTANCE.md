# W7 完整地面装备实例合同

状态：集成候选专项通过，等待最终跨域整合与 APK 验收。

## 边界

- 不修改任何怪物掉落槽、掉率、装备基础属性或属性主表。
- 装备掉落槽成功后，由 `GameRoot` 以一次死亡内稳定的 `session_nonce + death_key + item_index` 调用 `PlayerState.create_drop_item_instance` 一次。物化失败、拾取失败、保存失败及重试复用同一份记录，不再次生成。
- 非装备身份记录原样返回。旧的不含 `item_instance` 的装备接收调用继续生成普通基础实例，不参与小极品抽样；正式新地面装备链必须携带嵌套实例。

## 身份与随机数

`item.drop.instance.v1` 接受 `GameData` 可由精确 `itemId` 反查的全部装备。`instance_id` 与抽样均由 stable drop key 的 SHA-256 派生；规则内部新建局部 `RandomNumberGenerator`，不消费 LootRuntime 或 GameRoot 的掉落 RNG。属性主表只决定小极品资格；不在主表中的正式装备仍生成并传递完整普通实例，不会阻塞物化。

实例保存：精确 `item_id`、稳定 `instance_id`、drop key 摘要、raw/display 耐久及合同、武器幸运/诅咒、`modifiers` 和 `drop_affix` 来源映射。拾取边界校验字段白名单、数值范围、主表映射、修饰符等式与重复实例；带有非法 nested instance 的候选直接拒绝，不回退重建。

## V1 非原版配置

`assets/data/item_drop_instance_rules_v1.json` 集中声明开关、概率和映射。当前启用值是每件合格装备 `5%` 获得一项 `+1`，属于项目工程默认，不是原版或外部资料真值。开关与概率可在单一配置处调整，只影响之后生成的实例。`item.drop.affix.v1` 的已保存数值语义冻结为 `+1`；若未来要改变增量，必须新增合同版本和独立历史校验，禁止原地改写 V1。

候选属性仅来自该 `itemId` 在正式属性主表中实际存在的属性族：`dc/mc/sc/ac/mac` 分别映射到 `attack_max/magic_max/tao_max/defense_max/magic_defense_max`。实例使用现有真实消费格式 `Array[{stat, op: "add", value}]`，不建立 `random_stats` 第二权威；装备聚合先保留 catalog modifier 语义，再应用实例 modifier 一次。

## 持久化与兼容

- inventory、equipment、共享 warehouse 均保存同一完整字典；跨角色仓库存取不重建。
- 耐久和武器幸运/诅咒允许由既有正式玩法在合法范围内变化；身份、affix 与 modifiers 不变。
- 旧字符串装备和旧普通实例不补抽、不迁移成小极品。
- 单份存档及共享仓库拒绝非法 W7 实例；角色的背包、旧私仓与穿戴槽之间，以及当前角色背包/穿戴与独立共享仓库文件之间，均拒绝重复 `instance_id`。

## 专项入口

2026-09-09 主树验证：rules 与真实 `loot_world_placement_integration_test` PASS；persistence 首次暴露旧 opaque guard 抢先返回错误码，已将外部接收的 W7 重复检查移至模板构造前，内部穿脱转移预检保持兼容。复测 persistence、equipment_inventory_slot_swap、shared_warehouse_transaction 共 3/3 PASS，见 `evidence/instance_stage_d/runner_results_adhoc_20260909_130541_845_4136.json`。首次失败保留在 `evidence/instance_first_failure`。真实地面场景仍有既有 dummy renderer 放行日志，严格渲染接受仍单列 OPEN。

- `res://tests/item_drop_instance_rules_test.tscn`：精确主源资格、固定 key、5% 两类结果、局部 RNG、V1 历史记录不受开关/概率调整影响、永久最大耐久损失、伪造字段/数值及非装备透传。
- `res://tests/item_drop_instance_persistence_test.tscn`：完整拾取、改名展示不改 ID、保存失败重试、重复拒绝、真实保存/重载、共享仓库跨角色、穿戴属性实际生效、单档及 profile/shared 跨文件重复档拒绝。
