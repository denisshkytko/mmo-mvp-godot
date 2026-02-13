extends AbilityEffect
class_name EffectHealOrDamageByRelation

@export var damage_effect: AbilityEffect
@export var heal_effect: AbilityEffect

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return

	var caster_faction := ""
	if caster.has_method("get_faction_id"):
		caster_faction = String(caster.call("get_faction_id"))
	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))

	var relation := FactionRules.relation(caster_faction, target_faction)
	if relation == FactionRules.Relation.HOSTILE:
		if damage_effect != null:
			damage_effect.apply(caster, target, rank_data, context)
		return

	if heal_effect != null:
		heal_effect.apply(caster, target, rank_data, context)
