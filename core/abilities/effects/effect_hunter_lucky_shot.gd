extends AbilityEffect
class_name EffectHunterLuckyShot

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var school: String = "physical"
@export var scaling_mode: String = "phys_base_pct"
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/HunterLuckyShotProjectile.tscn")
@export var projectile_z_index: int = 2000

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (caster is Node2D) or not (target is Node2D):
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base_damage: int = _compute_base_damage(caster, rank_data, snap)
	if base_damage <= 0:
		return

	var crit_mult: float = float(snap.get("crit_multiplier", 2.0))
	if crit_mult <= 0.0:
		crit_mult = 2.0
	var crit_damage: int = max(1, int(round(float(base_damage) * crit_mult)))

	if not _spawn_projectile(caster as Node2D, target as Node2D, crit_damage, rank_data):
		var dealt_fallback: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, crit_damage, school)
		_restore_mana_from_damage(caster, dealt_fallback, float(rank_data.value_pct_2))

func _spawn_projectile(caster: Node2D, target: Node2D, damage: int, rank_data: RankData) -> bool:
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
	if not projectile.has_method("setup"):
		projectile.queue_free()
		return false

	projectile.call("setup", target, 0, caster)
	if projectile.has_signal("impacted"):
		projectile.connect("impacted", func(hit_target: Node2D) -> void:
			if hit_target == null or not is_instance_valid(hit_target):
				return
			var dealt: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, hit_target, damage, school)
			_restore_mana_from_damage(caster, dealt, float(rank_data.value_pct_2))
		)
	return true

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
		"spell_power_flat":
			return int(rank_data.value_flat) + int(round(spell_power))
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat)

func _restore_mana_from_damage(caster: Node, final_damage: int, percent: float) -> void:
	if caster == null or final_damage <= 0 or percent <= 0.0:
		return
	var gain: int = int(round(float(final_damage) * percent / 100.0))
	if gain <= 0:
		return

	if "c_resource" in caster and caster.c_resource != null:
		if caster.c_resource.resource_type != "mana":
			return
		var max_resource: int = int(caster.c_resource.max_resource)
		var current: int = int(caster.c_resource.resource)
		caster.c_resource.resource = min(max_resource, current + gain)
		return

	if "mana" in caster and "max_mana" in caster:
		caster.mana = min(int(caster.max_mana), int(caster.mana) + gain)
