# B05 视觉与音频冗余候选（只登记，不删除）

**只读固定提交：** `dfcfb9cda1b88d71d7cca3b432ba812831d93c23`。删除可能触及Scenes、资源、preload、autoload、反射、fixture和authoring，仅因主路径没直接调用某函数不能判dead code。

- `scripts/hud_asset_sanitizer.gd`：可从HUD读取到旧alpha组件/底盘旧技能残影清除，部分命名为legacy不代表已脱离正式图像准备。当前唯一v3_dragon底盘使用固定图，但其它图片可能通过UI texture/scrubber调用。没有静态ref完整闭环与性能/像素测试，不删除。
- `scripts/helmet_visual_v2.gd::persist_*()`：多种显式editor校准写入函数当前`git grep`未找到直接Gameplay调用。它们属于B07 authoring而非“后台偷偷写UI资源”；若未来清理须检查编辑器工具、Godot callable和旧校准工作流。不能因名字/grep缺少直调就判无用。
- `scripts/prepared_music_stream.gd`：TownMusicController保留preload历史诊断API，而现有正式BGM已采用预编译PCM；保留历史测试/证据用途候选，未经所有fixture/运行工程引用检查禁止删除。
- `SystemMenuPanel._audio_toggle/_on_music_toggled/_on_sfx_toggled`：可读到legacy v1布尔设置适配，但现网实际使用v2数值HSlider。保留旧合约兼容及测试，需验证完全无动态引用才可退役。
- `GameHUD.loot_label`：已由PlayerNoticePresenter取代文本显示，HUD注释称仅保留旧布局锚点/校准兼容。删除可能破坏历史UI布局或无障碍，非证明空引用。
- `TownMusicController`不是`AudioRuntimeService`第二个全局音效owner：前者受主城安全区+Loading并拥有一个Music bus PCM player，后者拥有SFX池及主声道SFX路由；不能合并以为降CPU。
- `FireWallFieldController`与`GroundSkillVisualCell`、`WarriorMeleeVisualEffect`与正式伤害不是重复计算：前者独占HP/tick，后者只画冻结几何与0.30s短表现，不产生第二次命中或新的技能planner。
- `scenes/tools/mafa_scene_editor.tscn`、`scenes/technical_art_sample.tscn`、`tools/map_editor/*`、74个runtime.map_visual source不是运行时HUD冗余；地图authoring/发布链B06+B07，保留原来的B04 cross-batch范围。
- HUD`attack_ring`已按用户确认6个席位。不能因为有旧兼容5个字段或历史底盘尺寸删除当前6按钮，也不得擅自恢复旧艺术样式。

**无可凭当前证据安全删除的生产资源或代码。** 没有任何同工作量CPU/真实GPU收益验证，因此删除/合并建议：NONE。
