extends Control

## 특수 이벤트 노드. 텍스트 선택지 + 결과 (위험/보상 트레이드오프).
## 풀 자체는 콘텐츠 작업이라 후순위.


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_tervan.jpg")


func _on_choice_a_pressed() -> void:
	print("[Event] 선택지 A — 미구현")


func _on_choice_b_pressed() -> void:
	print("[Event] 선택지 B — 미구현")


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
