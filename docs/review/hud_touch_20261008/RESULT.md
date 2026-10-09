# 主界面触控、尺寸、药水图标与目标血条

核验时间：2026-10-08（Asia/Shanghai）。工作区 C:/Users/Administrator/Documents/HardCore；分支 codex/integration；HEAD 215f0b2f651a51e6855ee813ddd99221690311a1。本轮保留已有音频、拾取、特装和群怪混合 dirty 改动，没有 commit、push、版本修改、APK 或安装。

## 用户要求与实施

六个技能按钮及图标放大20%：按钮72→86.4，图标50→60。中央攻击按钮及图标缩小15%：按钮120→102，图标90→76.5，外框128→108.8。技能环半径125→140，避免相邻放大圆形点击区域重叠；攻击中心保持不变。换敌/交互外框76→91.2，实际圆形点击区域与外框同尺寸、同中心，位于技能按钮上方，中心 y -377→-337（向南40）。摇杆152→182.4，底盘及旋钮同比例放大，水平中心保持，垂直中心向北16。

四个快捷槽的正式外框像素坐标保持不变。旧点击范围只覆盖132×135源像素的黑色内孔，改为登记的184×184源像素可见槽位外框（约55.5逻辑像素）；计数文字依旧在原内孔右下角。输入使用实时 Control 变换，按独立触点登记 DOWN、DRAG、UP。槽内超过12像素的轻微漂移仅取消长按，不再吞掉普通点击；出槽/系统取消/失焦/切图取消不耗药，外部释放清理归属。移动、攻击、技能和两个快捷槽同时按下互不覆盖归属。换敌/交互沿用正式圆形输入生命周期，排除触摸生成的模拟鼠标重复事件。

只处理用户指定的两种超级药水：超级治疗药水对应正式“超级金创药” hc.item.920017 / Items_00315.png；超级魔法药水对应正式“超级魔法药” hc.item.920042 / Items_00316.png。原20×25源图字节保持；正式显示清理各图 x=0、y=16..20 的独立五像素 alpha 杂点，瓶身 RGB/alpha 和原尺寸不变。按清理后的 alpha 加权视觉中心摆放，两图分别为(13.884615,13.542735)和(14.040179,13.589286)。处理结果和中心按纹理缓存，不逐帧扫描；其它物品原纹理与普通尺寸中心保持不变。

目标血条过去只有可变宽红色填充，没有完整不透明底色，低血时露出世界背景；旧矩形也没有覆盖源框内孔上边缘。新增 authoring 合同和离线生成器，从原框的中央封闭透明区域生成17121像素的精确掩膜，范围 Rect2i(99,33,464,39)，原660×109装饰 PNG SHA256 e595460b66850d568a193410fff9a67d0d56d14718ea7721a5b9108af3edceaf 保持不变。运行显示层为完整不透明底色→同掩膜按HP比例裁切的红色→原装饰框→单一文字。只覆盖内孔，不向外扩张装饰像素。用户最新要求：目标文字使用普通400字重、非斜体、无描边/阴影，原18字号和居中位置保留。

## 正式文件

- scripts/hud.gd、scripts/hud_chassis_designs.gd：尺寸、归属、变换、槽位外框、血条与普通字体。
- scripts/hud_utility_touch_button.gd：正式圆形归属与合法释放的一次触发。
- scripts/quick_item_icon_layout.gd：精确两个稳定ID与源路径限定的缓存显示清理。
- assets/ui/gothic_hud/v2/target_bar_fill_mask.source.json、tools/build_hud_target_bar_mask.py：掩膜权威输入与生成链。
- assets/ui/gothic_hud/v2/runtime/target_bar_fill_mask.png、其.import、target_bar_fill.gdshader、scripts/ui_generated/hud_target_bar_mask_geometry.gd：生成输出与按HP裁切。
- tests/hud_multitouch_quick_items_test、hud_touch_layout_20261008_test、hud_target_and_potion_art_test、hud_gothic_runtime_test、android_layout_test、circular_touch_button_lifecycle_test、hud_runtime_capture：直接专项、关联回归与实际截图。

hud.gd 的移除点击特装等更早改动来自已授权特装阶段，保留并引用其原记录，不归为本轮新增。

## 检查与证据复用

原生运行均使用本树 tools/run_godot_tests.ps1、headless、隔离 .godot/runtime_appdata，普通场景30秒，无固定FPS。最后两次原生 invocation 之间只修正三个测试的预期，生产源码没有改变：

1. runner_results_adhoc_20261008_133918_168_18480.json：真实多点快捷槽、Android正式主世界布局/交互、战士/目标文字居中3 PASS、原生退出0；另外3 FAIL完整保留。
2. runner_results_adhoc_20261008_134252_349_24364.json：修正上述3夹具后，药水/血条像素与普通字体、尺寸/圆形边界、完整HUD回归3 PASS、原生退出0、0引擎错误。

三项夹具修正原因：源内孔是曲线，中央上边缘开放行34而非全局包围盒行33；保持20×25尺寸的浮点值用近似几何比较；蓝药水视觉中心与红药水不同；可见外框点击区域是用户本轮授权变化，旧第二处断言仍要求黑孔大小。没有放宽真实业务、去掉杂点/居中/原像素保持断言或绘制装饰像素。

此前已留圆形生命周期和快捷物品→主世界消费者相关PASS；最新变化不修改底层生命周期或物品使用主线，按函数边界复用，不重复跑。音频、拾取、特装和群怪原证据均按原范围复用，不将本轮UI结果冒称其新的整体验收。早期取消触点耗药的实际FAIL、浮点/旧断言FAIL、一次错误枚举解析FAIL，全部原receipt保留。普通runner单场日志存在覆盖边界，历史失败原生日志集合为MISSING；最终六场原生日志已在native_logs按字节保全，不冒称历史日志完整。

两次最后实际命令、完整receipt、逐项producer原生退出、源码/输入/引擎指纹和原失败见 VERIFICATION.json。当前diff及diff --check均审阅；已有无关现场保留。

## 实际渲染与开放验收

实际 Godot OpenGL compatibility、AMD Radeon RX 6750 GRE 12GB、1598×720，使用正式 GameHUD 和既有世界背景fixture，四槽真实正式物品图标；不把背景fixture冒称手机游戏现场。左右安全区73/77，使用正式居中校正。仅这次用户要求的视觉预览启用GPU，console隐藏/屏外、独立 .godot/runtime_appdata/hud_preview_20261008_final。进程21584正常退出0，stderr为空。

- 完整实际画面：outputs/visual_acceptance/hud_runtime/hud_20261008_final.png。
- 快捷槽实际像素4倍近邻放大：hud_20261008_final_quickbar.png。
- 目标血条实际像素2倍近邻放大：hud_20261008_final_target.png。
- 原生日志：outputs/test_logs/hud_preview_20261008_final.stdout.log / .stderr.log。

视觉确认由用户看实际画面后决定，目前 NOT_RUN。APK: NOT_RUN；DEVICE TEST: NOT_RUN。PC专项和GPU截图不证明手机触感或最终帧率。用户要求先一起修正、展示、确认后再封装，当前不提前打包，也不满足关闭电脑条件。
