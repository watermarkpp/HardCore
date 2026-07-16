# BRAND-INTRO-1：游戏图标与开场动画报告

## 完成结果

用户提供的骷髅图已成为游戏正式图标、Godot内置加载画面和动态开场主体。动态开场固定显示：

> 刷是一种状态，刷没有目的没有终点

启动顺序为：系统应用图标 → 品牌静态加载画面 → 品牌动态开场 → 角色选择界面。Godot默认标志不再显示。

## 母版与派生资源

- 用户母版归档：`dev_art_sources/user_provided/branding/game_icon_master_20260715.png`
- 母版尺寸：1254×1254，RGB
- 母版SHA-256：`079c9afa23139a73b79ca6cb5910c46678ac3910d191803d1e0c6f78c1904664`
- 正式游戏图标：`assets/branding/game_icon.png`，1024×1024
- Android启动图标：`assets/branding/android_icon_192.png`，192×192
- Godot加载画面：`assets/branding/boot_splash.png`，1280×720
- 来源与输出清单：`assets/branding/brand_manifest.json`

本次没有使用生成模型重画，也没有改变骷髅、角、宝石或背景造型。所有运行资源都由母版进行确定性LANCZOS缩放和黑底横屏排版，可用`tools/build_brand_assets.py`重复生成。

## 动画与启动配置

- 新主场景：`scenes/brand_intro.tscn`
- 动画脚本：`scripts/brand_intro.gd`
- 下一场景：`scenes/character_select.tscn`
- 动画表现：黑底淡入、主体缓慢放大、红色余辉脉冲、文字逐步显现、黑场淡出。
- 用户在播放1秒后可通过键盘、鼠标或触屏跳过；不操作时自动进入角色选择。
- `project.godot`的图标与内置启动图已改为品牌资源；Android导出预设也显式指向品牌图标。

Godot场景代码只能在引擎初始化完成后执行，无法在引擎加载阶段播放自定义动画。因此本项目将内置Godot加载标志替换为同一品牌静态图，随后立即进入动态开场，从视觉上保证游戏品牌始终先出现且不露出Godot默认标志。

## 验收

- Godot 4.7资源导入：成功，退出码0。
- 品牌专项测试：通过；图标、启动画面、主场景、下一场景和完整中文均已连接。
- 真实OpenGL验收图：`outputs/visual_acceptance/brand_intro_20260715.png`。
- 完整关键回归：50/50通过。
- 本轮未构建APK。
