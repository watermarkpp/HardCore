# 主数据库与分级资料源越级使用审计

审计 ID：`source.precedence.audit.2026-07-24.v1`

审计日期：2026-07-24（Asia/Shanghai）

审计性质：只读；未运行生成器，未修改专业数据，未合并被审计的装备提交。

## 审计基线

- 完整扫描数据库：`outputs/resource_catalog/complete_local_mir_sources/catalog.sqlite`
- 完整扫描清单：`outputs/resource_catalog/complete_local_mir_sources/manifest.json`
- 来源优先级：`assets/data/source_priority_policy.json`
- SQLite SHA-256：`3a133f39e9a0bf0b065b29778ff4f40d33aaa009ba1bed0a3213ae3a33233c79`
- SQLite 完整性：`ok`
- distribution：58
- 文件：38,887
- 字节：14,595,954,010
- 未哈希文件：0
- 文件数与字节数覆盖：精确一致

`manifest.json` 中的 `sourceRoot` 保留迁移前的历史中文路径；清单、SQLite 和哈希仍完整有效。本次审计直接查询既有 SQLite，不重新扫描 14.6 GB 原始资料。

2026-07-17 的源目录复核 `passed=false`，原因是扫描完成后新增了 60 个文件、17,979,772 字节；没有原扫描文件丢失，也没有既有文件大小变化。新增内容包括未配置的 `mylgd` 目录和 UI/branding 文件，它们不在 2026-07-15 的完整扫描与正式来源优先级中，因此不得进入运行时。

## 强制判定规则

1. 每个目标先按 lane 查询 `primary`。
2. 主源只要存在目标记录、字段或资源，就禁止采用任何低级来源。
3. 只有主源明确 `missing` 才能按 `auxiliary_1 → auxiliary_2 → auxiliary_3` 逐级检索。
4. `unusable`、`incompatible`、版本表现不理想或画面不符合预期，不再构成降级理由；应修复解析、映射或兼容层。
5. 每次 fallback 必须保存所有更高等级来源的路径、版本/哈希、查询结果与逐项缺失证据。
6. 用户指定低级来源只代表允许核查；除非用户明确命令覆盖主源，否则仍不得跳过主源。

## 已拒绝的未合并提交

`codex/equipment` 提交 `7c37b77147ee284746bab5a009122069fbbcdaac` 不得合并。

- 该提交把 37 件武器的 Shape/Looks 统一切换到未列入正式优先级链的 `mylgd_mir2server_176/Mud2/DB/StdItems.DB`。
- 主数据库对其中 31 件存在精确同名 Shape。
- 31 件中的 29 件，低级来源 Shape 与主数据库 Shape 冲突。
- 其余 6 件也没有保存对所有更高等级来源的逐级缺失证据。
- 可以保留用户明确提供的语义事实作为验收条件，例如木剑/乌木剑/罗刹/嗜魂法杖/屠龙具有世界外观，以及职业归属与实体造型分类必须分离；数值与 Shape 仍需从主源重新建立兼容映射。

## 已完成的 primary-only 武器返修

- 集成提交：`2b0da07e`
- 稳定合同：`equipment.weapon_compatibility.primary.v1`
- 37 件正式武器中 35 件使用主客户端 StateItem/Weapon 像素，隐藏 0，命运之刃与落魄神兵保持未解析。
- 木剑、乌木剑、罗刹、噬魂法杖、屠龙均恢复世界外观。
- 罗刹使用 `integration_user_required_shared_primary_appearance`：采用主客户端 StateItem 40 与 Weapon feature 14 的斧类像素；数据库 Shape 保持空值，并保存主库及正式 auxiliary_1/2/3 的缺失/错误候选拒绝证据。
- `profession` 与 `visualWeaponClass` 独立：炼狱=战士/axe，裁决=战士/staff，龙纹剑=道士/sword，屠龙=战士/blade。
- 低级来源采用数为 0；被拒的 `mylgd`、21CQ 和 external mir2opensource 均未进入合同。
- Python 武器合同与 Godot 武器、视觉目录、角色排序、墙体遮挡、smoke 共 5 项通过。

## 当前主树的确定越级

| 编号 | 领域 | 确定范围 | 当前低级来源 | 主源证据与影响 |
|---|---|---:|---|---|
| V01 | 装备图标/Looks | 143/175 件 | 21CQ/web cache | `serviceEquipmentReference` 对 143 件有精确同名 `image`；现构建器未先查主库。已知辟邪手镯为 web 200、primary 194。 |
| V02 | 装备属性 | 143/175 件有主库同名；至少 65 件实值冲突 | 21CQ | `vanilla_176/items.json` 的 175 件全部来自 21CQ；运行时同名 first-wins，primary 只停留在参考字段。屠龙、炼狱、裁决、龙纹等重量、需求、耐久或属性存在冲突。 |
| V03 | 旧战士 wear 前置映射 | 20/23 件 | angelk | 主库对 20 件有同名 Shape；构建器只让 primary 补 3 个缺口，不覆盖先采纳的 angelk。虽然 formal visual 会覆盖部分字段，旧 manifest 仍被运行时加载。 |
| V04 | 怪物核心数值 | 157/214 怪物 | 21CQ | 主库存在受控匹配；156 条经验值与 primary 不同，HP/攻击/防御也存在大量冲突。运行时直接读取低源数值。 |
| V05 | Boss 核心数值 | 31/46 Boss | 21CQ | 30/31 的经验值与 primary 不同，HP/防御/攻击亦存在冲突。 |
| V06 | 比奇怪物覆盖 | 17 个怪物、68 个字段 | angelk | primary 对 accuracy/agility/attackInterval/moveInterval 均有值；发现 7 个实值冲突。 |
| V07 | 比奇运行时掉落 | 10 张运行表 | angelk/手写 | primary 对 22 个目标均存在精确同名掉落文件；构建器未查主源，运行时优先返回 community 表。 |
| V08 | 核心 Boss 掉落 | 1,854/3,424 条 | 21CQ | 42 个 bossName 中 25 个在 primary 存在精确同名掉落文件，覆盖 1,854 条当前低源记录。 |
| V09 | complete 怪物外观身份 | 98 条 | mylgd `Monster.DB` | primary 对 98 个目标已有 `Image`，而 98/98 与 mylgd Appr 冲突；运行时加载该 manifest。 |
| V10 | 早期怪物外观身份 | 30 条 | 21CQ | `bich_common` 24 条和 `bich_undead` 6 条在 primary 已有 `Image`，仍采用 21CQ；多数值冲突。 |
| V11 | 技能等级/训练点 | 105/132 条技能，共 138 个冲突字段 | 21CQ | primary 对 132 条均有候选记录；requiredCharacterLevel 39 条、trainingPoints 99 条仍选低源。manaCost 已正确选 primary，不在违规范围。 |
| V12 | 男性世界头盔定位锚点 | 12 件/11 视觉身份、232 个 pose-anchor | auxiliary `mir2opensource` Hair.wil | primary `client.classic_raw_complete/Data/Hair.wil` 明确存在；构建器直接硬编码 auxiliary Hair，未查主源。 |
| V13 | 怪物/地图服务端规则源码 | 多个生成器 | auxiliary_2 Crystal 源码 | 更高优先级 auxiliary_1 `minipizza` 存在对应 `MonsterInfo.cs`、`MonsterObject.cs`、`Map.cs`，生成器仍直接跳到 auxiliary_2。 |

## 尚缺证据、不能冒充确定越级

- 142 张地图和 9 个任务目前带有 21CQ 来源且缺 primary 查询记录，但尚未证明 primary 存在同语义逐字段目标，暂记 `SUSPECT_MISSING_EVIDENCE`。
- 命运之刃、赤血魔剑、祈祷之刃的旧 angelk Shape 在 primary 无精确同名；现有缺口是没有保存逐条查询路径、哈希和拒绝记录，暂记 `SUSPECT_MISSING_EVIDENCE`。
- complete 怪物资源中的 `Mon19/Mon20/Mon21` 辅助像素，经完整 SQLite 核实 primary 确无对应库，不属于“主库有却越级”；仍需补正式 fallback 证据。
- `build_warrior_paper_doll_asset.py` 的 angelk 旧实现当前不再由主入口调用，记 `HISTORICAL_ONLY`。

## 返修顺序与所有权

1. **已完成 equipment**：已用主数据库与主客户端资源重建武器兼容映射；木剑、乌木剑、罗刹、噬魂法杖、屠龙已有世界外观，职业与 `visualWeaponClass` 双轴分离。
2. **P0 equipment/integration**：装备属性和图标改为 primary-first；对 143 件逐字段生成采用/冲突报告，再由集成层接入。
3. **P0 monsters/integration**：怪物与 Boss 核心数值、比奇覆盖、complete/早期外观身份改为 primary-first。
4. **P0 integration/maps/monsters**：掉落文件按 primary 同名文件重建；地图刷新到掉落的最终映射由 integration 接入。
5. **P1 professions-skills/integration**：修正 105 条技能的 138 个越级字段。
6. **P1 equipment**：头盔 232 个锚点改用 primary Hair.wil 重新生成并验证；不得改变已经确认的头盔造型。
7. **P1 monsters/maps**：规则生成器严格执行 `server_rules` 的 primary/auxiliary 顺序。

所有返修必须在对应永久工作树完成，单域测试通过后逐项合并；禁止一次性混合重生成。
