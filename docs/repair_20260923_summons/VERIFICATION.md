# 怪物召唤与空掉落刷新修正

基线：9e3b9c36efc3c3cef5a851f7bfd63177d5c31d80。此次提交只包含召唤、空掉落出生准入和用户保存的祖玛教主之家发布。此前六项 UI/近战/安全区/校准工作仍保留，未混入本次提交。APK NOT_RUN。

## 最新用户裁决

- 幻影蜘蛛182召唤爆裂蜘蛛183；角蝇126召唤127保持。
- 非 Boss 召唤源（含精英召唤源）硬上限5，按 spawn_slot 统计存活加预留，死亡允许补齐。
- Boss 不套普通5只限制；祖玛教主160按后续明确指令每次4～7，上限15。其他 Boss 的公共缺省6～11、上限30保持，并有缺省配置回归。
- 原版 ObjMon.pas:1474–1500 随机读取四个 sZuma 配置。MirServer/Mir200/!Setup.txt:891–894 是祖玛卫士、祖玛雕像、祖玛弓箭手、楔蛾；精确对应156/153/150/128，均普通。原配置159精英错误，恢复128。
- 所有空掉落怪均允许正常出生，保留其他运行时门禁和全部掉落数据。当前153→156个可运行身份，解除的仅33/183/241的空掉落门禁。
- 地图人工保存 SHA256 4b03a27023ee4ebead8735b7a9898873ba5acba232f638310cea71815c528545；monster_spawn 6→4，boss_spawn 11→6（5精英+1教主）。地图层之外不重设计。

## 生成与边界

全量 canonical builder 在基线已有 special_normal 分类源哈希冲突，不能用全量重建回退分类/掉落。新正式 --spawn-and-summons-only 入口保留原发布目录其余领域，只更新召唤字段和显式出生政策，逐字段记录新来源；全量 builder 的既有验证不绕过、不宣称通过。

旧 DPV2 账本 runtime_disabled 描述历史掉落资格，仍保留原始表、槽和概率；GameData 不再将其当成出生禁令。空掉落怪不增加掉落槽。

## 测试进度

- Python生成验证5项 PASS：唯一身份、镜像一致、幂等、非法上限/未知ID拒绝、其他出生门禁仍有效、冻结字段比较。
- 召唤队列 431检查 PASS：普通5、Boss15、重复请求、回调重入、死亡补召、独立来源、出生预算不变。
- 真实 GameRoot 出生队列 PASS：182→183、126→127、160→四种普通怪，分别5/5/15，183实际死亡后补召；33/241正常出生和死亡；每帧最多1次构建/8次落点探测。
- 玩家宠物回归 PASS：taoist_summon_growth_contract、summon_growth_rank_upgrade、canonical_summon_integration（双宠/换图恢复）。SummonActor 源码未改。
- 地图实际加载 PASS：913106 无回退，2角蝇+2楔蛾+3祖玛卫士00+2祖玛雕像3+1教主。全67图发布身份矩阵 PASS；60墙体渲染绑定/867依赖文件 PASS。
- 核心/r1生命周期/角蝇跨母体生命周期补召回归 PASS；人工爆率 authority 回归 PASS，掉落 profile、156份战斗属性/分类、全部贴图未变。
- 固定源码提交 `7ffc1f3fcd798f22d69cc28fdb4e6ddb16d090a0` 复验 PASS：4/4 场景，零引擎错误；原始记录 `runner_results_adhoc_20260923_120725_364_10788.json`。同一源码60图/867依赖的渲染绑定检查再次 PASS。最终交付后续提交仅补文档与原始证据。

## 失败分类

- 最后补充 Boss 缺省配置测试，先复现错误继承祖玛4～7/15的13个失败，恢复公共缺省6～11/30后431检查全部通过；祖玛仍由专属配置保持4～7/15。

- 新测试先后遇到测试脚本属性名/静态类型和 JSON 浮点数组断言问题，修正 fixture 后通过；未据此修改玩法。
- 补充取消+重入测试曾复现 active+reserved 瞬时超5；生产队列修正为取消同世界任务时仍保留正在出生的一份预留，成功登记时转成存活、失败时释放、切世界时丢弃；431检查已覆盖成功/失败两种路径。
- dpv2_21cq_direct_runtime_test:94（旧槽数预期）和 summon_actor_state_machine_test:86（死亡测试 fixture）在干净基线9e3b9c36与本次均同位失败，记录为既有 FAIL，不把它们宣称通过，也不在本次扩大修复。
- 全量 canonical builder 的 special_normal authority 分类哈希既有 FAIL 保留；本次专用生成、字段冻结和真实消费者验证 PASS。

## 复现

```powershell
C:/Windows/py.exe -3.12 tests/monster_summon_catalog_test.py
C:/Windows/py.exe -3.12 tools/build_canonical_monster_catalog.py --spawn-and-summons-only --check
C:/Windows/py.exe -3.12 tests/canonical_monster_runtime_gate_closure_test.py
./tools/run_godot_tests.ps1 -TestPaths tests/monster_summon_hard_cap_test.tscn,tests/monster_summon_formal_birth_test.tscn,tests/zuma_saved_spawn_release_test.tscn,tests/canonical_monster_catalog_test.tscn -TimeoutSeconds 30
./tools/verify_wall_render_bindings.ps1
```

性能边界：没有新增场景遍历或怪物每帧工作；保留队列1构建/8探测预算。此处为功能与预算回归，Android帧率和温度未实测；DEVICE TEST: NOT_RUN，APK BUILD: NOT_RUN。
