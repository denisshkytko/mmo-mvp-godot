extends AbilityEffect
class_name EffectWarriorArmorBreak

const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var damage_effect: AbilityEffect
@export var debuff_effect: AbilityEffect
@export var vfx_scene: PackedScene = preload("res://game/vfx/abilities/WarriorArmorBreakVfx.tscn")
@export var vfx_layer_offset_from_target: int = 1

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if target is Node2D:
		_spawn_vfx(target as Node2D)
	if damage_effect != null:
		damage_effect.apply(caster, target, rank_data, context)
	if debuff_effect != null:
		debuff_effect.apply(caster, target, rank_data, context)

func _spawn_vfx(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or vfx_scene == null:
		return
	var parent: Node = target.get_parent()
	if parent == null:
		return
	var vfx: Node2D = vfx_scene.instantiate() as Node2D
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

	var anchor: Vector2 = VFX_ANCHOR_HELPER.resolve_world_collider_center(target, target.global_position)
	if target.has_method("get_body_hitbox_center_global"):
		var center_v: Variant = target.call("get_body_hitbox_center_global")
		if center_v is Vector2:
			anchor = center_v as Vector2
	vfx.global_position = anchor
	if vfx.has_node("AnimatedSprite2D"):
		var anim := vfx.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			anim.play("default")
