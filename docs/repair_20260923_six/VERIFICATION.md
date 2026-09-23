# 今日六项交付证据

源码提交：`1ea58045c853fd591bc0d9e41343713c5795bcd4`。后续交付提交只记录本证据和账本状态，不修改生产、测试或数据。

- 功能/相关回归：24个独立Godot场景的最新结果全部PASS，见 `evidence/latest_test_matrix.json`。早期FAIL完整保留，并在WORKLOG逐项分类和记录处理。
- 固定源码提交直接复验：6/6 PASS、0引擎错误；`evidence/runner_results_adhoc_20260923_125019_680_8912.json` 中 `git_head` 精确为上述源码提交。
- 全156怪选中圈、156怪异步冷激活、214接地记录覆盖、近战实际冷却/攻击/移动/阻挡/生命周期、HUD与安全区均有真实生产入口回归。手机视觉与性能未以本地测试替代。
- 精确170导入和生成检查均PASS；其余211份人工对齐、213份接地标定/输出逐条与基线相同。用户AGENTS及源草稿哈希均不变。
- 本批没有贴图、地图、掉落、召唤规则、宠物、版本号及导出配置变更；今天已合并的召唤规则与祖玛保存数据继承自f0eca40e。
- `git diff --stat`、完整生产/测试diff、`git status`、`git diff --check` 已审阅。无关AGENTS与23个UID留在原工作树，不进入本批提交。
- DEVICE TEST: NOT_RUN；APK BUILD: NOT_RUN（用户要求先不打包）。无本批手机FPS/温度结论。

## 复验命令

```powershell
./tools/run_godot_tests.ps1 -TestPaths tests/monster_target_ring_pixels_test.tscn,tests/moon_spider_shield_pursuit_test.tscn,tests/repair_six_combat_test.tscn,tests/safe_zone_skill_gate_test.tscn,tests/repair_six_ui_anchor_test.tscn,tests/hc_monster_ai/combat_epoch_delivery_test.tscn -TimeoutSeconds 30
./tools/run_godot_tests.ps1 -TestPaths tests/monster_ground_contact_runtime_test.tscn,tests/hc_monster_ai/geometry_test.tscn,tests/hc_monster_ai/inventory_test.tscn,tests/hc_monster_ai/path_test.tscn,tests/bich_monster_visual_test.tscn -TimeoutSeconds 30
./tools/run_godot_tests.ps1 -TestPaths tests/monster_ground_contact_cold_activation_test.tscn -TimeoutSeconds 60
C:/Windows/py.exe -3.12 tools/import_monster_ground_alignment_drafts.py --draft-root outputs/visual_acceptance/monster_ground_alignment_drafts --monster-id 170 --check
C:/Windows/py.exe -3.12 tools/build_monster_ground_contacts.py --monster-id 170 --check
```

导入命令应指向含原名 `monster_170.json` 的用户草稿目录（当前为 `outputs/visual_acceptance/monster_ground_alignment_drafts`）；证据副本命名为 `monster_170_user_draft.json`，不可用它覆盖其他草稿。在其他机器复验时指向实际原名草稿目录。

最新视觉裁决：半径仅爬行怪×1.3；黑锷170仅E/W向下10px。预览见 `evidence/target_ring_30_percent_review.png`，为源贴图合成对照；未经手机实际视觉验收。
