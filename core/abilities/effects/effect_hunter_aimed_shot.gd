extends AbilityEffect
class_name EffectHunterAimedShot

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var school: String = "physical"
@export var scaling_mode: String = "phys_base_pct"
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/HunterAutoAttackProjectile.tscn")
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

	if not _spawn_projectile(caster as Node2D, target as Node2D, final_damage):
		DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, final_damage, school)

func _spawn_projectile(caster: Node2D, target: Node2D, damage: int) -> bool:
	if caster == null or target == null or projectile_scene == null:
		return false
	var parent: Node = caster.get_parent()
	if parent == null:
		return false
	var projectile: Node2D = projectile_scene.instantiate() as Node2D
	if projectile == null:
		return false

	parent.add_child(projectile)
	projectile.z_as_relative = false
	projectile.z_index = projectile_z_index
	projectile.global_position = _resolve_anchor(caster)
	if projectile.has_method("setup"):
		projectile.call("setup", target, damage, caster)
		return true
	projectile.queue_free()
	return false

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
			return int(rank_data.value_flat)
