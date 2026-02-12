extends Control
class_name SkillPad

signal skill_pressed(slot_index: int)
signal interact_pressed()

@onready var quick_skill_btn: BaseButton = $QuickSkillBtn
@onready var skill_btn_1: BaseButton = $SkillBtn1
@onready var skill_btn_2: BaseButton = $SkillBtn2
@onready var skill_btn_3: BaseButton = $SkillBtn3
@onready var skill_btn_4: BaseButton = $SkillBtn4
@onready var interact_btn: BaseButton = $"../InteractBtn"

var _skill_buttons: Array[BaseButton] = []
var _default_textures: Array[Texture2D] = []


func _ready() -> void:
	_skill_buttons = [quick_skill_btn, skill_btn_1, skill_btn_2, skill_btn_3, skill_btn_4]
	_default_textures.clear()
	for btn in _skill_buttons:
		var tex_btn := btn as TextureButton
		_default_textures.append(tex_btn.texture_normal if tex_btn != null else null)
	_setup_slot_meta()
	for btn in _skill_buttons:
		btn.pressed.connect(_on_skill_button_pressed.bind(int(btn.get_meta("slot_index"))))
	interact_btn.pressed.connect(_on_interact_pressed)
	set_interact_visible(false)


func _setup_slot_meta() -> void:
	quick_skill_btn.set_meta("slot_index", 0)
	skill_btn_1.set_meta("slot_index", 1)
	skill_btn_2.set_meta("slot_index", 2)
	skill_btn_3.set_meta("slot_index", 3)
	skill_btn_4.set_meta("slot_index", 4)


func _on_skill_button_pressed(slot_index: int) -> void:
	emit_signal("skill_pressed", slot_index)


func _on_interact_pressed() -> void:
	emit_signal("interact_pressed")


func set_interact_visible(is_visible: bool) -> void:
	interact_btn.visible = is_visible


func set_slot_icon(_slot: int, _texture: Texture2D) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as TextureButton
	if btn == null:
		return
	btn.texture_normal = _default_textures[_slot]
	btn.texture_pressed = _default_textures[_slot]
	var icon := btn.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = _texture


func set_slot_cooldown(_slot: int, _pct: float) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as TextureButton
	if btn == null:
		return
	var overlay := btn.get_node_or_null("CooldownOverlay") as ColorRect
	if overlay == null:
		overlay = ColorRect.new()
		overlay.name = "CooldownOverlay"
		overlay.color = Color(0, 0, 0, 0.5)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(overlay)
		overlay.layout_mode = 1
		overlay.anchors_preset = Control.PRESET_FULL_RECT
		overlay.offset_left = 0
		overlay.offset_top = 0
		overlay.offset_right = 0
		overlay.offset_bottom = 0
	var pct: float = clamp(_pct, 0.0, 1.0)
	overlay.visible = pct > 0.0
	var base_color := overlay.color
	base_color.a = 0.2 + (0.6 * pct)
	overlay.color = base_color


func set_slot_enabled(_slot: int, _enabled: bool) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as BaseButton
	if btn == null:
		return
	btn.disabled = not _enabled
	btn.modulate = Color(1, 1, 1, 1.0 if _enabled else 0.5)
