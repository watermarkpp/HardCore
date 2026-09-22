# Android DeviceLab 三职业 40 级赤月档案重建方案

## 范围与结论

### 当前执行状态：用户已延期安装

用户于 2026-09-05 明确要求先拔掉手机，安装包做好后等其回来再安装。因此本文件仅保留后续设备步骤，本轮不执行安装、存档修改、补丁停用或冷启动验收。优先保留现有三份 40 级档案，仅规范化两个空槽；不要执行下文历史重建模板中的 50→40 操作，除非后续实际检查证明需要重建。严禁 `pm clear` 清除应用设置。

### 最新设备只读核验

2026-09-05 主控通过 ADB 实际读取目标手机：索引及索引备份已经是精确三职业 40 级；三份角色主档与备份均为 v10、40 级，装备名称为对应赤月八槽，技能数量为 6/14/13 且全部 rank 3，技能合同为 `skills.progression.hardcore.v2`。因此“现有生成器会创建 50 级”不等于“手机当前仍是 50 级”，不能混淆。

目前仍有一个具体设备档案问题：三档的圣物、徽章槽都不是空对象，而是有 instance_id、空 name 的生成器占位记录。最终安装时优先保留并经正式 checkpoint/apply/export 规范化现有三档的两个空槽，再核验完整合法性与冷启动；只有必要时才采用下文清档重建路径。用户允许删除旧档，但未强制必须删除已经符合等级要求的三档。本次仅只读，无设备写入。

- 审查基线：`codex/integration`，只读审查时 `HEAD=3c37c7a2c3e6d0c2ea1a5845e092f8dc85cdfe4e`。
- 本文只给出最终设备执行方案；本轮未调用 ADB、未运行 Godot、未删除任何数据、未修改生产代码或正式装备/技能模板。
- 最小安全路径是不改 `assets/data/equipment_test_loadouts.json` 的正式 50 级 QA 模板，也不新增一套平行存档生成器：
  1. 仅在确需重建且已精确备份、清理目标测试存档后，显式调用现有 DeviceLab `ensure_chiyue_test_roster`，只生成三份正式 v10 赤月档案和索引；不清应用设置；
  2. 逐个在角色大厅选中角色，使用现有 checkpointed `export_player_state` / `apply_player_state` 把该角色精确改为 40 级；
  3. 每次 apply 后立即再次 export。该 export 内部调用正式 `save_game()`，会同时把角色主档和 `character_profiles.json` 索引更新为 40；
  4. 全部三档完成后再额外 export 一次，使索引 `.bak` 也轮换为全 40 级，避免主索引损坏时回退到含 50 级的旧备份。

当前 `ensure_chiyue_test_roster()` 不能直接作为最终验收结果：它取 `max(loadout.level, skill minimum)`，赤月装备模板的 `level` 是 50；其专用 `_valid_chiyue_test_profile_document()` 也明确要求 `level >= 50`。同样不能调用 `prepare_qa_test_roster_v2()`，后者的合同就是 3 职业 × 3 档共 9 个角色。

## 现有正规入口及边界

### 三角色初始化

- 主机入口：`tools/device_lab.ps1 -Action ensure_chiyue_test_roster`。
- 设备实现：`scripts/device_lab_runtime.gd::_ensure_chiyue_test_roster()`。
- 存档实现：`scripts/player_state.gd::ensure_chiyue_test_roster()`。
- 稳定 profile ID：
  - `test.character.warrior.chiyue.v2`
  - `test.character.wizard.chiyue.v2`
  - `test.character.taoist.chiyue.v2`
- 该入口只追加三份赤月档，不会主动生成沃玛/祖玛六档；全新应用数据上应返回 `ok=true, created=3, indexed=3, total=3`。

### 单角色降级到精确 40

- `export_player_state` 只导出当前已选中的 active profile，并在导出前调用正式 `save_game()`。
- `apply_player_state` 只接受 `save_version == 10` 且 `profile_id == active_profile_id` 的文档；执行前自动创建 checkpoint，原子替换后重新走 `load_save()`，失败则恢复旧文档。
- apply 本身不更新 `character_profiles.json`。因此每次成功 apply 后必须紧接一次 `export_player_state`；export 的正式保存会调用 `_update_profile_index()`，只更新当前行并保留另外两行。
- 角色切换不在 DeviceLab action allowlist 中，必须通过角色大厅选择。每次修改前先 export，并核对导出的 `profile_id` 与目标稳定 ID 一致；不允许仅凭 UI 文案猜测 active profile。

## 应用数据初始化

### 集成执行裁决

用户授权的是删除测试存档，不扩大为清除全部应用设置。最终执行采用下述“只清存档、不清应用设置”路径；不运行 `pm clear`。先只读列出并确认精确的角色、索引、旧档、共享仓库和旧补丁路径，再停止应用并逐项处理。保留 UI 校准、设备设置和性能验收材料；旧补丁单独停用，不能随存档清理遗漏。2026-09-05 只读 ADB 已确认目标设备 `AADMVB3602042319` 在线，但尚未执行删除或安装。

最终安装阶段才执行，且仅针对精确包名 `com.personal.mafaoffline`。用户已经授权必要时删除手机上的旧测试存档；当前三份 40 级档无需无故重建。只有确需重建时，顺序为：

1. 先停止应用，并把需要保留的最后一份旧测试证据拉到主机验收目录（若无需保留可省略）。
2. 精确核验并逐项备份、移除目标测试存档及相关索引；不运行应用数据清除、不用目录通配、不触碰其他包或 UI 设置。
3. 启动当前 debug APK，等待角色大厅与 DeviceLab mailbox ready。

不能仅删 `files/characters` 就声称完成重建，因为存档权威还包括：

- `files/character_profiles.json` 及 `.bak/.tmp/quarantine`；
- `files/player_save_v03.json`、`files/player_save_v02.json` 及其备份（旧档迁移入口）；
- `files/shared_warehouse.json`、`files/shared_warehouse.transaction.json`；
- `files/test_roster_v2_reset.json`（9 人 QA reset marker）；
- `files/device_lab` 下的旧命令、结果和 checkpoint。

若验收负责人选择“只清存档、不清应用设置”，也必须用 `run-as com.personal.mafaoffline` 对以上固定路径逐一备份/移除，并在应用完全停止时操作；不能只删除角色目录。

## 精确执行顺序

以下命令是最终设备阶段的模板，本审查未执行。所有命令都应带同一个已确认的 `$Serial`，输出保存在一次验收专属目录中。

```powershell
$Serial = '<confirmed-adb-serial>'
$Evidence = '<absolute-device-acceptance-output-dir>'
$DeviceLab = 'C:\Users\Administrator\Documents\HardCore\tools\device_lab.ps1'

& $DeviceLab -Serial $Serial -Action ensure_chiyue_test_roster -TimeoutSeconds 20
```

确认结果精确为三档后，在手机角色大厅依次选中战士、法师、道士。每个角色重复：

```powershell
& $DeviceLab -Serial $Serial -Action export_player_state `
  -OutputPath "$Evidence\<profession>-before.json" -TimeoutSeconds 20
```

对导出 JSON 做 fail-closed 变换：只允许目标 ID/职业，保留整份文档，修改 `level=40`、`experience=0`，并把未使用的扩展装备槽规范化为空对象。当前生成器遍历现有十个 `EQUIPMENT_SLOTS`，而正式赤月 loadout 只定义八槽；因此初次生成会给 `圣物/徽章` 留下 `name=""` 的占位实例，最终档不应保留这种伪占用。

```powershell
$Expected = '<exact-stable-profile-id>'
$ExpectedProfession = '<战士|法师|道士>'
$InputPath = "$Evidence\<profession>-before.json"
$OutputPath = "$Evidence\<profession>-level40.json"

$d = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
if ([int]$d.save_version -ne 10) { throw 'save_version mismatch' }
if ([string]$d.profile_id -ne $Expected) { throw 'profile_id mismatch' }
if ([string]$d.profession -ne $ExpectedProfession) { throw 'profession mismatch' }
if ([int]$d.level -ne 50) { throw 'unexpected source level' }
$d.level = 40
$d.experience = 0
$d.equipment.'圣物' = [pscustomobject]@{}
$d.equipment.'徽章' = [pscustomobject]@{}
$json = $d | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
```

然后应用并立即复导出：

```powershell
& $DeviceLab -Serial $Serial -Action apply_player_state `
  -PayloadPath "$Evidence\<profession>-level40.json" -TimeoutSeconds 20
& $DeviceLab -Serial $Serial -Action export_player_state `
  -OutputPath "$Evidence\<profession>-after.json" -TimeoutSeconds 20
```

apply 结果必须 `ok=true`、`saveVersion=10`、`rolledBack=false` 且返回非空 checkpoint；若失败，停止，不继续下一角色。after 导出必须与目标 ID 匹配且已经是 40。三角色都完成后，保持任一角色 active，再额外 export 一次，确保角色及索引主/备份都已由 40 级状态轮换：

```powershell
& $DeviceLab -Serial $Serial -Action export_player_state `
  -OutputPath "$Evidence\final-backup-rotation.json" -TimeoutSeconds 20
```

不得在最终 40 级档案形成后再次调用 `ensure_chiyue_test_roster`。它的 50 级专用 validator 会返回 `existing_profile_invalid:<id>`；按现实现不会覆盖档案，但该失败也没有任何验收价值。

## v10 文件格式与不变量

角色主档位于 `files/characters/<profile_id>.json`，索引位于 `files/character_profiles.json`（Android 的 `user://` 映射到应用私有 `files/`）。三份最终角色文档应保留由现有生成器/正式保存产生的完整 v10 字段，至少包括：

- `save_version: 10`、精确 `profile_id`、`character_name`、`updated_at`；
- `level: 40`、正确 `profession/gender`、`experience: 0`；
- `inventory`、十槽 `equipment` 字典（八个赤月槽为实例，`圣物/徽章` 为 `{}`）；
- `learned_skills` 及正式保存补齐的 `skill_progression`；
- `quick_slots`、`quick_item_slots`、`equip_cycle_cursor`、`skill_button_assignments`；
- `warrior_runtime_state`、`quest_states`、`world_monster_respawn_state`；
- `content_packages/content_schema_version`；
- `map_id` 与 position contract 字段。

索引格式固定为：

```json
{
  "version": 1,
  "profiles": [
    {"id": "test.character.warrior.chiyue.v2", "name": "...", "profession": "战士", "gender": "男", "level": 40, "updated_at": 0},
    {"id": "test.character.wizard.chiyue.v2", "name": "...", "profession": "法师", "gender": "男", "level": 40, "updated_at": 0},
    {"id": "test.character.taoist.chiyue.v2", "name": "...", "profession": "道士", "gender": "男", "level": 40, "updated_at": 0}
  ]
}
```

`updated_at` 示例中的 0 仅表示字段类型；实际必须是正式保存生成的非负时间戳，不应手工写 0。

## 40 级装备与技能合法性证据

### 技能

`qa_test_character_skill_profiles_v2.json` 的正式 QA 合同明确 `minimum_character_level=40`、`skill_level=3`。当前技能目录逐条核对 rank 3 后：

- 战士 6/6，最高需求为烈火剑法 40；
- 法师 14/14，最高需求为冰咆哮 40；
- 道士 13/13，最高需求为召唤神兽 40。

因此 40 级正好满足三职业全部技能 rank 3，不能降到 39。

### 赤月装备

八槽名称和 item ID 必须保持现有赤月 loadout 不变：

- 战士：113 怒斩、140 天魔神甲、232–235 圣战套；
- 法师：114 龙牙、142 法神披风、236–239 法神套；
- 道士：115 逍遥扇、144 天尊道袍、240–243 天尊套。

按正式属性目录及现有运行时公式静态核算，40 级完整装备满足：

| 职业 | 主属性最低核算 / 最高需求 | 穿戴重量 / 上限 | 武器重量 / 手持上限 |
| --- | ---: | ---: | ---: |
| 战士 | DC 50 / 46 | 92 / 95 | 85 / 135 |
| 法师 | MC 30 / 28 | 28 / 31 | 25 / 30 |
| 道士 | SC 34 / 25 | 45 / 47 | 45 / 50 |

主属性“最低核算”只按每个不同装备记录计算一次，已经能满足需求；双手镯/双戒指的第二件只会进一步提高最终属性。职业、男装性别和槽位也来自现有已审计 loadout。最终验收仍需对设备导出逐槽核对，不能只凭这张静态表。

## 冷启动与“不回到 50/9 人”的门禁

`PlayerState._ready()` 只有在以下三项同时满足时才会调用九人 `prepare_qa_test_roster_v2()`：debug build、非 headless、项目设置 `hardcore/debug/enable_qa_test_roster=true`。当前 `project.godot` 和 `export_presets.cfg` 都没有设置这个键，默认值为 false；`ensure_chiyue_test_roster` 也只在显式 DeviceLab action 时调用。

构建最终 debug APK 前必须重新静态确认该键仍不存在或明确为 false。不能把 `test_roster_v2_reset.json` 当防护：如果设置意外开启，只有三档时 `prepare_qa_test_roster_v2()` 仍会判定未 ready 并补成九档。

## 最终验收清单

1. DeviceLab 初始化结果：`ok=true, created=3, indexed=3, total=3`。
2. 应用停止后，通过只读 `run-as` 拉取并保存：
   - `files/character_profiles.json` 和 `.bak`；
   - 三个 `files/characters/<stable-id>.json` 和各自 `.bak`；
   - `files/shared_warehouse.json`（确认是有效空仓库或期望状态）。
3. 主索引与备份索引都必须 `version=1`、精确三行、三个稳定 ID 各一次、每行 `level=40`；角色目录不得有另外六个沃玛/祖玛 v2 主档。
4. 三份角色主档和备份都必须通过 v10 业务校验：ID 与路径一致、`save_version=10`、核心容器类型正确、`level=40`。
5. 逐档检查八个赤月槽：名称、item ID 反查、职业/性别/槽位、耐久字段、唯一非空 `instance_id`；`圣物/徽章` 必须为 `{}`。
6. 逐档检查 `learned_skills` 数量 6/14/13、全部为 rank 3，`skill_progression` 同步为 `skills.progression.hardcore.v2`，button assignments 只引用已学技能。
7. 强制停止应用，冷启动到角色大厅：仍只显示三人且都是 40。依次选入三档，再 export，确认运行时导出仍为 v10/40、装备与技能不变。
8. 冷启动后再拉取主/备份和索引并计算 SHA-256；确认没有自动生成六个额外 profile，也没有任何行回到 50。

## 不采用的方案

- 不全局把 `equipment_test_loadouts.json` 的 9 套模板从 50 改为 40：会扩大正式 QA 合同和大量现有测试影响面。
- 不改 `ensure_chiyue_test_roster()` 或其 50 级专用 validator：设备一次性准备不值得引入生产存档格式变更。
- 不直接从主机拼三份 JSON 后 raw-copy 到应用私有目录：会绕过现有 checkpoint、原子写、reload 和索引更新路径。
- 不只 apply 后看 UI：apply 不更新索引，必须用后续 export/save 形成索引与备份闭环。
