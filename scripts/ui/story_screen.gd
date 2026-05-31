extends Control

## 게임 시작 시 인트로 화면. "계속" 누르면 거점으로 진입.
## 현재는 placeholder — 본문/슬라이드/타이핑 효과는 나중에.


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_tervan.jpg")


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub_screen.tscn")
