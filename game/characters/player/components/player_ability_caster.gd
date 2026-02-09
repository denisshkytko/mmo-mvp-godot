extends Node
class_name PlayerAbilityCaster

var p: Player = null
var _cooldowns: Dictionary = {} # ability_id -> time_left
var _active_aura_buff_id: String = ""
var _active_stance_buff_id: String = ""

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for k in _cooldowns.keys():
		var ability_id: String = String(k)
		var left: float = max(0.0, float(_cooldowns.get(ability_id, 0.0)) - delta)
		if left <= 0.0:
			_cooldowns.erase(ability_id)
		else:
			_cooldowns[ability_id] = left

func try_cast(ability_id: String, target: Node) -> Dictionary:
	if ability_id == "":
		return {"ok": false, "reason": "empty"}
	if p == null or p.c_spellbook == null:
		return {"ok": false, "reason": "no_spellbook"}
	var rank := int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	if rank <= 0:
		return {"ok": false, "reason": "not_learned"}

	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return {"ok": false, "reason": "no_db"}
	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def == null:
		return {"ok": false, "reason": "no_def"}
	if def.ability_type == "aura" or def.ability_type == "stance":
		return {"ok": false, "reason": "passive"}

	var rank_data: RankData = null
	if db.has_method("get_rank_data"):
		rank_data = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return {"ok": false, "reason": "no_rank"}

	if get_cooldown_left(ability_id) > 0.0:
		return {"ok": false, "reason": "cooldown"}

	var actual_target: Node = target
	if actual_target == null:
		actual_target = p

	match def.ability_type:
		"buff":
			var data := {
				"source_ability": ability_id,
				"ability_id": ability_id,
				"kind": "buff"
			}
			var buff_target: Node = actual_target
			if buff_target == null or not buff_target.has_method("add_or_refresh_buff"):
				buff_target = p
			buff_target.call("add_or_refresh_buff", "buff:%s" % ability_id, rank_data.duration_sec, data)
		"heal":
			pass
		"damage", "aoe_damage":
			pass

	_cooldowns[ability_id] = rank_data.cooldown_sec
	return {"ok": true, "reason": "", "target": actual_target}

func get_cooldown_left(ability_id: String) -> float:
	return float(_cooldowns.get(ability_id, 0.0))

func get_cooldown_pct(ability_id: String) -> float:
	if ability_id == "":
		return 0.0
	var left := get_cooldown_left(ability_id)
	if left <= 0.0:
		return 0.0
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_rank_data") or p == null or p.c_spellbook == null:
		return 0.0
	var rank := int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return 0.0
	if rank_data.cooldown_sec <= 0.0:
		return 0.0
	return clamp(left / rank_data.cooldown_sec, 0.0, 1.0)

func apply_active_aura(ability_id: String) -> void:
	if p == null or p.c_buffs == null:
		return
	var new_buff_id := ""
	if ability_id != "":
		new_buff_id = "aura:%s" % ability_id
	if _active_aura_buff_id != "" and _active_aura_buff_id != new_buff_id:
		p.c_buffs.remove_buff(_active_aura_buff_id)
	_active_aura_buff_id = new_buff_id
	if ability_id == "":
		return
	var data := {
		"source_ability": ability_id,
		"ability_id": ability_id,
		"kind": "aura"
	}
	p.c_buffs.add_or_refresh_buff(new_buff_id, 999999.0, data)

func apply_active_stance(ability_id: String) -> void:
	if p == null or p.c_buffs == null:
		return
	var new_buff_id := ""
	if ability_id != "":
		new_buff_id = "stance:%s" % ability_id
	if _active_stance_buff_id != "" and _active_stance_buff_id != new_buff_id:
		p.c_buffs.remove_buff(_active_stance_buff_id)
	_active_stance_buff_id = new_buff_id
	if ability_id == "":
		return
	var data := {
		"source_ability": ability_id,
		"ability_id": ability_id,
		"kind": "stance"
	}
	p.c_buffs.add_or_refresh_buff(new_buff_id, 999999.0, data)
