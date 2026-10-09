# HardCore 109 · B05 HUD、真实多指、Loading、音频与视觉审查

**固定审计源码：** `dfcfb9cda1b88d71d7cca3b432ba812831d93c23`；审查分支 `codex/v108-runtime-bug-review-20261009`。本轮只读独立审查，不采用主控并行推进后的生产修改；除将七份报告新增到 `external/B05/` 外不写生产、测试、场景、配置、源数据；Godot、APK、Android：**NOT_RUN**。用户选定的极高模式来自用户界面；本报告不声称能通过提示词切换模型。

## 范围与静态门禁

依原`AUDIT_SCOPE_MANIFEST.json`的`audio_presentation_ui` 154份和`presentation_scene_assets` 7份，共**161个原始文件**，逐一读取固定SHA的Git原始blob字节、绑定Git SHA/文件大小。`COVERAGE.json`逐条分组：17个明确B05核心功能语义审查、1个`hud.gd`（3075行）重点UI/触控分函数审查、6个大型商店/技能/仓库/装备编辑UI部分职责、4个Shader源码语义、4个正式场景绑定、34条资料角色/消费者部分、2条SVG、6条源工具、12条地图捕获/编辑工具、74条非UI的发布地图视觉资料与1个技术样例场景。**161个被读过≠161个全部完成语义深审。**74个map.visual属于B06地图发布链；装备视觉最复杂的资源/姿态对照属于B07；大文件无关业务交B08，不能因路径被混入B05就误判为UI代码。

## 已追通的正式链及用户冻结视觉要求

1. **手指与输入权威**：`VirtualJoystick._gui_input/_input`拥有一个摇杆touch id，`CircularTouchButton`把普通攻击/技能的本地GUI DOWN与全局UP按finger token区分，`HUD._item_slot_input`用每pointer的`_item_slot_presses`保存4快捷物品触摸，正式`GameRoot._on_item_quick_slot_use_requested`检查Gameplay gate后调用`PlayerState.use_quick_item_slot`。能沿真实入口追到移动+按住攻击/施法+快捷药；但暂停统一取消不涵盖快捷格、共享长按计时器会被第二个物品指针重新归属（见B05-001/004）。`TouchScrollSupport`在全局输入处理注册的ScrollContainer/RichTextLabel，第二指针可以覆盖第一个滚动owner（B05-002）。主控应对这三者做**定向多指而非重画布局**。
2. **冻结布局**：`HUDChassisDesigns`的唯一有效`v3_dragon`尺寸656×218.4（旧820×273的80%），快捷药原尺寸图像清理、可见Alpha居中；Joystick源矩形与六技能环的已接受尺寸均留存。检查`HUD._build_approved_hud/_build_target_bar/update_target/update_quick_slots`、`QuickItemIconLayout.prepare_texture/visible_center`、`SystemFont.font_weight=400`普通目标字体、无描边、对满背景的target fill shader。技能六按钮+20%、攻击-15%、摇杆+20%稍北、换敌/交互+20%、装备金边与标题字号保持既有校准；不在本次审查中改版或声称截图真机验收。
3. **Loading+CG**：`StartupLoading.tscn`绑定`BrandIntro`，`brand_intro.gd`先呈现不透明第一帧/HardCore原资产再允许正式资源准备，失败有独立覆盖与重试UI；`LoadingTransitionOverlay.begin_loading`在`show()`前同步设置Loading文字/Stage/0%和可见进度背景，`PROGRESS_BORDER_SCREEN_PX=2`在屏幕transform下换算逻辑边框。交接`_emit_covered_after_present`在非headless实际等待`RenderingServer.frame_post_draw`且检查serial/transition_id，地图准备不会仅凭显示状态提前遮挡。设备首次像素仍属NOT_RUN。
4. **音频**：`AudioPreferences`在无有效v2文件时明确Music/SFX默认1.0、主/备文件和合法0均正确；`SystemMenuPanel`的HSlider 0~100发`ui.audio.setting.v2`到GameRoot，再到`AudioPreferences.set_level`，SFX预处理采用用户`*0.5`一次性线性gain、SFX Bus 0dB以免重复。GameRoot根据PlayerState已提交item receipt发使用药/穿脱装备音效，Enemy的音效仅沿合法`attack_start/attack_frame`提交，已退役的怪物发现、战斗循环提示在`AudioRuntimeService`资源查找前跳过，不发生无声重复decode。全局24声道固定播放池，部分音效由Feature PresentationPort持有弱引用lease，退出停播释放。**去重账本缺失有界淘汰见B05-003。**
5. **主城BGM**：`TownMusicController`将约8,499,244字节的PCM文件在GameRoot加入节点时同步`load()`、非运行时OGG解码，真实播放另在合法安全区+Loading完成后延迟6秒开始，曲目约48.18s one-shot，跨地图保持已播放曲目直到自然结束，仅退出/取消明确stop。AudioRuntime同时在GameRoot ready时构建24个SFX Voice并预热176个合法资源路径（固定Git源字节合计约24,965,478）。这两种**启动预备工作**与**播放期间每帧混音**必须分开计时，文件字节不等于实际Godot CPU毫秒或Android掉帧（见B05-005验证缺口）。
6. **人物/技能/装备表现**：B02已在后续提交闭合永久坏动画的terminal收尾，本批不重复审判；`GroundSkillVisualCell`仍为火墙Controller拥有时钟/伤害的纯表现。`WarriorMeleeVisualEffect`仅消费合法STRICT_V2冻结快照、拒绝无效样本，0.3s暂停感知tween收尾；`EquipmentCharacterPreview`按`world_avatar`默认，库存显式`classic_avatar`，从正式wear/头盔patch源映射，非第二属性公式，隐藏的legacy full-panel仅历史审计。库存装备标题金色24pt、特殊效果详情显示生效/零耐久不生效，现有UI源不需要“优化设计”。

## FINDINGS摘要及裁决

| 编号 | 级别 | 类别 | 说明 |
|---|---|---|---|
| B05-001 | P2 | 源码取消边界缺口 | `GameRoot._cancel_player_input_boundary`未撤销HUD快捷道具finger ledger/长按Timer，系统菜单暂停后旧按压可能恢复使用 |
| B05-002 | P2 | 源码多指归属抢占 | `TouchScrollSupport._begin_drag_candidate`第二手指DOWN无论是否属于滚动都覆盖当前滚动owner，正在滚动的第一手指后续DRAG/UP无法完成原手势 |
| B05-003 | P2 | 音效状态无界增长 | `AudioRuntimeService._owner_release_seen`对每次新monster attack release追加Key，只在world exit或test reset清空 |
| B05-004 | P3 | 产品策略待定 | 两个快捷格不同pointer可并行DOWN但仅单一长按Timer，先前长按owner被后续DOWN覆盖；不得机械强行一指独占或更改技能/药品行为 |
| B05-005 | P3 | 性能验证缺口 | TownMusicController在GameRoot ready同步load PCM+BGM，SFX同步预热；需冷启动同源计时证明，不能凭字节大小定FPS/做长帧优化 |

**已闭合/不可重报：** B01/B02视觉终态修复及相关35项原生边界结果、AudioPreferences冷启动默认有声+合法0、系统菜单保存退出错误可见、怪物发现/进入战斗提示完全退役、本轮明确授权布局都保持冻结。不能把已修复Bug复记或把缺少Android设备实测当源码Bug。

## 本批整体判断

静态`B05_REVIEW_WITH_ACTIONABLE_GAPS`，未提交任何生产修复或执行原生测试，不授权109 APK。建议优先复现B05-001暂停旧道具指针（用户物品影响），再B05-002双指滚动的触控流、B05-003战斗长跑内存；对B05-004先获得产品独占规则，对B05-005先观测真实加载耗时。设备布局音频焦点验证仍`NOT_RUN`。

提交仅包含七份报告且`SOURCE_BINDING.fixed_source_sha`固定上述SHA。GitHub提交/接收不等于新源码发布验证。
