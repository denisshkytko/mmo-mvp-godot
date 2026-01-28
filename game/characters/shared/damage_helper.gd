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
	if attacker != null and "c_resource" in attacker and attacker.c_resource != null:
		attacker.c_resource.on_damage_dealt()
