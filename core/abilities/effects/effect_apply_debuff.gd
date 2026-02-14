extends "res://core/abilities/effects/effect_apply_buff.gd"
class_name EffectApplyDebuff

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if context == null:
		context = {}
	context["source"] = "debuff"
	context["is_debuff"] = true
	super.apply(caster, target, rank_data, context)
