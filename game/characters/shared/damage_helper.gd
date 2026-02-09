extends RefCounted
class_name DamageHelper

static func apply_damage(attacker: Node, target: Node, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if dmg <= 0:
		return
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", dmg, attacker)
	elif target.has_method("take_damage"):
		target.call("take_damage", dmg)
	if attacker != null:
		var danger_meter := _get_danger_meter(attacker)
		if danger_meter != null:
			danger_meter.on_damage_dealt(float(dmg), target)
	if attacker != null and "c_resource" in attacker and attacker.c_resource != null:
		attacker.c_resource.on_damage_dealt()

static func apply_damage_typed(attacker: Node, target: Node, dmg: int, dmg_type: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if dmg <= 0:
		return

	var final_dmg := dmg
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
		return

	if attacker != null:
		var danger_meter := _get_danger_meter(attacker)
		if danger_meter != null:
			danger_meter.on_damage_dealt(float(final_dmg), target)
	if attacker != null and "c_resource" in attacker and attacker.c_resource != null:
		attacker.c_resource.on_damage_dealt()

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
