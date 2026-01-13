extends Node
class_name PlayerBuffs

var p: Player = null

# id -> {"time_left": float, "data": Dictionary}
var _buffs: Dictionary = {}

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if _buffs.is_empty():
		return

	# Apply over-time consumable effects (heal / mana restore). These should work
	# even in combat, so we apply them directly here instead of piggy-backing on
	# PlayerStats regen (which is out-of-combat for HP).
	if p != null and not p.is_dead:
		_apply_consumable_hots(delta)

	var to_remove: Array[String] = []
	for k in _buffs.keys():
		var key: String = String(k)
		var entry: Dictionary = _buffs[key] as Dictionary
		var left: float = float(entry.get("time_left", 0.0)) - delta

		if left <= 0.0:
			to_remove.append(key)
		else:
			entry["time_left"] = left
			_buffs[key] = entry

	if to_remove.is_empty():
		return

	for id in to_remove:
		_buffs.erase(id)

	_notify_stats_changed()


func _apply_consumable_hots(delta: float) -> void:
	# Each buff may carry:
	# hot_hp_per_sec, hot_mp_per_sec, hot_hp_left, hot_mp_left, hot_tick_acc
	# We tick once per second (accumulator) and stop early if resource reaches max.
	var changed_any: bool = false
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		if not bool(data.get("consumable", false)):
			continue
		var hp_per: int = int(data.get("hot_hp_per_sec", 0))
		var mp_per: int = int(data.get("hot_mp_per_sec", 0))
		var hp_left: int = int(data.get("hot_hp_left", 0))
		var mp_left: int = int(data.get("hot_mp_left", 0))
		if hp_left <= 0 and mp_left <= 0:
			continue
		var acc: float = float(data.get("hot_tick_acc", 0.0)) + delta
		var did_tick: bool = false
		while acc >= 1.0:
			acc -= 1.0
			did_tick = true
			# HP
			if hp_left > 0 and hp_per > 0 and p.current_hp < p.max_hp:
				var need: int = p.max_hp - p.current_hp
				var give: int = min(hp_per, hp_left)
				give = min(give, need)
				if give > 0:
					p.current_hp += give
					hp_left -= give
					changed_any = true
			# Mana
			if mp_left > 0 and mp_per > 0 and p.mana < p.max_mana:
				var need2: int = p.max_mana - p.mana
				var give2: int = min(mp_per, mp_left)
				give2 = min(give2, need2)
				if give2 > 0:
					p.mana += give2
					mp_left -= give2
					changed_any = true

		# Stop early if resource is full (even if some total left), per design.
		var stop_early: bool = false
		if hp_per > 0 and p.current_hp >= p.max_hp:
			stop_early = true
		if mp_per > 0 and p.mana >= p.max_mana:
			stop_early = true

		# Write back updated counters.
		if did_tick:
			data["hot_hp_left"] = hp_left
			data["hot_mp_left"] = mp_left
		data["hot_tick_acc"] = acc
		entry["data"] = data
		_buffs[id] = entry

		if stop_early or (hp_left <= 0 and mp_left <= 0):
			# Expire by setting time_left to 0; main loop will remove & notify.
			entry["time_left"] = 0.0
			_buffs[id] = entry

	# Do not call _notify_stats_changed here — these buffs don't affect stats snapshot.
	# (Healing already applied directly.)


func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	if id == "":
		return
	_buffs[id] = {"time_left": duration_sec, "data": data}
	_notify_stats_changed()


func remove_buff(id: String) -> void:
	if _buffs.has(id):
		_buffs.erase(id)
		_notify_stats_changed()


# --- Stats helpers (for CharacterHUD) ---
# CharacterHUD shows HP/Mana regen from Player.get_stats_snapshot().
# Food/Drink should contribute here as temporary "regen" while the HOT is active.
func get_consumable_hot_totals() -> Dictionary:
	var hp_per_sec: float = 0.0
	var mp_per_sec: float = 0.0
	if _buffs.is_empty() or p == null:
		return {"hp_per_sec": 0.0, "mp_per_sec": 0.0}

	# Sum active consumable HOT buffs.
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		if not bool(data.get("consumable", false)):
			continue
		var hp_left: int = int(data.get("hot_hp_left", 0))
		var mp_left: int = int(data.get("hot_mp_left", 0))
		if hp_left <= 0 and mp_left <= 0:
			continue
		var hp_per: int = int(data.get("hot_hp_per_sec", 0))
		var mp_per: int = int(data.get("hot_mp_per_sec", 0))
		# Per design: stop contributing once resource is full.
		if hp_per > 0 and p.current_hp < p.max_hp and hp_left > 0:
			hp_per_sec += float(hp_per)
		if mp_per > 0 and p.mana < p.max_mana and mp_left > 0:
			mp_per_sec += float(mp_per)

	return {"hp_per_sec": hp_per_sec, "mp_per_sec": mp_per_sec}


func get_buffs_snapshot() -> Array:
	var arr: Array = []
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		arr.append({
			"id": id,
			"time_left": float(entry.get("time_left", 0.0)),
			"data": entry.get("data", {}) as Dictionary
		})
	return arr


# Legacy helper (used by PlayerCombat)
func get_attack_bonus_total() -> int:
	var bonus: int = 0
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		bonus += int(data.get("attack_bonus", 0))
	return bonus


func is_invulnerable() -> bool:
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		if bool(data.get("invulnerable", false)):
			return true
	return false


func apply_buffs_snapshot(arr: Array) -> void:
	_buffs.clear()

	for v in arr:
		if not (v is Dictionary):
			continue
		var d: Dictionary = v as Dictionary
		var id: String = String(d.get("id", ""))
		if id == "":
			continue
		var left: float = float(d.get("time_left", 0.0))
		if left <= 0.0:
			continue
		var data: Dictionary = d.get("data", {}) as Dictionary
		_buffs[id] = {"time_left": left, "data": data}

	_notify_stats_changed()


func clear_all() -> void:
	_buffs.clear()
	_notify_stats_changed()


func _notify_stats_changed() -> void:
	if p == null:
		return
	if p.c_stats != null:
		p.c_stats.request_recalculate(false)
