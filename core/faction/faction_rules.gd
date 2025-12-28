extends Node
class_name FactionRules

enum Relation { FRIENDLY, NEUTRAL, HOSTILE }

static func relation(from_faction: String, to_faction: String) -> int:
	# safety
	if from_faction == "" or to_faction == "":
		return Relation.NEUTRAL

	# mobs
	if from_faction == "aggressive_mob":
		if to_faction == "aggressive_mob":
			return Relation.FRIENDLY
		return Relation.HOSTILE

	if from_faction == "neutral_mob":
		if to_faction == "neutral_mob":
			return Relation.FRIENDLY
		return Relation.NEUTRAL

	# players/npcs factions: blue/red/yellow/green
	match from_faction:
		"blue":
			if to_faction in ["blue", "green"]:
				return Relation.FRIENDLY
			if to_faction == "yellow" or to_faction == "neutral_mob":
				return Relation.NEUTRAL
			if to_faction in ["red", "aggressive_mob"]:
				return Relation.HOSTILE

		"red":
			if to_faction in ["red", "green"]:
				return Relation.FRIENDLY
			if to_faction == "yellow" or to_faction == "neutral_mob":
				return Relation.NEUTRAL
			if to_faction in ["blue", "aggressive_mob"]:
				return Relation.HOSTILE

		"yellow":
			if to_faction == "yellow":
				return Relation.FRIENDLY
			if to_faction in ["red", "green", "blue", "neutral_mob"]:
				return Relation.NEUTRAL
			if to_faction == "aggressive_mob":
				return Relation.HOSTILE

		"green":
			if to_faction in ["green", "red", "blue"]:
				return Relation.FRIENDLY
			if to_faction == "yellow" or to_faction == "neutral_mob":
				return Relation.NEUTRAL
			if to_faction == "aggressive_mob":
				return Relation.HOSTILE

	return Relation.NEUTRAL

static func can_attack(attacker_faction: String, target_faction: String, attacker_is_player: bool) -> bool:
	var rel := relation(attacker_faction, target_faction)

	# Основное правило: атаковать можно только HOSTILE.
	# Исключение: игрок может атаковать NEUTRAL тоже.
	if rel == Relation.HOSTILE:
		return true
	if attacker_is_player and rel == Relation.NEUTRAL:
		return true
	return false
