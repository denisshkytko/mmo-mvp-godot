extends Node2D
class_name CastBarWidget

@onready var icon: TextureRect = $Icon
@onready var bar_fill: ColorRect = $BarBack/BarFill

func set_cast_visible(v: bool) -> void:
	visible = v

func set_progress01(progress: float) -> void:
	var p := clamp(progress, 0.0, 1.0)
	bar_fill.anchor_right = p

func set_icon_texture(tex: Texture2D) -> void:
	icon.texture = tex
