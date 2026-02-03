extends Control
class_name SkillPad

signal skill_pressed(slot_index: int)
signal interact_pressed()

@onready var quick_skill_btn: BaseButton = $QuickSkillBtn
@onready var skill_btn_1: BaseButton = $SkillBtn1
@onready var skill_btn_2: BaseButton = $SkillBtn2
@onready var skill_btn_3: BaseButton = $SkillBtn3
@onready var skill_btn_4: BaseButton = $SkillBtn4
@onready var interact_btn: BaseButton = $InteractBtn

var _skill_buttons: Array[BaseButton] = []


func _ready() -> void:
	_skill_buttons = [quick_skill_btn, skill_btn_1, skill_btn_2, skill_btn_3, skill_btn_4]
	_setup_slot_meta()
	_setup_positions()
	for btn in _skill_buttons:
		btn.pressed.connect(_on_skill_button_pressed.bind(int(btn.get_meta("slot_index"))))
	interact_btn.pressed.connect(_on_interact_pressed)


func _setup_slot_meta() -> void:
	quick_skill_btn.set_meta("slot_index", 0)
	skill_btn_1.set_meta("slot_index", 1)
	skill_btn_2.set_meta("slot_index", 2)
	skill_btn_3.set_meta("slot_index", 3)
	skill_btn_4.set_meta("slot_index", 4)


func _setup_positions() -> void:
	var center := size * 0.5
	_quick_center_button(quick_skill_btn, center)
	_position_button(skill_btn_1, center + Vector2(-120.0, -85.0))
	_position_button(skill_btn_2, center + Vector2(-150.0, 0.0))
	_position_button(skill_btn_3, center + Vector2(-120.0, 85.0))
	_position_button(skill_btn_4, center + Vector2(0.0, -135.0))
	_position_button(interact_btn, center + Vector2(0.0, -235.0))


func _quick_center_button(btn: Control, center: Vector2) -> void:
	btn.position = center - btn.size * 0.5


func _position_button(btn: Control, center_pos: Vector2) -> void:
	btn.position = center_pos - btn.size * 0.5


func _on_skill_button_pressed(slot_index: int) -> void:
	emit_signal("skill_pressed", slot_index)


func _on_interact_pressed() -> void:
	emit_signal("interact_pressed")


func set_interact_visible(is_visible: bool) -> void:
	interact_btn.visible = is_visible


func set_slot_icon(_slot: int, _texture: Texture2D) -> void:
	pass


func set_slot_cooldown(_slot: int, _pct: float) -> void:
	pass


func set_slot_enabled(_slot: int, _enabled: bool) -> void:
	pass
