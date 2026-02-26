extends CanvasLayer

func _ready() -> void:
	_disable_focus_for_mobile($Root)


func _disable_focus_for_mobile(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE
	elif node is LineEdit:
		(node as LineEdit).focus_mode = Control.FOCUS_NONE
	elif node is TextEdit:
		(node as TextEdit).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_focus_for_mobile(child)
