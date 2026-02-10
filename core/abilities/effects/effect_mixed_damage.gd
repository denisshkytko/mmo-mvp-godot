extends AbilityEffect
class_name EffectMixedDamage

@export var physical_effect: AbilityEffect
@export var magic_effect: AbilityEffect

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if physical_effect != null:
		physical_effect.apply(caster, target, rank_data, context)
	if magic_effect != null:
		magic_effect.apply(caster, target, rank_data, context)
