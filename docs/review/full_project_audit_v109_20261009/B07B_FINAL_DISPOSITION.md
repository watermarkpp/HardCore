# B07B 主控最终限定处置

Windows runner 现在在 resume 前把本次创建的进程放入独立 Job Object；失败只清理本次 handle，结束只终止自己的 job。7 项独立 PowerShell ownership 例和新 runner 的 native56 正常退出通过。Assign 失败强制注入、PID reuse、Linux 平台尚未运行。初始六项 helper receipt 在修正后被代理覆盖，原文件 MISSING；最终七项已按精确字节归档，不补造历史文件。

缺少或不匹配源码指纹的 framework receipt 失败关闭，9 项 receipt-only 负例/正例通过。Windows native 结果另外记录 wrapper/真实引擎各自 bytes/hash、receipt 引擎版本、scene/run/invocation 和隔离路径；环境 hash 仍须与外部冻结清单实际输入字节匹配，不把标签当源码扫描。

新的 immutable HC checks 写入同实例 nonce 独占目录，先获得原子目录 ownership，再写入/flush/读回核验。native56 13 项真实文件检查 PASS、原生退出 0、完整 framework receipt 和独立 PASS/FAIL 两份自定义 checks 保留，2537 个实际受测输入未变。它证明本次组件及 runner 正常结束，不代替旧战斗专项或设备验收。

清理 warning 分类另外保留每类 raw 行和数量；未知 ERROR 不扩入 allowlist。最终 4 项分类例通过，之前 3 项原结果保留。非 framework 的通用 PASS 继续仅作功能兼容结果，formal_evidence_status 为 MISSING；不据此生成正式上游通过凭据。

R2 QA 场景仅修正到已存在的同目录脚本；该场景需专用 GUI/seed 前提，未升级成普通 headless 回归。两个 diag 场景缺脚本、未注册正式套件，保留为不可运行的历史残留，MISSING。未制造空实现，也未删除证据；B08 继续核查残留职责。

全项目语义覆盖仍 MISSING。DEVICE TEST: NOT_RUN。各原始文件、source hash、native exit 和完整 checks 见 B07B_FINAL_EVIDENCE_LEDGER.json。
