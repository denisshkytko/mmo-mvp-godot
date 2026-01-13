extends Node

class_name FlowRouter

const LOGIN_SCENE: String = "res://ui/flow/LoginUI.tscn"
const CHARACTER_SELECT_SCENE: String = "res://ui/flow/CharacterSelectUI.tscn"
const WORLD_SCENE: String = "res://game/scenes/Main.tscn"


func go_login() -> void:
	if AppState.set_state(AppState.FlowState.LOGIN):
		get_tree().change_scene_to_file(LOGIN_SCENE)


func go_character_select() -> void:
	if AppState.set_state(AppState.FlowState.CHARACTER_SELECT):
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func go_world() -> void:
	if AppState.set_state(AppState.FlowState.WORLD):
		get_tree().change_scene_to_file(WORLD_SCENE)
