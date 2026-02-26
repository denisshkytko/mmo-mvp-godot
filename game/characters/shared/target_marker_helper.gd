extends RefCounted
class_name TargetMarkerHelper

# ------------------------------------------------------------
# TargetMarkerHelper
#
# По просьбе: TargetMarker подсвечивает тех, кто в данный момент
# агрессирует на игрока.
# ------------------------------------------------------------

static func set_marker_visible(marker: CanvasItem, is_aggressive_on_player: bool) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	marker.visible = is_aggressive_on_player
