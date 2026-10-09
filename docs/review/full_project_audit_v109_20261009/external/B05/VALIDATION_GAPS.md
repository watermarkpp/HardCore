# B05 验证缺口和最小门禁

固定审计源码 `dfcfb9cda1b88d71d7cca3b432ba812831d93c23`。本批**没有执行Godot native/PC headless/Android/APK**。旧原生验证只能在相关代码及合同未变化且对应条件真实覆盖时复用；B02视觉terminal已闭合结果不在本批重跑，也不当当前Android帧率成功证据。

## 新发现有界专项

- **B05-001：暂停屏障**。四快捷物品之一由手指A按下；同时手指B操作摇杆或按住攻击，Android返回键/菜单打开暂停并关闭后分别提供/丢失旧A抬起事件，含暂停期间Timer过期。必须验证`PlayerState.use_quick_item_slot`无旧手指导致的额外成功commit，HUD绑定不变，新A DOWN仍正常。对照手动无触控焦点变化（旧APP_FOCUS_OUT路径已经会cancel）。
- **B05-002：Scroll owner竞争**。SkillPanel/InventoryPanel ScrollContainer，A已滚动，B按其它手势控件/空白，A继续滚动与释放；`TouchScrollSupport`全局`touch_scroll_drag_active`/release guard应保护此前滚动，按钮不得误激活。B先A后、A取消、控件退场等负向也必须覆盖。
- **B05-003：长期音效账本**。固定30+怪真实攻击数/完成量/可播放比例，跟踪`AudioRuntimeService._owner_release_seen.size()`、p95/p99帧回调、音频voice容量、内存曲线，重复同release不可再播但新release一次有效。确认无需创建第二个声音服务/HP时钟，且不会恢复怪物发现音效。
- **B05-004：单长按Timer**。仅要求主控裁决：同时两快捷槽DOWN是否存在一位最新holder、旧holder能否继续普通tap、是否需要同一modal下两个独立hold；未经授权不能改。复现实验可复用B05-001多指脚本。
- **B05-005：首次主线程资源准备**。PC/Android各记BGM PCM `load`（8,499,244bytes）与SFX prewarm（176 WAV源路径、24,965,478bytes源文件）耗时、首个可操作帧、音乐6秒启动和播放期间callback负担独立采样。不能从字节数推断目标60FPS，避免音频质量、播放时钟或Volume0变化。

## User-accepted视觉的必要设备边界

- 手指移动/按住普通攻击和法术期间点4快捷药；真实Android物理触摸Index、GUI Rect2与popup安全区遮罩/Modal/暂停，先后触控布局位置不变。
- 已验收底盘缩小20%、6技能放大20%、攻击缩小15%、摇杆放大20%并稍北、换敌与交互放大20%、4快捷药图保留原图尺寸并alpha居中、目标栏普通中文文字和完全填充血条背景、装备24pt标题及已批准金色镶边。不重新设计；仅图像/手感检验。
- `StartupLoading/BrandIntro` 第一个可见真实帧必须既有HardCore CG、Loading文字和0%进度同时出现，2px屏幕尺度边框、opaque Loading不漏旧地图; native frame_post_draw与headless证据不同，不能拼接。
- 首次无偏好有声、v2显式合法0仍静音、主/备坏文件退回1.0；SFX用户0只在服务内一次性降低gain，药/伤害cue已提交才播；Android应用后台/前台焦点、蓝牙/声音通道中断尚未设备验证，**不能未测就增加定时轮询**。
- 音效怪物发现/进入战斗提示退役；BGM有先资源预备后延迟6s播放，天然48s one-shot而不是敌人声画的循环请求。退出必须释放prepared sample/voices。
- B04延续的装备预览：InventoryPanel明确`classic_avatar`，角色默认`world_avatar`，不能用旧完整装备窗填充UI；真实PNG/WIL透明裁剪、头盔素材与font相交属于B07像素审计。

## 未覆盖区（诚实保留）

源manifest 161个固定文件逐条字节读取，但只有B05相关的18个核心脚本含函数语义审查；其余6个大型业务Panel部分、34条JSON资料、12条地图编辑/视觉工具、74条地图runtime.visual、2个SVG和视觉样例等均明确在COVERAGE.json列明角色/未审分支。大量地图资源内容需要B06解码作者/编译器，不以“读过文件”声明通过。

未审生产业务：GameRoot/PlayerState其它职责B08，装备交易B04仍有待补、B06地图/存档、B07导出/美术/生产生成链。不存在B05单项全游戏release PASS。

报告生产改动：NONE，真实分支HEAD可能比固定`dfcfb9cda1b88d71d7cca3b432ba812831d93c23`更新；报告SOURCE_BINDING固定此SHA、不借后来修复替换本轮静态证据。
