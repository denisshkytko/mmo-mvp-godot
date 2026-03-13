extends AbilityEffect
class_name EffectPaladinJudgingFlame

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")
const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var hit_vfx_scene: PackedScene = preload("res://game/vfx/abilities/PaladinJudgingFlameVfx.tscn")
@export var vfx_layer_offset_from_target: int = 1

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base: int = _compute_base_damage(caster, rank_data, snap, context)
	if base <= 0:
		return

	var final: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	if final <= 0:
		return

	if target is Node2D:
		_spawn_hit_vfx(target as Node2D)

	var dealt: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, final, school)
	if dealt <= 0:
		return

	if school == "magic" and "c_buffs" in caster and caster.c_buffs != null and caster.c_buffs.has_method("restore_mana_from_spell_damage"):
		caster.c_buffs.call("restore_mana_from_spell_damage", dealt)

func _compute_base_damage(caster: Node, rank_data: RankData, snap: Dictionary, context: Dictionary) -> int:
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
			var phys_pct: float = float(rank_data.value_pct)
			var ability_id: String = String(context.get("ability_id", ""))
			if ability_id == "light_execution":
				phys_pct = float(rank_data.value_pct_2)
			return int(round(float(base_phys) * phys_pct / 100.0))
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat) + SP_SCALING.bonus_flat(spell_power, rank_data, "direct")

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
