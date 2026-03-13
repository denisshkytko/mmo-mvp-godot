extends AbilityEffect
class_name EffectMageMeteor

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const SP_SCALING := preload("res://core/abilities/spell_power_scaling.gd")
const VFX_ANCHOR_HELPER := preload("res://core/abilities/effects/vfx_anchor_helper.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var burn_tick_interval_sec: float = 1.0
@export var burn_debuff_suffix: String = "burn"
@export var cast_start_vfx_scene: PackedScene = preload("res://game/vfx/abilities/MageMeteorStartVfx.tscn")
@export var cast_start_y_offset: float = -220.0
@export var projectile_scene: PackedScene = preload("res://game/characters/mobs/projectiles/MageMeteorProjectile.tscn")
@export var projectile_z_index: int = 2000
@export var impact_vfx_scene: PackedScene = preload("res://game/vfx/abilities/MageMeteorMiddleVfx.tscn")
@export var persistent_vfx_data_key: String = "runtime_persistent_vfx"

func on_cast_start(caster: Node, target: Node, _rank_data: RankData, _context: Dictionary, cast_time_sec: float) -> Dictionary:
	if not (target is Node2D):
		return {}
	if cast_start_vfx_scene == null:
		return {}
	var target_2d := target as Node2D
	if target_2d == null or not is_instance_valid(target_2d):
		return {}
	var parent: Node = target_2d.get_parent()
	if parent == null:
		return {}

	var vfx: Node2D = cast_start_vfx_scene.instantiate() as Node2D
	if vfx == null:
		return {}
	parent.add_child(vfx)
	vfx.z_as_relative = false
	if target_2d is CanvasItem:
		vfx.z_index = int((target_2d as CanvasItem).z_index) + 1
	vfx.global_position = _resolve_cast_marker_anchor(target_2d)
	vfx.scale = Vector2.ZERO
	if "follow_target" in vfx:
		vfx.set("follow_target", target_2d)
	if "follow_world_collider_center" in vfx:
		vfx.set("follow_world_collider_center", true)
	if "follow_offset" in vfx:
		vfx.set("follow_offset", Vector2(0.0, cast_start_y_offset))
	if "keep_layer_offset_from_target" in vfx:
		vfx.set("keep_layer_offset_from_target", true)
	if "layer_offset_from_target" in vfx:
		vfx.set("layer_offset_from_target", 1)
	if "free_on_finish" in vfx:
		vfx.set("free_on_finish", false)

	var duration: float = maxf(0.01, cast_time_sec)
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector2.ONE, duration)
	return {"cast_preview_vfx": vfx}

func on_cast_cancel(cast_runtime: Dictionary) -> void:
	if cast_runtime.is_empty():
		return
	var preview_v: Variant = cast_runtime.get("cast_preview_vfx", null)
	if preview_v is Node2D and is_instance_valid(preview_v):
		(preview_v as Node2D).queue_free()

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
		_cleanup_preview(context)
		return

	var final: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	if final <= 0:
		_cleanup_preview(context)
		return

	if _spawn_projectile(caster as Node2D, target as Node2D, final, rank_data, context):
		return
	_cleanup_preview(context)

func _spawn_projectile(caster: Node2D, target: Node2D, damage: int, rank_data: RankData, context: Dictionary) -> bool:
	if projectile_scene == null:
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
	projectile.global_position = _resolve_projectile_spawn_position(target, context)
	_cleanup_preview(context)
	if not projectile.has_method("setup"):
		projectile.queue_free()
		return false
	projectile.call("setup", target, damage, caster)
	if projectile.has_signal("impacted_with_result"):
		projectile.connect("impacted_with_result", func(hit_target: Node2D, dealt_damage: int, _dmg_type: String) -> void:
			if hit_target == null or not is_instance_valid(hit_target):
				return
			if dealt_damage <= 0:
				return
			_apply_burn_and_vfx(caster, hit_target, dealt_damage, rank_data, context)
		)
		return true
	if projectile.has_signal("impacted"):
		projectile.connect("impacted", func(hit_target: Node2D) -> void:
			if hit_target == null or not is_instance_valid(hit_target):
				return
			var dealt: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, hit_target, damage, school)
			if dealt <= 0:
				return
			_apply_burn_and_vfx(caster, hit_target, dealt, rank_data, context)
		)
		return true
	projectile.queue_free()
	return false

func _resolve_projectile_spawn_position(target: Node2D, context: Dictionary) -> Vector2:
	var cast_runtime: Dictionary = context.get("cast_runtime", {}) as Dictionary
	if not cast_runtime.is_empty():
		var preview_v: Variant = cast_runtime.get("cast_preview_vfx", null)
		if preview_v is Node2D and is_instance_valid(preview_v):
			return (preview_v as Node2D).global_position
	return _resolve_cast_marker_anchor(target)

func _cleanup_preview(context: Dictionary) -> void:
	var cast_runtime: Dictionary = context.get("cast_runtime", {}) as Dictionary
	if cast_runtime.is_empty():
		return
	var preview_v: Variant = cast_runtime.get("cast_preview_vfx", null)
	if preview_v is Node2D and is_instance_valid(preview_v):
		(preview_v as Node2D).queue_free()

func _resolve_cast_marker_anchor(target: Node2D) -> Vector2:
	var base: Vector2 = VFX_ANCHOR_HELPER.resolve_world_collider_center(target, target.global_position)
	return base + Vector2(0.0, cast_start_y_offset)

func _apply_burn_and_vfx(caster: Node, target: Node2D, dealt: int, rank_data: RankData, context: Dictionary) -> void:
	var burn_total: int = int(round(float(dealt) * float(rank_data.value_pct) / 100.0))
	if burn_total <= 0:
		return

	var vfx_node: Node2D = _spawn_persistent_vfx(target)
	var ability_id: String = String(context.get("ability_id", ""))
	var duration_sec: float = max(0.01, float(rank_data.duration_sec))
	var entry_id: String = "debuff:%s:%s" % [ability_id, burn_debuff_suffix] if ability_id != "" else "debuff:%s" % burn_debuff_suffix
	var data := {
		"ability_id": ability_id,
		"source": "debuff",
		"is_debuff": true,
		"duration_sec": duration_sec,
		"caster_ref": caster,
		"flags": {
			"dot_total_damage_flat": burn_total,
			"dot_damage_school": school,
			"dot_tick_interval_sec": burn_tick_interval_sec,
		},
	}
	if vfx_node != null:
		data[persistent_vfx_data_key] = vfx_node
	_apply_debuff_to_target(target, entry_id, duration_sec, data)

func _spawn_persistent_vfx(target: Node2D) -> Node2D:
	if target == null or not is_instance_valid(target) or impact_vfx_scene == null:
		return null
	var parent: Node = target.get_parent()
	if parent == null:
		return null

	var vfx: Node2D = impact_vfx_scene.instantiate() as Node2D
	if vfx == null:
		return null
	parent.add_child(vfx)

	vfx.z_as_relative = false
	if target is CanvasItem:
		vfx.z_index = int((target as CanvasItem).z_index) + 1
	var anchor_global: Vector2 = VFX_ANCHOR_HELPER.resolve_world_collider_center(target, target.global_position)
	vfx.global_position = anchor_global
	if "follow_target" in vfx:
		vfx.set("follow_target", target)
	if "keep_layer_offset_from_target" in vfx:
		vfx.set("keep_layer_offset_from_target", true)
	if "layer_offset_from_target" in vfx:
		vfx.set("layer_offset_from_target", 1)
	if "follow_world_collider_center" in vfx:
		vfx.set("follow_world_collider_center", true)
	if "free_on_finish" in vfx:
		vfx.set("free_on_finish", false)
	if vfx.has_node("AnimatedSprite2D"):
		var anim := vfx.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			anim.play("default")
	return vfx

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

func _apply_debuff_to_target(target: Node, entry_id: String, duration_sec: float, data: Dictionary) -> void:
	if target == null:
		return
	if target.has_method("add_or_refresh_buff"):
		target.call("add_or_refresh_buff", entry_id, duration_sec, data)
		return
	if "c_buffs" in target and target.c_buffs != null:
		target.c_buffs.add_or_refresh_buff(entry_id, duration_sec, data)
		return
	if "c_stats" in target and target.c_stats != null and target.c_stats.has_method("add_or_refresh_buff"):
		target.c_stats.call("add_or_refresh_buff", entry_id, duration_sec, data)
