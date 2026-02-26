extends RefCounted
class_name DamageHelper

const COMBAT_TEXT_MANAGER_SCRIPT := preload("res://ui/game/hud/systems/combat_text/combat_text_manager.gd")
const COMBAT_TEXT_MANAGER_NODE_NAME := "CombatTextManager"

static func apply_damage(attacker: Node, target: Node, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if dmg <= 0:
		return
	var final_dmg: int = dmg
	if target.has_method("take_damage_from"):
		var result = target.call("take_damage_from", dmg, attacker)
		if typeof(result) == TYPE_INT or typeof(result) == TYPE_FLOAT:
			final_dmg = int(result)
	elif target.has_method("take_damage"):
		var result2 = target.call("take_damage", dmg)
		if typeof(result2) == TYPE_INT or typeof(result2) == TYPE_FLOAT:
			final_dmg = int(result2)

	_show_damage_number(target, final_dmg, "physical")

	if attacker != null:
		var danger_meter := _get_danger_meter(attacker)
		if danger_meter != null:
			danger_meter.on_damage_dealt(float(final_dmg) * _get_threat_multiplier(attacker), target)
	if attacker != null and "c_resource" in attacker and attacker.c_resource != null:
		attacker.c_resource.on_damage_dealt()

static func apply_damage_typed(attacker: Node, target: Node, dmg: int, dmg_type: String) -> void:
	apply_damage_typed_with_result(attacker, target, dmg, dmg_type)

static func apply_damage_typed_with_result(attacker: Node, target: Node, dmg: int, dmg_type: String) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if dmg <= 0:
		return 0

	var final_dmg: int = dmg
	if target.has_method("take_damage_from_typed"):
		var result = target.call("take_damage_from_typed", dmg, attacker, dmg_type)
		if typeof(result) == TYPE_INT or typeof(result) == TYPE_FLOAT:
			final_dmg = int(result)
	elif target.has_method("take_damage_typed"):
		var result2 = target.call("take_damage_typed", dmg, dmg_type)
		if typeof(result2) == TYPE_INT or typeof(result2) == TYPE_FLOAT:
			final_dmg = int(result2)
	else:
		apply_damage(attacker, target, dmg)
		return dmg

	_show_damage_number(target, final_dmg, dmg_type)

	if attacker != null:
		var danger_meter := _get_danger_meter(attacker)
		if danger_meter != null:
			danger_meter.on_damage_dealt(float(final_dmg) * _get_threat_multiplier(attacker), target)
	if attacker != null and "c_resource" in attacker and attacker.c_resource != null:
		attacker.c_resource.on_damage_dealt()
	return final_dmg

static func show_heal(target: Node, heal_amount: int) -> void:
	if heal_amount <= 0:
		return
	if target == null or not is_instance_valid(target):
		return
	if not (target is Node2D):
		return
	var t2d := target as Node2D
	var tree := t2d.get_tree()
	if tree == null:
		return
	var manager := _get_or_create_combat_text_manager(tree)
	if manager == null:
		return
	manager.show_heal(t2d, heal_amount)

static func _show_damage_number(target: Node, final_dmg: int, dmg_type: String) -> void:
	if final_dmg <= 0:
		return
	if target == null or not is_instance_valid(target):
		return
	if not (target is Node2D):
		return
	var t2d := target as Node2D
	var tree := t2d.get_tree()
	if tree == null:
		return
	var manager := _get_or_create_combat_text_manager(tree)
	if manager == null:
		return
	manager.show_damage(t2d, final_dmg, dmg_type)

static func _get_or_create_combat_text_manager(tree: SceneTree) -> CombatTextManager:
	if tree == null:
		return null
	var root: Window = tree.root
	if root == null:
		return null

	# Prefer scene-local manager. This avoids stale manager layering after scene swaps
	# (world -> character select -> world), where a root-level manager can end up
	# behind the newly loaded scene and make floating combat text invisible.
	var parent: Node = tree.current_scene
	if parent == null:
		parent = root

	var existing := parent.get_node_or_null(COMBAT_TEXT_MANAGER_NODE_NAME) as CombatTextManager
	if existing != null:
		parent.move_child(existing, parent.get_child_count() - 1)
		return existing

	# Cleanup legacy root-level singleton from older versions if it exists.
	var legacy := root.get_node_or_null(COMBAT_TEXT_MANAGER_NODE_NAME)
	if legacy != null and legacy != parent:
		legacy.queue_free()

	var manager := COMBAT_TEXT_MANAGER_SCRIPT.new() as CombatTextManager
	if manager == null:
		return null
	manager.name = COMBAT_TEXT_MANAGER_NODE_NAME
	parent.add_child(manager)
	parent.move_child(manager, parent.get_child_count() - 1)
	return manager

static func _get_threat_multiplier(attacker: Node) -> float:
	if attacker == null:
		return 1.0
	if not ("c_buffs" in attacker) or attacker.c_buffs == null:
		return 1.0
	if not attacker.c_buffs.has_method("get_active_stance_data"):
		return 1.0
	var stance_data: Dictionary = attacker.c_buffs.call("get_active_stance_data") as Dictionary
	if stance_data.is_empty():
		return 1.0
	var mult: float = float(stance_data.get("threat_multiplier", 1.0))
	if mult <= 0.0:
		return 1.0
	return mult

static func _get_danger_meter(attacker: Node) -> DangerMeterComponent:
	if attacker == null:
		return null
	if attacker.has_method("get_danger_meter"):
		var meter = attacker.call("get_danger_meter")
		if meter is DangerMeterComponent:
			return meter
	if "c_danger" in attacker:
		var meter = attacker.c_danger
		if meter is DangerMeterComponent:
			return meter
	var node := attacker.get_node_or_null("Components/Danger")
	if node is DangerMeterComponent:
		return node
	return null
