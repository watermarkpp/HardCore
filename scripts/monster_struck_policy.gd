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
##   Direct magic and ground-mine damage both use the ordinary positive-damage
##   STRUCK path in the current product. The historical RM_MAGSTRUCK walk
##   postponement is retired; only its old Lv<50 RNG draw is retained as an
##   invisible compatibility draw so actor RNG sequences remain stable.
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
## Legacy direct-magic reception boundary used only for actor-RNG continuity.
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


## Legacy direct-magic compatibility draw eligibility: level < 50 and not
## source-exempt. This no longer grants any movement side effect.
static func direct_magic_compatibility_draw_required(
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
