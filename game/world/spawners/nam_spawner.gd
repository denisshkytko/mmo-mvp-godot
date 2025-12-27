extends Node2D
class_name NamSpawner

# Только для режима Guard: куда "смотрит" моб в idle
# (пока это задел на будущее — если у моба появятся анимации/флип)
@export_enum("Default", "Up", "Right", "Down", "Left") var guard_facing: int = 0
