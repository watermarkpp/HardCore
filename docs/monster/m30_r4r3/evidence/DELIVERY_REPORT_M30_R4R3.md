# M30-R4R3 复审纠偏执行报告（标题条件：survival=guarded）

- 分支：`codex/m30-r4r3-evidence`（报告/证据）+ `codex/m30-r4r3-prune`（生产精简候选）；源 `e0a07564`
- 工作树：复用专用怪物树 `HardCore-worktrees\m30-r4r2`（未新建第二树）；Godot `tools\godot-4.7\Godot_v4.7-stable_win64_console.exe` = 4.7.stable.official.5b4e0cb0f（sha256 d8055fb8...，runner.json 逐轮记录）；Python 3.11.15
- 包：`HardCore_M30_R4R3_复审纠偏与受控精修包.zip`，SHA256SUMS 18/18 OK；离线 `tests/test_offline.py` 30/31（唯一失败=test_symlink_path_rejected：Windows 无符号链接特权无法建夹具，环境性，记录不阻塞）
- **安装器解析适配（零包字节改动）**：apply_r3.py 在 GBK 本机读 UTF-8 `PAYLOAD_SHA256.json` 报 `'gbk' codec can't decode`；改 manifest/期望 SHA 被禁止，改包文件又触发自校验 fail-closed——最终以 `PYTHONUTF8=1` 进程环境使 `read_text()` 默认 UTF-8，包字节与校验和完全未动
- 提交表：`9b9c5e86` diagnostics 7 目标（6 新+safe 扩展，0 生产）→ `1933d077` force-add 被 `*_probe*.gd` 忽略的 site_probe.gd → `d446beba` 诊断证据批次 → prune 分支 `49501f19`（enemy.gd blob 逐字节=f74a044c595d90e1a3c4a4a2cc2eeca151f7264c，GameRoot helper 保留）

## 分项结论（仅 PASS/FAIL/BLOCKED/NOT_RUN/MISSING）

| 项 | 判定 | 说明 |
|---|---|---|
| profile 短回归 | PASS | 大血量被生产属性刷新替换（profile_events=1）已证；显式 guard 保持余量（repairs 2-3）；对死亡/零 HP 状态不复活（rejected_dead_state=false 记录在案）；不自动证明死亡 |
| safe 短回归 | **双层** | 引擎侧 24/24 冻结合同断言 PASS（外中心不动、内中心按原 padding 推出、冻结公式、多边形兼容、非法上下文 fail-closed）；probe 层 FAIL 仅因 `1 resources still in use at exit` 计入 engine_error_count——该退出期告警存在于全部历史 PASS 运行。未改 WorldSpatialRules |
| eight 短回归 | **双层** | R3 diagnostics 运行 completed=7/8（dir 0 art-wait 期间零攻击消耗，R1 外圈首攻方差类；新观察器未恢复 art-wait 漏采，攻击时序未变）；prune 分支同日复跑 8/8 PASS——方差为间歇性，两轮 JSON 均保留 |
| 猪洞 f3 短检 observe | BLOCKED（有效前提证据） | `ONE_SHOT_HP_MARGIN_REPLACED_BY_PROFILE_RECALCULATION`：一次性大血量被生产属性重算回 89/89；完整状态入 JSON；未回填旧记录 |
| 猪洞 f3/f4 短检 guarded | PASS | 标题条件成立：生产属性监听后、保护前 HP=89/89 已录，repairs 2-3 次，HP 保持 999999965/10⁹；producer 信号逐 instance 记录（首代各 3 次） |
| 猪洞 f3 自然（480s） | PASS | 生命周期实测：死亡事务安排的原 480s 档真实等待（elapsed 531.7s）→ 新母体（复合身份 map/generation/instance/life=1）→ **新命 4 只归因重生母体 + 旧世 3 只共存**（admitted 3→7）→ 二杀后旧世子怪存活（starts 399→428 递增）；接收端消融拦截 3 次另计；屏幕像素+正式 GU 双坐标记录；probe 层 FAIL 同上（仅退出告警计数）。R2 失败根因限定表述（R3 封板修订）：**存活余量前提被破坏已证，guarded 下自然链通过，旧死亡链未完整追溯**（旧运行无死亡直接证据，不以新运行 JSON 回填旧日志） |
| 猪洞 f4 自然（480s） | PASS | 同上模式全链成立（新母体 producer 7 信号、admitted 3→7、starts 593→632）；guard repairs 3 |
| prune 重跑 | PASS | R4 core/R1 core/runtime/geometry/path/combat_epoch/母体烟测/AIA2×3 = 10/10；safe 24/24、D PASS、eight 8/8（同日复跑） |
| R3 性能（对照：diagnostics d446beba vs prune 49501f19） | 12/12 门槛 PASS | 预运行双方各 1 次不计门槛；顺序开跑前固定为 AB·BA·AB·BA·AB·BA；6 对 12 轮全部有效（exit 0+PASS marker+12 行 JSON），0 轮剔除（含双侧 192.87/147.20ms 离群轮原样保留）；中位数：prune 在 9/12 场景更优（sustained@30 −2.314ms、sustained@20 −0.915、dense@30 −0.472；3 项噪声级 +0.35 以内）。**算术/相对门槛 PASS ≠ 性能达标结论**：R2 历史 9/12（三失败差值 1.663/1.653/1.871ms、超门槛 0.195/0.129/1.027ms 不混写）与 fcc 0.131ms FAIL 原样保留；无 headless→真机外推 |
| 真机 / 录屏 | NOT_RUN | 无设备 |
| MISSING | — | 本轮无 .uid 需登记（headless 直跑不生成，场景已验证可跑）；无伪造项 |

## 诊断分支落点（按执行令第 3 节顺序）

f3/f4 自然模式均有新召唤（producer 7 信号、入队 4），无需走"无新召唤"四分支；producer→queue→spawn 全链在 guarded 前提下闭合。

## 待主控裁决

1. probe 层 engine_error_count 将退出期资源释放告警计为 FAIL（safe/自然两处）——是否属作者侧严格度过严。
2. eight dir 0 间歇性"art-wait 期间零攻击消耗"方差（7/8 与 8/8 两轮并存）。
3. prune 精简候选 12/12 门槛通过，是否采纳由主控定（本分支未并 integration）。
