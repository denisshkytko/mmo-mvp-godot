extends Control
class_name SkillPad

signal skill_pressed(slot_index: int)
signal interact_pressed()

const COOLDOWN_SHADER_CODE := "shader_type canvas_item;\n\nuniform float fill_pct : hint_range(0.0, 1.0) = 0.0;\n\nvoid fragment() {\n\tvec2 d = UV - vec2(0.5);\n\tif (length(d) > 0.5) {\n\t\tdiscard;\n\t}\n\tif (UV.y < (1.0 - fill_pct)) {\n\t\tdiscard;\n\t}\n\tCOLOR = vec4(0.0, 0.0, 0.0, 0.62);\n}\n"
const RANGE_RING_SHADER_CODE := "shader_type canvas_item;\n\nuniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 0.75);\nuniform float ring_thickness : hint_range(0.01, 0.25) = 0.08;\n\nvoid fragment() {\n\tvec2 d = UV - vec2(0.5);\n\tfloat r = length(d);\n\tif (r > 0.5 || r < (0.5 - ring_thickness)) {\n\t\tdiscard;\n\t}\n\tCOLOR = ring_color;\n}\n"
const RANGE_RING_OK_COLOR := Color(1.0, 1.0, 1.0, 0.72)
const RANGE_RING_BLOCKED_COLOR := Color(0.95, 0.24, 0.24, 0.9)

@onready var quick_skill_btn: BaseButton = $QuickSkillBtn
@onready var skill_btn_1: BaseButton = $SkillBtn1
@onready var skill_btn_2: BaseButton = $SkillBtn2
@onready var skill_btn_3: BaseButton = $SkillBtn3
@onready var skill_btn_4: BaseButton = $SkillBtn4
@onready var interact_btn: BaseButton = $"../InteractBtn"

var _skill_buttons: Array[BaseButton] = []
var _icon_rects: Array[TextureRect] = []


func _ready() -> void:
	_skill_buttons = [quick_skill_btn, skill_btn_1, skill_btn_2, skill_btn_3, skill_btn_4]
	_icon_rects.clear()
	for btn in _skill_buttons:
		var icon_rect := btn.get_node_or_null("Icon") as TextureRect
		_icon_rects.append(icon_rect)
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
	if _slot < 0 or _slot >= _icon_rects.size():
		return
	var icon_rect := _icon_rects[_slot]
	if icon_rect == null:
		return
	icon_rect.texture = _texture


func set_slot_cooldown(_slot: int, _pct: float) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as TextureButton
	if btn == null:
		return
	var overlay := _ensure_cooldown_overlay(btn)
	if overlay == null:
		return
	var pct: float = clamp(_pct, 0.0, 1.0)
	overlay.visible = pct > 0.0
	if not overlay.visible:
		return
	var mat := overlay.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill_pct", pct)


func _ensure_cooldown_overlay(btn: TextureButton) -> ColorRect:
	var overlay := btn.get_node_or_null("CooldownOverlay") as ColorRect
	if overlay != null:
		return overlay
	overlay = ColorRect.new()
	overlay.name = "CooldownOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.layout_mode = 1
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.offset_left = 6
	overlay.offset_top = 6
	overlay.offset_right = -6
	overlay.offset_bottom = -6
	overlay.color = Color.WHITE
	var shader := Shader.new()
	shader.code = COOLDOWN_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fill_pct", 0.0)
	overlay.material = mat
	btn.add_child(overlay)
	return overlay


func set_slot_enabled(_slot: int, _enabled: bool) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as BaseButton
	if btn == null:
		return
	btn.disabled = not _enabled
	btn.modulate = Color(1, 1, 1, 1.0 if _enabled else 0.5)

func set_slot_out_of_range(_slot: int, _blocked: bool) -> void:
	if _slot < 0 or _slot >= _skill_buttons.size():
		return
	var btn := _skill_buttons[_slot] as TextureButton
	if btn == null:
		return
	var ring := _ensure_range_ring(btn)
	if ring == null:
		return
	var mat := ring.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("ring_color", RANGE_RING_BLOCKED_COLOR if _blocked else RANGE_RING_OK_COLOR)

func _ensure_range_ring(btn: TextureButton) -> ColorRect:
	var ring := btn.get_node_or_null("RangeRing") as ColorRect
	if ring != null:
		return ring
	ring = ColorRect.new()
	ring.name = "RangeRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.layout_mode = 1
	ring.anchors_preset = Control.PRESET_FULL_RECT
	ring.offset_left = 0
	ring.offset_top = 0
	ring.offset_right = 0
	ring.offset_bottom = 0
	ring.color = Color.WHITE
	var shader := Shader.new()
	shader.code = RANGE_RING_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ring_color", RANGE_RING_OK_COLOR)
	ring.material = mat
	btn.add_child(ring)
	btn.move_child(ring, 0)
	return ring
