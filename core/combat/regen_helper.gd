extends RefCounted
class_name RegenHelper

# ------------------------------------------------------------
# RegenHelper
#
# Унифицированный реген HP по проценту от max_hp.
# Возвращает новое значение HP.
# ------------------------------------------------------------

static func tick_regen(current_hp: int, max_hp: int, delta: float, pct_per_sec: float) -> int:
	if max_hp <= 0:
		return current_hp
	if current_hp >= max_hp:
		return max_hp
	var add_hp: int = int(ceil(float(max_hp) * pct_per_sec * delta))
	if add_hp <= 0:
		add_hp = 1
	return min(max_hp, current_hp + add_hp)