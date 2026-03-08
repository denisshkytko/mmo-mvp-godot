extends RefCounted
class_name OverlayRelationColors

const DARK_BLUE := Color(0.07, 0.17, 0.45, 1.0)
const DARK_RED := Color(0.45, 0.08, 0.08, 1.0)
const ORANGE := Color(0.90, 0.48, 0.08, 1.0)
const GREEN := Color(0.12, 0.55, 0.20, 1.0)
const RASPBERRY := Color(0.72, 0.08, 0.36, 1.0)
const YELLOW := Color(0.92, 0.82, 0.10, 1.0)
const GOLD := Color(1.0, 0.84, 0.10, 1.0)

static func hp_color_for_faction_target(player_faction: String, target_faction: String) -> Color:
	var rel: int = FactionRules.relation(player_faction, target_faction)
	if rel == FactionRules.Relation.HOSTILE:
		return DARK_RED
	if rel == FactionRules.Relation.FRIENDLY:
		if target_faction == player_faction:
			return DARK_BLUE
		return GREEN
	# neutral
	return ORANGE

static func mob_hp_color(is_aggressive: bool) -> Color:
	return RASPBERRY if is_aggressive else YELLOW

static func highlight_colors(base: Color, edge_alpha: float = 0.5) -> Dictionary:
	var center := base
	center.a = 1.0
	var edge := base
	edge.a = clamp(edge_alpha, 0.0, 1.0)
	return {"center": center, "edge": edge}
