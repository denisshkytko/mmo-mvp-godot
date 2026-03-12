extends AbilityEffect
class_name EffectHunterMagicShot

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var start_vfx_scene: PackedScene = preload("res://game/vfx/abilities/HunterPoisonedArrowStartVfx.tscn")
@export var end_vfx_scene: PackedScene = preload("res://game/vfx/abilities/HunterPoisonedArrowEndVfx.tscn")
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/HunterMagicShotProjectile.tscn")
@export var vfx_z_index: int = 2000

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (caster is Node2D) or not (target is Node2D):
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base: int = _compute_base_damage(caster, rank_data, snap)
	if base <= 0:
		return
	var final_damage: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	if final_damage <= 0:
		return

	_run_sequence(caster as Node2D, target as Node2D, final_damage)

func _run_sequence(caster: Node2D, target: Node2D, final_damage: int) -> void:
	if caster == null or target == null:
		return
	var world_parent: Node = caster.get_parent()
	if world_parent == null:
		return

	var caster_pos: Vector2 = _resolve_anchor(caster)
	var shot_dir: Vector2 = _resolve_shot_direction(caster_pos, _resolve_anchor(target))
	var shot_rotation: float = shot_dir.angle()
	var start_dur: float = _spawn_effect(world_parent, start_vfx_scene, caster_pos, shot_rotation)
	if start_dur > 0.0:
		await caster.get_tree().create_timer(start_dur).timeout

	if target == null or not is_instance_valid(target):
		return

	var proj_node: Node = projectile_scene.instantiate() if projectile_scene != null else null
	var projectile := proj_node as HunterMagicShotProjectile
	if projectile == null:
		_apply_damage_if_valid(caster, target, final_damage)
		return

	world_parent.add_child(projectile)
	projectile.z_as_relative = false
	projectile.z_index = vfx_z_index
	projectile.global_position = caster_pos
	projectile.setup(target, caster)
	projectile.impacted.connect(func(hit_target: Node2D) -> void:
		_on_projectile_impacted(world_parent, caster, hit_target, final_damage)
	)

func _on_projectile_impacted(world_parent: Node, caster: Node2D, target: Node2D, final_damage: int) -> void:
	if world_parent == null or caster == null:
		return
	if target == null or not is_instance_valid(target):
		return
	var impact_pos: Vector2 = _resolve_anchor(target)
	var shot_dir: Vector2 = _resolve_shot_direction(_resolve_anchor(caster), impact_pos)
	var shot_rotation: float = shot_dir.angle()
	var end_dur: float = _spawn_effect(world_parent, end_vfx_scene, impact_pos, shot_rotation)
	if end_dur > 0.0:
		await caster.get_tree().create_timer(end_dur).timeout
	_apply_damage_if_valid(caster, target, final_damage)

func _apply_damage_if_valid(caster: Node2D, target: Node2D, final_damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return
	DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, final_damage, school)

func _spawn_effect(parent: Node, scene: PackedScene, world_pos: Vector2, rotation_rad: float = 0.0) -> float:
	if parent == null or scene == null:
		return 0.0
	var node: Node2D = scene.instantiate() as Node2D
	if node == null:
		return 0.0
	parent.add_child(node)
	node.z_as_relative = false
	node.z_index = vfx_z_index
	node.global_position = world_pos
	node.rotation = rotation_rad
	return _extract_duration(node)

func _extract_duration(node: Node) -> float:
	if node == null:
		return 0.0
	var anim: AnimatedSprite2D = node.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
	if anim == null or anim.sprite_frames == null:
		return 0.0
	var name: StringName = anim.animation
	if name == StringName("") or not anim.sprite_frames.has_animation(name):
		return 0.0
	var fps: float = float(anim.sprite_frames.get_animation_speed(name))
	if fps <= 0.0:
		return 0.0
	var frame_count: int = anim.sprite_frames.get_frame_count(name)
	if frame_count <= 0:
		return 0.0
	return float(frame_count) / fps


func _resolve_shot_direction(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	var v: Vector2 = to_pos - from_pos
	if v.length_squared() <= 0.0001:
		return Vector2.RIGHT
	return v.normalized()

func _resolve_anchor(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ZERO
	if node.has_method("get_body_hitbox_center_global"):
		var v: Variant = node.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return node.global_position

func _compute_base_damage(caster: Node, rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	var attack_power: float = float(derived.get("attack_power", 0.0))
	match scaling_mode:
		"flat":
			return int(rank_data.value_flat)
		"phys_base_pct":
			var base_phys: int = 0
			if "c_combat" in caster and caster.c_combat != null and caster.c_combat.has_method("get_attack_damage"):
				base_phys = int(caster.c_combat.call("get_attack_damage"))
			return int(round(float(base_phys) * float(rank_data.value_pct) / 100.0))
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat) + SP_SCALING.bonus_flat(spell_power, rank_data, "direct")
