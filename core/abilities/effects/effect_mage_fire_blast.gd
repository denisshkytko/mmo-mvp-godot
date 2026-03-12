extends AbilityEffect
class_name EffectMageFireBlast

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var hit_vfx_scene: PackedScene = preload("res://game/vfx/abilities/MageFireBlastVfx.tscn")
@export var fallback_z_index: int = -5

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (target is Node2D):
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base: int = _compute_base_damage(caster, rank_data, snap)
	if base <= 0:
		return

	var final: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	var dealt: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, final, school)
	if dealt <= 0:
		return

	_spawn_hit_vfx(target as Node2D)

func _spawn_hit_vfx(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or hit_vfx_scene == null:
		return
	var parent: Node = target.get_parent()
	if parent == null:
		return
	var vfx: Node2D = hit_vfx_scene.instantiate() as Node2D
	if vfx == null:
		return
	parent.add_child(vfx)
	vfx.z_as_relative = false
	vfx.z_index = _resolve_vfx_z_index(target)
	vfx.global_position = _resolve_world_collider_center(target)

func _resolve_vfx_z_index(target: Node2D) -> int:
	if target == null:
		return fallback_z_index
	if "visual_root" in target:
		var visual_v: Variant = target.get("visual_root")
		if visual_v is CanvasItem and is_instance_valid(visual_v):
			return int((visual_v as CanvasItem).z_index) - 1
	if target is CanvasItem:
		return int((target as CanvasItem).z_index) - 1
	return fallback_z_index

func _resolve_world_collider_center(target: Node2D) -> Vector2:
	if target == null:
		return Vector2.ZERO
	if "world_collision" in target:
		var wc: Variant = target.get("world_collision")
		if wc is CollisionShape2D and is_instance_valid(wc):
			return (wc as CollisionShape2D).global_position
	var node_wc := target.get_node_or_null("WorldCollider") as CollisionShape2D
	if node_wc != null:
		return node_wc.global_position
	if target.has_method("get_body_hitbox_center_global"):
		var v: Variant = target.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return target.global_position

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
