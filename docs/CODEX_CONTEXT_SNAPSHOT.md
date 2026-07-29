# Codex 精简上下文快照

更新时间：2026-07-29（Asia/Shanghai）

用途：给主任务和专业工作树提供快速、可核实的启动索引，减少重复扫描和重复测试。
准确性规则：本文件不是代码或 Git 状态的替代品；只核实本次任务实际触及的分支、文件、接口和专项测试。

## 30 秒启动顺序

1. 完整读取根目录 `AGENTS.md`。
2. 运行 `git branch --show-current` 和 `git status --short`。
3. 阅读本快照对应专业段落，只打开“最小必读”中与当前问题有关的文件。
4. 专业修改在永久工作树完成；集成主树只调度、审查、逐项合并和验收。
5. 不因本快照而跳过当前证据核实；也不在未触及领域重复全量扫描或旧测试。

## 当前集成基线

- 主目录：`C:\Users\Administrator\Documents\HardCore`
- 分支/运行时代码基线：`codex/integration` @ `eaf6be85`（本次快照提交只改本文档）。
- tracked 状态：黑铁头盔 151 的旧 `scale_100` 六动作生成图集共 6 个既有在制修改继续保护；本次男性头发接入未暂存、覆盖或提交这些旧图。146/147/149/150/151/218/224/228/232 共 9 份已验收人工草稿继续冻结；236/240 最新人工草稿分别为 SHA-256 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`，均保持 dirty 并禁止覆盖。
- 未跟踪状态：既有审计/报告输出与 Godot 生成的 `*.gd.uid` 继续保护，不得顺带清理或提交。
- 当前无待合并专业提交。
- `eaf6be85`（装备提交 `2c6dd064`）按用户最终方案隐藏所有世界人物头盔前层、后层与头部擦除遮罩，只在世界人物上显示经典主客户端 `Hair.wil` 的男性发型 1（男性偏移 0、source block 2）。idle/walk/attack/cast/hit/death 共 232 帧直接按主客户端 Hot 坐标组图，无缩放、旋转、插值或补帧；纸娃娃、背包、地面及 11 份人工草稿均保持冻结。集成专项 6/6、装备全套 17/17、冻结文件 15/15 哈希不变。
- `b4c11258`（装备提交 `7392602`）修复头盔校准跨行为串改：重置当前帧恢复该动作/方向/帧的最近保存值；键盘 `+/-` 只缩放当前姿态；非 idle 撤销不会清除 idle 的未保存公共映射。当时对非 idle 源映射采用的禁改保护已由 `d9c3d11a` 升级为逐姿态独立保存。装备工作树和真实集成基线专项均为 2/2 通过，集成测试前后全部头盔草稿 SHA-256 零变化。
- `d9c3d11a`（装备提交 `98b2dbe`）新增逐动作/人物方向/帧独立的头盔源方向：多个目标可选择同一个 `source_row`，但各自保存位移、横纵缩放与旋转；idle frame 0 公共基准保持原语义。新版草稿以 `poseFrameIndependentSource=true` 显式启用最终生成的逐目标独立烘焙，旧草稿继续走原生成路径。集成校准专项 2/2、无写入最终生成模拟 1/1 通过，全部正式草稿 SHA-256 零变化。
- 来源优先级总表为 `assets/data/source_priority_policy.json`；每个 lane 必须先查 `primary`，只有精确目标确实 `missing` 才允许逐级 fallback。主源不可用、不兼容或效果不符合预期时必须修复解析/映射，禁止换用低级来源。
- 完整资料扫描记录位于 `outputs/resource_catalog/complete_local_mir_sources/catalog.sqlite`（SHA-256 `3a133f39e9a0bf0b065b29778ff4f40d33aaa009ba1bed0a3213ae3a33233c79`）与 `manifest.json`：58 个 distribution、38,887 文件、14,595,954,010 字节、0 未哈希、SQLite integrity `ok`。
- 越级使用审计见 `docs/audit/SOURCE_PRECEDENCE_VIOLATION_AUDIT_2026-07-24.md`。未合并装备提交 `7c37b771` 因跳过主库采用未配置 mylgd 数据已拒绝；不得 cherry-pick。
- primary-only 武器返修已集成为 `2b0da07e`：37 件中 35 件可见、隐藏 0、命运之刃/落魄神兵未解析；木剑、乌木剑、罗刹、噬魂法杖、屠龙均有世界外观，低级库采用数为 0。
- 用户已逐项确认武器与男性衣服外观；冻结提交 `c7489047` 将 37 件武器更新为 36 可见、0 隐藏、仅落魄神兵 1 件视觉未解析，并固定命运之刃、屠龙、炼狱等用户确认映射。
- 装备属性不再走 Crystal `server_data`：`2a61617` 新增独立 `equipment_attributes` lane，唯一主源为 `assets/data/equipment_attribute_master.json`（`equipment.attribute.master.v1` / `project.hardcore.equipment_attribute_master.v1`）。该表覆盖 37 武器与 12 男衣；Crystal 仍是其他服务端数据范围的主源，禁止反向覆盖装备属性。
- 上述装备属性合同已由用户审核工作簿正式升级为 `equipment.attribute.master.v2` / `project.hardcore.equipment_attribute_master.v2`：共 163 条唯一装备，其中 114 条头盔、项链、手镯、戒指审核覆盖；证据 SHA-256 为 `CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D`。`magicEvasionPercent` 与 `magicEvasionPoints` 分离，准确、敏捷和攻击速度档位均进入正式字段。
- `combat.resolution.openmir2.v1` 已接入运行时：物理命中统一为 `Random(敏捷) < 准确`；玩家基础 AntiMagic 为 1 点且只由 `PlayerState` 注入，怪物/通用空目标默认 0；直接法术固定按 AntiMagic → 随机 MAC → 最终扣血结算；攻击速度按 `max(0, 900 - tier × 60)` 毫秒且只影响物理攻击间隔。施毒继续使用独立 AntiPoison。
- `595e485d` 将反向伤害区间明确为 `legacy_clamp_negative_span`：最终跨度 `max-min`，负跨度钳零，绝不交换端点；幸运/诅咒只影响正跨度分布。
- `fcead306` 新增通用 `roll_primary_stat`：signed 总幸运统一作用于正跨度 DC/MC/SC，`+9/-9` 稳定命中上下限；治愈术使用 SC 掷骰，固定效果与施毒独立成功门不受幸运误影响。
- `b7d0ad7b` 完成 `equipment.blessing_luck.v2`：祝福油三结果、固定 5% 负面、幸运 7/诅咒 10、逐级抵消、全部装备基础 `luck-curse`、武器实例幸运/诅咒、零耐久停用和存档恢复均接入；跨度因子固定为 `R=max(1,floor(abs(DCmax-DCmin)/5))`，命运之刃幸运 +3 后可继续提升。
- 用户授权的 `MIR2_176_33技能唯一真源_Codex_v1.0.1.zip` 已提升为 `skills` lane 唯一主源：ZIP SHA-256 `2DAC78D285DFF8D5F1BA36A8B83E0E8F11C70B76ACE15A34EE7FBFB802862A22`，SOT JSON SHA-256 `275555E9F879969E4BB4BECFC268E0ED0912B7D79EF6DEA89731FE43DB0562F7`。共 33 技能、四 rank、150 条 P1 语义合同；旧 360ms 与烈火自动开关决定已被该显式主源覆盖。
- `bb0e5c35`、`06e3479b`、`11b62c06` 将 33 技能生产入口统一接入 canonical Router、六类适配器和 v4 熟练度存档。法师/道士身体施法固定为 6 帧×100ms=600ms；释放点、身体动作、总动作锁和技能冷却分离。烈火为显式一次充能：身体动作 600ms、总动作锁 800ms、独立冷却 8s、充能寿命 10s；800ms 后可普通攻击，8s 内不可再次充能，空挥不消耗，有效近战尝试消费，永不自动释放。
- 技能冷却按稳定 `skill_id` 独立保存于运行时，不再复用共享物理攻击锁；烈火充能只读 UI 快照字段为 `fire_armed`、`fire_expires_remaining_ms`，稳定状态 ID 为 `warrior.fire_sword.charge_armed`，不跨存档恢复。
- `38592e01` + `b779594c` 修正原客户端装备页纸娃娃：Prguse #376 底图按主源码固定绘制于 `(38,52)`，衣服/武器/头盔继续使用 `(31,96)+Hot`；人物选择与装备页各只保留一个纸娃娃，选中存档装备与实时换装均有专项回归。
- `1d74fc72` 将地图外圈由旧圆半径净空升级为 `18×9` 等距椭圆脚底的逐边法向支撑距离；比奇四边真实 CharacterBody 脚点误差统一为 `-0.749978px`，内部碰撞、遮挡、地面坐标、相机和裙边未改。
- `4a52cc54` 与 `b0235f07` 完成最终纸娃娃整改：12 个男性头盔严格由原客户端 StateItem 主资料按原坐标派生透明头部补丁及擦除遮罩，禁止 AI 重绘；人物选择与装备页默认使用高清透明 `classic_avatar`，固定按人物底图→衣服→武器→头盔绘制，完整 Prguse #376 底图、装备槽和矩形背景永不进入玩家界面。三职业×沃玛/祖玛/赤月 9 个独立真实存档、itemId/name-only 旧存档解析、角色选择、装备实时刷新与受控可视截图均通过。
- `cc1edacc` 修复旧/设备存档的世界穿戴身份解析：地图人物现在与纸娃娃统一支持 `item_id`、`itemId`、`itemName`、`name`，稳定 ID 优先，名称只在正式 `equipment_visual_catalog.itemsById` 中精确反查。战士赤月档 itemId 140「天魔神甲」固定加载男性 feature 12 的六动作；ID-only、itemName-only、真实九角色档和 OpenGL 受控截图均通过，不再出现纸娃娃/属性正常但世界衣服退回或消失。
- `d6b4cec3` 按战士技能系统的动作状态机模板接入法师 14 项、道士 12 项主动技能的正式主资料动画与选帧图标；来源只使用 `Magic.wil`、`Magic2.wil`、`Mon3.wil`、`Mon18.wil` 及原客户端规则代码，没有分级库 fallback。道士被动 `taoist.spiritual_warfare` 的主源没有施法事件，保持 `no_runtime_visual`，禁止伪造动画。
- `841c3e57` 将上述 26 个法师/道士主动技能图标接入技能面板、HUD 快捷栏和攻击环；4 个战士既有图标及优先级保持不变，所有法道主动技能禁止回退为背包物品缩略图。
- 越级审计列出的其余领域尚未返修完成，禁止写成已完成。明日从审计文档按优先级继续：装备图标/属性与旧穿戴、怪物/Boss 数值与外观、掉落、技能、头盔锚点及服务端规则生成器；每一项都必须先修主源解析或映射，再运行对应专项测试并逐项集成。
- 用户已确认此前截图来自当时最新 APK；不要再次怀疑或重复核验安装版本。用户已实机确认碰撞、装饰物遮挡、地图错位和视角全部解决，四项正式冻结；除非出现新的明确证据，后续任务不得顺带调整。
- 用户已实机确认 214 个 `monster_id` 逐个、逐姿态人工复核的 v4 怪物脚下光圈正确，正式冻结；除非出现新的明确证据，禁止顺带修改脚点、光圈中心、椭圆尺寸或投影策略。
- 战士/法师/道士 × 沃玛/祖玛/赤月的 9 个独立满技能测试人物已进入最新 APK；三职业装备外观仍需按原客户端正式素材重新取证，不能再将装备栏缩略图或带窗口背景的 raw stateitem 图当作纸娃娃/世界穿戴层。
- 装备显示使用男性专用正式管线：原客户端装备页纸娃娃、男性世界衣服与男性世界武器继续使用正式素材；12 个男性世界头盔素材和校准数据保留但运行时隐藏，世界人物改为经典主客户端男性完整头发动作。新增或重建世界穿戴资源禁止生成女性资产。
- 头盔概念表的格子顺序不可信。每个视觉身份必须保存显式 `sourceSlotDirectionOrder`，再重排为 `N,NE,E,SE,S,SW,W,NW`；方向重复或缺失必须阻断构建，禁止猜测。

## 最终 APK

- 状态：下列 APK 是 12:10 的上一版测试包，尚未包含 `4a52cc54` 与 `b0235f07` 的最终纸娃娃整改；用户要求先确认截图，因此当前未重新构建 APK。
- 文件：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-debug.apk`
- 构建时间：`2026-07-26 12:10:58`
- 大小：`1,653,572,428` 字节
- SHA-256：`1117D14E37960025E0D1C2205E960CA38A8D76B668FE5F295A91C824F6488E8A`
- 包信息：`com.personal.mafaoffline`，versionCode `35`，versionName `1.16.0-bich-map-runtime`，应用名 `HardCore`，`arm64-v8a`。
- 签名验证：APK Signature Scheme v2/v3 均通过，签名者 1。
- 本包包含 214 种怪物逐 ID v4 光圈校准、9 个三职业三套装满技能独立测试人物、男性专用正式人物与装备显示管线、`world_avatar`/`classic_avatar` 双模式纸娃娃、primary-only 世界武器兼容合同、正式装备视觉目录、神兽动画、人物列表触摸滚动、法师/道士360ms施法动作与移动锁、26 个法师/道士主动技能的主资料动画和选帧图标，以及等距椭圆脚底四边地图边界修复；角色存档只补建缺失项，不覆盖后续测试进度。

## 最近已集成结果

| 集成提交 | 领域 | 结果 |
|---|---|---|
| `d639aa85`、`28e64994`（装备专业提交 `8545045`、`ad3b1ad`） | equipment/integration | 头盔校准工具新增按“动作＋方向＋帧”独立保存的无损姿态参数：方向键每次 0.5px 只调整当前帧，右键菜单支持横向/纵向分别 ±5%、整体 ±5%、向左/向右各 5°、旋转归零和当前帧全部变换重置。高清覆盖层使用真正的非等比显示变换，横向调整只改变宽度、纵向调整只改变高度，不再被保持宽高比模式重新等比适配。动作栏继续完整覆盖 `idle/walk/attack/cast/hit/death`，并新增所有动作帧的直接按钮；death 明确显示 0 起始、1 后仰、2 倒地、3 躺地。可选 `poseTransforms` 向后兼容旧 `equipment.helmet.calibration_draft.v1`，保存只写参数，预览直接变换原始 RGBA，不生成或压缩图片。11 份人工草稿 SHA-256 逐项未变；装备树和集成树无损校准、映射编辑、头盔运行时、男性世界穿戴专项均通过。 |
| `3618db9d`（装备专业提交 `59a98606`） | equipment/integration | 纠正最终化后校准工具错误读取低分辨率运行时纸娃娃合同的问题。编辑器恢复为用户保存时的独立高清校准视图：11 个目标固定使用保存当时的纸娃娃参考矩形，世界八方向、纸娃娃、背包和地面继续直接读取冻结的原始 RGBA 切片；运行时素材替换不得反向改变编辑器中的大小或位置。240 天尊纸娃娃恢复为保存时的 `32×41` 参考矩形、`65%`、位置 `(263,136.5)`，不再使用最终化后 `18×29` 的运行时成品反推。11/11 人工草稿 SHA-256 逐项未变；集成树校准布局与映射编辑器专项 2/2 通过。 |
| `c2d9048a`、`2c396d7f`（装备专业提交 `8ba485dd`、`02fedb7b`） | equipment/integration | 用户完成的 11 个视觉身份、12 个头盔 ID 已正式最终化并接入游戏主体。每个身份从冻结高清草稿直接生成 `idle/walk/attack/cast/hit/death` 六动作、八方向及全部动作帧；按人物动作逐帧头部枢轴平移，只在动作轮廓确实需要时使用有界二维二阶矩形变，保持每个方向原始长宽比例。世界、纸娃娃、背包、地面均从各自选定原素材直接做一次预乘 Alpha Lanczos 压缩，运行时固定 nearest/`1x`，禁止二次压缩。最终合同为 `equipment.helmet.finalization.v1`，确定性哈希 `344A59D31259810F577E000375C6EB1F7D0989E58A1369CA0C2F00CA434B442B`；Windows 对人工草稿及四份最终合同均禁用行尾转换，首次检出不会产生无意义回写。11/11 人工草稿 SHA-256 前后完全一致。Python 头盔专项 17/17、Godot 头盔专项 10/10、装备套件 17/17、全局冒烟 1/1 通过。 |
| `2daf3513`（装备专业提交 `1bf2f4ba`） | equipment/integration | 240 天尊头盔进入“只校准、不烘焙”阶段：用户提供的 1774×1333 RGBA 十图原稿（SHA-256 `B82153C7888F258EA783A24BCB43A6302C3C52EF58BC66310A52C6EC2E6B39C7`）是标准 4×3 网格，前8格按 `N/NE/E/SE/S/SW/W/NW` 仅作 Alpha 有效边界裁切，保持 203–239×354–361px 原始长宽，透明世界图集为 956×722px；第三排第1格 208×354px 固定为 `dedicated_inventory`，第2格 214×356px 固定为 `dedicated_ground`，后两格为空且不参与方向映射。校准工具新增对称的“地面专用”第九项、预览与草稿保存合同，背包/地面默认各自选中专用源；全程不清底、不改用户镂空、不改色、不重采样、不提前压缩，当前活动目标切换为 `item_id=240` / `visualAssetId=heavenly_taoist`。旧 240 正式世界六动作、纸娃娃、背包、地面与在制天尊六动作生成图集均保持冻结；146/147/149/150/151/218/224/228/232/236 人工草稿及正式 override 未变。Python 无损/冻结守卫 14/14、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `c3326ece`（装备专业提交 `5973dbd3`） | equipment/integration | 236 法神头盔进入“只校准、不烘焙”阶段：用户提供的 1448×1086 RGBA 八方向原图（SHA-256 `604E257C431C7E963D76D2BC4FDC21AE93BC099C5B114AD7C214B23F482E8EFA`）按上排 `N/NE/E/SE`、下排 `S/SW/W/NW` 使用每格完整 Alpha 并集边界裁切，八张方向图保持各自 287–346×291–312px 原始长宽，透明编辑器图集为 1384×624px；`N/NE/NW` 的左右角与头环主体分别保持 3 个独立 Alpha 连通部件及原始间距，未按单部件裁切、未重新拼接。全程不清底、不改用户镂空、不改色、不重采样、不提前压缩，当前活动目标切换为 `item_id=236` / `visualAssetId=god_magic`。旧 236 正式世界六动作、纸娃娃、背包、地面与在制法神六动作生成图集均保持冻结；146/147/149/150/151/218/224/228/232 人工草稿及正式 override 未变。Python 无损/冻结守卫 12/12、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `ede3c10f`（装备专业提交 `a0cb7d28`） | equipment/integration | 232 圣战头盔进入“只校准、不烘焙”阶段：用户提供的 1448×1086 RGBA 八方向原图（SHA-256 `486B7FB95AF5F24B61D0FECFB9BBD22F9B1E3550189C5CEDC1B8D264452DBEC2`）按上排 `N/NE/E/SE`、下排 `S/SW/W/NW` 仅作每格 Alpha 有效边界裁切，八张方向图保持各自 227–316×363–405px 原始长宽，透明编辑器图集为 1264×810px；灰色仅存在于透明像素 RGB，未清底、未重新抠图、未改色、未重采样、未提前压缩，当前活动目标切换为 `item_id=232` / `visualAssetId=holy_war`。旧 232 正式世界六动作、纸娃娃、背包、地面与在制圣战六动作生成图集均保持冻结；146/147/149/150/151/218/224/228 人工草稿及正式 override 未变。Python 无损/冻结守卫 10/10、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `17675bfc`（装备专业提交 `c3a9abe9`） | equipment/integration | 228 记忆头盔进入“只校准、不烘焙”阶段：用户提供的 1448×1086 RGBA 八方向原图（SHA-256 `ED3AA3AAE0C106110C24CCBF43A17E71E2D7C418E2ECDBC12E996CF74B3624E6`）按上排 `N/NE/E/SE`、下排 `S/SW/W/NW` 仅作每格 Alpha 有效边界裁切，八张方向图保持各自 270–298×407–417px 原始长宽，透明编辑器图集为 1192×834px；不清底、不重新抠图、不改色、不重采样、不提前压缩，当前活动目标切换为 `item_id=228` / `visualAssetId=memory`。旧 228 正式世界六动作及其东西向修补合同、纸娃娃、背包、地面、正式 override 均保持冻结；146/147/149/150/151/218/224 人工草稿未变。Python 无损/冻结守卫 8/8、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `694ee5a4`（装备专业提交 `dedc613a`） | equipment/integration | 224 祈祷头盔进入“只校准、不烘焙”阶段：用户提供的 1448×1640 RGBA 九图原稿（SHA-256 `7BA8D678D6902411E5D1EB25891E3EBD67DDC606A345F2B43ABBD3D172AE3AD5`）前两排按 `N/NE/E/SE/S/SW/W/NW` 仅作 Alpha 有效边界裁切，保持 267–287×387–411px 原始长宽；第三排未扣除面部的 274×411px `S` 单独保存为 `dedicated_inventory` 并作为背包默认第九项，不参与世界方向映射。全程不清底、不重新抠图、不修改脸窗、不改色、不重采样；当前活动目标切换为 `item_id=224` / `visualAssetId=prayer`。正式世界六动作、纸娃娃、背包、地面、正式 override 和主树在制 prayer 图集均未改，146/147/150/151/218 人工草稿保持冻结；Python 无损/冻结守卫 6/6、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `c289f93b`（装备专业提交 `f4be0e35`） | equipment/integration | 218 神秘头盔进入“只校准、不烘焙”阶段：用户提供的 1774×1343 RGBA 九图原稿（SHA-256 `8C4990E164B528A09833B55B99D94C51F3D254ECF4BF7A3B3A71815621232063`）前两排按 `N/NE/E/SE/S/SW/W/NW` 仅作 Alpha 有效边界裁切，保持 272–312×376–381px 原始长宽；第三排未扣除面部的 281×376px `S` 单独保存为 `dedicated_inventory` 并作为背包默认第九项，不参与世界方向映射。全程不清底、不重新抠图、不修改脸窗、不改色、不重采样；当前活动目标切换为 `item_id=218` / `visualAssetId=mystery`。正式世界六动作、纸娃娃、背包、地面、正式 override 和主树在制 mystery 图集均未改，146/147/150/151 人工草稿保持冻结；Python 无损/冻结守卫 5/5、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `c7a081d9`（装备专业提交 `770c86b8`） | equipment/integration | 151 黑铁头盔进入“只校准、不烘焙”阶段：用户提供的 1491×1055 RGBA 八方向原图（SHA-256 `917B2BBFDA8463B509B61866EA3E125AD77FFB68288D5F52C199526F5AFD79FF`）已经包含真实 Alpha，洋红仅存在于透明像素 RGB；按上排 `N/NE/E/SE`、下排 `S/SW/W/NW` 仅作每格 Alpha 有效边界裁切，不清底、不重新抠图、不改色、不重采样。八张方向图保持各自原始长宽（255–294×367–393px），透明编辑器图集为 1176×786px；当前活动目标切换为 `item_id=151` / `visualAssetId=black_iron_golden_151`。正式世界六动作、纸娃娃、背包、地面、正式 override 及主树中在制黑铁六动作生成图集均未改，146/147/150 人工草稿保持冻结；Python 原图逐像素/冻结守卫 4/4、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `55651fe4`（装备专业提交 `394715a7`） | equipment/integration | 头盔校准工具的世界外观缩放下限由 50% 放宽为 5%，继续保持每次 5% 的右键/快捷键步长；界面控件、会话覆盖、草稿校验和最终单次烘焙校验统一使用 `WORLD_SCALE_MIN_PERCENT=5`，避免只改按钮后保存被拒绝。纸娃娃缩放范围未改；146/147/150 人工草稿与正式 override 哈希保持不变。装备树与集成树 Godot 校准专项均 4/4 通过。 |
| `b387172c`（装备专业提交 `0a58a866`） | equipment/integration | 150 骷髅头盔进入“只校准、不烘焙”阶段：用户提供的 1491×1055 RGBA 八方向原图（SHA-256 `DE5753D3B36797D0937967032BE238B3CDE55582588FF4B99D42794740605C0D`）按上排 `N/NE/E/SE`、下排 `S/SW/W/NW` 仅作每格 Alpha 有效边界裁切；保留用户已有透明像素、半透明边缘和脸部镂空，不清底、不补洞、不改色、不重采样。八张方向图保持各自原始长宽（279–364×403–431px），透明编辑器图集为 1456×862px；当前活动目标切换为 `item_id=150` / `identityId=skeleton`。正式世界六动作、纸娃娃、背包、地面与 override 均未改，146/147 人工草稿哈希保持不变；Python 原图逐像素/冻结守卫 3/3、Godot 校准专项 4/4 在装备树与集成树均通过。 |
| `50e10061`（装备专业提交 `ac743c73`） | equipment/integration | 146 精灵、147 青铜与149 道士头盔的校准预览统一改为“原始RGBA纹理+非破坏显示变换”：世界人物卡不再先把头盔压进低分辨率人物帧，而是按每方向自己的原始宽高、人物头部锚点、独立位移与独立5%比例挂载高清纹理层；八方向源图、纸娃娃、背包与地面均直接使用原始纹理，地面不再复用64×64方向缩略图。保存仍只写参数，正式游戏图集必须等用户明确要求加载时才从原图统一单次压缩。草稿加载链现以最新草稿中的源路径/哈希为优先，使当前149目标下重新选择146/147时仍恢复各自原切片；146/147草稿和正式override哈希均未改变。Python原图/冻结守卫2/2、Godot校准专项4/4通过。 |
| `f6cec727`（装备专业提交 `5be70aa5`） | equipment/integration | 149 道士头盔进入“只校准、不烘焙”阶段：用户提供的 1350×1637 PNG（SHA-256 `27A87E2CF4E49D3E6FD093A6330F6EE55921908ED074AB486EA0A72262F41408`）已经包含完整 Alpha，严格禁止清底、重新抠图、修改脸窗或重采样；仅按 Alpha 有效边界逐像素裁出 `N/NE/E/SE/S/SW/W/NW` 八张 225–245×365–385px 原始 RGBA 世界方向图，以及第九张 232×378px 黑色脸内层正面图。第九张作为独立 `dedicated_inventory` 进入背包下拉第九项“背包专用”并默认选中，不参与八方向映射；纸娃娃与地面仍从八方向选择。正式世界六动作、纸娃娃、背包、地面与 override 均未改，146/147 用户草稿哈希保持不变；Python 逐像素裁切/冻结守卫 2/2、Godot 校准专项 3/3 通过。 |
| `12601d14`（装备专业主提交 `ce60df1a`，测试跟进至 `b027ed66`） | equipment/integration | 头盔校准工具的世界外观与纸娃娃方向键微调由每次 1px 降为每次 0.5px；半像素只允许进入校准会话、未最终化草稿和隔离测试 override，正式运行时 override 继续执行整数像素合同，等待最终高清单次烘焙。世界方向与纸娃娃右键缩放菜单统一使用工具视口鼠标坐标，并在鼠标旁 12px 显示、受视口边界约束，不再混用桌面全局坐标。真实 `item_146` 用户草稿 SHA-256 `F7130C45C2837AD2819D57BBED939710A1FE25C2784A44A23368F9E4183DEC40` 及正式 override/在制图集均未改；测试同时修正为验证原高清切片直接单次缩放，禁止用二次缩放结果作预期。装备树及集成树校准专项最终 3/3 通过。 |
| `d47b5a50`（装备专业提交 `16f25289`） | equipment/integration | 146 精灵头盔进入“只校准、不烘焙”阶段：用户提供的 1448×1086 原图按 `N/NE/E/SE/S/SW/W/NW` 清除连通白色/洋红背景并无缩放切成八张约 294–301×204–242px 的透明原分辨率方向图；校准工具启动后自动选中 `item_id=146`，只在会话中建立八方向一一对应映射，可正常切换、微调和保存草稿。正式世界六动作、纸娃娃、背包、地面与运行时 override 均未改；最终单次压缩和游戏接入留到用户完成全部校准后统一执行。Python 单目标回归及 Godot 校准工具专项 2/2 通过。 |
| `4fea1e60`（装备专业提交 `5d9aec69`） | equipment/integration | 仅重建 147/148 共用的 `identityId=bronze_magic` 世界六动作图集：从 SHA-256 `8D5B9B4AF6E28947CB4437D5F09EA8F26FD8822B4D589D619A8153EDA37504EE` 的 1774×887 透明八方向母图直接进行预乘 Alpha + Lanczos 单次缩放，运行时保持 nearest/`1x`；232 个方向帧单元的有效包围盒与返修前逐项一致，只替换框内像素。新增精确单目标重建器与冻结哈希守卫；147/148 纸娃娃、擦除遮罩、背包、地面及 `item_147` 人工草稿哈希均未变化。Python 单目标回归、Godot 校准工具与共享身份专项通过。 |
| `623e44e`（UI 专业提交 `a9ef38b0`，装备专业提交 `623e44e`） | UI/equipment/integration | 修复头盔校准纸娃娃：`classic_avatar` 头发现在读取正式 `avatarOnly.stagePosition=[80,44]`，与人物/衣服共用 168×199 画布，不再漂到左上或显示光头；纸娃娃头盔从错误的原图 25% 改为按当前物品正式头部补丁尺寸与位置建立 100% 基准，高分辨率原切片只改变显示矩形、不产生中间重采样；旧 `[110,32] + 25%` 草稿只对该精确旧默认自动迁移，其他人工参数保持不变。点击纸娃娃区域后方向键每次移动头盔 1px，世界方向坐标不受影响；点击世界两排后恢复世界方向微调。集成专项 5/5 通过，正式 override 与冻结生成图集哈希未变。 |
| `e0110944`（专业提交 `df6fc7da`） | equipment/integration | 头盔校准改为无损两阶段：透明 4×2 原图固定按 `N,NE,E,SE,S,SW,W,NW` 切为 8 张原分辨率 PNG 并逐张保存 SHA-256，不做方向扫描；世界八方向各自支持右键 ±5%，下方放大人偶/头部从可见界面移除；新增战士赤月套装纸娃娃拖放/缩放/八向选择、背包选向和地面选向。保存只写 `equipment.helmet.calibration_draft.v1`（`runtimeReadable=false`、`finalized=false`），正式 override 与运行图集保持不变；最终加载函数未接 UI 按钮，只允许用户全部确认后从原切片单次 Lanczos 生成、运行时 nearest/`1x`。装备工作树与真实集成基线专项均 6/6 通过。 |
| `54c6222e`、`da77aa14`（专业提交 `5219aff6`、`449a1f6`） | equipment/integration | 天尊头盔 `item_id=240` / `identityId=heavenly_taoist` 使用用户提供的 `1448×1086` 洋红底八方向原图完成单目标替换：上排 `N/NE/E/SE`、下排 `S/SW/W/NW`，源图 SHA-256 `A5E474DA3C081AD2F5DD0926BD9DD1358E4179737E6B8D5614A77CF7B2BA9E8E`。六动作世界 atlas 保持 `192×160px` 单元、nearest/`1x`，实际八方向内容为 `10×16/10×18/14×20/14×23/12×21/15×23/13×20/10×17px`，全部不超过正式客户端方向包围盒；纸娃娃 `32×41px` 画布内内容 `13×24px` 并保留透明脸窗，背包 `36×35px`、地面 `16×17px` 同源单次烘焙。v2 映射、动作 SHA、纸娃娃/背包/地面合同同步；非 240 合同与 224 个冻结素材逐项零变化。Godot 运行时验收 7/7、装备套件 17/17、单目标 Python 回归通过。 |
| `8506bcef`（专业提交 `b64702b`） | equipment/integration | 圣战头盔 232 从用户确认的 `1536×1024` 高清八方向母图直接以预乘 Alpha + Lanczos 单次烘焙，禁止复用上一版低分辨率成品；八方向高度逐项保持为 `23/21/20/22/23/22/22/23px`，横向直径缩为约 80%，语义 bbox 固定为 `17×23/13×21/12×20/14×22/15×23/13×22/12×22/14×23px`。纸娃娃内容为 `19×29px`，保持全封闭 `no_cutout`、运行时 nearest/`1x`、既有方向映射/pivot/nudge 不变；146/147/149/150/151 只读像素参数审计、非 232 冻结哈希与 Godot 集成专项均通过 |
| `80de01b1`（专业提交 `e5910aa`） | equipment/integration | 仅将法神头盔 236 世界穿戴层在当前基础上再缩小 10%：原始高清源单次 Lanczos 烘焙，atlas 单帧仍为 `192×160px`，实际头盔最大 `14×17px`，运行时 nearest/`1x`；纸娃娃、擦除遮罩、背包和地面四文件 SHA-256 前后逐项一致，真实角色八方向合成与 Godot 集成专项 6/6 通过 |
| `0f134e74`（专业提交 `f539c19`） | equipment/integration | 按用户复核从 `1774×887` 原图重新单次烘焙法神头盔 236，不复用上一版小图；在 `443c08c8` 基础上再缩小约 18%，世界八方向为 `13–15×18–19px`，纸娃娃内容 `17×24px`。烘焙使用 Lanczos、运行时 nearest，并清除 `alpha≤3` 的绿幕亚像素残边；真实角色八方向合成与 Godot 集成专项 6/6 通过 |
| `443c08c8`（专业提交 `bae1d81`） | equipment/integration | 修正法神头盔 236 尺寸漏检：世界八方向由 `24–29×35–36px` 收敛为 `16–19×22–23px`，与当前圣战头盔使用同一 `0.64` 烘焙比例、nearest 像素缩放及运行时 `1x`；纸娃娃内容限制为 `24×29px`，真实角色八方向合成与 Godot 集成专项 6/6 通过 |
| `165f3500`（专业提交 `c6ac7b01`） | equipment/integration | 法神头盔 `item_id=236` / `identityId=god_magic` 按圣战头盔同类单目标流程完成八方向、六动作、纸娃娃、背包与地面素材替换；用户原图 SHA-256、全遮脸、方向映射与非 236 零变化守卫通过，Godot 集成专项 5/5 通过 |
| `0268128`、`bf8bff64`、`d51f4aeb` | UI/integration | 烈火 UI 固定显示“主动充能/充能/未充能·就绪”，只读 canonical charge 快照，彻底移除旧开关文案 |
| `11b62c06` | skills/integration | stable skill ID 独立冷却；烈火 600ms 身体、800ms 动作锁、8s 冷却与10s充能寿命分离 |
| `06e3479b` | skills/player | 废止烈火自动开关，旧存档 auto 仅迁移为 false，正式状态 ID 改为 `warrior.fire_sword.charge_armed` |
| `bb0e5c35` | integration/runtime | 33 技能生产入口、六类适配器、法道正式视觉、v4 技能进度存档与中文旧名迁移 |
| `df7738ec`、`1e427621` | skills/tests | 169 条包合同绑定；150 条 P1 均由真实 Callable 执行语义验证，无缺项或多项 |
| `da791b22`、`45d10fc2`、`988bb0bc`、`9b4105b6`、`16f442da` | skills | 33技能唯一真源、进度/施法服务及战士/法师/道士 canonical runtime |
| `49637d0d` | rules | `skills` lane 主源提升为用户授权的 1.0.1 唯一真源包并加入来源守卫 |
| `cc1edacc` | equipment/player | 旧存档四字段世界穿戴解析；战士赤月天魔神甲 itemId 140 / feature 12 六动作与非透明截图通过 |
| `b0235f07` | UI | 人物选择/装备页使用透明高清 `classic_avatar`；完整装备页与内置槽位禁入玩家界面；9 个真实存档和 name-only 旧存档均通过 |
| `4a52cc54` | equipment | 12 个男性头盔由原客户端 StateItem 主资料派生透明头部补丁与擦除遮罩，禁止 AI 生成素材进入运行时 |
| `841c3e57` | UI | 26 个法师/道士主动技能在技能面板、快捷栏和攻击环使用主资料动画选帧图标；4 个战士图标冻结不变 |
| `d6b4cec3` | skills | 按战士动作状态机模板接入法师14项、道士12项主资料动画与图标；1项道士被动明确无施法视觉 |
| `c4257bfc`、`fa0ccd50`、`8223dda1` | equipment/UI | 纸娃娃双模式合同与玩家界面 `world_avatar`；`classic_avatar` 保留透明分层，完整装备页仅审计 |
| `345d073` | rules | 专业工作树开工前必须同步/锁定集成基线，交付后必须在当前主树复验，禁止旧基线假通过 |
| `1d74fc72` | maps | 外圈边界按当前等距椭圆脚底逐边求支撑距离；比奇四边与全部发布地图物理边界专项通过 |
| `8c7f6b4a` | maps/tests | 新增比奇四边真实 CharacterBody 边界对称性回归 |
| `b779594c` | UI | 人物选择/装备页单一纸娃娃、选中存档装备读取、实时换装刷新与触摸穿透 |
| `38592e01` | equipment | 按 FState.pas 修正 Prguse #376 `(38,52)` 底图坐标与单层合成合同 |
| `d2b8ab8` | skills/player | 法师/道士360ms施法身体动作与移动锁；释放点、冷却、施法速度和长特效时序完全分离 |
| `c1839b4` | integration/runtime | 玩家受直接法术统一转交 `take_direct_spell_damage`，禁止重复 MAC、物防或二次扣血 |
| `228063c` | integration/runtime | 火球、大火球、雷电、灵魂火符稳定技能 ID 与 AntiMagic/MAC 运行时接线 |
| `3700cd1d` | skills | 直接法术与施毒实际命中闭环；AntiMagic 与 AntiPoison 隔离 |
| `3d84db6c` | UI | 魔法躲避显示百分比，准确/敏捷显示点数，攻击速度显示档位 |
| `f85e6941` | skills/player | 装备 v2 魔闪内部点与攻击速度档位进入玩家聚合 |
| `555080da` | skills/player | 准确/敏捷严格命中、AntiMagic 与物理攻速统一规则 |
| `4130b5ac` | rules/integration | 来源优先级正式提升到装备属性主表 v2 |
| `e28fa1e5` | equipment | 导入用户审核工作簿，163 条正式装备属性与 v2 Schema |
| `b7d0ad7b` | equipment | `equipment.blessing_luck.v2`、R=0 边界修正、全部装备 luck/curse 汇总、消耗/耐久/存档回归 |
| `fcead306` | skills/player | 通用 `roll_primary_stat` 与 DC/MC/SC、治愈术、固定效果、反向区间专项 |
| `2a61617` | rules/integration | 装备属性独立主源 lane、项目正式主表授权、来源守卫与装备测试入口 |
| `26df7993` | equipment | 49 条武器/男衣属性正式主表、结构化需求/定位/性别/负重、反向区间 warning、炼狱 feature22 回归 |
| `595e485d` | skills/player | `legacy_clamp_negative_span` 统一 DC/MC/SC 反向区间、普通攻击与技能实际接线 |
| `c7489047` | equipment | 冻结用户逐项确认的武器与男性衣服世界外观映射 |
| `2b0da07e` | equipment | 主源专用武器兼容合同；35/37 可见、0 隐藏、2 未解析，职业与实体造型双轴分离 |
| `62a7c00` | audit | 固化主库/分级库越级审计，列出 13 类确定违规及逐域返修顺序 |
| `9512dbb` | rules | fallback 收紧为只有 primary 明确 missing 才允许；unusable/incompatible 必须修复而非降级 |
| `3eebf00` | rules | 总纲加入数据库与资料源 primary-first 硬规则 |
| `7bd71d5d` | equipment | 男性世界头盔扩展：12 itemId、11 视觉身份、6 动作、8 方向、2784 逻辑帧；方向显式识别与重排 |
| `a00fb90` | rules | 集成主任务成为唯一项目内审批者，禁止把子任务审批、取舍或测试确认转交用户 |
| `3e3510fa` | integration/tests | Godot 自动化固定使用 console/headless、安全 runner、项目内日志与隔离 APPDATA，避免 Windows c0000005 弹窗 |
| `5543fd9c` | equipment | 男性世界武器合同：37 件正式武器，31 件可见、2 件经典隐藏、4 件待原始证据 |
| `94ebf0a7` | equipment | 男性世界衣服合同：12/12 男性衣服、6 动作、8 方向 |
| `fe539a1d` | equipment | 原客户端男性装备页纸娃娃资源阶段与完整 StateItem 坐标溯源 |
| `c88c6277` | monsters | 214 种怪物逐 ID 独立人工复核脚点、光圈中心、椭圆尺寸与地面/飞行/悬浮策略 |
| `5fd35f07` | integration/tests | 覆盖男女基础外观、实时换装和运行时性别刷新 |
| `ae5e800f` | integration/tests | 更新旧回归断言，法师正式人物层不再隐藏 |
| `edcb989b` | equipment/tests | 装备图集画布与脚点测试改为读取正式视觉目录 |
| `f6290510` | integration | 接入战士、法师、道士正式人物基础、衣服、武器与头盔运行时外观 |
| `5eba6942` | equipment | 175 件正式装备目录、73 个可视穿戴项与 456 张世界穿戴动作图集 |
| `a78222ac` | UI | 人物列表支持整块区域触摸滑动；装备界纸娃娃居中 |
| `466f261a` | skills | 道士神兽正式动画接入 |
| `8165123` | integration | 自动补建 9 个独立三职业三套装满技能测试人物，且不覆盖既有测试进度 |
| `07fe41d4` | equipment | 9 套沃玛/祖玛/赤月正式装备目录，共 72 个装备槽 |
| `b23ed8d0` | monsters | 214 种怪物按动作和方向使用稳定真实脚底接触点 |
| `2809e74a` | skills | 三职业完整 33 技能模板与 9 个稳定人物配置 ID |
| `23e14745` | integration | 接入人物中心 ±14% 柔性镜头与帧率无关的 1.06–1.16 动态缩放 |
| `8f522258` | monsters | 214 个怪物逐 ID 使用八方向 idle 真实身体顶点固定头顶锚点 |
| `f7165027` | maps/docs | 明确人物位于屏幕坐标 36%–64% 的中央带 |
| `aa75736a` | maps | 柔性边缘相机 v2 与不可行走渐暗地图外裙边 |
| `956393cf` | integration | Camera2D 以视口侵蚀后的地图菱形约束中心，避免暴露地图外区域 |
| `c4af44a1` | monsters | 怪物物理脚底改为 2:1 等距椭圆，战斗/AI 标量半径不变 |
| `1b7e53da` | skills/player | 玩家物理脚底改为 18×9 等距椭圆 |
| `46cfcd27` | maps | 统一真实地图边界、遮挡深度 v5 与菱形相机约束服务 |
| `1a67e76f` | integration | 新增共享等距脚底契约 `world.actor_footprint.iso_ellipse.v1` |
| `4e022999` | monsters | 冷启动异步贴图激活后重新计算固定头顶层 |
| `e0165bef` | UI | 血球/蓝球恢复到框体孔径；2664×1200 安全区布局 |
| `4957b340` | maps | 房屋/树木遮挡阈值修正；角色脚点可达可见地图边缘 |
| `4ffe67eb` | monsters | 最终复合头顶层固定为身体→血条→名字 |
| `72ad3e46` | maps | 编辑器画面几何统一应用到运行时实例 |
| `ce42d172` | UI | 拾取提示按安全视口居中 |
| `a56e65e1` | UI | 技能配置弹窗背景约束到弹窗范围 |
| `48fea9bc` | skills | 烈火冷却归零立即恢复 ready |
| `f82717f6` | integration | 快捷技能配置接线与烈火自动开关运行时 |
| `8860c012` | rules | 除删除现有文件/数据外直接执行，不再询问 |

当前关键契约：

- integration：`world.actor_footprint.iso_ellipse.v1`、`test.character.roster.full_equipment_skills.v1`。
- maps：`map_editor_runtime_collision_geometry_v2`、`map_visible_edge_actor_footprint_clearance_v2`、`published_blocked_cells_after_erasure_v1`、`map_editor_runtime_visual_geometry_v5`、`map_actor_occlusion_sort_v5`、`map_diamond_camera_center_constraint_v2`、`player_priority_soft_edge_v1`、`map_runtime_nonwalkable_edge_skirt_v1`。
- monsters：`monster.overhead_anchor.v4`、`monster.overhead_layout.v3`、`monster.ground_contact.v4`、`monster.ground_contact.calibration.v4`；214 个 `monster_id` 各自保存人工复核的脚点、光圈中心、椭圆尺寸和投影策略，贴图异步激活后必须刷新。
- UI：`ui.hud.resource_orb.hole_fill.v1`、`skill_button_assignment_contract_v2`、`ui.hud.skill_icon.caster.<stable_skill_id>`。
- equipment：`equipment.attribute.master.v2`、`project.hardcore.equipment_attribute_master.v2`、`equipment.test_loadouts.classic_three_tiers.v1`、`equipment.visual_catalog.formal_wearables.v1`、`equipment.paper_doll.presentation_modes.v1`、`equipment.paper_doll.world_avatar.v1`、`equipment.paper_doll.avatar_only.v1`、`equipment.paper_doll.original_client_stage.v1`、`equipment.paper_doll.classic_flattened_head_patch.v1`、`equipment.helmet.calibration_draft.v1`、`equipment.helmet.presentation_calibration.v1`、`equipment.world_wear.male_dress.v1`、`equipment.world_wear.male_weapon.v1`、`equipment.world_helmet.male.extension.v1`、`equipment.world_helmet.runtime_visibility.v1`、`equipment_actor_visual_sort_unit_v3` 与 9 个 `test.loadout.{profession}.{tier}.v1`。
- skills：`skills.runtime_router.cn_mir2_176.v1`、`skills.progression.cn_mir2_176.v1`、`skills.production_adaptation.hardcore.v1`、`warrior.fire_sword.charge_armed`、`combat.resolution.openmir2.v1`、`physical.hit.random_agility.strict_lt.v1`、`magic.evasion.anti_magic.direct_spell.v1`、`physical.attack_speed.interval_tier.v1`、`player.direct_spell_damage.openmir2.v1`、`caster_skill_animation.v1`、法师/道士主动技能 `action_duration=0.60` / `action_frame_count=6` / `action_frame_time_ms=100` 时序字段、`legacy_clamp_negative_span`、`test.characters.full_skills.v1` 与 9 个 `test.character.{profession}.{woma|zuma|chiyue}.v1`。

## 已通过的必要验收

- 总回归：`SMOKE_TEST_PASS`。
- integration：共享 36×18 等距脚底契约通过；运行时 Camera2D 菱形视口约束通过。
- camera：2664×1200 下人物屏幕偏移≤全尺寸 14%，动态缩放为 1.06–1.16；80×80 与 38×38 地图外露均由 1536px 不可行走裙边覆盖。
- monsters：v4 数据生成检查、214/214 人工复核覆盖、214 种怪物五动作八方向运行时坐标链、214/214 冷激活、完整怪物客户端美术通过。
- test roster：9 个独立存档、72 个正式装备槽、99 个角色技能加载项、三职业选择恢复和二次启动不覆盖通过。
- player/equipment：原客户端男性装备页纸娃娃、男性世界衣服、男性世界武器、经典男性完整头发动作、实时换装、正式装备视觉目录、装备纸娃娃居中和战士旧回归通过；世界头盔与头部遮罩全动作隐藏，头盔正式素材仍可解析；天魔神甲真实赤月档及 `item_id`/`itemId`/`itemName` 旧档兼容、六动作全帧非透明与 OpenGL 受控截图通过。
- equipment attributes：163 条唯一正式装备、114 条工作簿覆盖、v2 Schema/来源优先级/幂等构建、魔闪点数拆分、准确/敏捷/攻速档位及 UI 单位均通过。
- combat resolution：严格物理命中、AntiMagic/AntiPoison 隔离、玩家与怪物默认点数边界、直接法术 AntiMagic→MAC→扣血、tier 物理攻击间隔、GameRoot 稳定技能 ID 和共享运行时转交均通过；最终相关回归 9/9，`SMOKE_TEST_PASS`。
- blessing/luck：`equipment.blessing_luck.v2`、三结果、5% 负面、幸运 7、诅咒 10、命运之刃 R=0 修正、全部装备 luck/curse、消耗/存档/零耐久、DC/MC/SC 与治愈术专项通过。
- damage ranges：`legacy_clamp_negative_span`、通用 `roll_primary_stat`、战士公式、攻击时序与法系伤害公式通过；反向区间不会被幸运/诅咒交换端点，恢复正跨度后效果自动恢复。
- equipment helmets：12 itemId/11 视觉身份、66 物理 atlas、2784 逻辑帧、6 动作×8 方向、透明角、Hair 逐帧锚点/SHA 溯源与 StateItem 世界像素零复用通过；法神头盔 `item_id=236` 使用用户授权原图单次 Lanczos 烘焙，atlas 单帧保持 `192×160px`、世界头盔最大 `14×17px`、纸娃娃内容保持 `17×24px`，运行时保持 nearest/`1x`；背包与地面素材冻结未变，非 236 文件及合同数据零变化。
- helmet calibration：无损校准工作流、旧映射编辑回归、240 当前 active target 自动加载、正式纸娃娃头发坐标、头盔正式尺寸基准/旧默认迁移、方向键纸娃娃独立微调和 UI 纸娃娃组件通过；世界姿态现在按动作/方向/帧独立保存 0.5px 位移、横纵各 5% 缩放和左右各 5° 旋转，death 4 帧可直接逐帧选择；240 世界透明图切割为 8/8 独立原分辨率 PNG，第三排背包/地面专用图分别直出并保存为独立 source variant，集成专项 4/4 通过。
- physics：玩家 18×9、普通怪物 16×8、Boss 28×14 的真实物理与软件探针通过；战斗/AI 半径未改。
- occlusion：11 张已发布地图、52 个交叉、4 类装饰物和 3 个比奇回归点通过；碰撞区、脚底深度点、装饰物遮挡基线已分离。
- maps：比奇真实源 E2E（180 个阻挡格）；11 张地图真实 `CharacterBody2D` 脚点可达可见边缘且外环阻挡。
- monsters：真实名字/血条节点覆盖 4 类怪物、8 方向、idle/walk/attack/hit/death 全帧和 Camera2D 缩放；214 种怪物加载通过。
- UI：2664×1200 HUD 血蓝球尺寸/对称/安全区通过；技能配置与拾取提示专项通过。
- paper doll：玩家界面透明高清 `classic_avatar`、完整装备页/槽位禁入、12 个原客户端头盔透明补丁及擦除遮罩、三职业三套装 9 个真实存档、itemId/name-only 解析、人物选择、装备实时刷新和非 headless 可视截图全部通过；`world_avatar` 仅保留为地图/兼容回退。
- skills：33 技能唯一真源、四 rank、169 条包合同与150条可执行语义合同全部通过；生产入口、六类适配器、v4进度存档/中文旧名迁移、法师/道士600ms施法动作与移动锁、独立技能冷却、26项正式视觉和图标通过。烈火显式一次充能、600ms身体/800ms动作锁/8s独立冷却/10s寿命、空挥保留、有效攻击消费及 UI 只读状态通过。最终技能/UI专项 20/20，`SMOKE_TEST_PASS`。

只在相关代码再次变化时重跑对应专项；跨域接线或发布前再跑一次 smoke。

## 永久工作树状态

| 工作树 | 分支/HEAD | dirty | 集成状态 |
|---|---|---:|---|
| `HardCore-worktrees/maps` | `codex/maps` @ `2a4d6ccf` | 72 untracked | 用户地图编辑器内容，继续保护；代码等价结果已集成为 `1d74fc72` |
| `HardCore-worktrees/monsters` | `codex/monsters` @ `45781ded` | tracked clean；68 UID | 已集成为 `c88c6277` |
| `HardCore-worktrees/ui-art` | `codex/ui-art` @ `a9ef38b0` | tracked clean；Godot UID/输出继续保护 | 纸娃娃 `avatarOnly.stagePosition` 头发坐标修复已集成；专项 1/1、集成复验通过 |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` @ `be710c6e` | 27 项 tracked 技能视觉在制修改；66 UID 继续保护 | 33技能 runtime 与150条可执行语义合同已集成；当前 fire_wall / summon_skeleton 视觉返修未交付，禁止清理或覆盖 |
| `HardCore-worktrees/equipment` | `codex/equipment` @ `2c6dd064` | 4 个既有 monster import 修改、1 个既有试点截图脚本修改及 UID/生成项继续保护 | 经典主客户端男性 Hair.wil 六动作 232 帧与世界头盔隐藏策略已作为 `eaf6be85` 集成；纸娃娃、背包、地面、11 份人工草稿、旧正式头盔素材和在制生成图集保持冻结 |

### maps 保护红线

maps 的 72 项未跟踪内容全部视为用户进行中的地图编辑器内容，禁止清理、还原、覆盖或批量暂存。重点包括地图 editor JSON/备份、ground chunks/manifests/state/preview、新地图工作区和 UID。开始新 maps 任务时只暂存本次明确修改的文件。

## 各领域最小必读

- maps：`AGENTS.md`；`scripts/map_editor/map_editor_runtime_collision_geometry_service.gd`；`scripts/map_editor/map_editor_runtime_visual_geometry_service.gd`；`scripts/world_background.gd`；对应地图 E2E 测试。
- monsters：`AGENTS.md`；`scripts/enemy.gd`；`scripts/monster_overhead.gd`；`scripts/monster_visual.gd`；`tests/monster_health_bar_anchor_test.gd`。
- UI：`AGENTS.md`；`scripts/gothic_ui_theme.gd`；目标面板或 `scripts/hud.gd`；对应 UI 专项测试。
- skills：`AGENTS.md`；`scripts/player.gd`；`scripts/profession_rules.gd`；`scripts/skill_loadout_rules.gd`；对应状态机测试。
- equipment：`AGENTS.md`；`scripts/equipment_rules.gd`；`assets/data/equipment_actor_sort_contract.json`；对应排序契约测试。

## 下次实机验收清单

1. 已冻结：碰撞、装饰物遮挡、地图错位和视角均由用户实机确认通过。
2. 已冻结：v4 怪物脚下光圈已由用户实机确认正确。
3. 待验收：角色选择页出现 9 个独立测试人物；三职业各有沃玛、祖玛、赤月三档完整装备并学习本职业全部技能；列表整块区域可直接上下滑动。
4. 待验收：法师、道士不再显示占位符；世界人物全动作显示经典男性头发且不显示头盔，纸娃娃/背包/地面仍保留头盔；男性基础形象、正式散件/套装换装、装备界纸娃娃居中和神兽动画正常；禁止重新引入女性角色资产。
5. 怪物名字固定在血条上方；各体型血条位于各自真实身体顶点上方约 8px，不再统一过高或随动作抖动。
6. 血球/蓝球恢复孔径尺寸且左右对称。
7. 拾取提示居中；技能配置弹窗背景不越界；快捷技能可置换；烈火点击后显示“充能”，800ms 后下一次有效近战消费，空挥保留，8s 内不可重复充能，绝不自动释放。

用户实测结果优先级高于内部测试；若实机失败，先保存截图和 APK 哈希，再按所属专业工作树返修。
