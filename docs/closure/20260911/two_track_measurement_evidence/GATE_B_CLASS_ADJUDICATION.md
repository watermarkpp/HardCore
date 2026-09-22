# B/C 类逐项裁决证据表（主控指令：逐项审，不许一键标 stale）· 2026-09-12

前置：A 项已关闭——工作树 project.godot 存在未提交漂移（丢 show_image/fullsize/
minimum_display_time/build_revision），`git restore` 恢复为 HEAD 权威内容后
brand_intro_test 复测 PASS（runner_results_adhoc_20260912_191408_698_23440.json）。
漂移疑似窗口化探针运行期间 Godot 重写 project.godot 所致；已提交内容与主控核验一致。

干净树复跑后仍 FAIL 的逐项定性（证据=测试断言上下文+生产代码现状）：

## 已可裁决
1. loot_visual_clock_test —— **stale（测试断言已删除的合同）**
   `_bob_time`/`bob_time` 在 LootPickup 上不存在；4004874f（已验收 "static loot"）
   删除 bobbing；相邻 loot_stable_identity/loot_runtime_item_policy 全 PASS。
   待授权：改写/退役该测试为 static-loot 断言。
2. combat_unit_source_priority_test —— **基线既有失败（先于 ff）**
   工作树文件哈希 91C2526CD6C8B0ED…(LF) ≠ pin 3E7D5DFB2DA386CF…；且
   combat_unit_contract_v1.json 与 source_priority_policy.json 均不在
   c91781bd..b51e0253 改动清单 → integration 基线上同样失败，非本次引入。
   下一步：在 c91781bd 复算同哈希确认后，按"更新 pin 或还原合同"由主控定（涉主源总表）。
3. packaged_bytecode_contract_test —— 按 20260912 裁决移至 Android 构建后验证（V74_GDC_DIR）。
4. complete_client_resource_catalog_test —— 构建前置：本树未生成
   outputs/resource_catalog/complete_client_frame_catalog/manifest.json；跑 catalog builder 后复测。
5. character_select_touch_scroll_test / unbuilt_planned_map_not_playable_test ——
   自身 PASS 标记已打印后 import-cache 竞态 preload 报错；同树后续同资源用例全 PASS。
   定性环境；统一预热 .godot import 后复测。

## 疑似真实生产问题（各需 1 步确认，未改任何生产/测试）
6. equipment_durability_policy_test:77 —— repair_button 存在且 L75 PASS；L76
   damage_equipment_durability 后按钮文本不含金币/价格；shop_panel.gd 中
   `_refresh_repair_preview()` 仅 L124/L412 两处调用、未见 durability 变化信号连接
   → 疑似维修预览不随耐久损伤实时刷新（或连接被 R3.3 重构移除）。
7. inventory_paper_doll_input_refresh_test:71 —— 装备变化后 preview.render_revision()
   未增长 → 纸娃娃未重渲染；需追 preview.refresh() 触发链。
8. monster_audio_hook_test:173 —— freed service cache 未恢复 replacement 实例；
   涉 EnemyActor 音频服务缓存时钟/失效机制（R6.1 曾改 enemy.gd）。
9. bich_monster_visual_test:65 —— 稻草人 velocity RIGHT 后 current_direction≠2；
   方向枚举映射疑似在已验收怪物提交中变更，需对照 monster_visual.gd 当前枚举。

## 合同冲突（需主控按已冻结布局合同逐项裁决，测试与生产均未动）
10. shop_gothic_ui_test —— HC_UI6_DETAIL_SPACE_PLAN_REQUIRED(匕首) + "购买页两个
    操作按钮没有统一为出售按钮规格"；presenter 试排由面板传入 spec 区域决定，
    R3.3 冻结新商店布局=旧停靠几何期望失效。
11. ui_r5_panels_test —— 同 presenter 机制（长属性/仓库背包侧 SPACE_PLAN + 长正文
    滚动 3 断言）；R5 旧合同 vs R3.3/R6.1 新几何。
12. real_panel_matrix_warehouse_bag/_stash —— NON_PORTRAIT_DETAIL ×13（药水类）；
    同 presenter，60s 复跑同败非超时。
13. warehouse_gothic_ui_test:303 —— 校准 overlay 报"当前界面没有已保存数据"；
    需查 R6.1 面板 id/校准 profile 路径是否变更或测试种子缺失（隔离 appdata）。

## 结论
- 0 项已改生产、0 项已改测试（除已恢复的工作树漂移 project.godot→HEAD 权威内容）。
- 下轮动作建议：先跑 4 个"1 步确认"（6/7/8/9）+ 基线哈希复核（2）+ builder/import 预热（4/5），
  再由主控对 10-13 逐项裁决，然后全量门禁复跑。
