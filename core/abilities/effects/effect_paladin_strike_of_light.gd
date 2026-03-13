extends AbilityEffect
class_name EffectPaladinStrikeOfLight

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")
const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var hit_vfx_scene: PackedScene = preload("res://game/vfx/abilities/PaladinStrikeOfLightVfx.tscn")
@export var vfx_layer_offset_from_target: int = 100

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var phys_base: int = _compute_phys_base_damage(caster, rank_data)
	var magic_base: int = _compute_magic_base_damage(rank_data, snap)

	if target is Node2D:
		_spawn_hit_vfx(target as Node2D)

	var total_dealt: int = 0
	if phys_base > 0:
		var phys_final: int = STAT_CALC.apply_crit_to_damage_typed(phys_base, snap, "physical")
		if phys_final > 0:
			total_dealt += DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, phys_final, "physical")

	if magic_base > 0:
		var magic_final: int = STAT_CALC.apply_crit_to_damage_typed(magic_base, snap, "magic")
		if magic_final > 0:
			var dealt_magic: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, magic_final, "magic")
			total_dealt += dealt_magic
			if dealt_magic > 0 and "c_buffs" in caster and caster.c_buffs != null and caster.c_buffs.has_method("restore_mana_from_spell_damage"):
				caster.c_buffs.call("restore_mana_from_spell_damage", dealt_magic)

	if total_dealt <= 0:
		return

func _compute_phys_base_damage(caster: Node, rank_data: RankData) -> int:
	var base_phys: int = 0
	if "c_combat" in caster and caster.c_combat != null and caster.c_combat.has_method("get_attack_damage"):
		base_phys = int(caster.c_combat.call("get_attack_damage"))
	return int(round(float(base_phys) * float(rank_data.value_pct) / 100.0))

func _compute_magic_base_damage(rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	return int(rank_data.value_flat_2) + SP_SCALING.bonus_flat(spell_power, rank_data, "direct")

func _spawn_hit_vfx(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or hit_vfx_scene == null:
		return
	var parent: Node = target.get_parent()
	if parent == null:
		return
	var vfx: Node2D = hit_vfx_scene.instantiate() as Node2D
	if vfx == null:
		return
	vfx.z_as_relative = false
	if "keep_layer_offset_from_target" in vfx:
		vfx.set("keep_layer_offset_from_target", true)
	if "layer_offset_from_target" in vfx:
		vfx.set("layer_offset_from_target", vfx_layer_offset_from_target)
	if "follow_world_collider_center" in vfx:
		vfx.set("follow_world_collider_center", true)
	if "follow_target" in vfx:
		vfx.set("follow_target", target)
	parent.add_child(vfx)

	var anchor: Vector2 = target.global_position
	if target.has_method("get_body_hitbox_center_global"):
		var center_v: Variant = target.call("get_body_hitbox_center_global")
		if center_v is Vector2:
			anchor = center_v as Vector2
	else:
		anchor = VFX_ANCHOR_HELPER.resolve_world_collider_center(target, target.global_position)
	vfx.global_position = anchor
	if vfx.has_node("AnimatedSprite2D"):
		var anim := vfx.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			anim.play("default")
