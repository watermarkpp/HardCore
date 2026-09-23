# 今日六项交付证据

最终生产源码：`8b32fb15780541cb39925ee693af3474ca4c43dc`；前序源码提交1ea58045实现六项修复。非爬行怪保护断言提交：`b4438d485a06614352552fbb2d15099425b4ef96`，与8b32fb15的生产/数据/工具完全相同。后续交付提交仅整理本文及证据，不再改变已确认效果。

## 最终范围及人工确认

- 用户已确认四张修改后的爬行怪预览满意，并明确不再生成对比图、不实施“按贴图中心自动对齐”的备选方案。已展示的原预览只复制归档到 `evidence/crawling_direction_adjusted_0.png`～`_3.png`。
- 33个爬行身份半径×1.3；9个长体型身份92/94/110/118/120/121/122/123/170使用已确认的方向偏移。所有S方向保持原位置；N为贴图行0，S为行4。
- 其余123个身份保持原尺寸、全部八方向零偏移。脚点、贴图、碰撞和阴影不随黄圈改变。既有170手工脚点导入仍保留；此次方向调整没有再改任何脚点数据。精确冻结证据：`evidence/crawler_scope_preservation.json`。
- 老图 `evidence/target_ring_30_percent_review.png` 是仅E/W偏移阶段的历史对照，不能作为最终N/斜向效果依据。

## 自动测试

- 最终生产源码8b32fb15直接复验：8/8 PASS、0引擎错误，见 `evidence/runner_results_adhoc_20260923_130706_305_6028.json`。涵盖全156怪八方向黄圈、校准器、接地、月魔蜘蛛魔法盾、统一近战、安全区、HUD与攻击epoch。
- 固定b4438d48复验：黄圈与校准器2/2 PASS、0引擎错误，见 `evidence/runner_results_adhoc_20260923_130917_013_2084.json`。显式验证33个爬行、123个非爬行身份；校准器11个身份×8方向验证。
- 累计相关测试最新结果：26个独立场景中25 PASS、1 FAIL，见 `evidence/latest_test_matrix.json`。不将既有综合校准器失败计为PASS。
- 既有FAIL：`ui_visual_acceptance_lab_test` 第118行玩家走路预览帧不变。旧基线f0eca40e同一行失败，原测试保留不改；基线证据为 `evidence/runner_results_adhoc_20260923_130145_712_18788.json`。本次怪物校准器范围由独立专项覆盖，此专项不代表整个校准器综合测试通过。
- 精确170导入和生成检查均PASS；其余211份人工对齐、213份接地标定/输出逐条与基线相同。用户AGENTS及源草稿哈希均不变。方向偏移追加后，三份脚点/接地文件与1ea58045完全相同。
- 早期失败、基线复现和处理原因完整保存在WORKLOG及原始runner报告中。

## 复验命令

```powershell
./tools/run_godot_tests.ps1 -TestPaths tests/monster_target_ring_pixels_test.tscn,tests/monster_target_ring_calibrator_test.tscn,tests/monster_ground_contact_runtime_test.tscn,tests/moon_spider_shield_pursuit_test.tscn,tests/repair_six_combat_test.tscn,tests/safe_zone_skill_gate_test.tscn,tests/repair_six_ui_anchor_test.tscn,tests/hc_monster_ai/combat_epoch_delivery_test.tscn -TimeoutSeconds 30
C:/Windows/py.exe -3.12 tools/import_monster_ground_alignment_drafts.py --draft-root outputs/visual_acceptance/monster_ground_alignment_drafts --monster-id 170 --check
C:/Windows/py.exe -3.12 tools/build_monster_ground_contacts.py --monster-id 170 --check
```

导入命令应指向含原名 `monster_170.json` 的用户草稿目录；证据副本 `monster_170_user_draft.json` 不覆盖源草稿。完整相关回归命令和其余报告保留于本目录历史提交及证据矩阵。

## 交付边界

- 今天召唤、空掉落出生和祖玛保存数据继承f0eca40e。此后六项修复未改掉落、玩家宠物、其他地图、版本或导出配置。
- 用户批准同步main和codex/integration并推送；最终文档提交承载上述固定源码和证据，远端身份以交付回复中实际ls-remote结果为准。
- 已审阅生产/测试最终差异，执行 `git diff --stat`、`git diff`、`git status`、`git diff --check`。用户既有AGENTS和23个无关UID保持原状，不并入提交。
- DEVICE TEST: NOT_RUN；APK BUILD: NOT_RUN（用户要求先不打包）。用户确认的是已展示的预览效果，不虚构本批手机视觉/FPS/温度结论。
