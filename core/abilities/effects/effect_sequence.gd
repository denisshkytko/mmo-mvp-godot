extends AbilityEffect
class_name EffectSequence

@export var effects: Array[AbilityEffect] = []

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if rank_data == null:
		return
	for effect in effects:
		if effect == null:
			continue
		effect.apply(caster, target, rank_data, context)
