# B02 验证与覆盖缺口

## 必要定向验证（本轮均 NOT_RUN）
- B02-001：接受近战/法术并在windup途中打开真正暂停菜单；保持暂停超过windup，检查Enemy HP、MP、攻击提交、状态时钟；恢复后一次结算；死亡/转图epoch取消仍有效。
- B02-002：同一次高速projectile physics segment命中2个不同stable order怪，交换出生序；做近/远首接触及切线exact测试。
- B02-003：PlayerCharacter仅因零运动碰撞分离改变Ground GU、无方向输入，现有movement信号是否遗漏；30群怪光环不能因此失效。
- B02-004：隐身戒指破隐后仍被合法Enemy攻击，在交战中换装后重穿；验证是否应只在脱战恢复。
- B02-005：以现行“submission”玩法判定纯失败施法破隐，未授权不改。
- B02-006：只有证明某个实际正式技能/加载拓展可形成非MP invalid quote时才做前置拒绝合同；用户准许的道士免材料不变。
- B02-007：旧装备吸血与Feature吸血以原始伤害/最终损失何者为准，先核对产品权威再验证。

## 尚未完成的静态深审
- 本批manifest三组59路径均实际取到源码与结构索引，但各路径对应 **INDEX_ONLY_PENDING_DEEP_REVIEW** 和 **PARTIAL_SEMANTIC_REVIEW** 未完成所有功能出口的语义与动态消费者闭环；详情见COVERAGE.json。
- 非B02的Monster攻击、Boss、完整物品/装备事务、save migration、UI/Android、地图发布、导出等仍为 NOT_RUN。
- 现有测试名称与部分测试正文可核，但本轮未实际运行、不用历史测试名冒充PASS；有旧功能证据也不得外推到新增暂停/碰撞/排序条件。
- 目前未进行 60FPS、PC正式新窗口、真机触摸与渲染检查；B01资源/generation/泄漏修复为独立施工，非B02固定源码。

## 修复前门禁
不修改用户约定的瞬时AOE、目标快照、近战commit、持续FireWall逐跳、飞行体位移躲避、输入时钟与已提交伤害。任何调整需新定向合同+原相关回归，复测时附受测SHA/engine/scene/fixture/exit/log。不得仅为使断言PASS改变含义。
