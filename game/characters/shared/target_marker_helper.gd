extends RefCounted
class_name TargetMarkerHelper

# ------------------------------------------------------------
# TargetMarkerHelper
#
# TargetMarker должен отображаться на текущей цели игрока.
# ------------------------------------------------------------

static func set_marker_visible(marker: CanvasItem, owner: Node) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	if owner == null or not is_instance_valid(owner):
		marker.visible = false
		return

	var gm: Node = Engine.get_main_loop().root.get_node_or_null("Game/GameManager")
	if gm == null or not gm.has_method("get_target"):
		marker.visible = false
		return

	var target_v: Variant = gm.call("get_target")
	var is_player_target: bool = target_v is Node and is_instance_valid(target_v) and (target_v as Node) == owner
	marker.visible = is_player_target
