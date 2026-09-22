class_name MonsterStruckPolicy
extends RefCounted

## Vanilla-1.76 monster struck policy (R1).
##
## Evidence chain (server side, Delphi 1.76 family):
##   TAnimalObject.Struck(hiter):
##     m_dwStruckTick := GetTickCount;
##     SetTargetCreat(hiter)  (retarget handled by the existing threat system)
##     m_dwHitTick := m_dwHitTick + LongWord(150 - _MIN(130, m_Abil.Level * 4));
##     // WalkTime := WalkTime + (300 - _MIN(200, (Abil.Level div 5) * 20));
##   The WalkTime line is COMMENTED OUT in lzxsz, Diamond and OpenMir2:
##   an ordinary physical STRUCK must never create a gameplay movement lock.
##
##   Direct magic (RM_MAGSTRUCK, ObjMon/Animal processing):
##     if ProcessMsg.wIdent = RM_MAGSTRUCK and monster and not exempt
##        and monster.Level < 50 then
##       m_dwWalkTick := m_dwWalkTick + 800 + Random(1000);
##   Fire wall (TFireBurnEvent.Run) sends RM_MAGSTRUCK_MINE, which never
##   enters that branch: ground-mine ticks keep their STRUCK presentation and
##   attack-tick penalty but must never postpone the walk tick.
##
## Level-50 note (evidence conflict, resolved R1): two Delphi trees and
## OpenMir2 keep the ordinary attack-tick penalty for every level, while one
## native-binary rebuild (LyoMir2, 0x71E291) claims a Level<50 gate there.
## We follow the three directly verifiable source chains: the ordinary
## struck attack delay applies at every level (Lv33+ saturates at 20ms). This
## only affects a 20ms per-hit penalty on Lv50+ monsters; no runtime switch.

const ORDINARY_ATTACK_DELAY_BASE_MS := 150
const ORDINARY_ATTACK_DELAY_MAX_REDUCTION_MS := 130
## TAnimalObject.Struck: m_Abil.Level * 4 (the struck FRAME time uses *5).
const ORDINARY_ATTACK_DELAY_LEVEL_REDUCTION_MS := 4
const STRUCK_FRAME_TIME_BASE_MS := 200
const STRUCK_FRAME_TIME_MIN_MS := 80
const STRUCK_FRAME_TIME_LEVEL_REDUCTION_MS := 5
const DIRECT_MAGIC_WALK_DELAY_BASE_MS := 800
const DIRECT_MAGIC_WALK_DELAY_RANDOM_SPAN_MS := 1000
## RM_MAGSTRUCK walk delay requires monster.Level < 50 in the original server.
const DIRECT_MAGIC_WALK_DELAY_LEVEL_CAP := 50
## The original client accelerates a queued message backlog (>= 2 messages)
## by playing frame time at 2/3 speed; expressed as a countdown multiplier
## that is 1.5x. Kept here so visual code stays a pure consumer of policy.
const STRUCK_BACKLOG_SPEED_MULTIPLIER := 1.5
const STRUCK_BACKLOG_ACCELERATION_THRESHOLD := 2
## Malformed-input guard only; normal play never approaches this.
const MAX_PENDING_STRUCK := 255


## Ordinary struck: the next attack deadline slips by
## 150 - min(130, level * 4) milliseconds (146ms at Lv1, 20ms at Lv33+).
static func attack_delay_ms(level: int) -> int:
	var safe_level := maxi(1, level)
	return (
		ORDINARY_ATTACK_DELAY_BASE_MS
		- mini(
			ORDINARY_ATTACK_DELAY_MAX_REDUCTION_MS,
			safe_level * ORDINARY_ATTACK_DELAY_LEVEL_REDUCTION_MS
		)
	)


## Client struck frame time: max(80, 200 - level * 5) milliseconds per frame.
## The full struck duration is hit frame count x this value; the frame count
## comes from the monster's own canonical ActStruck framesPerDirection.
static func struck_frame_ms(level: int) -> int:
	var safe_level := maxi(1, level)
	return maxi(
		STRUCK_FRAME_TIME_MIN_MS,
		STRUCK_FRAME_TIME_BASE_MS - safe_level * STRUCK_FRAME_TIME_LEVEL_REDUCTION_MS
	)


## Direct magic (RM_MAGSTRUCK): postpone the next autonomous walk by
## 800 + Random(1000) milliseconds. `random_0_to_999` is the roll already
## drawn by the caller's RNG (deterministic in tests).
static func direct_magic_walk_delay_ms(random_0_to_999: int) -> int:
	return DIRECT_MAGIC_WALK_DELAY_BASE_MS + clampi(
		random_0_to_999,
		0,
		DIRECT_MAGIC_WALK_DELAY_RANDOM_SPAN_MS - 1
	)


## Direct magic walk delay eligibility: level < 50 and not source-exempt.
## Ordinary struck (RM_STRUCK) eligibility is separate: any positive damage.
static func direct_magic_can_delay_walk(
	level: int,
	source_exempt: bool
) -> bool:
	return level < DIRECT_MAGIC_WALK_DELAY_LEVEL_CAP and not source_exempt


## Original client backlog acceleration: with >= 2 queued messages the frame
## time is played at 2/3 speed (countdown multiplier 1.5x) until it drains.
static func struck_speed_multiplier(pending_count: int) -> float:
	return (
		STRUCK_BACKLOG_SPEED_MULTIPLIER
		if pending_count >= STRUCK_BACKLOG_ACCELERATION_THRESHOLD
		else 1.0
	)
