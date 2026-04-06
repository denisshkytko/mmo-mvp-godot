extends Node

enum ActivityTier { FULL, SIM, SLEEP }

const FULL_RADIUS_MULTIPLIER: float = 2.0
const SIM_RADIUS_MULTIPLIER: float = 5.0
const FALLBACK_BASE_RADIUS: float = 1200.0

var _player_cached: Node2D = null
var _full_radius: float = FALLBACK_BASE_RADIUS * FULL_RADIUS_MULTIPLIER
var _sim_radius: float = FALLBACK_BASE_RADIUS * SIM_RADIUS_MULTIPLIER
var _radii_ready: bool = false

func _process(_delta: float) -> void:
	_refresh_player_ref()
	_refresh_radii()

func get_activity_tier_for(entity: Node2D) -> int:
	if entity == null or not is_instance_valid(entity):
		return ActivityTier.SLEEP
	_refresh_player_ref()
	_refresh_radii()
	if _player_cached == null or not is_instance_valid(_player_cached):
		return ActivityTier.FULL
	var dist_sq := entity.global_position.distance_squared_to(_player_cached.global_position)
	var full_sq := _full_radius * _full_radius
	if dist_sq <= full_sq:
		return ActivityTier.FULL
	var sim_sq := _sim_radius * _sim_radius
	if dist_sq <= sim_sq:
		return ActivityTier.SIM
	return ActivityTier.SLEEP

func _refresh_player_ref() -> void:
	if _player_cached != null and is_instance_valid(_player_cached):
		return
	var tree := get_tree()
	if tree == null:
		return
	_player_cached = NodeCache.get_player(tree) as Node2D

func _refresh_radii() -> void:
	var vp := get_viewport()
	if vp == null:
		if not _radii_ready:
			_apply_fallback_radii()
		return
	var cam := vp.get_camera_2d()
	var zoom := cam.zoom if cam != null else Vector2.ONE
	var visible_size := vp.get_visible_rect().size * zoom
	var x := (visible_size.x + visible_size.y) * 0.5
	if x <= 1.0:
		if not _radii_ready:
			_apply_fallback_radii()
		return
	_full_radius = x * FULL_RADIUS_MULTIPLIER
	_sim_radius = x * SIM_RADIUS_MULTIPLIER
	_radii_ready = true

func _apply_fallback_radii() -> void:
	_full_radius = FALLBACK_BASE_RADIUS * FULL_RADIUS_MULTIPLIER
	_sim_radius = FALLBACK_BASE_RADIUS * SIM_RADIUS_MULTIPLIER
	_radii_ready = true
