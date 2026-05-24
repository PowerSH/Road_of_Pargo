extends Control

## 거점 (마을 광장). 용병 고용 / 아이템 상점 / NPC 조우 / 맵 진입.
## 챕터 시작 위치 + 챕터 사이 통과 도시 역할 둘 다.


func _on_hire_pressed() -> void:
	print("[Hub] 용병 고용 — 미구현")


func _on_shop_pressed() -> void:
	print("[Hub] 아이템 상점 — 미구현")


func _on_npc_pressed() -> void:
	print("[Hub] NPC 조우 — 미구현")


func _on_to_map_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_to_menu_pressed() -> void:
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
