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

	var tree := owner.get_tree()
	if tree == null:
		marker.visible = false
		return

	var gm: Node = NodeCache.get_game_manager(tree)
	if gm == null:
		# Fallback for non-standard scene trees.
		gm = tree.root.get_node_or_null("Game/GameManager")
	if gm == null or not gm.has_method("get_target"):
		marker.visible = false
		return

	var target_v: Variant = gm.call("get_target")
	if not (target_v is Node):
		marker.visible = false
		return
	var target := target_v as Node
	if not is_instance_valid(target):
		marker.visible = false
		return

	marker.visible = target == owner
