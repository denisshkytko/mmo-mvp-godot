extends EffectApplyBuff
class_name EffectApplyAura

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null:
		return
	var aura_id: String = String(context.get("ability_id", ""))
	if "c_spellbook" in caster and caster.c_spellbook != null and aura_id != "":
		caster.c_spellbook.aura_active = aura_id

	var final_target: Node = caster
	context["source"] = "aura"
	super.apply(caster, final_target, rank_data, context)
