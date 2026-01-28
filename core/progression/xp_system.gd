extends RefCounted
class_name XpSystem

const A_LEVEL_SCALE := 0.17
const DIFF_CUTOFF := 10
const NEG_POW := 1.5
const POS_POW := 0.2
const POS_BONUS_PER_LVL := 0.05

static func xp_reward_same_level(base_xp: int, mob_level: int) -> int:
	var mult: float = 1.0 + A_LEVEL_SCALE * float(mob_level - 1)
	return int(round(float(base_xp) * mult))

static func xp_diff_multiplier(delta: int) -> float:
	if abs(delta) >= DIFF_CUTOFF:
		return 0.0
	if delta == 0:
		return 1.0
	if delta < 0:
		var x: float = float(DIFF_CUTOFF + delta) / float(DIFF_CUTOFF)
		return pow(x, NEG_POW)
	var x_pos: float = float(DIFF_CUTOFF - delta) / float(DIFF_CUTOFF)
	return pow(x_pos, POS_POW) * (1.0 + POS_BONUS_PER_LVL * float(delta))

static func xp_reward_for_kill(base_xp_l1: int, mob_level: int, player_level: int) -> int:
	var delta := mob_level - player_level
	var mult := xp_diff_multiplier(delta)
	if mult <= 0.0:
		return 0
	var same_level := xp_reward_same_level(base_xp_l1, mob_level)
	var xp_float: float = float(same_level) * mult
	if xp_float > 0.0 and xp_float < 1.0:
		return 1
	return int(round(xp_float))

static func xp_to_next(level: int) -> int:
	var l: int = max(1, level)
	var xp_float: float = 100.0 * pow(float(l), 1.35) * exp(float(l - 1) / 30.0)
	return int(round(xp_float))
