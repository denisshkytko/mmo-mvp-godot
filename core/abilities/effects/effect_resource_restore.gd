extends AbilityEffect
class_name EffectResourceRestore

@export var resource_type: String = "mana"

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if target == null or rank_data == null:
		return
	if resource_type != "mana":
		return
	var max_mana: int = 0
	var mana: int = 0
	if "max_mana" in target and "mana" in target:
		max_mana = int(target.max_mana)
		mana = int(target.mana)
	elif "c_resource" in target and target.c_resource != null:
		if target.c_resource.resource_type != "mana":
			return
		max_mana = int(target.c_resource.max_resource)
		mana = int(target.c_resource.resource)
	else:
		return

	var gain: int = int(ceil(float(max_mana) * float(rank_data.value_pct) / 100.0))
	if gain <= 0:
		return
	var new_mana: int = min(max_mana, mana + gain)
	if "mana" in target:
		target.mana = new_mana
	elif "c_resource" in target and target.c_resource != null:
		target.c_resource.resource = new_mana
