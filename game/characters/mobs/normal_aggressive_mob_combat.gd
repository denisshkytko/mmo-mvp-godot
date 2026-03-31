extends Node
class_name NormalAggresiveMobCombat

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const MOB_VARIANT := preload("res://core/stats/mob_variant.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const PROFILER_UTILS := preload("res://core/debug/profiler_utils.gd")

enum AttackMode { MELEE, RANGED }

var attack_mode: int = AttackMode.MELEE

# melee params
var melee_stop_distance: float = 45.0
var melee_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
var melee_cooldown: float = 1.2

# ranged params
var ranged_attack_range: float = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
var ranged_cooldown: float = 1.5
var ranged_projectile_scene: PackedScene = null

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, snap: Dictionary) -> void:
	var t_total := Time.get_ticks_usec()
	_attack_timer = max(0.0, _attack_timer - delta)

	if target == null or not is_instance_valid(target):
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.tick_total", Time.get_ticks_usec() - t_total)
		return
	if not target.has_method("take_damage"):
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.tick_total", Time.get_ticks_usec() - t_total)
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.tick_total", Time.get_ticks_usec() - t_total)
		return

	var t_distance := Time.get_ticks_usec()
	var dist: float = _distance_between_body_hitboxes(actor, target)
	FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.distance_check", Time.get_ticks_usec() - t_distance)
	var t_damage_calc := Time.get_ticks_usec()
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var raw: int = STAT_CALC.compute_mob_unarmed_hit(ap)
	var variant_id: int = int(snap.get("mob_variant", MOB_VARIANT.MobVariant.NORMAL))
	raw = int(round(float(raw) * MOB_VARIANT.damage_mult(variant_id)))
	var dmg: int = STAT_CALC.apply_crit_to_damage(raw, snap)
	FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.damage_calc", Time.get_ticks_usec() - t_damage_calc)

	var aspct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + max(0.0, aspct) / 100.0
	if "c_stats" in actor and actor.c_stats != null and actor.c_stats.has_method("get_attack_speed_multiplier"):
		speed_mult *= float(actor.c_stats.call("get_attack_speed_multiplier"))
	if speed_mult < 0.1:
		speed_mult = 0.1

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _attack_timer <= 0.0:
			var t_melee_attack := Time.get_ticks_usec()
			DAMAGE_HELPER.apply_damage(actor, target, dmg)
			if actor != null and actor.has_method("play_model_combat_action"):
				actor.call("play_model_combat_action", "melee", false)
			_attack_timer = melee_cooldown / speed_mult
			FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.melee_attack", Time.get_ticks_usec() - t_melee_attack)
			PROFILER_UTILS.track_count("mob_aggressive.combat.attacks.melee")
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.tick_total", Time.get_ticks_usec() - t_total)
		return

	# RANGED
	if dist <= ranged_attack_range and _attack_timer <= 0.0:
		var t_ranged_attack := Time.get_ticks_usec()
		_fire_ranged(actor, target, dmg)
		if actor != null and actor.has_method("play_model_combat_action"):
			actor.call("play_model_combat_action", "ranged", false)
		_attack_timer = ranged_cooldown / speed_mult
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.ranged_attack", Time.get_ticks_usec() - t_ranged_attack)
		PROFILER_UTILS.track_count("mob_aggressive.combat.attacks.ranged")
	FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.tick_total", Time.get_ticks_usec() - t_total)

func _fire_ranged(actor: Node2D, target: Node2D, damage: int) -> void:
	var t_total := Time.get_ticks_usec()
	if ranged_projectile_scene == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.ranged_fire", Time.get_ticks_usec() - t_total)
		return

	var inst: Node = ranged_projectile_scene.instantiate()
	var proj: Node2D = inst as Node2D
	if proj == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.ranged_fire", Time.get_ticks_usec() - t_total)
		return

	var parent: Node = actor.get_parent()
	if parent == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.ranged_fire", Time.get_ticks_usec() - t_total)
		return

	parent.add_child(proj)
	proj.global_position = _projectile_spawn_origin(actor)

	if proj.has_method("setup"):
		proj.call("setup", target, damage, actor)
	FRAME_PROFILER.add_usec("mob_aggressive.combat.physics.ranged_fire", Time.get_ticks_usec() - t_total)

func get_stop_distance() -> float:
	return melee_stop_distance if attack_mode == AttackMode.MELEE else ranged_attack_range

func get_attack_damage() -> int:
	var actor_owner := get_parent()
	if actor_owner != null and "c_stats" in actor_owner and actor_owner.c_stats != null and actor_owner.c_stats.has_method("get_stats_snapshot"):
		var snap: Dictionary = actor_owner.c_stats.call("get_stats_snapshot") as Dictionary
		var derived: Dictionary = snap.get("derived", {}) as Dictionary
		var ap: float = float(derived.get("attack_power", 0.0))
		return max(1, STAT_CALC.compute_mob_unarmed_hit(ap))
	return 1


func _distance_between_body_hitboxes(a: Node2D, b: Node2D) -> float:
	if a == null or b == null:
		return INF
	var a_pos := a.global_position
	var b_pos := b.global_position
	if a.has_method("get_body_hitbox_center_global"):
		a_pos = a.call("get_body_hitbox_center_global")
	if b.has_method("get_body_hitbox_center_global"):
		b_pos = b.call("get_body_hitbox_center_global")
	return a_pos.distance_to(b_pos)

func _projectile_spawn_origin(actor: Node2D) -> Vector2:
	if actor == null:
		return Vector2.ZERO
	if actor.has_method("get_body_hitbox_center_global"):
		var v: Variant = actor.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return actor.global_position
