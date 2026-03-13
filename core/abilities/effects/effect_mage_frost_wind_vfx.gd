extends AbilityEffect
class_name EffectMageFrostWindVfx

const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var vfx_scene: PackedScene = preload("res://game/vfx/abilities/MageFrostWindVfx.tscn")
@export var z_offset_from_caster: int = -1

func apply(caster: Node, _target: Node, _rank_data: RankData, _context: Dictionary) -> void:
	if caster == null or not (caster is Node2D):
		return
	if vfx_scene == null:
		return
	var caster_2d := caster as Node2D
	var parent: Node = caster_2d.get_parent()
	if parent == null:
		return

	var vfx: Node2D = vfx_scene.instantiate() as Node2D
	if vfx == null:
		return
	parent.add_child(vfx)
	vfx.z_as_relative = false
	if caster is CanvasItem:
		vfx.z_index = int((caster as CanvasItem).z_index) + z_offset_from_caster
	vfx.global_position = VFX_ANCHOR_HELPER.resolve_world_collider_center(caster_2d, caster_2d.global_position)
