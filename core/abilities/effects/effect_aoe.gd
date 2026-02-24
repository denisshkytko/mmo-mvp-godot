extends AbilityEffect
class_name EffectAOE

const PLAYER_COMBAT := preload("res://game/characters/player/components/player_combat.gd")

@export var radius_mode: String = "melee" # melee | ranged | ranged_half | self
@export var target_filter: String = "enemies_only" # enemies_only | allies_only
@export var inner_effect: AbilityEffect

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or inner_effect == null:
		return
	if caster.get_tree() == null:
		return

	var def: AbilityDefinition = context.get("ability_def") as AbilityDefinition
	var radius: float = _get_radius(def)
	var nodes := caster.get_tree().get_nodes_in_group("faction_units")
	for node in nodes:
		if not (node is Node2D):
			continue
		var target_node: Node2D = node as Node2D
		if target_node == null or not is_instance_valid(target_node):
			continue
		if target_node == caster:
			continue
		if not _is_valid_target(caster, target_node):
			continue
		if caster.global_position.distance_to(target_node.global_position) > radius:
			continue
		inner_effect.apply(caster, target_node, rank_data, context)

func _get_radius(def: AbilityDefinition) -> float:
	match radius_mode:
		"ranged":
			return PLAYER_COMBAT.RANGED_ATTACK_RANGE
		"ranged_half":
			return PLAYER_COMBAT.RANGED_ATTACK_RANGE * 0.5
		"self":
			return PLAYER_COMBAT.MELEE_ATTACK_RANGE
		_:
			return PLAYER_COMBAT.MELEE_ATTACK_RANGE

func _is_valid_target(caster: Node, target: Node) -> bool:
	if caster == null or target == null:
		return false
	var caster_faction := ""
	if caster.has_method("get_faction_id"):
		caster_faction = String(caster.call("get_faction_id"))
	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	var rel := FactionRules.relation(caster_faction, target_faction)
	match target_filter:
		"allies_only":
			return rel != FactionRules.Relation.HOSTILE
		_:
			if rel == FactionRules.Relation.HOSTILE:
				return true
			if rel != FactionRules.Relation.NEUTRAL:
				return false
			if "current_target" in target and target.current_target == caster:
				return true
			if "aggressor" in target and target.aggressor == caster:
				return true
			return false
