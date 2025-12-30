extends Node
class_name PlayerStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")

var p: Player = null

signal stats_changed(snapshot: Dictionary)

# --- Saved primary base (level 1) ---
@export var base_str: int = 10
@export var base_agi: int = 10
@export var base_end: int = 10
@export var base_int: int = 10
@export var base_per: int = 10

# --- Primary growth per level ---
# (Only these scale directly from level)
@export var str_per_level: int = 1
@export var agi_per_level: int = 1
@export var end_per_level: int = 1
@export var int_per_level: int = 1
@export var per_per_level: int = 1

# "Base gear" placeholder.
# Player spawns in simple grey items in the future. For now, we keep
# a tiny base defense so early combat does not feel too punishing.
@export var base_gear_defense: int = 2

# Cached last snapshot (for UI)
var _snapshot: Dictionary = {}

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
	return 10 + (new_level - 1) * 5

func recalculate_for_level(full_restore: bool) -> void:
	if p == null:
		return

	_snapshot = _build_snapshot()

	# Apply to public fields (HUDs rely on these)
	p.max_hp = int(_snapshot.get("derived", {}).get("max_hp", p.max_hp))
	p.max_mana = int(_snapshot.get("derived", {}).get("max_mana", p.max_mana))

	# Keep compatibility fields (old code uses p.attack/p.defense)
	p.attack = int(round(float(_snapshot.get("derived", {}).get("attack_power", p.attack))))
	p.defense = int(round(float(_snapshot.get("derived", {}).get("defense", p.defense))))

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


func apply_primary_data(data: Dictionary) -> void:
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


func export_primary_data() -> Dictionary:
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
	var base_primary := {
		"str": base_str,
		"agi": base_agi,
		"end": base_end,
		"int": base_int,
		"per": base_per,
	}
	var per_lvl := {
		"str": str_per_level,
		"agi": agi_per_level,
		"end": end_per_level,
		"int": int_per_level,
		"per": per_per_level,
	}

	# Gear placeholder. Later Equipment will fill these.
	var gear := {
		"primary": {},
		"secondary": {
			"defense": base_gear_defense,
			"magic_resist": 0,
			"speed": 0,
			"crit_chance_rating": 0,
			"crit_damage_rating": 0,
		}
	}

	var buffs: Array = []
	if p != null and p.c_buffs != null:
		buffs = p.c_buffs.get_buffs_snapshot()

	return STAT_CALC.build_player_snapshot(p.level, base_primary, per_lvl, gear, buffs)

func take_damage(raw_damage: int) -> void:
	if p == null:
		return
	# Any incoming damage puts player in combat (pauses HP regen)
	if p.has_method("mark_in_combat"):
		p.call("mark_in_combat")

	# неуязвимость через баф (если есть)
	var buffs: PlayerBuffs = p.c_buffs
	if buffs != null and buffs.is_invulnerable():
		return

	var dmg: int = max(1, raw_damage - p.defense)
	p.current_hp = max(0, p.current_hp - dmg)

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
