extends AbilityEffect
class_name EffectHailstorm

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")
const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var school: String = "magic" # physical | magic
@export var scaling_mode: String = "spell_power_flat" # flat | phys_base_pct | spell_power_flat | attack_power_pct
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/MageFrostboltProjectile.tscn")
@export var projectile_z_index: int = 2000
@export var wave_delay_sec: float = 0.10
@export var base_arc_offset_px: float = 96.0
@export var odd_pair_step_mul: float = 1.15
@export var even_pair_base_mul: float = 0.70
@export var even_pair_step_mul: float = 1.0

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (caster is Node2D) or not (target is Node2D):
		return
	if projectile_scene == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base_damage: int = _compute_base_damage(caster, rank_data, snap)
	if base_damage <= 0:
		return

	var hit_count: int = max(1, int(rank_data.value_flat_2))
	var final_damage: int = STAT_CALC.apply_crit_to_damage_typed(base_damage, snap, school)
	if final_damage <= 0:
		return

	_spawn_hailstorm_burst(caster as Node2D, target as Node2D, final_damage, hit_count)

func _spawn_hailstorm_burst(caster: Node2D, target: Node2D, damage: int, hit_count: int) -> void:
	var parent: Node = caster.get_parent()
	if parent == null:
		return
	var launcher := Node.new()
	launcher.name = "HailstormBurstLauncher"
	parent.add_child(launcher)

	var waves: Array = _build_fan_waves(hit_count)
	if waves.is_empty():
		launcher.queue_free()
		return

	var shared_start: Vector2 = _resolve_anchor(caster)
	for wave_idx in range(waves.size()):
		if wave_idx > 0:
			var timer := launcher.get_tree().create_timer(wave_delay_sec)
			await timer.timeout
		if not is_instance_valid(launcher) or not is_instance_valid(caster) or not is_instance_valid(target):
			break
		if "is_dead" in target and bool(target.get("is_dead")):
			break
		var wave_offsets: Array = waves[wave_idx] as Array
		for offset_v in wave_offsets:
			var offset: float = float(offset_v)
			_spawn_single_projectile(parent, shared_start, caster, target, damage, offset)

	if is_instance_valid(launcher):
		launcher.queue_free()

func _spawn_single_projectile(parent: Node, spawn_pos: Vector2, caster: Node2D, target: Node2D, damage: int, arc_offset: float) -> void:
	var projectile: Node2D = projectile_scene.instantiate() as Node2D
	if projectile == null:
		return
	parent.add_child(projectile)
	projectile.z_as_relative = false
	projectile.z_index = projectile_z_index
	projectile.global_position = spawn_pos

	if projectile.has_method("setup"):
		projectile.call("setup", target, damage, caster)
	else:
		projectile.queue_free()
		return

	if "use_curved_path" in projectile:
		projectile.set("use_curved_path", absf(arc_offset) > 0.001)
	if "path_arc_offset_px" in projectile:
		projectile.set("path_arc_offset_px", arc_offset)
	if "path_start_global" in projectile:
		projectile.set("path_start_global", spawn_pos)
	if projectile.has_method("refresh_path_from_current_target"):
		projectile.call("refresh_path_from_current_target")

func _build_fan_waves(hit_count: int) -> Array:
	var waves: Array = []
	if hit_count <= 0:
		return waves

	var pair_count: int = hit_count / 2
	var has_center: bool = (hit_count % 2) == 1
	if has_center:
		waves.append([0.0])
		for pair_idx in range(pair_count):
			var mul: float = odd_pair_step_mul * float(pair_idx + 1)
			var arc: float = base_arc_offset_px * mul
			waves.append([arc, -arc])
	else:
		for pair_idx in range(pair_count):
			var mul: float = even_pair_base_mul + even_pair_step_mul * float(pair_idx)
			var arc: float = base_arc_offset_px * mul
			waves.append([arc, -arc])
	return waves

func _resolve_anchor(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ZERO
	return VFX_ANCHOR_HELPER.resolve_world_collider_center(node, node.global_position)

func _compute_base_damage(caster: Node, rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	var attack_power: float = float(derived.get("attack_power", 0.0))

	match scaling_mode:
		"flat":
			return int(rank_data.value_flat)
		"phys_base_pct":
			var base_phys: int = 0
			if "c_combat" in caster and caster.c_combat != null:
				if caster.c_combat.has_method("get_attack_damage"):
					base_phys = int(caster.c_combat.call("get_attack_damage"))
			return int(round(float(base_phys) * float(rank_data.value_pct) / 100.0))
		"spell_power_flat":
			return int(rank_data.value_flat) + SP_SCALING.bonus_flat(spell_power, rank_data, "direct")
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat)
