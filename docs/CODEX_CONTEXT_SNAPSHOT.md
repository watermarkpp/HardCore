# Codex 精简上下文快照

## 2026-08-01：魔法盾常驻正式视觉与法师技能全链审计（未构建 APK）

- 职业技能提交 `92ae4e28` 已作为集成提交 `298bd6a2` 接入稳定合同 `skills.wizard.magic_shield.cast_then_hold_final_frame.v1`：魔法盾使用主资料库 `Data/Magic.wil` indices `3880..3889` 的十帧成形动画，播放一次后保留完整第十帧；只要 `magic_shield_snapshot.active` 同时满足剩余持续时间和剩余容量，正式盾形持续跟随人物，任一归零后立即移除。旧 `player._draw()` 蓝色占位圆已删除；重复补盾替换同一人物的旧视觉，不叠加多层。
- 审计发现并修正抗拒火环真实目标映射：正式范围仍是人物周围相邻一圈八格，怪物使用现有 2:1 脚底占位与技能格接触判定；每个运行时结果携带稳定怪物实例 ID，实际推送各自对应怪物，不再把全部效果错误施加给一个锁定目标或在无锁定时失效。该接线由集成提交 `3e99079f` 完成。
- 职业技能提交 `0929efa3` 已作为集成提交 `1bfe0872` 接入，集成提交 `3e99079f` 完成火墙正式 2×2 伤害接线：四个格子均以怪物占位接触判定，不再用第一格圆心半径 `74px` 的圆形近似；同一施法者/同一怪物每个结算周期仍最多一次伤害。正式原始威力、MAC、持续时间与 `tick_interval_ms=1000` 均未改变。
- 法师十四技能审计以唯一主源 `assets/data/vanilla_176/skills_source_of_truth_v1.json` 为准：单体技能自身最大范围 9 格，法术锁定保持独立 12 格；地狱火 5×1 不穿透直线、疾光电影 8×1 穿透直线、地狱雷光半径二格外环最多 24 目标、爆裂火焰/冰咆哮精确 3×3、火墙精确 2×2，均按怪物占位接触判定。两轮定向回归 `16/16` 全部通过，覆盖真源/公式、目标与锁定、几何、直接法伤、火墙不叠加、施法动作锁、正式动画和生产入口。
- 本轮未构建 APK。236/240 人工头盔与三份怪物脚点合同 SHA-256 仍为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`、`DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。

## 2026-08-01：法术锁定、火墙不叠加与雷电术细化（未构建 APK）

- 职业技能提交 `6df25c26` 已作为集成提交 `a61cc99c` 接入，UI 提交 `8b6c2be1` 已作为集成提交 `b30e256e` 接入：法术锁定与物理攻击锁定分离；法师/道士使用 12 个逻辑地图格的独立锁定，换敌键可在不施法时循环选择，目标死亡或离开 12 格才解除；每个法术仍使用自身正式范围。范围技能使用怪物 2:1 脚底占位与技能格 SAT 相交判定。攻击法术支持点击一次、按住连续释放并遵守动作/冷却门；魔法盾为开关，容量不高于 20% 或接近结束时通过原 MP、冷却和动作管线自动补盾。
- 火墙现在必须有 12 格内有效法术锁定，2×2 中心严格使用锁定怪物脚点；无锁定时拒绝释放，不再退化到朝向地面点。正式 `tick_interval_ms=1000`、技能等级/MC 原始威力、MAC 和持续时间公式均未改。职业技能提交 `0f1336cd` 已作为集成提交 `a852967f` 接入：不同火墙仍独立存在，不识别、合并或刷新区域；同一施法者的多个火墙无论完全、二分之一或四分之一覆盖同一怪物，每个 1 秒结算周期最多造成一次该施法者的火墙伤害。真实运行回归验证首个周期只记一次、0.25 秒内无额外 tick、约 1 秒后下一次合法 tick 正常，两个火墙各自原始伤害值未被改写。
- 雷电术确认继续使用主资料库 `Data/Magic2.wil` indices `10..15` 六帧和原锚点；职业技能提交 `53cd5657` 已作为集成提交 `ee9887e8` 接入稳定呈现合同 `skills.wizard.lightning.slender_axis.v1`：仅运行时 X 轴缩放为 `0.62`、Y 轴保持 `1.0`，原 PNG、纵向高度、帧数、时序、伤害、范围和锁定均未改。审图位于 `HardCore-worktrees/professions-skills/outputs/visual_acceptance/lightning_slender/wizard_lightning_slender_6_frames.png`。
- 验证结果：法术/火墙/雷电定向 `5/5`，完整 Warrior 套件 `25/25`；关键回归连续通过前 72 项后，测试入口遇到一个已退出进程的空 `Path`，修复进程清理竞态后剩余 Monster 套件 `16/16` 通过，游戏测试零失败。236/240 人工头盔与三份怪物脚点合同 SHA-256 仍为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`、`DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。

## 2026-08-01 Android v57：攻击触摸票据与可靠释放

- UI 永久工作树提交 `aefec7aa` 已作为集成提交 `4d82edc8` 接入，新增稳定合同 `ui.input.circular_touch.lifecycle.v1`：每次真实 touch/mouse/ui_accept 按下生成唯一 token；同一 touch_id 的重复 DOWN 不再重复发起；按钮外松手由全局 release-only 兜底结束；触摸取消、隐藏、退树、应用/窗口失焦均可靠取消；Android 触摸产生的模拟鼠标事件不再双发。HUD 保留旧信号兼容，但 GameRoot 只接 token 信号，HUD 布局、尺寸、图片、文字和视觉常量未改。
- 集成提交 `34753ed0` 新增 `combat.input.attack_ticket.touch_lifecycle.v1`：真实点击票据、长按续攻和技能按钮触发彻底分离；同一 token 最多产生一张票据，不同快速点击各自保留；松手只停止续攻，cancel/失焦/死亡清除幽灵输入；队列上限 32；战士、法师、道士共用同一调度合同。旧的无上限计数累加与只清 held、不清输入生命周期的路径已移除。
- 回归结果：触摸/UI/三职业定向专项 `6/6`、完整 Warrior 套件 `21/21`、最终 Critical 套件 `78/78` 全部通过。236/240 头盔人工稿及三份怪物脚点合同 SHA-256 仍分别为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`、`DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。
- Android 固定构建提交为 `85205bb8`，APK 为 `outputs/hardcore/HardCore-v57-attack-touch-tickets-debug.apk`，大小 `244,369,521` 字节，SHA-256 `5666E45DB6FD21E3BE574AB98D04D752F20D76529D70C17975A057DBB76CFED0`。包信息为 `versionCode=57`、`versionName=1.17.21-attack-touch-tickets`；已在 HONOR 90（REA-AN00）保留存档覆盖安装并启动，手机回读版本、进程和前台 Activity 正常，启动日志无 Godot 脚本错误或 Android 崩溃。

## 2026-08-01 Android v56：半月蓝量门槛与野蛮冲撞目标释放

- 职业技能提交 `76a977ee` 已作为集成提交 `5b68dfa9` 接入。半月在攻击输入时 MP 已不足，会沿既有优先级直接降级到刺杀或普通攻击，主体动作、视觉、范围与效果保持一致且不扣半月 MP；若输入后才耗尽 MP，则保留已启动动作并使用既有命中帧晚期降级。
- 新增稳定合同 `gameplay.warrior.wild_rush.original_locked_target_release.v1`：野蛮冲撞虽为方向技能，释放快照仍保留输入阶段已验证的原目标实例 ID，使现有 GameRoot 目标链能实际执行冲撞；其他方向/区域技能仍不追踪目标。集成定向相关链 `8/8`、完整 Warrior 套件 `21/21` 通过。236/240 头盔人工稿、三份怪物脚点合同及 HUD 哈希均保持冻结值不变。
- Android 固定构建提交为 `a33a6572`，APK 为 `outputs/hardcore/HardCore-v56-warrior-mana-rush-target-debug.apk`，大小 `244,365,425` 字节，SHA-256 `AF7C445EDC9978A5A5C1DC24A2C3B08D9FA23DE5EBC4C63FA9796C0666BE8731`。包信息为 `versionCode=56`、`versionName=1.17.20-warrior-mana-rush-target`、`HardCore`、`arm64-v8a`，v2/v3 签名与运行时资源探针通过；已在 HONOR 90（REA-AN00）保留数据覆盖安装并启动，手机回读版本、进程与前台 Activity 正常，启动日志无 Godot 脚本错误或 Android 崩溃。

## 2026-08-01 Android v55：怪物占位面积近战命中

- 用户确认近战采用“中心负责瞄准、面积负责命中”：自动锁定与强制转向仍瞄准怪物人工脚点；最终资格不再要求技能区域覆盖脚点中心，只要固定技能面积与怪物现有 2:1 物理占位椭圆接触或重叠即进入准确/伤害判定。普通怪与 Boss 直接复用各自 `collision_radius`，未修改人工脚点、碰撞半径、技能距离/宽度、目标数量、伤害、准确、动画或 UI。
- 职业技能提交 `716263321313b34f3d1986a023042888e681a17c` 已作为集成提交 `3f4bd4f1` 接入，新增稳定合同 `gameplay.warrior.melee_footprint_intersection.iso_polygon_sat.v1` 与 `diagnostic.warrior.melee_footprint_candidate.v1`，复用 `world.actor_footprint.iso_ellipse.v1`。面积相交使用确定性凸多边形 SAT，边缘接触算命中；半月跨主/侧扇区与刺杀跨 1.5 格主/次段时均主区优先且只归类一次。
- 集成接线提交 `6ba697ce` 使普通、烈火、半月与刺杀的主/次候选全部读取怪物实时脚点和 `collision_radius`；逐刀日志同时保留旧中心点判定与最终面积判定。新增真实移动输入保持用例：刺杀目标中心超过 2.5 格、仅身体边缘接触末端时，旧点判定拒绝、新面积判定接受并成功扣血。两组定向回归 `14/14`、完整 Warrior 套件 `21/21` 通过。
- 冻结对象零变化：`item_236.json` / `item_240.json` SHA-256 仍为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` / `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`；三份怪物脚点合同仍为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`；冻结 HUD 仍为 `5944EE47CCA2C262DEC08FB8213FF505993B60FF2AC13BC924069E4DF38EF3D7`。
- Android 固定构建提交为 `6c405c84`，APK 为 `outputs/hardcore/HardCore-v55-melee-footprint-hitbox-debug.apk`，大小 `244,361,329` 字节，SHA-256 `2D9129134330AC819F16333A32E73C1A8F195AEC18A24238CBA61353BAD7BFC4`。包信息为 `versionCode=55`、`versionName=1.17.19-melee-footprint-hitbox`、`HardCore`、`arm64-v8a`，v2/v3 签名与运行时资源探针通过；已在 HONOR 90（REA-AN00）保留数据覆盖安装并启动，手机回读版本、进程与前台 Activity 正常，启动日志无 Godot 脚本错误或 Android 崩溃。

## 2026-08-01 Android v54：近战地图格八方向统一修正

- 手机 v53 逐刀诊断已锁定根因：复现角度中人物到目标的浮点地图格差值约为 `(-0.56,-1.31)`、距离 `1.31` 格；旧 screen/projected 45° 量化错误选为 index 5，导致刺杀横向值 `0.56 > 0.50` 而连续 `12/12` 被 `OUTSIDE_ATTACK_LANE` 拒绝。按方案 A 的地图格坐标量化应为 index 4，前向约 `0.935`、横向约 `-0.375`，属于合法第一格；该证据排除了准确 MISS 与扣血提交失败。
- 职业技能修正 `7bef5aedd852a7563fcaf6ed0e6bd0c0160ecfec` 已作为集成提交 `f1a69a4c` 接入，新增 `gameplay.professions.combat_direction_space.iso_64x32_tile_8dir.v1` 与 `gameplay.warrior.melee_release_facing.canonical_tile_8dir.v2`。运行时现在固定使用“世界脚点差→浮点地图格差→地图格八方向→视觉/世界投影”的唯一链路；旧 screen/projected 量化仅保留为诊断对照。
- 集成接线提交 `082c93fd` 使输入自动转向、攻击请求、释放帧几何、普通/刺杀/半月/烈火候选筛选及诊断全部复用同一个 authoritative `direction_index`；攻击动作已开始时的拒绝输入不再改写人物朝向。法师/道士的魔法锁定路径未改。
- 手机固定死角已加入非 test mode 的端到端回归；近战方向/诊断/几何/移动锁定/状态机/正式技能入口等相关回归两组共 `14/14` 通过。236/240 头盔人工草稿、三份怪物脚点合同与冻结 HUD 的 SHA-256 均保持开工值不变。
- APK 从固定提交 `082c93fd` 的隔离工作树导出为 `outputs/hardcore/HardCore-v54-melee-tile-direction-fix-debug.apk`，大小 `244,357,233` 字节，SHA-256 `F5C67BA082BA223A53E5C9A12686A81D70AFE47307842C92291CA87B218869AA`。包信息为 `versionCode=54`、`versionName=1.17.18-melee-tile-direction-fix`、`HardCore`、`arm64-v8a`；v2/v3 签名通过。已对 HONOR 90（REA-AN00）执行保留数据覆盖安装并启动，手机回读版本正确、进程与前台 Activity 正常，启动日志无 Godot 脚本错误或 Android 崩溃。

## 2026-08-01 Android v53：方案 A 近战逐刀诊断与角度边界证据

- 职业技能永久工作树提交 `ad910399` / `4f2d2f20` 已分别作为集成提交 `58c03259` / `6b76ed85` 接入；新增只读稳定合同 `diagnostic.warrior.melee_candidate.v1`、`diagnostic.warrior.melee_direction_loop.v1`、`diagnostic.warrior.melee_angle_quantization.v1`。精确八方向的编号与投影闭环全部一致，但 fractional tile 边界存在已证明的策略差异：`delta=(1,0.5)` 当前投影后 screen-45 量化为 SE/index 7，方案 A 的 tile-space-45 量化为 S/index 0；运行时会逐刀同时记录两种结果，不提前改变游戏判定。
- 集成接线提交 `b643c215` 新增 `combat.melee.runtime_diagnostic.jsonl.v1`：每次真实近战从输入、锁定、人物/目标实时脚点、输入/释放八向、动画行、候选逐项拒绝码、准确/敏捷/随机点、正式扣血提交到最终结果共用一个 `action_id`。结果明确区分 `GEOMETRY_NO_ELIGIBLE_TARGET`、`CANONICAL_SKILL_REJECTED`、`ACCURACY_MISS`、`DAMAGE_COMMIT_FAILED` 与 `HIT_COMMITTED`；只增加观测，不改范围、伤害、命中率或冻结数据。
- 近战定向、锁定回退、移动攻击、攻击时序、战士状态机、正式技能运行时、八方向/边界角度及非 test mode 的真实命中随机链回归 `13/13` 通过。236/240 头盔草稿、三份怪物脚点合同与冻结 HUD 的 SHA-256 继续分别为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`、`DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`、`5944EE47CCA2C262DEC08FB8213FF505993B60FF2AC13BC924069E4DF38EF3D7`，与本轮开工记录一致。
- APK 从固定提交 `b643c215e71542fe71725259663e30edcf448ea4` 的全新隔离工作树导出为 `outputs/hardcore/HardCore-v53-melee-diagnostic-a-debug.apk`，大小 `244,352,944` 字节，SHA-256 `A36D719BC2C5AB4501D6355F7ED74506BBA94CBE809678A6D34379D449FD399A`。包信息为 `versionCode=53`、`versionName=1.17.17-melee-diagnostic-a`；v2/v3 签名、包名、应用名、arm64 与运行时资源探针通过。构建完成时 ADB 未枚举到设备，尚未覆盖安装。

## 2026-07-31 Android v52：移动近战同一坐标系与攻杀定稿表

- 怪物工作树提交 `2c300b25` 已作为集成提交 `d747e675` 接入，稳定合同 `monster.melee_player_contact.iso_footprint_fractional_tile.v1` 取消普通近战怪物用统一屏幕欧氏圆停止追击的旧逻辑。旧 48px 接敌距离换算正式 64×32 等距格后为 S/N `1.5`、E/W `0.75`、四斜向 `1.590990`，会让斜向怪物停在玩家 1.5 格攻击范围外；新逻辑按正式浮点地图格与 2:1 脚印共同约束。八方向真实追击最终距离 S/N 约 `1.1603`、E/W 约 `0.7459`、四斜向约 `1.3267`，均不超过 1.5 格，至少保留 10px 脚印间隙且稳定后连续 8 帧零抖动。155px 远程怪物未进入该合同；人工怪物脚点、碰撞外形和 AI 数值未改。
- 职业提交 `1ac5bf64` 与集成接线 `4ffb5c4b` 新增 `gameplay.warrior.melee_release_facing.locked_input_8dir.v1`：玩家输入帧完成自动转向后，近战动画与命中扇区在整次动作中共用同一八方向；命中帧仍刷新人物/怪物实时脚点，但不会只让伤害代码暗中转向。法师、道士单体投射物继续按释放帧实时追踪。烈火冷却、MP不足或目标失效时按烈火→半月→刺杀→普通降级，冷却只在合法烈火 HIT/MISS 后建立，冷却期间不再锁死攻击键。
- 攻杀定稿提交 `c91a82b4` 已作为集成提交 `a07ce8d9` 接入，跨系统伤害接线为 `2d8a64db`，稳定合同升级为 `gameplay.warrior.melee_modifiers.v2`。0/1/2/3 级分别要求人物等级 `19/19/22/24`、本级修炼值 `0/4000/8000/16000`；常驻准确 `+0/+1/+2/+3`；每次合法近战动作只掷一次 `1/7、1/6、1/5、1/4`，触发后在普通/刺杀/半月/烈火各自公式和取整完成后，对该动作内每个实际命中固定追加 `+2/+4/+6/+8`，多目标循环不得重新掷骰。技能 SOT SHA-256 为 `1FDF28D3C575D18D2E7E0F875B008EB4F6F719752E4974CBCA399C66C62C7C2C`，来源优先级审计全部通过。
- 集成回归结果：攻杀/释放/烈火定向 `10/10`、Warrior `21/21`、Monster `16/16`、最终跨系统 Critical `78/78`。三份怪物脚点合同哈希仍为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`；236/240 头盔草稿与冻结 HUD 哈希保持开工值不变。
- APK 从固定提交 `61765d516981e89dead20f27edbbd8c616e8c1b0` 的全新隔离工作树导出为 `outputs/hardcore/HardCore-v52-moving-melee-slaying-debug.apk`，大小 `244,332,060` 字节，SHA-256 `CB1A30BD47D421D3E5A24FEDEB010F4769649EAA42CCD96D208149E5FDCBF679`。包信息为 `versionCode=52`、`versionName=1.17.16-moving-melee-slaying`；v2/v3 签名、包名、应用名、arm64 架构及运行时资源探针通过。构建时 ADB 未枚举到设备，因此尚未覆盖安装。

## 2026-07-31 Android v51：近战锁定与实际受击对象解耦

- 集成运行时提交 `23fb3961` 新增稳定策略 `combat.melee_lock.facing_priority_nonexclusive.v1`：攻击锁定只负责自动朝向和目标优先级，不再独占伤害许可。普通攻击与烈火仍为单目标；锁定目标在当前攻击几何内时优先命中，锁定目标在范围外时改为命中当前刀锋范围内最近的怪物。烈火仍禁止真正空放。
- 职业技能提交 `40a3ce3c` 已作为集成提交 `bc0486e3` 接入，稳定合同 `gameplay.warrior.melee_target_count.v1` 明确普通攻击/烈火最多 1 个目标，刺杀/半月不设目标数上限；每只进入既定刺杀直线或半月扇区的怪物独立执行命中、MISS 与伤害判定，范围、宽度、角度和伤害公式均未扩大。技能 SOT 运行时合同 SHA-256 为 `DF2199E337F4EDD087CC060C0B59DE1C5839C309FC953EB0DCBD77FAC0ED4FBC`，来源优先级审计已授权且通过。
- 当前集成 Warrior 完整套件 `21/21` 通过，包含新增远端锁定目标与近端实际受击对象回退、移动释放、普通/烈火单体及刺杀/半月多目标回归。三份怪物脚点合同、236/240 头盔人工草稿与冻结 HUD 的 SHA-256 均保持不变。
- APK 从固定提交 `1571db9d0ee7ed0d80b7cb48d7fb12de2c18f673` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v51-melee-lock-impact-debug.apk`，大小 `244,327,964` 字节，SHA-256 `FF44C801ADF50D74638D54A6FF450AAEA87AB8CDF071B774A9A78628F3CE0137`。包信息为 `versionCode=51`、`versionName=1.17.15-melee-lock-impact`；签名、包名、架构和运行时资源自动验证通过。构建后手机在 ADB 大包传输期间断开，覆盖安装待设备重新枚举后继续。

## 2026-07-31 Android v50：全职业实时命中/发射几何

- 职业技能提交 `5d383b4b` 已作为集成提交 `9ba353cf` 接入，跨系统运行时接线为 `461df415`，Android 固定构建提交为 `d7717832`。新增稳定合同 `gameplay.professions.combat_release_geometry.live_footpoint.v1`：攻击或技能在输入时只保存原目标实例 ID 与自动转向后的动画方向，在实际命中/发射帧读取人物和原目标的实时脚点；动画中途不切方向，动作结束后仍恢复移动输入。
- 普通攻击、刺杀、半月和烈火的主目标禁止在前摇期间静默换成附近怪物；原目标实时越出既有合法范围才真正挥空。法师、道士的单体直伤与投射物沿用相同原目标/实时脚点规则；方向、目标区域与自身区域技能保留输入方向，不会被改造成追踪技能。既有命中率、脚点、范围、伤害、投射物碰撞和技能资源规则均未改动。
- 完整关键回归 `76/76` 通过；覆盖目标跨八方向边界、人物/目标同时移动、原目标消失、旁边存在诱饵目标、真实超距、战士四种近战模式以及法师/道士释放几何。236/240 头盔草稿、三份怪物脚点合同与 `scripts/hud.gd` 的 SHA-256 均与施工前一致。
- Android 包为 `versionCode=50`、`versionName=1.17.14-live-hit-geometry`、包名 `com.personal.mafaoffline`、应用名 `HardCore`。APK 从固定提交的全新隔离工作树导出为 `outputs/hardcore/HardCore-v50-live-hit-geometry-debug.apk`，大小 `244,327,964` 字节，SHA-256 `81567059C29FEBD47039292332C00C0C65E0EFB0F6465991F8F585968616D648`；结构与签名验证通过。已对 HONOR 90（REA-AN00）执行保留数据覆盖安装并启动，手机端回读版本正确，进程与前台活动正常，启动日志无 Godot 脚本错误或 Android 崩溃。

## 2026-07-31 Android v49：野蛮冲撞原子推移测试包

- Android 版本提交为 `975eb257e990ce1866643d44a8ae70908d040ad5`：`versionCode=49`、`versionName=1.17.13-wild-rush-atomic`，包名继续为 `com.personal.mafaoffline`，应用名继续为 `HardCore`。APK 从该固定提交的全新隔离工作树导出为 `outputs/hardcore/HardCore-v49-wild-rush-atomic-debug.apk`，大小 `244,319,577` 字节，SHA-256 `58BBE5FDF78CB01B97B61CA34A5AAAA8D3B652386F6B6AB4F472B4DE1DCF3975`。
- APK v2/v3 签名、`arm64-v8a`、minSdk 24、targetSdk 36、12 个编译脚本和运行时资源探针通过。已对连接的 HONOR 90（REA-AN00）执行保留数据覆盖安装并启动；手机端回读版本正确，前台活动为 `GodotAppLauncher`，启动后日志未发现 Godot 脚本错误或 Android 崩溃。

## 2026-07-31 野蛮冲撞三格原子推移

- 职业技能永久工作树提交 `c3efe96c` 已作为集成提交 `c917963a` 接入，跨系统游戏运行时接线提交为 `9038b225`。稳定合同为 `gameplay.warrior.wild_rush.atomic_tile_push.v1`；技能 SOT 运行时合同 SHA-256 更新为 `34634C4ED2A3519A98F32CF35D8299D3A86A668430061BD220E1F80A900F4024`，原始授权 ZIP 证据哈希不变，来源优先级审计通过。
- 目标必须是人物 `1.5` 逻辑格内、等级严格低于人物的存活普通怪物；Boss、不可移动、同级/高级、安全区内或超距目标均拒绝。已有锁定目标时禁止静默换成邻近怪物；无合法目标不启动动作、不扣 MP、不进入冷却。资格通过后不再掷随机成功率。
- 推动方向只由人物脚点到怪物脚点的真实浮点地图格连线量化为八方向，忽略输入朝向；人物和怪物保持原间距同步移动最多固定 `3` 格。完整三格走廊内存在第二只存活怪物时技能照常发动但双方零位移；静态障碍位于第 1/2/3 格时分别移动 0/1/2 格，无障碍移动 3 格。双方完整碰撞脚印会在写入位置前统一预检，禁止只移动其中一方。
- 野蛮冲撞不造成目标伤害或自身伤害；被动态/静态阻挡时仍按有效发动提交资源与冷却，但只有实际移动至少 1 格才增加熟练度。旧 `50px` 位移、随机成功率及 `path_blocked_after_start` 像素阻挡字段已退出该技能链。
- 集成 Warrior 完整套件 `18/18`、最终定向回归 `3/3`、来源优先级审计全部通过。冻结对象零变化：236/240 头盔草稿、三份怪物脚点合同及人物脚点合同 SHA-256 均与开工记录一致。

## 2026-07-31 战士近战浮点逻辑格范围

- 职业技能提交 `dac5da83`、等距朝向修正 `3379036b` 已分别作为集成提交 `dbd0adba`、`c92d2b43` 接入；游戏主体接线提交为 `bb7dc7e5`。新增稳定合同 `gameplay.warrior.melee_geometry.fractional_tile.v1`，所有近战资格只读取人物/怪物实体脚点并转换为浮点正式地图格，不再用屏幕像素距离判定。
- 正式范围为：普通攻击与烈火 `1.5` 格单目标；半月 `1.5` 格、相对方向 `[7,0,1,2]` 四扇区、最多 4 目标；刺杀 `2.5` 格、宽 1 格直线、前段/末段各最多 1 目标。0.5 格只作为长度容错，不增加刺杀第三目标格、半月第二圈、宽度、角度或最大目标数。未来范围加成采用加法并封顶：普通/烈火/刺杀最多 `+1.0` 格，半月最多 `+0.5` 格。
- 烈火开启后不再降级为半月、刺杀或普通攻击。无合法 `1.5` 格目标、冷却中或资源不足时，输入在动作前拒绝，不播放、不扣费、不新增冷却、不训练且不进入攻击队列；只有已经进入合法物理命中判定的 HIT 或 MISS 才消费烈火。攻杀仍是一刀一次的全局近战概率层。
- 技能 SOT 运行时合同 SHA-256 更新为 `8AFF4FBC23E3DD2A72732F29825B78B2EE2A4A374B6A0F2AB93ED378ED59B63E`，原始授权 ZIP 证据哈希保持不变。职业技能专项 9/9、集成 Warrior 完整套件 18/18 通过。
- 冻结对象零变化：`item_236.json` / `item_240.json` 仍为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` / `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`；三份怪物脚点合同仍为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。

## 2026-07-31 独立攻击锁定与逐次攻击输入

- 集成运行时新增 `combat.attack_lock.tile_radius.v1`：攻击锁定只使用正式地图格坐标，按八方向网格的 Chebyshev 距离限制在角色周围 `10` 格。自动锁定默认开启；无锁定时，点击或按住普通攻击会从四周合法怪物中选择最近目标；已有目标时，即使出现更近怪物也保持原锁定，并在每次攻击输入时强制转向。目标死亡、失效或越过 `10` 格才释放。
- 换敌键与攻击共用同一组 `10` 格候选：没有目标时从最近怪物开始，有目标时按格距离循环到下一只；不再限制人物正面，也不再要求先关闭自动选怪。攻击锁定和技能临时选敌已经拆开，技能施放不会覆盖攻击目标；持久魔法锁定尚未实现，留待后续独立设计。
- 普通攻击输入改为逐次登记：每次快速或慢速点击都对应一次攻击，发生在上一刀动作/冷却期间的点击不会丢失；长按继续按攻击间隔连续触发，松开只停止继续追加。攻击动作结束后继续使用未被清除的摇杆/键盘方向，人物恢复该方向并继续移动。
- `mobile_targeting_test` 覆盖 10/11 格边界、背后最近目标、持续锁定、强制转向、点击队列、长按、松开恢复移动、换敌循环及技能目标隔离；当前集成 Warrior 完整套件 `18/18` 通过。冻结 HUD、236/240 头盔草稿和三份怪物脚点合同 SHA-256 均保持不变。

## 2026-07-31 Android v48：战士动作稳定与 HUD 可视金属内沿填充

- 职业技能提交 `4d50549e` 已作为集成提交 `5d2bd904` 接入；跨系统命中帧接线为 `c8505925`。刺杀/半月的主体动作在攻击输入时锁定，不再因瞬时 `has_combat_target` 或半月 MP 检测降为普通攻击；实际目标资格、MP 与效果降级改由 `SkillInputPolicy.resolve_warrior_hit_effect` 在命中帧决定。攻杀剑法仍只在一次有效近战命中事务中判定一次，永远不成为独立主体动作或特效。
- UI 提交 `36f720ce`、合并修正树 `2d09b896` 与最终内衬修正 `7945fe97` 已作为集成提交 `ea0d6c50` / `050f9a22` / `633113fb` 接入。旧四技能圆框、红菱形和直横连接条由 `ui.hud.chassis.legacy_skill_alpha_mask.v2` 精确移除；中央徽章、向上尖头和下方正式弧形金属横梁逐像素保留。
- `round_action_frame_v3.png` 原图保持不变。运行时 `ui.hud.action_frame.inner_dark_rim_mask.v1` 按 360 个方向逐径向寻找第一枚亮金属像素，只清除其内侧深色/半透明衬圈，亮金属与外侧四尖角保持原 RGBA；攻击内容使用 `90px`，六环技能内容使用 `50px`，frame 最后绘制遮边。无技能槽隐藏底色和图标、透出地图，只居中显示“空”。该视觉已由用户根据 4× 放大图明确验收通过并冻结。
- 集成回归：Warrior 完整套件 `18/18` 通过；HUD/Android 布局/触摸滚动/技能图标专项 `6/6` 通过，新增 360 向内容覆盖、内衬清零、亮金属原值和绘制层级断言。最终验收图为 `HardCore-worktrees/ui-art/outputs/visual_acceptance/hud_runtime/hud_visible_inner_rim_2664x1200.png`，4× 按钮图为 `hud_visible_inner_rim_action_detail_4x.png`。
- 用户冻结对象零变化：`item_236.json` / `item_240.json` SHA-256 仍为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` / `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`；三份怪物脚点合同仍为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。
- APK 从固定提交 `e12bf11d25ba61f674f94446375faad90031231c` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v48-action-frame-fill-debug.apk`，大小 `244,294,808` 字节，SHA-256 `6ED212D5E1EB098267F06DB5E407EA19883347A50220A302A6E485DDB3FEED61`。包信息为 `versionCode=48`、`versionName=1.17.12-action-frame-fill`、`com.personal.mafaoffline`、`HardCore`；结构验证通过。已对连接的 HONOR 90 保留数据覆盖安装并启动，前台活动为 `GodotAppLauncher`，启动后近期日志未发现 Godot 脚本错误或 Android 崩溃。

## 2026-07-31 Android v47 六环技能与战士近战整合

- 专业交付已按工作树依次集成：装备 `5da60808`（集成 `b2ff4858`）、职业技能 `4fac69b6`（集成 `8f9b34a8`）、UI `f45c2a68`（集成 `9db42247`）；跨系统接线提交为 `64de7041`，Android 固定构建提交为 `74109c5c`。
- HUD 取消屏幕中间四个技能按钮，保留下方四个物品槽；攻击键周围改为六个独立主动技能槽，攻击键本身支持配置主动技能与一键清空恢复普通攻击。被动技能只在技能列表展示，禁止配置到攻击键或六环。所有相关存档升级为 `save_version=6` / `gameplay.skill.button_assignments.v3`，旧四槽迁移到六环前四槽，攻击键保持独立。
- 战士攻击优先级固定为烈火 > 半月 > 刺杀 > 普通；烈火、半月、刺杀是开关，野蛮冲撞仍为点击释放。基本剑术继续提供所有近战常驻命中加成。攻杀剑术不再抢占攻击动作：每次有效近战动作只进行一次原始概率判定，触发后先叠加攻杀 DC/命中，再进入普通、刺杀、半月或烈火本体公式；半月多目标与刺杀双格共享同一次判定，主体动画与技能效果不被替换。
- 12 个正式头盔的背包图与地面图全部改用用户在校准工具中保存的独立来源，运行时保持 `1x` / nearest，禁止二次缩放。纸娃娃和世界图集未重建。`item_236.json` / `item_240.json` SHA-256 继续为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` / `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`。
- UI、技能与装备专项分别通过 14/14、warrior 18/18、equipment 17/17；最终 `critical` 74/74 全部通过。三份冻结怪物脚点合同 SHA-256 继续为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。
- APK 从固定提交 `74109c5ceb809f2648a534d820f308756546b714` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v47-six-ring-warrior-ui-debug.apk`，大小 `244,282,231` 字节，SHA-256 `ECEC7AE5F2DBB24176B96D9BA6C60B994D044B389A33FAAACFDC30AA30B2D4B0`。包信息为 `versionCode=47`、`versionName=1.17.11-six-ring-warrior-ui`、`com.personal.mafaoffline`、`HardCore`；APK v2/v3 签名、arm64-v8a、minSdk 24、targetSdk 36 和运行时资源探针通过。构建完成时 ADB 设备列表为空，尚未覆盖安装。

更新时间：2026-07-31（Asia/Shanghai）

用途：给主任务和专业工作树提供快速、可核实的启动索引，减少重复扫描和重复测试。
准确性规则：本文件不是代码或 Git 状态的替代品；只核实本次任务实际触及的分支、文件、接口和专项测试。

## 2026-07-31 Android v46 怪物人工脚点坐标归一化

- 怪物专业提交 `97734d8a` 在只读加载阶段重放历史校准台的 S 向预览位移，并在视觉脚点向量中等量抵消；怪物实体、碰撞、攻击判定和目标黄圈继续以 actor-local `(0,0)` 为唯一脚点。UI 专业提交 `14984c0c` 已作为 `bb3d682f` 集成，使验收台和游戏使用完全相同的变换链。
- 人物没有接入怪物历史位移重放。正式人物常量继续为 `runtimeVisualPosition=(7.5,12.5)`、`visualFootAnchorAdjustment=(-7.5,-12.5)`，最终脚点仍为 `(0,0)`；人物脚点、比奇边界、通用边界、等距碰撞、投射物命中链和移动目标选择回归与怪物/UI 联动合计 12/12 通过。
- 212 份人工怪物草稿及三份正式怪物脚点合同未被重写；三份正式合同 SHA-256 继续为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。人物人工草稿 SHA-256 继续为 `5D01E19C509E9C970B928475263E233552EE50A00BE7C04FD3BF6BD1CFD088A4`。
- APK 从固定提交 `6a983c60da2dd29388ffe25048f1d6f443a7a300` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v46-monster-foot-normalized-debug.apk`，大小 `244,215,702` 字节，SHA-256 `C3C1BB1CD768AE217A053F7427A178C5DC04424BB968673E6385A095A7058444`。
- 包信息为 `versionCode=46`、`versionName=1.17.10-monster-foot-normalized`、`com.personal.mafaoffline`、`HardCore`；APK v2/v3 签名和运行时资源探针通过，包内三份怪物脚点合同与源文件逐字节同哈希，人物脚点合同语义逐字段一致。已对连接的 HONOR 90 保留数据覆盖安装并成功启动，前台活动为 `GodotAppLauncher`，近期日志无 Godot 脚本错误或崩溃。

## 2026-07-30 Android v42 坐标隔离测试包

- Android 版本提交为 `aa0914bf`：`versionCode=42`、`versionName=1.17.6-target-coordinate-isolation`，包名继续为 `com.personal.mafaoffline`，应用名继续为 `HardCore`。
- APK 从固定提交 `aa0914bf788728294ad1e2a7d0f85488bb00f878` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v42-target-coordinate-isolation-debug.apk`，大小 `244,198,886` 字节，SHA-256 `6FEA504954E52019E5A6415829000CDC7823F002F8B03990690191D68383CB4E`。
- APK v2/v3 签名、arm64-v8a、minSdk 24、targetSdk 36、横屏/可调整窗口和运行时资源探针通过；12 个关键编译脚本、男性 `Hair.wil block 4`、纸娃娃 base/hair/head patch、世界头盔隐藏和 586 帧施法资源均在包内。
- 已通过项目内 ADB 对连接的 HONOR 90（REA-AN00）执行保留数据覆盖安装并启动。手机端回读为 v42，`GodotAppLauncher` 位于前台，应用进程正常，近期日志未发现崩溃或 Godot 脚本错误。
- 构建前后人物脚点草稿、两份抽检怪物草稿和三份怪物正式脚点合同 SHA-256 保持不变。

## 2026-07-30 怪物黄圈坐标链最终解耦

- 本节覆盖下方早期“地面黄圈直接采用人工视觉脚点”的实现记录。怪物专业提交 `f195a961` 已作为集成提交 `1fc2dfa5` 接入：地面怪物的实时目标黄圈中心固定为怪物 `CharacterBody2D` / 碰撞脚印的本地物理原点 `(0,0)`；`visualRootOffset`、`visualFootOffset`、Sprite 锚点、动作、方向和帧只能移动外观，禁止再推动目标黄圈。飞行/悬浮怪物继续使用明确的地面投影。
- 黄圈大小规则未变：仍为对应怪物 2:1 物理脚印半径的 `1.25` 倍，所以体型差异只影响半径，不影响中心。怪物专项会主动扰动视觉根位置、Sprite 锚点和视觉脚点，证明地面黄圈仍保持 `(0,0)`。
- UI 专业提交 `a971ad44` 已作为集成提交 `56ae1fb8` 接入。视觉验收台现在分别显示并报告：人工视觉脚点、怪物物理原点、游戏实时目标黄圈；状态区独立给出“黄圈-目标”和“脚点-原点”差值，并标明当前动作/方向/帧是否等于保存时的校准姿态，不再用同一份人工偏移同时构造参考值与实际值。
- 真实集成回归 10/10 通过：验收台、214 怪物冷热加载、五动作八方向、比奇普通怪、亡灵、完整客户端美术、尸王、怪物等距脚印、比奇地面坐标和共享角色脚印合同。
- 冻结数据零变化：`monster_21.json` / `monster_23.json` SHA-256 仍为 `C531C41C914261766626BE87E7BC2741D72531CD9893F7C599E5141F65ADB32E` / `DCAC46EB2688458F33516AD1C37685D8F83C7CAD96FE86A3FBD36C5B284E0FCE`；三份正式合同仍为 `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`、`AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`、`36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`。

## 2026-07-30 怪物人工脚点二次冻结与目标光圈同心

- 用户重新完成的 212 份怪物脚点草稿已成为唯一最新人工基线，源草稿聚合 SHA-256 为 `0993DD6600091B584F247CDA02B0AFEABB164E73952FEB87C57A886AAD515E7A`；只读导入前后聚合哈希一致。后续生成器、校准器、缓存和旧合同均禁止覆盖这些人工值。
- 怪物专业提交 `90f3f716` 已作为集成提交 `b478b7cc` 接入：地面怪物的黄色目标光圈中心直接采用人工视觉脚点；飞行/悬浮怪物继续保留已有投影关系。黄色目标光圈半径固定为对应怪物 2:1 物理脚印半径的 `1.25` 倍，因此中心完全相同、长宽同比放大，并随每只怪物的碰撞体积自然变化。
- UI 专业提交 `dabd8872` 已作为集成提交 `ed3d850e` 接入：视觉验收台橙色正式光圈直接读取游戏运行时目标光圈的中心与半径，不再维护第二套诊断坐标。
- 真实集成基线检查通过：精确草稿导入、v5 合同生成、怪物专项 10/10，以及 UI/怪物联动 2/2。人物脚点草稿 SHA-256 仍为 `5D01E19C509E9C970B928475263E233552EE50A00BE7C04FD3BF6BD1CFD088A4`；236/240 头盔草稿继续冻结且未被暂存。
- Android v41 测试包从固定提交 `233d4539` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v41-monster-ring-foot-debug.apk`，大小 `244,198,886` 字节，SHA-256 `F668B92EECF0A071E14E08C3912DD7BF98AC582C378118B010DB4A638BC92FA6`；`versionCode=41`、`versionName=1.17.5-monster-ring-foot`。APK v2/v3 签名和运行时资源探针通过，已对连接的 HONOR 90 保留数据覆盖安装并成功启动。
- 最新人工脚点已完整备份到 `outputs/visual_acceptance/backups/monster_feet_20260730_191500.zip`：包含 212 份原始草稿、3 份正式运行时合同和逐文件哈希清单，ZIP SHA-256 为 `DB9276E4E12AB4F4D8DD0EAF56BDFC9EE6690092EEB6A15F49E87B8CDE212D91`。
- UI 专业提交 `f248cdf6` / `8d5c82cd` 已作为集成提交 `4a8b5d75` / `5ee31695` 接入。验收台专用启动参数 `-MonsterGroundReview` 会直接进入怪物模式：青十字显示人工保存脚点，黄色椭圆与黄色小十字显示游戏实际目标光圈；两者不一致时绘制红色连接线，并在状态区显示 X/Y 差值。214 个怪物均可切换，212 个读取人工草稿，2 个读取正式飞行投影合同。

## 2026-07-30 Android v40 怪物地面层修复包

- 怪物专业提交 `5c1436ab` 已由集成提交 `8a803ce2` 接入；Android 版本提交为 `7d75f307`。正式 WIL 素材等待异步加载时不再生成旧程序圆影，临时光圈中心统一使用标准脚点 `(0,0)`，贴图激活/释放会为未选中怪物无条件刷新缓存的地面绘制层。
- APK 从固定提交 `7d75f307` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v40-ground-layer-fix-debug.apk`，大小 `244,194,790` 字节，SHA-256 `BAAE73D036AF2F67ADC38D9095AB2BDA044D80FF30C53ED7DFD78BDE52113AFA`。
- 包信息为 `versionCode=40`、`versionName=1.17.4-ground-layer-fix`、包名 `com.personal.mafaoffline`、应用名 `HardCore`、`arm64-v8a`、`minSdk=24`、`targetSdk=36`；APK v2/v3 签名、12 个编译脚本与运行时资源探针通过。
- 集成专项 9/9 通过：214 怪物冷激活/正式脚点/覆盖、等距物理、比奇普通怪/亡灵、兽人古墓运行画面和地图怪物预取。完整怪物套件中的3个旧失败已在未修改的 v39 基线复现，属于旧 Boss/人物下沉断言，不是本次回归。
- 212 份人工怪物脚点及两份正式地面合同保持冻结，三份相关 JSON 的 SHA-256 分别保持 `9A3144C27546F61FFB1723880106C965987D7689A78C83CC883EB358E0F01BEF`、`FDBB233ED951C969CB35C950E8D682AB69C97BE2466262A0BE257A2BD6A89152`、`04477F070BBFD0D89048AD11459338BF53CFECF1F7282899061261C6EACDD909`。
- 已通过 ADB 对连接的 HONOR 90 执行保留数据覆盖安装并启动；手机端回读确认 `versionCode=40`、`versionName=1.17.4-ground-layer-fix`。

## 2026-07-30 Android v39 怪物脚点测试包

- APK 从固定集成提交 `eaf42c0a` 的全新隔离工作树导出：`outputs/hardcore/HardCore-v39-monster-feet-debug.apk`，大小 `244,194,790` 字节，SHA-256 `D347862CCA2E712107E8328AAA12E5EFD0EDB650AF8AE7C774AD3BCAC018809F`。
- 包信息为 `versionCode=39`、`versionName=1.17.3-boundary-fix`、包名 `com.personal.mafaoffline`、应用名 `HardCore`、`arm64-v8a`、`minSdk=24`、`targetSdk=36`；APK v2/v3 签名、运行时资源探针和横屏/可调整尺寸合同通过。
- APK 内 `monster_ground_alignment_manual_v1.json`、`monster_ground_contact_calibrations.json`、`monster_ground_contacts.json` 与 `complete_monster_client_art_sources.json` 的 SHA-256 均与构建提交逐字节一致，确认最新 212 份怪物脚点及牛魔碎片素材进入安装包。
- 已通过 ADB 对连接的 HONOR 90 执行保留数据覆盖安装；手机端回读确认 `versionCode=39`、`versionName=1.17.3-boundary-fix` 和最新更新时间。

## 2026-07-30 怪物人工脚点正式接入与动画修复

- 最新怪物专业提交 `5f912b41` 已由集成提交 `3312f0ab` 接入；此前怪物专业提交 `19be26ed` / UI 专业提交 `ff707360` 分别由集成提交 `ee09aefd` / `072c1289` 接入。
- 用户完成的 212 份 `monster_<id>.json` 校准草稿已只读导入 `monster.ground_alignment.manual.v1`，最新源文件聚合 SHA-256 为 `B5229D08E7C1DFBC36D3C50C45A14A81AE46CAE8C84EFEBB42204EA38408FE00`。最新精确更新牛头魔 `210/211`、牛魔侍卫 `216/217`、牛魔将军 `218/219`、牛魔法师 `220/221`；其余 204 份正式人工数据逐条不变。其他牛系列未重新保存的草稿继续使用已加载正式值；仅飞行投影的猎鹰 `monster_id=97/98` 保留原有离地关系。
- 正式运行时升级为 `monster.ground_contact.v5` / `monster.ground_contact.calibration.v5`：普通怪/Boss 基础视觉原点、用户 `visualRootOffset`、视觉脚点和光圈中心各只应用一次；验收台识别已正式导入的同哈希草稿，禁止二次叠加偏移。
- 祖玛教主使用主资料 `Mon7.wil` 中物化前缀之后的正确动作段：idle/walk/attack/hit/death 起始帧为 `1340/1420/1500/1580/1600`，并锁定原 `384×336` 画布与 `[114,237]` 脚点，避免破坏用户坐标。
- 所有怪物 Sprite2D 启用图集区域过滤裁切，阻止牛魔系列相邻格碎片渗入。牛魔将军 `monster_id=218/219` 共用的 `appearance=204/raceImg=19/MA19` 五动作图集进一步仅移除不超过 48 像素的 8 连通孤立碎片，共 962 块/3813 像素；原 `272×272` 单帧画布、`[84,143]` 脚点、人工脚点参数和全部缩放策略保持不变。触龙神原素材多帧齐全；验收台仅在预览时解除潜伏隐藏以便查看 idle/attack/death，游戏内钻地机制不变。
- 最新集成验收：精确草稿导入检查、v5 数据生成检查、214 怪物/40,144 帧几何审计和怪物运行时专项 8/8 全部通过。98 个冻结头盔文件在本轮没有被暂存或修改。

## 2026-07-30 本地视觉验收台

- UI 专业提交 `cd168dd4` 已由集成提交 `ff235d1a` 接入。本地入口为 `tools/run_visual_acceptance_lab.ps1`，独立场景为 `tools/visual_acceptance_lab/visual_acceptance_lab.tscn`；不修改 `project.godot`，不写角色存档、校准草稿或正式素材。
- 当前最小版本直接实例化正式 `PlayerCharacter` / `PlayerVisual` 运行时合成，覆盖战士、法师、道士，`idle/walk/attack/cast/hit/death` 六动作与八方向；支持 25%/50%/100%/200% 播放、逐帧、1–4 倍显示、三种背景、一键重载正式素材和截图。
- 播放驱动修复已由 UI 提交 `1d86eba5` / `05731bbf`、集成提交 `677ae9d6` / `f8a11079` 接入：使用 `PROCESS_MODE_ALWAYS` 的独立 60 Hz 计时器驱动正式视觉帧，初始 3× 显示倍率真实应用，并由真实 SceneTree 时间推进、正式身体贴图区域切换和预览缩放回归覆盖“按钮切换但人物不动”。
- 人物脚点手动对齐由 UI 提交 `7855c2a9`、集成提交 `60348875` 接入：黄色角色地面原点、粉色 `36×18` 物理脚印和蓝色 `64×32` 地图菱形中心固定为同一 `(0,0)`；用户先点击鞋底中点定义蓝色视觉脚点，再拖动整套人物视觉或用方向键按 `0.5px` 微调使蓝黄重合。用户最终草稿 SHA-256 `5D01E19C509E9C970B928475263E233552EE50A00BE7C04FD3BF6BD1CFD088A4` 已由正式合同 `player.visual_ground_alignment.manual.v1` 和集成提交 `7de58783` 接入：人物视觉偏移 `(+7.5,+8.5)`、脚点修正 `(-7.5,-12.5)`，最终视觉脚点为 `(0,0)`；UI 提交 `52910b19` / `c8674538` 与集成提交 `db6b93a3` / `f874b275` 保证重开工具不会二次叠加该偏移。
- 辅助层同时显示角色坐标、正式视觉脚点、`18×9` 物理脚印、64×32 地面菱形与当前帧边界，用于直接暴露外观锚点和物理坐标漂移。截图只写入 `outputs/visual_acceptance/**`。
- UI 工作树与真实集成基线专项通过；正式接入最终回归 6/6：`player_visual_ground_alignment_test`、两项等距物理/脚印合同、`ui_visual_acceptance_lab_test`、`player_three_profession_visual_catalog_test`、`equipment_world_helmet_hidden_hair_test`。
- `item_236.json` / `item_240.json` 冻结 SHA-256 仍分别为 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` 与 `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`，本任务未修改任何头盔草稿或生成图。

## 2026-07-30 v38 无损精简发布

- 集成提交：`5137be3d`（怪物图集改用无损导入）、`a2b29e83`（Android v38 与生产排除规则）、`2bf81def`（APK 资源完整性验证与可选基线变化证明分离）。APK 对应运行时提交为 `a2b29e83`。
- 最终 APK：`outputs/hardcore/HardCore-slim-v38-debug.apk`；`244,091,990` 字节（232.78 MiB）；SHA-256 `562082FD18DC51ECB65F00F610EDF82295B9A92FDA98BDB0B1D73C5765FA4D43`；`versionCode=38`、`versionName=1.17.2-slim`、包名 `com.personal.mafaoffline`、应用名 `HardCore`，v2/v3 签名均通过。
- 相比 v37 的 `1,648,238,897` 字节减少 `1,404,146,907` 字节（约 85.2%）。核心收益来自 580 张怪物 PNG 的 Godot 无损压缩导入：编译纹理由约 1,303.12 MiB 降至 78.06 MiB；原 PNG 聚合哈希、580 个 `.uid`、像素和运行时稳定 ID 均未改变。
- 生产排除仅覆盖确定不参与运行时的地图原始批次、staging `source/rgba_native`、调色板源图、墙体预览及 UI/装备设计源文件；地图运行时 fallback 所需的 174 个 `editor_canvas` 导入全部保留。
- APK 独立资源探针通过：12 个关键编译脚本、男性 `Hair.wil block 4` 六动作、世界头盔隐藏、纸娃娃 base/hair、12 个头盔 patch、586 帧技能动画、580 个怪物 CTEX 均存在；怪物 CTEX 不含 ETC2/S3TC/VRAM 压缩标记。
- 当前真实集成基线验证：怪物专项 15/15、地图/怪物定向专项 4/4、完整关键回归 74/74 全部通过。14 份冻结头盔草稿/正式合同、视觉目录与纸娃娃头部 patch 构建前后 SHA-256 零变化。
- 清理完成：删除所有旧 APK、旧视频/截图/日志/重建预览、未跟踪旧审计快照，以及主树和现存工作树的可再生 `.godot`/`outputs` 缓存；保留最终 v38 APK、`complete_local_mir_sources`、`complete_client_frame_catalog`、永久工作树、所有 dirty/冻结素材和 `dev_art_sources` 只读主资料。

## 2026-07-29 v37 运行时实证修复

- 集成运行时提交：`53514548`；Android `versionCode=37`、`versionName=1.17.1-runtime-proof`，角色选择页显示 `release.runtime-proof.v37` 构建指纹。
- APK：`outputs/hardcore/HardCore-runtime-proof-v37-debug.apk`；SHA-256 `6E12C921D7A234E6C508DEE76AB1331E81D7B16B96865E78F9F8B1D1E4D76456`；大小 `1,648,238,897` 字节；包名继续为 `com.personal.mafaoffline`，签名 v2/v3 通过。
- 存档升级到 v5：中央技能栏 4 格与攻击环 3 格独立保存和触发；旧四格档只迁移一次。debug APK 首次启动会把旧测试人物移入 `user://test_roster_archives/`，清空活动索引并严格生成 9 个 `test.character.<profession>.<tier>.v2` 人物；战士/法师/道士分别为 6/14/13 个完整技能。
- 纸娃娃 classic base 与男性头发改为编译期 preload，动态资源失败时再走正式 world-avatar 可见回退，禁止静默空白；角色选择、背包和 HUD 生产入口均有回归。
- 玩家施法改用 canonical 学习状态；新增真实角色→HUD→Player→GameRoot 技能结算和 Enemy→Player 三帧受击硬直 E2E。世界人物继续隐藏所有头盔层并使用主资料库男性 `Hair.wil block 4` 六动作。
- 当前集成专项 15/15、完整关键回归 74/74；独立 APK 探针确认 12 个关键编译脚本变化、世界头盔四项 `false`、男性头发六动作、纸娃娃 base/hair 与 12 个头盔 patch、586 帧技能动画。14 份冻结头盔草稿/正式合同 SHA-256 全部零变化。
- APK 从固定提交的全新工作树和全新 `.godot` 缓存导入、导出；隔离构建临时目录已从 Git 注册表移除并移入 Windows 回收站，可恢复。

## 30 秒启动顺序

1. 完整读取根目录 `AGENTS.md`。
2. 运行 `git branch --show-current` 和 `git status --short`。
3. 阅读本快照对应专业段落，只打开“最小必读”中与当前问题有关的文件。
4. 专业修改在永久工作树完成；集成主树只调度、审查、逐项合并和验收。
5. 不因本快照而跳过当前证据核实；也不在未触及领域重复全量扫描或旧测试。

## 当前集成基线

- 主目录：`C:\Users\Administrator\Documents\HardCore`
- 分支/运行时代码基线：`codex/integration` @ `5ee31695`（本次快照提交只改本文档）。
- tracked 状态：黑铁头盔 151 的旧 `scale_100` 六动作生成图集共 6 个既有在制修改继续保护；本次男性头发接入未暂存、覆盖或提交这些旧图。146/147/149/150/151/218/224/228/232 共 9 份已验收人工草稿继续冻结；236/240 最新人工草稿分别为 SHA-256 `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC`、`81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457`，均保持 dirty 并禁止覆盖。
- 未跟踪状态：既有审计/报告输出与 Godot 生成的 `*.gd.uid` 继续保护，不得顺带清理或提交。
- 当前无待合并专业提交。
- `52b54608` 完成本轮 Android 集成测试包配置：应用名继续为 `HardCore`，兼容包 ID 继续为 `com.personal.mafaoffline`，versionCode `36`、versionName `1.17.0-full-integration`、目标架构 `arm64-v8a`；导出排除测试、文档、开发原稿、校准草稿、审计输出和高清 `scale_100` 编辑资产，运行时合同与正式成品保留。
- `35568e45`（装备提交 `26f25e39`）和 `6827bb7d`（职业技能提交 `ce58f7bc`）只修正已经过时的测试期望：正式武器可见性改为罗刹/嗜魂法杖/鹤嘴锄可见且只剩落魄神兵未解析；烈火测试改为 canonical 一次充能语义。两项均未改运行时合同、素材或用户冻结数据。
- 本轮真实集成基线验收：装备套件 17/17、战士技能套件 18/18、跨领域发布专项 17/17、完整关键套件 74/74 全部通过，`SMOKE_TEST_PASS`。技能主源共 33 项；26 项正式法师/道士主动技能视觉共 586 帧，fallback 为 0。
- `698482bf`（装备提交 `6249ed86`）按用户指定切换为主资料库经典 `Hair.wil block 4`（男性外观 2）；与同发行版 `Hum.wil` 使用相同 600 帧动作块和 Hot 坐标。idle/walk/attack/cast/hit/death 共 232 个目标帧全部存在且非空，直接组图，无缩放、旋转、插值、补帧或低级来源替换；世界人物继续隐藏全部头盔层。
- `92b3bdba`（UI 提交 `2e0fba4a`）修正纸娃娃装备头盔时错误隐藏男性头发的问题。`classic_avatar` 现在始终绘制男性头发，随后按衣服、武器、头盔顺序绘制装备，使头盔位于头发之上；可见边界同样始终计入头发。240 用户最终纸娃娃头盔直接加载回归、人物选择、背包刷新、三职业换装专项 7/7 与装备全套 17/17 通过；纸娃娃、背包、地面、11 份人工草稿及四份正式合同共 15/15 哈希不变。
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
- `4a52cc54` 与 `b0235f07` 完成最终纸娃娃整改：12 个男性头盔严格由原客户端 StateItem 主资料按原坐标派生透明头部补丁及擦除遮罩，禁止 AI 重绘；人物选择与装备页默认使用高清透明 `classic_avatar`，当前固定按人物底图→男性头发→衣服→武器→头盔绘制，头盔在头发之上，完整 Prguse #376 底图、装备槽和矩形背景永不进入玩家界面。三职业×沃玛/祖玛/赤月 9 个独立真实存档、itemId/name-only 旧存档解析、角色选择、装备实时刷新与受控可视截图均通过。
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

- 状态：最新完整集成 Android 精简测试包，headless import/export 均成功并完成独立 APK 元数据、架构、清单、运行时资源与签名验证。
- 文件：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-slim-v38-debug.apk`
- 构建时间：`2026-07-30`
- 大小：`244,091,990` 字节
- SHA-256：`562082FD18DC51ECB65F00F610EDF82295B9A92FDA98BDB0B1D73C5765FA4D43`
- 包信息：`com.personal.mafaoffline`，versionCode `38`，versionName `1.17.2-slim`，应用名 `HardCore`，`arm64-v8a`、横屏。
- 签名验证：APK Signature Scheme v2/v3 均通过，签名者 1；证书 SHA-256 `c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc`，与上一测试包签名者一致，可覆盖安装并保留兼容存档。
- 本包包含当前集成分支全部正式运行时工作：33 技能及正式技能动画/图标、硬直与受击中断、完整装备属性和穿戴、纸娃娃/背包/地面头盔展示、世界人物隐藏头盔并使用经典主资料库男性 `Hair.wil block 4` 全动作头发、男性衣服/武器外观、三职业九个满技能测试人物、地图/碰撞/遮挡、怪物外观与 v4 脚下光圈、UI 与角色存档兼容。15 份受保护头盔草稿和正式合同构建前后 SHA-256 全部不变。

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
- monsters：`monster.overhead_anchor.v4`、`monster.overhead_layout.v3`、`monster.ground_alignment.manual.v1`、`monster.ground_contact.v5`、`monster.ground_contact.calibration.v5`；212 个 `monster_id` 使用用户冻结草稿，猎鹰 97/98 保留飞行投影，贴图异步激活后必须刷新。
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
| `HardCore-worktrees/monsters` | `codex/monsters` @ `90f3f716` | 本轮任务文件 clean；既有 UID/报告继续保护 | 最新 212 份人工脚点已冻结导入；黄色目标光圈以人工脚点为圆心、按对应怪物物理脚印 `1.25×` 同比放大，已作为 `b478b7cc` 集成；专项 10/10 通过 |
| `HardCore-worktrees/ui-art` | `codex/ui-art` @ `dabd8872` | 本轮代码 clean；Godot import/UID/输出继续保护 | 验收台橙色正式光圈改为直接读取游戏运行时目标光圈几何，已作为 `ed3d850e` 集成；UI/怪物联动 2/2 通过 |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` @ `0929efa3` | 既有 UID/输出继续保护 | 33 技能 runtime、150 条可执行语义合同和 26 项正式主动技能视觉已集成；魔法盾常驻正式末帧、抗拒火环逐目标实例映射和火墙精确四格判定已分别作为 `298bd6a2`、`1bfe0872`、`3e99079f` 集成 |
| `HardCore-worktrees/equipment` | `codex/equipment` @ `26f25e39` | 既有 monster import、试点截图脚本、UID/生成项继续保护 | 男性 `Hair.wil block 4`、世界头盔隐藏、纸娃娃/背包/地面头盔均已集成；`26f25e39` 的正式武器可见性测试修正已作为 `35568e45` 集成，冻结草稿与生成图继续保护 |

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
2. 待复验：下一版 APK 中比奇省、兽人古墓的黄色选中光圈必须以最新人工脚点为中心，大小随怪物体积变化；正式 WIL 长条阴影保持原样。
3. 待验收：角色选择页出现 9 个独立测试人物；三职业各有沃玛、祖玛、赤月三档完整装备并学习本职业全部技能；列表整块区域可直接上下滑动。
4. 待验收：法师、道士不再显示占位符；世界人物全动作显示经典男性头发且不显示头盔，纸娃娃/背包/地面仍保留头盔；男性基础形象、正式散件/套装换装、装备界纸娃娃居中和神兽动画正常；禁止重新引入女性角色资产。
5. 怪物名字固定在血条上方；各体型血条位于各自真实身体顶点上方约 8px，不再统一过高或随动作抖动。
6. 血球/蓝球恢复孔径尺寸且左右对称。
7. 拾取提示居中；技能配置弹窗背景不越界；快捷技能可置换；烈火点击后显示“充能”，800ms 后下一次有效近战消费，空挥保留，8s 内不可重复充能，绝不自动释放。

用户实测结果优先级高于内部测试；若实机失败，先保存截图和 APK 哈希，再按所属专业工作树返修。
