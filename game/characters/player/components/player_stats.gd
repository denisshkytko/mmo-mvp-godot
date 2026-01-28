extends Node
class_name PlayerStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const PROG := preload("res://core/stats/progression.gd")
const XP_SYSTEM := preload("res://core/progression/xp_system.gd")

var p: Player = null

signal stats_changed(snapshot: Dictionary)

# --- Legacy primary base (level 1) ---
var base_str: int = 10
var base_agi: int = 10
var base_end: int = 10
var base_int: int = 10
var base_per: int = 10

# --- Legacy primary growth per level ---
# (Only these scale directly from level)
var str_per_level: int = 1
var agi_per_level: int = 1
var end_per_level: int = 1
var int_per_level: int = 1
var per_per_level: int = 1

# Cached last snapshot (for UI)
var _snapshot: Dictionary = {}
var _base_stats: Dictionary = {}
var _equipment_bonus: Dictionary = {}
var _use_legacy_primary: bool = false
var _legacy_base_primary: Dictionary = {}
var _legacy_per_level: Dictionary = {}

# Regen accumulators (float pools so small regen values still work)
var _hp_regen_pool: float = 0.0
var _mana_regen_pool: float = 0.0

func setup(player: Player) -> void:
	p = player

func add_xp(amount: int) -> void:
	if p == null:
		return
	if amount <= 0:
		return

	p.xp += amount
	while p.xp >= p.xp_to_next:
		p.xp -= p.xp_to_next
		p.level += 1
		p.xp_to_next = _calc_xp_to_next(p.level)
		recalculate_for_level(true)

func _calc_xp_to_next(new_level: int) -> int:
	return XP_SYSTEM.xp_to_next(new_level)

func recalculate_for_level(full_restore: bool) -> void:
	if p == null:
		return

	_snapshot = _build_snapshot()
	_apply_rage_mana_override(_snapshot)

	# Apply to public fields (HUDs rely on these)
	p.max_hp = int(_snapshot.get("derived", {}).get("max_hp", p.max_hp))
	p.max_mana = int(_snapshot.get("derived", {}).get("max_mana", p.max_mana))

	# Keep compatibility fields (old code uses p.attack/p.defense)
	p.attack = int(_snapshot.get("derived", {}).get("attack_power", p.attack))
	p.defense = int(_snapshot.get("derived", {}).get("defense", p.defense))

	# Optional extra fields (safe even if UI ignores them)
	if p.has_method("set"):
		p.set("spell_power", int(round(float(_snapshot.get("derived", {}).get("spell_power", 0.0)))))
		p.set("magic_resist", int(round(float(_snapshot.get("derived", {}).get("magic_resist", 0.0)))))
		p.set("hp_regen", float(_snapshot.get("derived", {}).get("hp_regen", 0.0)))
		p.set("mana_regen", float(_snapshot.get("derived", {}).get("mana_regen", 0.0)))

	if full_restore:
		p.current_hp = p.max_hp
		p.mana = p.max_mana
	else:
		p.current_hp = clamp(p.current_hp, 0, p.max_hp)
		p.mana = clamp(p.mana, 0, p.max_mana)

	emit_signal("stats_changed", _snapshot)

func _get_resource_type() -> String:
	if p == null:
		return "mana"
	if "c_resource" in p and p.c_resource != null:
		return String(p.c_resource.resource_type)
	return String(PROG.get_resource_type_for_class(p.class_id))

func _apply_rage_mana_override(snapshot: Dictionary) -> void:
	if _get_resource_type() != "rage":
		return
	var derived: Dictionary = snapshot.get("derived", {}) as Dictionary
	derived["max_mana"] = 0
	derived["mana_regen"] = 0
	snapshot["derived"] = derived
	if p != null:
		p.max_mana = 0
		p.mana = 0


func request_recalculate(full_restore: bool = false) -> void:
	# public method for Buffs/Equipment changes
	recalculate_for_level(full_restore)


func tick(delta: float) -> void:
	# Stage 1: player regen from derived stats
	if p == null or p.is_dead:
		return
	if _snapshot.is_empty():
		return

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	var hp_regen_per_sec: float = float(d.get("hp_regen", 0.0))
	var mana_regen_per_sec: float = float(d.get("mana_regen", 0.0))
	if hp_regen_per_sec <= 0.0 and mana_regen_per_sec <= 0.0:
		return

	# Mana regenerates ALWAYS (in and out of combat)
	if mana_regen_per_sec > 0.0 and p.mana < p.max_mana:
		_mana_regen_pool += mana_regen_per_sec * delta
		if _mana_regen_pool >= 1.0:
			var add_mana: int = int(floor(_mana_regen_pool))
			_mana_regen_pool -= float(add_mana)
			p.mana = min(p.max_mana, p.mana + add_mana)
	else:
		_mana_regen_pool = 0.0

	# HP regenerates ONLY out of combat
	var out_of_combat := true
	if p.has_method("is_out_of_combat"):
		out_of_combat = bool(p.call("is_out_of_combat"))
	if out_of_combat and hp_regen_per_sec > 0.0 and p.current_hp < p.max_hp:
		_hp_regen_pool += hp_regen_per_sec * delta
		if _hp_regen_pool >= 1.0:
			var add_hp: int = int(floor(_hp_regen_pool))
			_hp_regen_pool -= float(add_hp)
			p.current_hp = min(p.max_hp, p.current_hp + add_hp)
	else:
		# reset pool when healing is not allowed (prevents "stored" regen)
		_hp_regen_pool = 0.0


func get_stats_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func get_base_stat(stat_id: String):
	if _base_stats.has(stat_id):
		return _base_stats[stat_id]
	return 0

func get_equipment_bonus(stat_id: String):
	if _equipment_bonus.has(stat_id):
		return _equipment_bonus[stat_id]
	return 0

func get_total_stat(stat_id: String):
	return get_base_stat(stat_id) + get_equipment_bonus(stat_id)

func apply_primary_data(data: Dictionary) -> void:
	var incoming_class_id := String(data.get("class_id", "")).strip_edges()
	if incoming_class_id != "":
		_use_legacy_primary = false
		_legacy_base_primary = {}
		_legacy_per_level = {}
		return

	_use_legacy_primary = true
	# Backward compatible: if no keys, keep defaults
	base_str = int(data.get("base_str", base_str))
	base_agi = int(data.get("base_agi", base_agi))
	base_end = int(data.get("base_end", base_end))
	base_int = int(data.get("base_int", base_int))
	base_per = int(data.get("base_per", base_per))

	# Optional: allow save to override per-level growth later
	str_per_level = int(data.get("str_per_level", str_per_level))
	agi_per_level = int(data.get("agi_per_level", agi_per_level))
	end_per_level = int(data.get("end_per_level", end_per_level))
	int_per_level = int(data.get("int_per_level", int_per_level))
	per_per_level = int(data.get("per_per_level", per_per_level))

	_legacy_base_primary = {
		"str": base_str,
		"agi": base_agi,
		"end": base_end,
		"int": base_int,
		"per": base_per,
	}
	_legacy_per_level = {
		"str": str_per_level,
		"agi": agi_per_level,
		"end": end_per_level,
		"int": int_per_level,
		"per": per_per_level,
	}
	if PROG.DEBUG_LOGS:
		print("PlayerStats legacy primary loaded (class_id missing).")


func export_primary_data() -> Dictionary:
	if not _use_legacy_primary:
		return {}
	return {
		"base_str": base_str,
		"base_agi": base_agi,
		"base_end": base_end,
		"base_int": base_int,
		"base_per": base_per,
		"str_per_level": str_per_level,
		"agi_per_level": agi_per_level,
		"end_per_level": end_per_level,
		"int_per_level": int_per_level,
		"per_per_level": per_per_level,
	}


func _build_snapshot() -> Dictionary:
	var class_id := "warrior"
	if p != null:
		var id_from_player := String(p.class_id)
		if id_from_player != "":
			class_id = id_from_player

	var base_primary: Dictionary
	var per_lvl: Dictionary
	if _use_legacy_primary:
		if _legacy_base_primary.is_empty():
			_legacy_base_primary = {
				"str": base_str,
				"agi": base_agi,
				"end": base_end,
				"int": base_int,
				"per": base_per,
			}
		if _legacy_per_level.is_empty():
			_legacy_per_level = {
				"str": str_per_level,
				"agi": agi_per_level,
				"end": end_per_level,
				"int": int_per_level,
				"per": per_per_level,
			}
		base_primary = _legacy_base_primary.duplicate(true)
		per_lvl = _legacy_per_level.duplicate(true)
	else:
		var primary_int := PROG.get_primary_for_entity(p.level, class_id, "player_default")
		var zero_per := {"str": 0, "agi": 0, "end": 0, "int": 0, "per": 0}
		base_primary = primary_int
		per_lvl = zero_per

	var gear_base := {
		"primary": {},
		"secondary": {},
	}

	var gear_equipment := {
		"primary": {},
		"secondary": {},
	}

	if p != null and p.c_equip != null:
		gear_equipment = _collect_equipment_modifiers()

	var gear_total := _merge_gear(gear_base, gear_equipment)

	var buffs: Array = []
	if p != null and p.c_buffs != null:
		buffs = p.c_buffs.get_buffs_snapshot()

	var snapshot_level := p.level
	if not _use_legacy_primary:
		snapshot_level = 1
	var base_snapshot: Dictionary = STAT_CALC.build_player_snapshot(snapshot_level, base_primary, per_lvl, gear_base, buffs)
	var total_snapshot: Dictionary = STAT_CALC.build_player_snapshot(snapshot_level, base_primary, per_lvl, gear_total, buffs)

	if OS.is_debug_build() and p != null and p.class_id == "mage" and p.level <= 4:
		print("Player mage L%d primary=%s" % [p.level, str(total_snapshot.get("primary", {}))])

	_base_stats = _collect_flat_stats(base_snapshot)
	_equipment_bonus = _diff_stats(total_snapshot, base_snapshot)

	return total_snapshot

func _collect_equipment_modifiers() -> Dictionary:
	var out := {
		"primary": {},
		"secondary": {},
	}
	var equip: Dictionary = p.c_equip.get_equipment_snapshot()
	if equip.is_empty():
		return out
	var db := get_node_or_null("/root/DataDB")
	for slot_id in equip.keys():
		var v: Variant = equip[slot_id]
		if v == null or not (v is Dictionary):
			continue
		var d: Dictionary = v as Dictionary
		var id: String = String(d.get("id", ""))
		if id == "":
			continue
		if db == null or not db.has_method("get_item"):
			continue
		var meta: Dictionary = db.call("get_item", id) as Dictionary
		var mods: Dictionary = meta.get("stats_modifiers", {}) as Dictionary
		for key in mods.keys():
			var val: int = int(mods.get(key, 0))
			if val == 0:
				continue
			_map_modifier(out, String(key), val)
		var secondary := out.get("secondary", {}) as Dictionary
		var typ: String = String(meta.get("type", "")).to_lower()
		if typ == "armor":
			var a := meta.get("armor", {}) as Dictionary
			secondary["defense"] = int(secondary.get("defense", 0)) + int(a.get("physical_armor", 0))
			secondary["magic_resist"] = int(secondary.get("magic_resist", 0)) + int(a.get("magic_armor", 0))
		elif typ == "offhand":
			var o := meta.get("offhand", {}) as Dictionary
			secondary["defense"] = int(secondary.get("defense", 0)) + int(o.get("physical_armor", 0))
			secondary["magic_resist"] = int(secondary.get("magic_resist", 0)) + int(o.get("magic_armor", 0))
		out["secondary"] = secondary
	return out

func _map_modifier(gear: Dictionary, stat_key: String, value: int) -> void:
	var primary := gear.get("primary", {}) as Dictionary
	var secondary := gear.get("secondary", {}) as Dictionary

	match stat_key:
		"STR":
			primary["str"] = int(primary.get("str", 0)) + value
		"AGI":
			primary["agi"] = int(primary.get("agi", 0)) + value
		"END":
			primary["end"] = int(primary.get("end", 0)) + value
		"INT":
			primary["int"] = int(primary.get("int", 0)) + value
		"PER":
			primary["per"] = int(primary.get("per", 0)) + value
		"AttackPower":
			secondary["attack_power"] = int(secondary.get("attack_power", 0)) + value
		"SpellPower":
			secondary["spell_power"] = int(secondary.get("spell_power", 0)) + value
		"SpeedRating":
			secondary["speed"] = int(secondary.get("speed", 0)) + value
		"CritChanceRating":
			secondary["crit_chance_rating"] = int(secondary.get("crit_chance_rating", 0)) + value
		"CritDamageRating":
			secondary["crit_damage_rating"] = int(secondary.get("crit_damage_rating", 0)) + value
		"HPRegen":
			secondary["hp_regen"] = float(secondary.get("hp_regen", 0.0)) + float(value)
		"ManaRegen":
			secondary["mana_regen"] = float(secondary.get("mana_regen", 0.0)) + float(value)
		_:
			pass

	gear["primary"] = primary
	gear["secondary"] = secondary

func _merge_gear(base_gear: Dictionary, extra_gear: Dictionary) -> Dictionary:
	var merged := {
		"primary": {},
		"secondary": {},
	}
	for cat in ["primary", "secondary"]:
		var out_cat: Dictionary = {}
		var base_cat: Dictionary = base_gear.get(cat, {}) as Dictionary
		var extra_cat: Dictionary = extra_gear.get(cat, {}) as Dictionary
		for key in base_cat.keys():
			out_cat[key] = base_cat[key]
		for key in extra_cat.keys():
			var v: float = float(out_cat.get(key, 0)) + float(extra_cat.get(key, 0))
			out_cat[key] = v
		merged[cat] = out_cat
	return merged

func _collect_flat_stats(snapshot: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var prim: Dictionary = snapshot.get("primary", {}) as Dictionary
	var derived: Dictionary = snapshot.get("derived", {}) as Dictionary
	for key in prim.keys():
		out[key] = prim[key]
	for key in derived.keys():
		out[key] = derived[key]
	return out

func _diff_stats(total_snapshot: Dictionary, base_snapshot: Dictionary) -> Dictionary:
	var total_stats := _collect_flat_stats(total_snapshot)
	var base_stats := _collect_flat_stats(base_snapshot)
	var out: Dictionary = {}
	for key in total_stats.keys():
		out[key] = float(total_stats.get(key, 0)) - float(base_stats.get(key, 0))
	return out

func take_damage(raw_damage: int) -> void:
	if p == null:
		return
	if "c_resource" in p and p.c_resource != null:
		p.c_resource.on_damage_taken()

	# неуязвимость через баф (если есть)
	var buffs: PlayerBuffs = p.c_buffs
	if buffs != null and buffs.is_invulnerable():
		return

	var phys_pct: float = float(_snapshot.get("physical_reduction_pct", 0.0))
	var final: int = int(ceil(float(raw_damage) * (1.0 - phys_pct / 100.0)))
	final = max(1, final)
	p.current_hp = max(0, p.current_hp - final)

	if p.current_hp <= 0:
		_on_death()

func _on_death() -> void:
	# 1) помечаем игрока мёртвым (останавливаем движение/атаки)
	p.is_dead = true

	get_tree().call_group("mobs", "on_player_died")

	# 2) сбрасываем бафы
	if p != null and p.c_buffs != null:
		p.c_buffs.clear_all()

	# 3) сброс таргета + запрос сейва
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm != null:
		if gm.has_method("clear_target"):
			gm.call("clear_target")
		if gm.has_method("request_save"):
			gm.call("request_save", "death")

	# 4) показываем окно респавна (RespawnUi в GameUI)
	var respawn_ui: Node = get_tree().get_first_node_in_group("respawn_ui")
	if respawn_ui != null and respawn_ui.has_method("open"):
		respawn_ui.call("open", p, 3.0) # 3 секунды ожидания (можешь поменять)
