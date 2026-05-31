extends Control

## 보물 노드. 무조건 보상 획득 (전투 없음). 골드 / 아이템 / 렐릭류.


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_canyon.jpg")


func _on_take_pressed() -> void:
	print("[Treasure] 보상 획득 — 미구현")
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
