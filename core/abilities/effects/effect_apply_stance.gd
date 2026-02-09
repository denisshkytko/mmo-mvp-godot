extends EffectApplyBuff
class_name EffectApplyStance

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null:
		return
	var stance_id: String = String(context.get("ability_id", ""))
	if "c_spellbook" in caster and caster.c_spellbook != null and stance_id != "":
		caster.c_spellbook.stance_active = stance_id

	var final_target: Node = caster
	context["source"] = "stance"
	super.apply(caster, final_target, rank_data, context)
