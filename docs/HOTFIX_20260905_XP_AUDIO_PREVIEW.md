# 2026-09-05 经验、HUD 与音频 hotfix

基线：`e263cc93713f6863e293d2b0c03c83c657eb7034`（主树）。
目标安装基包：审计里程碑 `70 / 1.19.0-audit-milestone`，构建源 `52ae0565856c2d99a28639b2bf0c6278186e0858`。

## 用户范围

- 人物升级门槛变为原值的 10%；经验奖励数值、死亡损失规则不乘倍。
- 经验条横向覆盖第一个快捷物品槽左外框至第四槽右外框；保留样式。
- 暂停当前技能音效，保留未来恢复能力，不静音背景音乐。
- 用户提供的 `1788586979404.m4a` 用作统一城镇音乐；Loading 结束 10 秒后单次播放，每次入城重新允许播放，离城/切图取消旧播放。
- 升级脚下发光动画仅进入校准器预览。用户确认以前不接入正式升级事件；后续接入须保证一次杀怪/任务经验结算连升多级仅播一次，失败回滚不得播。

## 冻结与交付边界

不修改地图发布数据、怪物刷新、AI、碰撞、已验收技能图标、装备和存档格式。不重置手机存档，不覆盖已交付里程碑 APK 或标签。

本次动画存在明确的用户视觉确认门禁。校准器预览通过自动测试不代表用户已认可，也不代表手机已安装或验收。当前文件为施工记录，最终测试、补丁身份与设备状态将在取得实际证据后补齐。

## 施工与预览状态（待确认，尚未打补丁）

- XP、HUD、技能静音、音乐控制器及 GameRoot Loading 接线已经修改。专项 `progression_test`、`hud_gothic_runtime_test`、`ui_level_up_preview_test`、`town_music_controller_test`、`warrior_client_art_test`、`initial_world_bootstrap_test` 通过；主控独立 `town_music_runtime_test` 通过，证据 `outputs/test_logs/runner_results_adhoc_20260905_203839.json`，0 engine errors。均为基线上的工作区测试，不是已提交 HEAD 的证据。
- 原 `game_root_loading_transition_test` 在第 24 行“test mode must preserve synchronous travel”断言失败，未修改旧断言；尚未独立复验基线，因此不宣称这是已证明的既有失败。
- 实际 GUI 预览发现 Variant 推断编译错误，已显式标注类型修复。截图又发现出生点水井遮挡人物，专用 `-LevelUpPreview` 模式将冻结、无保存的校准人物移到空地；默认校准器和游戏出生点不改。
- 用户指出动画感觉卡顿：发现自动预览每轮在峰值人为停顿 0.85 秒。已移除中途暂停和状态代码，重新打开连续播放预览（不截图），只保留每次完整动画之间 0.65 秒空隙。尚未据此声称实测帧率无问题。
- 校准器入口：`tools/launch_ui_layout_calibrator.ps1 -LevelUpPreview`；日志 `outputs/test_logs/ui_layout_calibrator.log`。动画仍仅预览，无升级事件接入。
- 音乐范围待用户选择：正式数据没有独立 town_boundary；比奇运行时安全区仅出生点周围 9GU，另外四城为各自 authored safe-area。当前候选按这五图安全区触发，不能声称覆盖整座城市。已询问用户选择安全区或整张主城所在地图。
- 用户最终明确选择“按主城安全区触发”，以上范围问题已关闭。离区/切图停止并取消延时，同一次入区仅播一次。
- 尚未提交、push、制作 PCK 或安装手机。导入产生的额外 `.gd.uid` 尚待按本次起始 clean 状态精确整理，不属于已确认交付范围。

## 后续动画裁决

- 用户明确确认脚下椭圆光圈符合游戏视角，冻结该光圈；仅十字与环绕线段返工为光焰。光圈绘制区（从椭圆 draw_set_transform 到复位 ONE，LF 归一）的 SHA-256 为 `65BCB440EF701E76D0BA288F5154FCE353795AD6E6C96304DDAEA491E3332DA1`。
- 用户随后表示“动画通过”，又明确允许“调整到位，然后直接采用”。因此光焰几何/可见度可修正并直接接入，不再要求二次动画确认；脚下光圈冻结仍有效。
- v2 的真实 GUI 渲染暴露 `Invalid polygon data, triangulation failed`；headless 状态测试没有发现这个问题。后续版本须补全动画进度与各光焰片的三角化检查，并以实际渲染零报错验收，不能只屏蔽日志。
- 正在接入 `PlayerState.levels_gained(previous_level, new_level)`，成功经验结算后发出一次；正式组件作为玩家子节点且 z=0，随人物移动；退出世界断开信号。`tests/player_level_up_effect_runtime_test.tscn` 为新增集成专项，结果尚待执行。

## 一级库技能音效核查：按用户条件放弃本次恢复

用户追加条件：只有完整才接入；不完整就放弃。`client_assets` 主源 `dev_art_sources/reference/mir2_client_raw` 实际有 544 个 WAV，worker 验证文件头及 ffprobe 可读 544/544；`Wav/sound.lst` 有 528 条非空映射，其中 9 条引用缺失文件。主控独立确认 `sound.lst` 第 784 行附近 `10110/10111 → wav/M11-1.wav` 的文件不存在，WAV 计数为 544。

规则一级源 `dev_art_sources/reference/original_gameofmir/MirClient/ClMain.pas:2423` 和 `Actor.pas:2318` 使用 `wMagicId → MagicSerial`，随后按开始/飞行/爆发等阶段播放。尚未形成当前 33 个稳定 skill_id 与这些序号、实际文件的完整核验映射。源码明确无独立音效的阶段不应仅因空项判为缺失，但目前证据仍不足以声称 33 技能全部准确可用。

结论：这次不恢复技能/普攻声音，`SKILL_AUDIO_ENABLED=false` 保持。未采用辅助级来源、未猜测对应关系。用户提供的城镇背景音乐是另一个已授权范围，不受此放弃决定影响。

## 最终视觉确认

用户再次验收“ok 动画合格”：光柱宽高为调整前的 75%，按实时地面投影 y 动态切换前/后层，背景层 `show_behind_parent=true`，两层均在 actor z=0；脚下光圈保持原样。最终视觉组件文件 SHA-256：`3C338B687343CDFC3A6ED4FA3AACF4768EE4443259AE37AEE27EC36812369E48`（提交前工作区字节）。

专项 `ui_level_up_preview_test` 和 `player_level_up_effect_runtime_test` 分别在 `runner_results_adhoc_20260905_212222.json`、`runner_results_adhoc_20260905_212238.json` 通过，0 engine errors。主控实际 GUI 预览 `outputs/visual_acceptance/level_up_preview_depth_75.png`，`ui_layout_calibrator.log` 零 ERROR；前后层随同一瓣旋转跨界的断言已覆盖。此确认冻结视觉，不等于手机已安装。
