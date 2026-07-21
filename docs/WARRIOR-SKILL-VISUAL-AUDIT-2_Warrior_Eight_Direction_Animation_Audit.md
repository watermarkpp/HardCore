# WARRIOR-SKILL-VISUAL-AUDIT-2：战士技能八方向动画审计报告

日期：2026-07-15  
状态：完成；主客户端与主客户端规则复核、底层修复、真实 OpenGL 截图、专项及完整关键回归均通过；未构建 APK。

## 资料范围

- 客户端像素主资料：`client.classic_raw_complete`，即`dev_art_sources/reference/mir2_client_raw/Data`。
- 客户端规则主资料：`source.original_gameofmir.mirclient`，即`dev_art_sources/reference/original_gameofmir/MirClient`。
- 方向公式、动作帧数和四种命中特效基址均由主资料复核：攻杀800、刺杀1410、半月1700、烈火3480；公式为`base + direction * 10 + actionFrame`。
- 本轮未引用辅客户端覆盖主客户端像素，也未用无来源特效替换缺失内容。

## 查出的底层问题

1. 人物与技能特效使用了不同的运行原点。Hum/Weapon按经典脚点`(64,80)`打包，但运行人物按`(96,108)`落地，导致技能特效相对人物偏右32、偏下28像素。
2. 所有武器曾被强制塞进人物的`192×160`画布。裁决之杖攻击动作有9帧越出画布上缘，集中在SE、S、SW、W、NW方向；最严重帧丢失超过一半有效武器像素。
3. 烈火源效果横跨633×478像素，旧生成器为满足单张2048纹理上限把它缩小到52%。人物与武器仍为100%，因此火焰长度被压短并向人物原点收缩，表现为“烧到自己、从裁决杆身中部起火”。
4. 经典客户端按角色原点叠加烈火，不感知不同武器的实际长度。裁决比普通剑长，恢复1:1之后仍需按用户要求增加武器头吸附规则。

## 修复

- 统一人物、武器和Magic.wil的经典角色原点；技能特效运行偏移固定为`(-32,-28)`，不再按截图手调。
- 身体继续使用`192×160 / anchor(64,80)`；武器改用独立`192×224 / anchor(68,112)`画布。运行时允许身体与武器使用不同区域尺寸，但两者共享同一个角色原点。
- 穿戴生成器切换到当前工程主客户端目录，并新增硬失败规则：任何源像素越界立即终止构建，禁止PIL静默裁图。
- 烈火恢复Magic.wil原始1:1像素。为维持移动端单纹理不超过2048，将48帧拆成4张`1920×1920`分片，每张3帧×4方向；旧52%图集已删除。
- 生成器从每个Weapon.wil攻击帧计算远端武器头质心，从每个烈火帧计算近端高亮火焰起燃质心；运行时按当前已装备武器、当前方向和当前帧计算`武器头－起燃点`，逐帧吸附。该机制适用于已建立动态穿戴映射的所有武器，不给裁决写死截图偏移。

## 验收

- `tools/verify_judgement_staff_atlas.py`：裁决5动作、8方向、源帧顺序和实际像素全部通过。
- `tools/audit_warrior_skill_visuals.py`：穿戴3496帧、技能特效192帧完成检查；旧裁决布局稳定复现9个裁切帧，新布局裁切为0；48个烈火帧均有起燃点，所有武器攻击帧均有武器头元数据。
- 战士专项回归：14/14通过。
- 完整关键回归：51/51通过。
- 六技能八方向总图：`outputs/visual_acceptance/warrior_skill_direction_audit/warrior_skill_six_by_eight_audit.png`。
- 烈火八方向原尺寸、武器头吸附图：`outputs/visual_acceptance/warrior_skill_direction_audit/fire_hit.png`。
- 烈火逐方向隔离验收图（排除相邻大特效重叠）：`outputs/visual_acceptance/warrior_skill_direction_audit/fire_hit_weapon_head_isolated.png`。
- 机器报告：`outputs/validation/warrior_skill_visual_audit.json`。

## 后续硬规则

1. 人物身体、武器、头盔和技能特效必须共享角色原点；允许图层使用不同画布，不得为了共享region而裁掉长武器。
2. 超过单纹理上限的效果必须分片，不得缩放源像素冒充原始比例。
3. 需要从武器端点发出的技能必须使用逐武器、逐方向、逐帧的像素附着元数据，不得用一个全局平移量代替。
4. 美术验收必须先重建Godot导入缓存，再以非headless OpenGL实机截图确认；仅验证路径、文件存在或旧截图不算通过。
