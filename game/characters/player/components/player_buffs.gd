extends Node
class_name PlayerBuffs

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

const BuffData := preload("res://core/buffs/buff_data.gd")

const SPIRITS_AID_ABILITY_ID: String = "spirits_aid"
const SPIRITS_AID_READY_BUFF_ID: String = "passive:spirits_aid_ready"
const SPIRITS_AID_COOLDOWN_SEC: float = 900.0
const DEFENSIVE_REFLEXES_ABILITY_ID: String = "defensive_reflexes"
const DEFENSIVE_REFLEXES_READY_BUFF_ID: String = "passive:defensive_reflexes_ready"

var p: Player = null

# id -> {"time_left": float, "data": Dictionary}
var _buffs: Dictionary = {}
var _spirits_aid_cd_left: float = 0.0
var _defensive_reflexes_cd_left: float = 0.0

func setup(player: Player) -> void:
	p = player
	_sync_spirits_aid_ready_state()
	_sync_defensive_reflexes_ready_state()

func tick(delta: float) -> void:
	if _spirits_aid_cd_left > 0.0:
		_spirits_aid_cd_left = max(0.0, _spirits_aid_cd_left - delta)
		if _spirits_aid_cd_left <= 0.0:
			_sync_spirits_aid_ready_state()

	if _defensive_reflexes_cd_left > 0.0:
		_defensive_reflexes_cd_left = max(0.0, _defensive_reflexes_cd_left - delta)
		if _defensive_reflexes_cd_left <= 0.0:
			_sync_defensive_reflexes_ready_state()

	if _buffs.is_empty():
		return

	# Apply over-time consumable effects (heal / mana restore). These should work
	# even in combat, so we apply them directly here instead of piggy-backing on
	# PlayerStats regen (which is out-of-combat for HP).
	if p != null and not p.is_dead:
		_apply_consumable_hots(delta)
		_apply_periodic_heal_effects(delta)
		_apply_periodic_resource_effects(delta)
		_apply_periodic_damage_effects(delta)

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
					var hp_before: int = p.current_hp
					p.current_hp += give
					hp_left -= give
					var actual_heal: int = max(0, p.current_hp - hp_before)
					if actual_heal > 0:
						DAMAGE_HELPER.show_heal(p, actual_heal)
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


func _apply_periodic_resource_effects(delta: float) -> void:
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		var mana_pct: float = float(flags.get("mana_pct_of_max_per_tick", data.get("mana_pct_of_max_per_tick", 0.0)))
		if mana_pct <= 0.0:
			continue
		var interval: float = float(flags.get("mana_tick_interval_sec", data.get("mana_tick_interval_sec", 2.0)))
		if interval <= 0.0:
			interval = 2.0
		var acc: float = float(data.get("mana_tick_acc", 0.0)) + delta
		var changed := false
		while acc >= interval:
			acc -= interval
			if p == null or p.mana >= p.max_mana:
				continue
			var add_mana: int = int(round(float(p.max_mana) * mana_pct / 100.0))
			if add_mana <= 0:
				add_mana = 1
			p.mana = min(p.max_mana, p.mana + add_mana)
			changed = true
		data["mana_tick_acc"] = acc
		if changed:
			entry["data"] = data
			_buffs[id] = entry
		else:
			entry["data"] = data
			_buffs[id] = entry

func _apply_periodic_heal_effects(delta: float) -> void:
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		var heal_flat: int = int(flags.get("hp_regen_tick_flat", data.get("hp_regen_tick_flat", 0)))
		if heal_flat <= 0:
			continue
		var interval: float = float(flags.get("hp_regen_tick_interval_sec", data.get("hp_regen_tick_interval_sec", 1.0)))
		if interval <= 0.0:
			interval = 1.0

		var acc: float = float(data.get("hp_regen_tick_acc", 0.0)) + delta
		while acc >= interval:
			acc -= interval
			if p == null or p.is_dead or p.current_hp >= p.max_hp:
				continue
			var hp_before: int = p.current_hp
			p.current_hp = min(p.max_hp, p.current_hp + heal_flat)
			var healed: int = max(0, p.current_hp - hp_before)
			if healed > 0:
				DAMAGE_HELPER.show_heal(p, healed)

		data["hp_regen_tick_acc"] = acc
		entry["data"] = data
		_buffs[id] = entry

func _apply_periodic_damage_effects(delta: float) -> void:
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		var total_pct: float = float(flags.get("dot_total_pct_of_attack_damage", 0.0))
		var source_attack_damage: float = float(flags.get("dot_source_attack_damage", 0.0))
		var total_damage_flat: float = float(flags.get("dot_total_damage_flat", 0.0))
		var bonus_damage_flat: float = float(flags.get("dot_bonus_damage_flat", 0.0))

		var total_damage: float = 0.0
		if total_damage_flat > 0.0 or bonus_damage_flat != 0.0:
			total_damage = max(0.0, total_damage_flat + bonus_damage_flat)
		elif total_pct > 0.0 and source_attack_damage > 0.0:
			total_damage = max(0.0, source_attack_damage * total_pct / 100.0)
		if total_damage <= 0.0:
			continue

		var duration: float = max(0.01, float(data.get("duration_sec", entry.get("time_left", 0.0))))
		var interval: float = max(0.1, float(flags.get("dot_tick_interval_sec", 1.0)))
		var school: String = String(flags.get("dot_damage_school", "physical"))
		var ignore_mitigation: bool = bool(flags.get("dot_ignore_physical_mitigation", false))
		var ticks_total: int = max(1, int(round(duration / interval)))
		var damage_per_tick: int = max(1, int(round(total_damage / float(ticks_total))))

		var acc: float = float(data.get("dot_tick_acc", 0.0)) + delta
		while acc >= interval:
			acc -= interval
			if p == null or p.is_dead or p.c_stats == null:
				break
			if p.c_stats.has_method("apply_periodic_damage"):
				p.c_stats.call("apply_periodic_damage", damage_per_tick, school, ignore_mitigation)
		data["dot_tick_acc"] = acc
		entry["data"] = data
		_buffs[id] = entry

func add_or_refresh_buff(id: String, duration_sec: float, data: Variant = {}, ability_id: String = "", source: String = "") -> void:
	if id == "":
		return
	var data_dict := _normalize_buff_data(data)
	var entry_ability_id: String = ability_id if ability_id != "" else String(data_dict.get("ability_id", ""))
	var entry_source: String = source if source != "" else String(data_dict.get("source", ""))
	var effective_duration: float = duration_sec
	if effective_duration <= 0.0:
		effective_duration = 999999.0
	_buffs[id] = {
		"time_left": effective_duration,
		"data": data_dict,
		"ability_id": entry_ability_id,
		"source": entry_source,
	}
	_notify_stats_changed()


func remove_buff(id: String) -> void:
	if not _buffs.has(id):
		return
	var entry: Dictionary = _buffs[id] as Dictionary
	var source: String = String(entry.get("source", ""))
	if source == "aura" or source == "stance" or source == "passive":
		return
	_buffs.erase(id)
	_notify_stats_changed()

func remove_buffs_with_prefix(prefix: String) -> void:
	if prefix == "":
		return
	var removed_any := false
	for k in _buffs.keys():
		var id: String = String(k)
		if id.begins_with(prefix):
			_buffs.erase(id)
			removed_any = true
	if removed_any:
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
			"data": entry.get("data", {}) as Dictionary,
			"ability_id": String(entry.get("ability_id", "")),
			"source": String(entry.get("source", "")),
		})
	return arr

func get_active_stance_data() -> Dictionary:
	for k in _buffs.keys():
		var id: String = String(k)
		if id == "active_stance" or id.begins_with("stance:"):
			var entry: Dictionary = _buffs[id] as Dictionary
			var data: Dictionary = entry.get("data", {}) as Dictionary
			if data.has("on_hit"):
				return data.get("on_hit", {}) as Dictionary
			return data
	return {}


func on_owner_took_damage() -> void:
	if _buffs.is_empty():
		return
	var removed_any := false
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		if bool(flags.get("remove_on_damage", false)) or bool(data.get("remove_on_damage", false)):
			_buffs.erase(id)
			removed_any = true
	if removed_any:
		_notify_stats_changed()

func get_move_speed_multiplier() -> float:
	var mult: float = 1.0
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		var pct: float = float(flags.get("move_speed_pct", data.get("move_speed_pct", 0.0)))
		if pct != 0.0:
			mult *= (1.0 + pct / 100.0)
			continue
		var direct_mult: float = float(flags.get("move_speed_multiplier", data.get("move_speed_multiplier", 1.0)))
		if direct_mult > 0.0 and direct_mult != 1.0:
			mult *= direct_mult
	if mult <= 0.0:
		return 1.0
	return mult

func get_attack_speed_multiplier() -> float:
	var mult: float = 1.0
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var aspd_mult: float = float(data.get("attack_speed_multiplier", 1.0))
		if aspd_mult > 0.0 and aspd_mult != 1.0:
			mult *= aspd_mult
	if mult <= 0.0:
		return 1.0
	return mult

func is_stunned() -> bool:
	for k in _buffs.keys():
		var id: String = String(k)
		var entry: Dictionary = _buffs[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		if bool(flags.get("stunned", false)) or bool(data.get("stunned", false)):
			return true
	return false


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
		var flags: Dictionary = data.get("flags", {}) as Dictionary
		if bool(flags.get("invulnerable", false)) or bool(data.get("invulnerable", false)):
			return true
	return false


func get_spirits_aid_cooldown_left() -> float:
	return max(0.0, _spirits_aid_cd_left)

func set_spirits_aid_cooldown_left(seconds: float) -> void:
	_spirits_aid_cd_left = max(0.0, seconds)
	_sync_spirits_aid_ready_state()

func can_use_spirits_aid() -> bool:
	if _spirits_aid_cd_left > 0.0:
		return false
	if p == null or p.c_spellbook == null:
		return false
	return int(p.c_spellbook.learned_ranks.get(SPIRITS_AID_ABILITY_ID, 0)) > 0

func consume_spirits_aid() -> bool:
	if not can_use_spirits_aid():
		return false
	_spirits_aid_cd_left = SPIRITS_AID_COOLDOWN_SEC
	if _buffs.has(SPIRITS_AID_READY_BUFF_ID):
		_buffs.erase(SPIRITS_AID_READY_BUFF_ID)
		_notify_stats_changed()
	return true

func _sync_spirits_aid_ready_state() -> void:
	var should_show_ready: bool = can_use_spirits_aid() and p != null and not p.is_dead
	var had_ready: bool = _buffs.has(SPIRITS_AID_READY_BUFF_ID)
	if should_show_ready and not had_ready:
		_buffs[SPIRITS_AID_READY_BUFF_ID] = {
			"time_left": 999999.0,
			"data": {
				"ability_id": SPIRITS_AID_ABILITY_ID,
				"source": "passive"
			},
			"ability_id": SPIRITS_AID_ABILITY_ID,
			"source": "passive",
		}
		_notify_stats_changed()
	elif not should_show_ready and had_ready:
		_buffs.erase(SPIRITS_AID_READY_BUFF_ID)
		_notify_stats_changed()

func get_defensive_reflexes_cooldown_left() -> float:
	return max(0.0, _defensive_reflexes_cd_left)

func set_defensive_reflexes_cooldown_left(seconds: float) -> void:
	_defensive_reflexes_cd_left = max(0.0, seconds)
	_sync_defensive_reflexes_ready_state()

func can_trigger_defensive_reflexes() -> bool:
	if _defensive_reflexes_cd_left > 0.0:
		return false
	if p == null or p.c_spellbook == null:
		return false
	return int(p.c_spellbook.learned_ranks.get(DEFENSIVE_REFLEXES_ABILITY_ID, 0)) > 0

func consume_defensive_reflexes() -> bool:
	if not can_trigger_defensive_reflexes():
		return false
	_defensive_reflexes_cd_left = _get_defensive_reflexes_cooldown_sec()
	if _buffs.has(DEFENSIVE_REFLEXES_READY_BUFF_ID):
		_buffs.erase(DEFENSIVE_REFLEXES_READY_BUFF_ID)
		_notify_stats_changed()
	return true

func try_consume_defensive_reflexes_on_hit() -> bool:
	if p == null or p.is_dead:
		return false
	return consume_defensive_reflexes()

func _get_defensive_reflexes_cooldown_sec() -> float:
	if p == null or p.c_spellbook == null:
		return 8.0
	var rank: int = int(p.c_spellbook.learned_ranks.get(DEFENSIVE_REFLEXES_ABILITY_ID, 0))
	if rank <= 0:
		return 8.0
	var db := get_node_or_null("/root/AbilityDB")
	if db != null and db.has_method("get_rank_data"):
		var rank_data: RankData = db.call("get_rank_data", DEFENSIVE_REFLEXES_ABILITY_ID, rank)
		if rank_data != null and rank_data.cooldown_sec > 0.0:
			return rank_data.cooldown_sec
	return 8.0

func _sync_defensive_reflexes_ready_state() -> void:
	var should_show_ready: bool = can_trigger_defensive_reflexes() and p != null and not p.is_dead
	var had_ready: bool = _buffs.has(DEFENSIVE_REFLEXES_READY_BUFF_ID)
	if should_show_ready and not had_ready:
		_buffs[DEFENSIVE_REFLEXES_READY_BUFF_ID] = {
			"time_left": 999999.0,
			"data": {
				"ability_id": DEFENSIVE_REFLEXES_ABILITY_ID,
				"source": "passive"
			},
			"ability_id": DEFENSIVE_REFLEXES_ABILITY_ID,
			"source": "passive",
		}
		_notify_stats_changed()
	elif not should_show_ready and had_ready:
		_buffs.erase(DEFENSIVE_REFLEXES_READY_BUFF_ID)
		_notify_stats_changed()

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
		var data: Dictionary = _normalize_buff_data(d.get("data", {}) as Dictionary)
		var entry_ability_id: String = String(d.get("ability_id", data.get("ability_id", "")))
		var entry_source: String = String(d.get("source", data.get("source", "")))
		_buffs[id] = {
			"time_left": left,
			"data": data,
			"ability_id": entry_ability_id,
			"source": entry_source,
		}

	_sync_spirits_aid_ready_state()
	_sync_defensive_reflexes_ready_state()
	_notify_stats_changed()


func clear_all() -> void:
	_buffs.clear()
	_notify_stats_changed()


func _notify_stats_changed() -> void:
	if p == null:
		return
	if p.c_stats != null:
		p.c_stats.request_recalculate(false)

func _normalize_buff_data(data: Variant) -> Dictionary:
	if data is BuffData:
		return (data as BuffData).to_dict()
	if data is Dictionary:
		return data as Dictionary
	return {}
