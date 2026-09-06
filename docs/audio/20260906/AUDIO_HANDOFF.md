# HardCore 音频闭环交付证据（2026-09-06）

## 结果

- 基线：`7c3019da4d3732766bdea2655abfedbea84e5b7b`。
- 33 个 canonical 技能和 153 个 `runtime_allowed` 怪物均已按稳定 ID 审计；不再以“项目里尚无 `.play()`”冒充声源缺失。
- 共生成 1,152 条 authoring 语义记录；其中 509 条有精确主源样本，可直接进入 runtime；349 个唯一 WAV（50,384,200 bytes）按源 SHA-256 去重后落到 `assets/audio/sfx/client/`。
- 当前 727 个物品/货币稳定身份已逐对象审计；278 个身份有精确成功路由，共 454 条 `use/equip/unequip/loot` 路由。
- 其余记录逐项保留主源空槽、调用守卫或真正缺文件证据，不按相邻编号/文件名补音。
- `AudioRuntimeService.play_event(event_id, context)` 是统一入口；物品使用 `play_item_event(stable_item_key, semantic_event, context)`。服务只建 24 个固定 SFX 播放器，不为 509 个事件各建节点。NPC 和怪物环境声均使用与玩法独立的 RNG。

机器可检详情：

- `assets/data/audio/audio_bindings.source.json`：完整 authoring 记录、来源规则、每个样本哈希与状态。
- `assets/data/audio/audio_bindings.runtime.json`：仅包含 `EXACT` 事件和 7 个 NPC 稳定 ID。
- `assets/data/audio/audio_requirements.json`：33 技能、156 怪物记录（153 可运行）、727 个当前物品/货币稳定身份逐对象状态。
- `assets/data/audio/exact_mapping_report.json`：计数、重复 ID 装载裁决、真正缺文件、空槽和调用守卫汇总。

## 主源规则与身份桥

`client_assets` 主源为 `dev_art_sources/reference/mir2_client_raw/Wav`；`client_rules` 主源为 `dev_art_sources/reference/original_gameofmir/MirClient`。关键文件及 SHA-256：

- `SoundUtil.pas`：`85d21c3029d00e5cccf4d9d5e691d3d083ac5560101ddb8afad11f8be40bbfac`
- `Actor.pas`：`55a43cfdca869810217e007f2284d293c8d69c8d0867cc879327ddcde87e19cd`
- `Grobal2.pas`：`e29027ff7ea1a713847af5742261455859f5822bd3a3d97698f03442e3a07c6a`
- `PlayScn.pas`：`6c9d1d191368ebc841bb10e51d248e8bfe7e344013e866d30f70a775cc9694d4`
- `magiceff.pas`：`66606a4e495790f83e8a6fce3809ec54963882ff0b55ca390d1442b4e4699f3c`
- `ClMain.pas`：`c0928322de261cc600384f0b278f14ea8b44034c7e900cc5aa3aea0c05f7775b`
- `FState.pas`：`d2ad68723041cb102b80b0b23aabf0859e7f08113431c6ff29d8ff5ed163fea4`

已复现的原客户端规则：

- `SoundUtil.LoadSoundList` 只接受严格递增的 sound ID。重复 1680、1943 均采用第一次出现的行，后行不会覆盖；生成器复现该行为。
- 魔法：`10000 + MagicSerial * 10` 为施法，`+1` 为飞行发射，`+2` 为非飞行效果或飞行到达。`Grobal2.pas` 的 1..33 常量与当前 canonical skill ID 使用显式表桥接。
- 怪物：`200 + client_appearance * 10 + phase`；phase 0/1/2/3/4/5 分别为出现、走/转第 1 帧的 1/8 环境声、攻击动作起点、攻击第 3 帧武器声、受击、死亡。`+6` 只在主源 appearance 80 的守卫内调用，其它怪物明确标为 `NOT_APPLICABLE_SOURCE_GUARD`。
- 玩家武器：主源按 `(m_btWeapon div 2)` 的 classic shape 选择短兵50、木制51、剑52、刀/刃53、斧54、棍55、长兵56、徒手57。`PlayerVisual` 以装备稳定 ID 读正式 `worldWear.shape`，不再按“木剑”文字猜配；已装备但 ID/shape 不可证时保持安静，只有真正未装武器才用徒手57。攻杀 130/131（男/女）、刺杀 132、半月 133、烈火 137，均在 client effect frame 播放。136 虽有常量但主源没有相应调用，未接入；野蛮冲撞也没有借用相邻技能编号。
- 物品：`ItemClickSound` 的 StdMode/手腕名称分支在生成期编译为稳定 ID 路由，运行时不读显示名。武器 111、衣服 112、戒指 113、腰带/腕部 114、项链 115、头盔 116、手镯/手套 117、通用 118；`ItemUseSound` 药品 108、食物 107；金币变更 106。HardCore 只在当前成功 commit 后播放，不复制主源“请求发送前点击就播”的失败路径。

## 精确缺口

只有两条事件出现“有效索引点名文件、但主源快照无该文件”：

- `skill.wizard.lightning.cast`：sound 10110，`sound.lst` line 784，`wav\\M11-1.wav` 缺失。雷电术已存在的其它精确 phase 不受影响。
- `monster.112.attack_frame`（黑色恶蛆，appearance 74）：sound 943，`sound.lst` line 406，`wav\\940-3.wav` 缺失；出现/环境/攻击起点/受击/死亡仍分别有精确样本。

主源有效空槽统一标为 `SILENCE_VERIFIED`；不是缺资源，也不会用邻号补齐。物品路由中，当前 175 件装备的穿/卸、102 个可证实药品的使用、金币入账/余额变更均已闭合。普通拾取/丢弃在 `ClMain.pas`/`FState.pas` 相应成功路径没有专用 `PlaySound`；卷轴、技能书等也不在 `ItemUseSound` 的 StdMode 0..2 内，因此保持安静并拒绝借用药品声。UI 103/104/105 只有通用/石/玻璃材质语义，已生成 `ui.button.normal.click`/`ui.button.rock.click`/`ui.button.glass.click`；当前 UI 没有显式材质类型合同，不从 Gothic 皮肤或文件名猜配。

## 已实现运行时

- 主城 BGM：Loading 完成/主城入场后 6 秒，`Music` bus，线性音量 0.70，loop=false；播出后离安全区或跨图不中断，自然结束，不重叠；显式 world/session 退出停止。冻结 OGG SHA-256 为 `c750b7ee2c6a3baaa326d1dbcfaaa6bca853df5c00c6adb6d444b2bbac1e71c6`。
- NPC：14 个 WAV 初始化预热、7 个 stable service ID、每 NPC 独立 RNG；新 NPC 替换旧声，关面板不停，替换资源不可用时不会遗留旧 NPC 声；`SFX` 与 BGM 的 `Music` 独立。
- 玩家：`PlayerVisual` 在现有 `CLIENT_EFFECT_FRAME` 只向共享服务发送精确 weapon/body-skill event；旧本地 `WeaponAudio` 保持停止，视觉帧与像素合同未改。
- 投射物：`SkillProjectile` 只在 `_ready` 视觉/角色验证成功后发 `.launch`；精确命中目标或有效路径达到射程终点时发 `.impact`。缺投影、快照失效、过期/清理/跨图不会冒充 impact；launch/impact 各有一次门闩。
- 怪物环境声：当前 Enemy 钩子使用自身独立音频 RNG，仅 client frame 1 按主源 1/8 触发，不消耗 gameplay RNG；该钩子已专项通过。服务的 `play_monster_ambient_if_due` 是备用精确 API，当前不重复调用，避免双重抽签。
- 物品：`play_item_event` 只接受 `item:<item_id>`、`service:<serviceIndex>`、`currency:gold`；显示名、类别名和文件名均不是 fallback。
- 通用事件：349 个唯一资源预热；24 声部固定池允许同一事件来自多个 actor 并发，不会因 event ID 相同互相重启。池满时只允许同/更高优先级替换最老的最低优先级声部。

## 工具与验证

`tools/audio/audio_pipeline.py build-exact` 可从主源、canonical skill、canonical monster 三者重新生成资源和合同；`validate` 同时检查 NPC、runtime events、路径存在性及 authoring/runtime 对应关系。

当前纯数据验证：

- `py_compile`：PASS。
- `build-exact`：PASS（33 skills / 153 runtime monsters / 1,152 authoring events / 509 runtime events / 349 unique assets / 727 item identities / 454 item routes）。
- `validate`：PASS（7 NPC bindings / 509 runtime events / 727 item route identities / 0 errors）。

施工期 Godot 证据（扩展前）：

- `tests/audio_runtime_service_test.tscn`：基础版 PASS，`outputs/test_logs/runner_results_adhoc_20260906_143106.json`（当时覆盖 14 NPC/491 event sample、490 runtime events、24 声部池、怪物 exact ID、攻杀男女变体）。全武器/物品/ambient 扩展后的 510 sample、509 event、727 item route 断言已更新，待独占 Godot 时段复跑；不用旧 PASS 冒充当前验收。
- `tests/warrior_client_art_test.tscn`：PASS，`outputs/test_logs/runner_results_adhoc_20260906_143135.json`。确认 `PlayerVisual` 音频 hook 未破坏冻结视觉帧/像素合同，旧 local `WeaponAudio` 仍不播放。
- `tests/town_music_controller_test.tscn`：PASS（14:28:51 同批次中该场景通过；另一音频场景的旧预热实现当时失败，已由 14:31:06 的干净服务 PASS 取代）。

跨域接线合同见 `SFX_CALLPOINTS.md`。
