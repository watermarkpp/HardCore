# 精确音效跨域接线合同

音频包已经解决声源与 stable ID 映射；integration/对应 owner 只需在真实成功阶段发语义事件，禁止再解析文件名、显示名或 appearance。

## 公共 API

```gdscript
var result: Dictionary = audio_runtime_service.play_event(event_id, context)
var result: Dictionary = audio_runtime_service.play_monster_event(monster_id, semantic_event, context)
var result: Dictionary = audio_runtime_service.play_item_event(stable_item_key, semantic_event, context)
var result: Dictionary = audio_runtime_service.play_monster_ambient_if_due(monster_id, client_frame, audio_owner_key, context)
var result: Dictionary = audio_runtime_service.play_player_physical_contact(classic_weapon_shape, context)
audio_runtime_service.stop_all_audio("world_exit")
```

- `play_event`/`play_monster_event` 只影响展示，不得改变伤害、冷却、召唤或生成结果。
- 返回 `status == "played"` 表示已找到精确绑定并提交到声部；缺映射、未预热、并发池保护均 fail-closed，不得回退显示名或邻号。
- `context` 只用于展示变体与诊断；攻杀传 `{"gender": PlayerState.gender}` 可稳定选择 130/131。音频 RNG 与玩法 RNG 完全独立。
- 当前服务加入 group `audio_runtime_service`；`PlayerVisual` 已从该 group 在原 client effect frame 发武器/技能体声。

## 技能成功阶段

事件 ID 来自 `audio_bindings.runtime.json`，形式为 `skill.<canonical_skill_id>.<phase>`：

- `.cast`：学习/职业/目标/距离/冷却/资源检查均成功，并真正进入施法动作后调用。按钮点击、快捷键按下、目标选择或失败请求不得调用。
- `.launch`：已由 `SkillProjectile._ready()` 在 projectile role/视觉就绪后内部发出；当前有飞行 phase 的精确技能为火球术、大火球、灵魂火符。GameRoot 不得重复发 launch。
- `.impact`：已由 `SkillProjectile` 在实际目标接触或有效路径射程终点内部发出。投影/快照拒绝、过期清理、跨图取消不发；GameRoot 不得重复发 impact。
- `.effect`：非飞行技能的效果已经提交后调用；若本次被规则拒绝，不调用。

战士体声和武器声已由 `scripts/player_visual.gd:_update_action_audio()` 在 `WarriorCombatMath.CLIENT_EFFECT_FRAME` 接好：普通攻击只发武器声；攻杀/刺杀/半月/烈火同时发武器层和对应技能体声；野蛮冲撞与烈火蓄力不借用不存在的专属声音。武器层以 stable item ID 解决正式 `worldWear.shape`，按主源 shape 分组发 `player.weapon.short/wood/sword/blade/axe/club/long/fist.swing`；已装备但缺 ID/shape 时 fail-closed，不用名称或“默认剑”猜配。

玩家受击/死亡由 `PlayerVisual.play_action()` 的真实新动作起点发出：PvE hit 先 `player.hurt.pve.body`(72)，再发按性别选择 138/139 的 `player.hurt.voice`；death 发按性别选择 144/145 的 `player.death.voice`。同一活动动作重复请求不会重播。死亡音乐不接入，保持主城 BGM 已播出后不因离区、跨图或死亡被截断的用户规则。

玩家物理接触由 damage context 严格证明，不以 `attacker is PlayerCharacter` 猜测。`GameRoot._apply_physical_hit()` 仅在命中闸通过后标记；legacy AOE 仅在 `physical_accuracy == true` 且 source skill 不走 anti-magic 时标记。`EnemyActor.take_damage()` 只在正数扣血、非致死并实际调用既有 `visual.play_hit()` 的分支中调用 `play_player_physical_contact()`，随后保留原怪物 hurt 顺序。法术、毒伤、miss、零伤害与未进入 hit 表现的致死分支不发。服务按精确 classic shape 播放 weapon 60..65 与 body 70..73；未知装备 ID/shape 拒绝，只有真正空手返回 shape 0。

## 怪物成功阶段

调用 `play_monster_event(monster_id, semantic_event, context)`，`monster_id` 必须是 runtime actor 的稳定整数 ID：

- `appear`：怪物 spawn 已成功且 actor 进入可见生命周期时一次。
- `ambient`：Enemy 在原客户端等价的 walk/turn client frame 调用 `play_monster_ambient_if_due(...)`；服务只在 frame 1 以该 actor 的 `audio_owner_key` 独立 RNG 执行 1/8 抽样。Enemy 不得自行消耗 gameplay RNG，不得再直接发 `ambient`。
- `attack_start`：攻击状态已经接受并开始时。不要在 AI 仅选中目标时播放。
- `attack_frame`：可视攻击动作到 client frame 3 时；这是武器/摆动层，不等同伤害提交。
- `hurt`：实际造成正数 HP 扣减并进入受击表现后。miss、免疫、零伤害不调用。
- `death`：HP 到零的死亡状态只转换一次时。
- `death_secondary`：runtime 合同只为 source guard 命中的 appearance 80 对象生成；其它 ID 请求会 fail-closed。

怪物缺某一 phase 不影响同对象其它精确 phase；例如 monster 112 仅 `attack_frame` 因主源缺 `940-3.wav` 被拒绝，其它 phase 可正常播放。

## 召唤物攻击

`assets/data/vanilla_176/taoist_summon_baseline.json` 已给出 exact 模板身份：变异骷髅 `monster_id=145`/client appearance 37，神兽 `monster_id=146`/client appearance 171。因此 SummonActor 可直接复用已生成的 `monster.145.*`/`monster.146.*` 事件，不从 `summon_name` 解析。

- `_begin_attack` 确实进入攻击状态后发 `attack_start`。
- `_release_pending_attack` 的动作释放帧发 `attack_frame`；该声属于动作帧，不以命中成功为前提。
- 神兽当前是 3 GU directed direct-spell 和 body fire visual，没有创建 `SkillProjectile`；只发 monster 146 的 attack phase，不发 skill launch/impact。
- monster 145 的 hurt 是主源空槽，保持安静；monster 146 的 appear/ambient/attack_start/attack_frame/hurt/death 均有精确 1910..1915 样本。

## NPC、BGM 与退出

- NPC 成功交互继续走 `play_npc_interaction_success(stable_service_id, context)`；关闭面板不调用 stop。
- BGM 的安全区离开/跨图不调用 cancel；只在 world/session/app 显式退出时停止。
- 退出统一优先调用 `stop_all_audio(reason)`；若 GameRoot 仍分别管理，可保持 BGM `cancel(reason)` 与 audio service `stop_all_audio(reason)` 两个明确边界。

## 物品与货币成功阶段

`play_item_event` 仅接受以下稳定键，不接受显示名或类别名：

- `item:<item_id>`：`assets/data/vanilla_176/items.json` 的装备 ID，以及 `item_runtime_authority_v1.json` 的新物品 ID。
- `service:<serviceIndex>`：`service_item_catalog.json` 的非装备物品稳定 serviceIndex。
- `currency:gold`：金币唯一键。

当前公开 semantic 列表：

- `use_success`：药品/可证实消耗品已真正扣除数量并提交效果后一次。调用示例：`play_item_event("service:%d" % service_index, "use_success", context)` 或 `play_item_event("item:%d" % item_id, "use_success", context)`。
- `equip_success`：新装备已写入穿戴槽、背包/持久化提交成功后一次。
- `unequip_success`：旧装备已从穿戴槽移回背包并提交成功后一次。换装如同时完成卸下与穿上，owner 按其真实 commit 结果分别发送；失败回滚不发。
- `loot_success`：仅 `currency:gold`，在拾取批次完成且金币 delta 已入账后发一次。
- `balance_change_success`：仅保留给源中明确的服务端 `SM_GOLDCHANGED` 成功接收边界。同一次拾取不可再与 `loot_success` 重复发；当前商店买入/卖出主源没有专用成功声，因此不接此事件，也禁止用失败前会触发的宽泛 `profile_changed` 代替。

普通物品拾取/丢弃在主源成功路径无专用声，不调用物品声。卷轴、技能书等未命中主源 `ItemUseSound` 分支的身份会返回 `silent_or_unmapped_item_event`，不得用 108 药品声兜底。

## UI 材质声

主源可证实 `ui.button.normal.click`/`ui.button.rock.click`/`ui.button.glass.click` 分别为 sound 103/104/105，但当前 HardCore widget 没有显式的三类材质合同，运行时状态为 `NOT_STARTED`。未增加 exact UI material stable ID 前，不从 Gothic 样式、按钮文案或文件名猜选。玩家脚步同理：主源 sound 1..32 和帧点已知，但当前地图没有 legacy 表面身份，保持未接入而不是默认地面声。
