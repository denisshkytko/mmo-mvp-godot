extends AbilityEffect
class_name EffectRevivePlayer

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if target == null or rank_data == null:
		return
	if not target is Corpse:
		return
	var corpse := target as Corpse
	if not corpse.owner_is_player:
		return
	if corpse.owner_entity_id == 0:
		return

	var owner_obj: Object = instance_from_id(corpse.owner_entity_id)
	if owner_obj == null or not (owner_obj is Player):
		return
	var owner := owner_obj as Player
	if not is_instance_valid(owner):
		return

	var hp_restore_pct: float = max(0.0, rank_data.value_pct)
	var mana_restore_pct: float = max(0.0, rank_data.value_pct_2)
	owner.is_dead = false
	owner.current_hp = max(1, int(round(float(owner.max_hp) * hp_restore_pct / 100.0)))
	owner.mana = max(0, int(round(float(owner.max_mana) * mana_restore_pct / 100.0)))

	var respawn_ui: Node = owner.get_tree().get_first_node_in_group("respawn_ui")
	if respawn_ui != null and respawn_ui.has_method("close"):
		respawn_ui.call("close")

	if owner.has_node("CastBar"):
		var cast_bar := owner.get_node("CastBar") as ProgressBar
		if cast_bar != null:
			cast_bar.visible = false
			cast_bar.value = 0.0

	if owner.c_buffs != null:
		owner.c_buffs.clear_all()
	if owner.has_method("_apply_spellbook_passives"):
		owner.call("_apply_spellbook_passives")

	owner.global_position = corpse.global_position
	corpse.queue_free()
