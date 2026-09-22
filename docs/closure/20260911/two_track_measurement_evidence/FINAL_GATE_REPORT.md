# 最终组合门禁 · 原样回报（2026-09-12）

对象：b51e0253（codex/r3-3-single-heading，ff 候选）· 未执行集成 ff · 未打 APK · 零生产改动

## 总量
- critical：337 PASS / 10 FAIL · equipment：24 / 1 · monster：41 / 1 · adhoc(47)：35 / 12
- 60s 复跑甄别：shop_space_0/1/2、hc_monster_ai/runtime_test 均为 30s 超时伪失败 → **60s 全 PASS**
- 去重后真实 FAIL：**14 项**（明细如下），其余 ~441 全 PASS

## A. 集成内容类（ff-only 会抹掉 integration 侧设置——最重要）
1. **brand_intro_test**：feature 树 project.godot 缺 integration 侧三行：
   `boot_splash/show_image=true`、`boot_splash/fullsize=false`、`boot_splash/minimum_display_time=0`。
   ff-only 后 integration= b51e0253，这三行将消失（brand_intro 断言的正是 fullsize=false）。
   **ff-only 不可用**：project.godot 双侧分叉（feature 改了 version+autoload，integration 加了 boot_splash 设置），需主控裁决合并方式。

## B. 测试与既验收变更失同步（stale tests，随 ff 入库）
2. loot_visual_clock_test —— 断言已删除的 `_bob_time`（4004874f "static loot" 删 bobbing，测试未同步）
3. equipment_durability_policy_test —— "商店没有显示唯一维修价格预览"（vs R3.3 商店布局重做）
4. shop_gothic_ui_test —— `HC_UI6_DETAIL_SPACE_PLAN_REQUIRED: 匕首` + "购买页两个操作按钮没有统一为出售按钮规格"
5. ui_r5_panels_test —— 4 失败：`HC_UI6_DETAIL_SPACE_PLAN_REQUIRED`（长属性测试/仓库背包侧）+ 长正文滚动 3 断言
6. real_panel_matrix_warehouse_bag / _stash —— `NON_PORTRAIT_DETAIL` ×13（药水类详情呈现，60s 复跑同败）
7. inventory_paper_doll_input_refresh_test —— "Equipment change did not refresh the paper doll"
8. warehouse_gothic_ui_test —— "仓库校准存档仍有稳定路径缺失：当前界面没有已保存数据"
9. monster_audio_hook_test —— "freed service cache must recover the replacement instance"
10. combat_unit_source_priority_test —— 断言失败（L22）
11. bich_monster_visual_test —— "稻草人 移动方向错误"

## C. 环境/构建前置缺失（非代码回归）
12. complete_client_resource_catalog_test —— `outputs/resource_catalog/complete_client_frame_catalog/manifest.json`
    未生成（资源目录 builder 未在本工作树运行；"构建前测试"需先跑 builder）
13. packaged_bytecode_contract_test —— `V74_GDC_DIR not set`（Android 构建流水线环境变量）
14. character_select_touch_scroll_test / unbuilt_planned_map_not_playable_test —— 自身 PASS 标记已打印，
    随后 import-cache 竞态 preload 报错（本工作树首次导入新增 png；同树后续用例同资源全 PASS）

## 主控裁决点
1. A 类：project.godot 分叉下 ff-only 会丢 integration 设置——改为普通 merge（解决 project.godot）或
   授权在 feature 线补三行后 ff，需主控定。
2. B 类 10 项：多为"测试未跟上已验收变更"（static loot、R3.3 布局、docked presenter 空间计划），
   但按指令不放宽门槛——需主控逐项定性"测试陈旧（授权修测试）"vs"真实回归（授权修生产）"。
3. C 类 3 项：打包前流程补齐（跑 catalog builder、设置 V74_GDC_DIR、预热 import 缓存）即可消除。

证据：outputs/test_logs/runner_results_{critical,equipment,monster,adhoc}_*.json + 本文件同级日志。
