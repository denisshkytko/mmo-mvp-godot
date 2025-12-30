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


func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	if id == "":
		return
	_buffs[id] = {"time_left": duration_sec, "data": data}
	_notify_stats_changed()


func remove_buff(id: String) -> void:
	if _buffs.has(id):
		_buffs.erase(id)
		_notify_stats_changed()


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
