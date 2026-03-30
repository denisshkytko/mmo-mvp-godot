extends RefCounted
class_name TargetMarkerHelper

# ------------------------------------------------------------
# TargetMarkerHelper
#
# TargetMarker должен отображаться на текущей цели игрока.
# ------------------------------------------------------------

static var _cache_frame: int = -1
static var _cache_tree: SceneTree = null
static var _cache_game_manager: Node = null
static var _cache_target: Node = null

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

	_refresh_target_cache(tree)
	if _cache_target == null or not is_instance_valid(_cache_target):
		marker.visible = false
		return
	marker.visible = _cache_target == owner


static func _refresh_target_cache(tree: SceneTree) -> void:
	if tree == null:
		_cache_game_manager = null
		_cache_target = null
		_cache_tree = null
		_cache_frame = -1
		return
	var frame: int = Engine.get_process_frames()
	if _cache_tree == tree and _cache_frame == frame:
		return
	_cache_tree = tree
	_cache_frame = frame
	if _cache_game_manager == null or not is_instance_valid(_cache_game_manager):
		_cache_game_manager = NodeCache.get_game_manager(tree)
		if _cache_game_manager == null:
			# Fallback for non-standard scene trees.
			_cache_game_manager = tree.root.get_node_or_null("Game/GameManager")
	if _cache_game_manager == null or not is_instance_valid(_cache_game_manager) or not _cache_game_manager.has_method("get_target"):
		_cache_target = null
		return
	var target_v: Variant = _cache_game_manager.call("get_target")
	_cache_target = target_v as Node if target_v is Node else null
