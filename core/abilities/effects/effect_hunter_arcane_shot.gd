extends AbilityEffect
class_name EffectHunterArcaneShot

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/HunterArcaneShotProjectile.tscn")
@export var projectile_z_index: int = 2000

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

	var projectile := _spawn_projectile(world_parent, caster)
	if projectile == null:
		_apply_damage_if_valid(caster, target, final_damage)
		return

	projectile.setup(target, caster)
	projectile.impacted.connect(func(hit_target: Node2D) -> void:
		_apply_damage_if_valid(caster, hit_target, final_damage)
	)

func _spawn_projectile(parent: Node, caster: Node2D) -> HunterArcaneShotProjectile:
	if parent == null or projectile_scene == null:
		return null
	var node := projectile_scene.instantiate() as HunterArcaneShotProjectile
	if node == null:
		return null
	parent.add_child(node)
	node.z_as_relative = false
	node.z_index = projectile_z_index
	node.global_position = _resolve_anchor(caster)
	return node

func _apply_damage_if_valid(caster: Node2D, target: Node, final_damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not (target is Node2D):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return
	DAMAGE_HELPER.apply_damage_typed_with_result(caster, target as Node2D, final_damage, school)

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
