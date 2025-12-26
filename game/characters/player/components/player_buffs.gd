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

	for id in to_remove:
		_buffs.erase(id)

func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	if id == "":
		return
	_buffs[id] = {"time_left": duration_sec, "data": data}

func remove_buff(id: String) -> void:
	if _buffs.has(id):
		_buffs.erase(id)

func get_buffs_snapshot() -> Array:
	var arr: Array = []
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		arr.append({
			"id": id,
			"time_left": float(entry.get("time_left", 0.0)),
		})
	return arr

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
