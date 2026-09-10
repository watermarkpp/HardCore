# M30-R4R2 一致性执行报告

- 分支：`codex/m30-r4r2-consistency`（工作树 `HardCore-worktrees\m30-r4r2`）
- BASE：`cfe1b81f`；核心提交 `52ad3f8a`（生产=包作者代码）；测试/证据 `c885ad4e` + 探针诊断 `1294ddf`
- 基线观察树：`m30-r4r2-baseline` @ `0278dde0`（tests-only，生产 blob 逐字节=BASE：enemy f74a044c/game_root bbaac7b8/monster_visual 389e0696 已核）
- 包：`HardCore_M30_R4R2_复审与核心修复包.zip`，SHA256SUMS 18/18 OK；离线套件随包；安装器 manifest/patch：`outputs/m30_r4r2_{88i7d3cz,8xfueys9}`（PREVIEW 9 文件 → APPLIED_NOT_COMMITTED，`git diff --check`=0）

## 分项结论（仅 PASS/FAIL/BLOCKED/NOT_RUN/MISSING）

| 项 | 判定 | 说明 |
|---|---|---|
| 证据先行（第1项） | PASS | R1 十条八方向失败 stdout/stderr/runner JSON、r2 超时日志、旧 R4 D（标注为旧，不作新 D 引用）→ `evidence/r1_8way_failures/`（9 文件）；archive_evidence.py 复制+SHA256 校验 |
| 基线观察器（第2项） | PASS | tests-only 应用后八方向 **PASS 8/8**（基线生产码 + 修正观察器）。R1 的 completed=2/8 判定为观察伪影而非生产回归；此 PASS 不宣称生产性能提升 |
| 完整包应用（第3项） | PASS | 9 文件=2 生产+1 既有测试+6 新增（2 tscn 安装器生成）；禁改项核对：AIA2 函数、2GU/1.5GU、攻击间隔、命中时刻、move_speed、召唤 8/1/96 与上限数据零变化；GameRoot 严格限于授权窄改（投影求值块 + 只读 `hc_m30_stable_enemy_ground_point`）；enemy.gd +17/-1（稳定点门 `_hc_m30_navigation_point_stable`，无 GameRoot 的隔离夹具保持原权威） |
| test_safe_projection | **FAIL（需复审）** | 16 检查 1 失败："body padding still requires relocation"。生产 `hc_m30_stable_enemy_ground_point` 与冻结 pre-R2 公式**逐位一致**（第29行 PASS）；但冻结投影仅在**中心**入区带时重定位，夹具点 (11.2,10)（1.2GU，中心在外、身位重叠）原样返回——第28行（身位重叠须重定位）与第29行（==冻结公式）在该夹具点上互斥不可同时成立，属包作者侧合同不一致。未改生产投影公式与断言含义，保留 JSON 上报 |
| 八方向（新观察器） | PASS | 基线 8/8、候选 8/8；无跳方向，无 BLOCKED。注意：runner 的 TimeoutSeconds 参数上限 60（order 范式 180 超出既有 runner 参数范围，已按"实际测试 runner 路径"自由度用 60，记录在案） |
| 功能回归 | PASS | R1 core、R4 core、runtime、geometry、path、combat_epoch、母体函数烟测 7/7；引擎 4.7.stable.official.5b4e0cb0f headless/opengl3，隔离 APPDATA |
| 冷热 D（新） | PASS | `M30_D_COLD_PRECONDITION engine_cached_paths=0 coordinator_profile_or_job_absent=true cold_proven=true`；冷生 factory_cpu 6.033ms、视觉就绪 86.942ms、sync_load_delta 0；attacking_children=5。测量完整性判定；性能达标另列 |
| AIA2 三场景 | PASS | ordinary_attack tap/hold_kill_release/hold_kill_retarget 3/3 |
| 猪洞现场 f3 | **FAIL（需复审）** | 正式地图 913003 gen2，母体 126 slot `editor:913003:1:0`，life 1→自然重生 480s 档真实等待后重生（新 instance/life）✓；旧世 3 子怪存活归因首代 ✓；**重生母体 25s 出生窗口内零新召唤入队**（累计 admitted_children 停在 3，last_pump_tick=418≈首代早期）——rule enabled、cooldown 0、warning 0 仍不泵队。两次运行（含证据增强适配）同点失败 |
| 猪洞现场 f4 | **FAIL（需复审）** | 地图 913004，同一失败点；子怪 starts=4（f4 有交战）亦不触发新命 |
| 接收端消融 | NOT_RUN | 母体新命触发点未复现，因果消融无对象可拦截；未改 summon_rule.enabled |
| 旧表算术审计 | PASS | `audit_rev07.py`：status PASS，17 文件，dual_gate 12/12，head 标签与实际 hash 另核（v72=909821c9 记录一致）；仅算术复核，非 R2 性能 |
| R2 性能 | 9/12 PASS（原样） | 6 对严格交替（base=0278dde0 vs cand=1294ddf5），12/12 轮全部有效（exit 0+PASS marker+12 行 JSON），无超时。FAIL：dense_crowd@30 +1.663ms、sustained_close_attacks@30 +1.653ms、world_obstacles@20 +1.871ms。尾部诊断（与中位数判定分开）：候选 p1 冷态污染（99/103ms）+ worl20 逐轮递减（20.48→16.31）示次序/预热效应；所有轮原样保留。v72/fcc 历史与旧 0.131ms FAIL 原样保留；不宣称 30 怪 60FPS |
| 真机 / 录屏 | NOT_RUN | 无设备接入；未把程序化八向覆盖写成已录屏 |
| MISSING | — | 无伪造项；探针 `.gd` 被 `*_probe*.gd` 忽略规则拦截，按 R1 先例 `git add -f` 精确路径并入测试提交 |

## 适配清单（全部记录）

1. runner 超时参数 180→60（参数范围限制，非断言改变）。
2. `pig_site_probe.gd` 失败路径增加 births 窗口证据快照（仅证据收集，断言/阈值/流程零变化）。
3. 无其他改动；生产投影公式、断言含义、首攻取样起点、freshness、8/8 与 2 walk 样本均未触碰。

## 待主控复审

1. safe_projection 第28/29行的作者侧合同互斥。
2. 猪洞重生母体零入队（f3/f4 双图复现，含完整 queue/starts/位置/rule 证据）。
