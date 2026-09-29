extends RefCounted
## Pure reception policy. The owning combat service supplies the ACTUAL source
## message family, acceptance result, actor eligibility and already drawn roll.
## Skill names, target level overrides and timers do not belong here.
const DIRECT: StringName = &"DIRECT"
const MINE: StringName = &"MINE"
const PHYSICAL: StringName = &"PHYSICAL"

static func needs_walk_roll(kind: StringName, level: int, is_monster: bool, source_exempt: bool, message_received: bool) -> bool:
    return kind == DIRECT and message_received and is_monster and level > 0 and level < 50 and not source_exempt

static func walk_delta_ms(kind: StringName, level: int, is_monster: bool, source_exempt: bool, message_received: bool, roll_0_to_999: int) -> int:
    if not needs_walk_roll(kind, level, is_monster, source_exempt, message_received):
        return 0
    if roll_0_to_999 < 0 or roll_0_to_999 > 999:
        push_error("source176: invalid Random(1000) sample")
        return -1
    return 800 + roll_0_to_999

static func ordinary_struck_attack_delta_ms(kind: StringName, level: int, final_damage: int) -> int:
    if kind != DIRECT and kind != MINE and kind != PHYSICAL:
        return 0
    if final_damage <= 0:
        return 0
    if level <= 0:
        push_error("source176: invalid monster level")
        return -1
    return 150 - mini(130, level * 4)

static func pushed_walk_delta_ms(successful_source_steps: int, is_monster: bool) -> int:
    ## Successful source steps, NOT round(displacement_GU) or attempted steps.
    if successful_source_steps < 0:
        push_error("source176: negative successful push count")
        return -1
    return successful_source_steps * 800 if is_monster else 0

static func struck_frame_ms(level: int) -> int:
    if level <= 0:
        return -1
    return maxi(80, 200 - level * 5)
